#!/bin/bash
# tmux-reminder.sh — non-blocking advisory nudge to run long jobs under tmux.
#
# Long-running bash (builds, test suites, installs, 3+ `&&` chains, backgrounded
# `&`) survives a disconnect only if it lives in a tmux/Screen session. This
# emits an additionalContext nudge (ECC-style, exit 0 always) so the operator
# remembers to `tmux new -s build` first. Advisory only — never blocks.
#
# Bypass (advisory, non-blocking anyway): CLAUDE_HOOK_PROFILE=off /
# CLAUDE_DISABLED_HOOKS=tmux-reminder.

set -uo pipefail

HOOK_ID="tmux-reminder"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') 2>/dev/null || exit 0
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(hook_strip_quoted "$COMMAND")
_GREP="command grep"

emit() {
  local msg="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg c "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null
  fi
  exit 0
}

# Long-running command fingerprints. Anchored on word boundaries so a token like
# `makefile` or `dockerfile` doesn't trip `make` / `docker build`.
LONG_PAT='(^|[[:space:];&|`(])(npm[[:space:]]+(test|run[[:space:]]+(build|ci)|ci)|pytest|go[[:space:]]+test|cargo[[:space:]]+(build|test)|make([[:space:]]|$)|docker[[:space:]]+build|bash[[:space:]]+install)'

if printf '%s\n' "$STRIPPED" | $_GREP -qE "$LONG_PAT"; then
  emit "[tmux-reminder] This looks long-running (build/test/install). Run it inside tmux (\`tmux new -s build\`) so a disconnect does not kill it — a dropped SSH/app session takes a bare foreground job with it. (Advisory only; ECC-style non-blocking reminder.)"
fi

# 3+ `&&`-chained commands — heuristic for "compound, probably slow".
# ponytail: count-by-tr is O(n) and avoids a second grep -o fork.
AND_COUNT=$(printf '%s' "$STRIPPED" | tr -cd '&' | wc -c | tr -d ' ')
if [ "${AND_COUNT:-0}" -ge 6 ]; then
  emit "[tmux-reminder] This chains 3+ commands with \`&&\`. Run it under tmux (\`tmux new -s chain\`) so a disconnect does not kill the chain partway. (Advisory only; ECC-style non-blocking reminder.)"
fi

# Backgrounded with trailing `&` (but not `&&`).
if printf '%s\n' "$STRIPPED" | $_GREP -qE '(&&)?[^&]&[[:space:]]*$'; then
  emit "[tmux-reminder] Backgrounded with \`&\` — fine for fire-and-forget, but if you want to see output later, \`tmux new -s job\` keeps it attached to a session, not this shell. (Advisory only; ECC-style non-blocking reminder.)"
fi

exit 0