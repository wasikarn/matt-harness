#!/bin/bash
# Fact-forcing edit gate — ECC gateguard-fact-force.js four-fact-force port
# (CLAUDE.md §Hook architecture (current profile ladder design)). Denies the FIRST Edit/Write/MultiEdit of each file path per
# session, forcing the agent to state importers/callers, affected API, data
# schemas, and the user's verbatim instruction BEFORE the edit lands. The
# second touch of the same path passes — friction, not a wall.
#
# State: $HOME/.claude/fact-force/<session>.txt — one repo-relative path per
# line. Per-session; a 30-min idle timeout resets the file (parity with ECC's
# SESSION_TIMEOUT_MS). Atomic write (temp+mv) for concurrent-hook safety.
#
# Exemptions (parity with ECC):
#   - empty file_path → allow
#   - .claude/settings*.json → allow (config-protection owns those)
#   - subagent invocation (agent_id / parent_tool_use_id present) → allow;
#     the parent session already passed the first-touch gate
#   - state-write failure → allow with stderr warning (avoid a retry loop)
#
# Denial budget: first N denials (default 3, KBG_FACT_FORCE_FULL_DENIALS) get
# the full 4-fact block; subsequent denials get a condensed one-line reminder.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off              # all hooks off
#   export CLAUDE_HOOK_PROFILE=minimal          # this gate off (standard/strict on)
#   export CLAUDE_DISABLED_HOOKS=fact-force-gate
#   export KBG_GATEGUARD=off                     # parity with ECC_GATEGUARD
#   export KBG_FACT_FORCE_DISABLED=1             # this gate only

set -uo pipefail

HOOK_ID="fact-force-gate"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable

hook_require_jq

# Master off-switches (checked AFTER hook_init so PROFILE/DISABLED still apply).
case "${KBG_GATEGUARD:-on}" in off|0|false|disabled|disable) exit 0 ;; esac
[ "${KBG_FACT_FORCE_DISABLED:-0}" = "1" ] && exit 0

case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

# Resolve the target path(s). Edit/Write: tool_input.file_path. MultiEdit:
# tool_input.edits[].file_path — deny on the first UN-checked inner path.
paths=""
if [ "$TOOL" = "MultiEdit" ]; then
  paths=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.edits[].file_path // empty' 2>/dev/null)
else
  paths=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
fi
[ -z "$paths" ] && exit 0

# Subagent invocation → parent already gated.
if printf '%s\n' "$INPUT" | jq -e '(.agent_id // .agentId // .parent_tool_use_id // .parentToolUseId // empty) | length > 0' >/dev/null 2>&1; then
  exit 0
fi

# Session state file (one path per line). Repo-relative keys so the same path
# across projects doesn't collide; fall back to the raw path if $CLAUDE_PROJECT_DIR unset.
STATE_DIR="$HOME/.claude/fact-force"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
sid_safe=$(printf '%s' "${SID:-no-sid}" | tr -c 'a-zA-Z0-9_' '_')
STATE_FILE="$STATE_DIR/$sid_safe.txt"

# 30-min idle timeout: if the state file is older than that, reset it.
if [ -f "$STATE_FILE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$STATE_FILE" 2>/dev/null || echo 0) ))
  [ "$age" -gt 1800 ] && rm -f "$STATE_FILE" 2>/dev/null
fi

is_checked() {  # echo "checked" if $1 in state, "" otherwise
  [ -f "$STATE_FILE" ] && grep -qxF -- "$1" "$STATE_FILE" 2>/dev/null && echo checked
}

mark_checked() {  # append $1 atomically; best-effort
  local tmp
  tmp="$STATE_FILE.tmp.$$"
  { [ -f "$STATE_FILE" ] && cat "$STATE_FILE"; printf '%s\n' "$1"; } > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp"
}

# Denial budget: count denials this session (one per unchecked path touched).
denial_count() {
  [ -f "$STATE_FILE" ] && grep -cxF . "$STATE_FILE" 2>/dev/null || echo 0
}

FULL_BUDGET="${KBG_FACT_FORCE_FULL_DENIALS:-3}"
case "$FULL_BUDGET" in ''|*[!0-9]*) FULL_BUDGET=3 ;; esac

emit_full() {  # $1=action(edit|creation) $2=safe-path
  cat <<EOF
[Fact-Forcing Gate]

Before ${1} ${2}, present these facts:

1. List ALL files that import/require this file (use Grep)
2. List the public functions/classes affected by this change
3. If this file reads/writes data files, show field names, structure, and date format (use redacted or synthetic values, not raw production data)
4. Quote the user's current instruction verbatim

Present the facts, then retry the same operation.
Recovery: if this gate is blocking setup or repair work, run this session with \`KBG_GATEGUARD=off\` or add \`fact-force-gate\` to \`CLAUDE_DISABLED_HOOKS\`.
EOF
}

emit_condensed() {  # $1=action $2=safe-path $3=ordinal
  printf '[Fact-Forcing Gate] (denial #%s this session) First %s of %s: briefly state importers/callers, affected API, data schemas if any, and the user verbatim instruction, then retry. (KBG_GATEGUARD=off disables this gate.)\n' "$3" "$1" "$2"
}

sanitize_path() {  # strip control chars, truncate to 500 (message-only)
  printf '%s' "$1" | tr -d '\000-\037\177' | cut -c1-500
}

while IFS= read -r p; do
  [ -z "$p" ] && continue
  # .claude/settings*.json → config-protection owns these.
  case "$p" in
    */.claude/settings.json|*/.claude/settings.*.json|.claude/settings.json|.claude/settings.*.json) continue ;;
  esac
  if [ -z "$(is_checked "$p")" ]; then
    action="edit"; [ "$TOOL" = "Write" ] && action="creation"
    safe=$(sanitize_path "$p")
    n=$(denial_count)
    if [ "$n" -gt "$FULL_BUDGET" ]; then
      msg=$(emit_condensed "$action" "$safe" "$n")
    else
      msg=$(emit_full "$action" "$safe")
    fi
    mark_checked "$p"  # record BEFORE emitting so a state-write fail still allows retry
    hook_decision deny "$msg"
  fi
done <<<"$paths"

exit 0