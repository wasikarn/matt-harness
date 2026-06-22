#!/bin/bash
# l4-act-gate.sh — the Act-layer self-launch guard (design §5 Act-layer gate + §8,
# ADR 0004). The launchd plist + kill-file live OUTSIDE the repo (~/Library/LaunchAgents
# + ~/.claude), where the repo-relative cage and the voluntary check-act subcommand
# cannot reach. This PreToolUse gate mechanically DENIES any write or launchctl
# mutation targeting them while an autonomy run is armed (autonomy_on) — so a
# self-launched loop cannot rewrite its own cadence or escape the kill-switch.
# Model discipline is not a cage.
#
# Flag-scoped: with the autonomy flag unset (every normal session) this gate exits 0
# immediately. Protected surfaces (the distinctive suffix is matched, so $HOME / ~
# variants all resolve):
#   plist   ~/Library/LaunchAgents/com.kbg.l4-launcher.plist
#   kill    ~/.claude/kbg-l4-kill
# A Slice-0 hard precondition for Slice 3 self-launch (#31): #1 is not buildable
# until this ships gauntlet-green with a real-DENY test.
#
# Bypass (normal sessions only — has no effect during an armed run, by autonomy
# immunity in _lib.sh):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=l4-act-gate

set -uo pipefail

HOOK_ID="l4-act-gate"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable

# Flag-scoped: only active inside an authorized autonomy run (single-key autonomy_on,
# design §5 F1 — armed only from a per-repo .claude/settings.local.json).
autonomy_on || exit 0

hook_require_jq
_GREP="command grep"
SEP='(^|[[:space:];&|()`])'
PLIST_SUFFIX='com.kbg.l4-launcher.plist'
KILL_SUFFIX='kbg-l4-kill'
ACT_SUFFIXES="($PLIST_SUFFIX|$KILL_SUFFIX)"

# Write/Edit/MultiEdit: deny if file_path targets the plist or kill-file.
case "$TOOL" in
  Write|Edit|MultiEdit)
    _fp=$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null) || _fp=""
    if [ -n "$_fp" ]; then
      case "$_fp" in
        *"$PLIST_SUFFIX"|*"$KILL_SUFFIX")
          hook_decision deny "autonomy run: $TOOL targets the out-of-repo launchd plist/kill-file ('$_fp') — a self-launched loop may not rewrite its own cadence or escape the kill-switch (design §8, ADR 0004). Manage the plist/kill-file out-of-band, not from inside an armed run." ;;
      esac
    fi
    ;;
esac

# Bash: deny launchctl mutations + writes to the plist/kill-file.
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null) || {
    echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
    exit 1
  }
  [ -z "$COMMAND" ] && exit 0
  STRIPPED=$(hook_strip_quoted "$COMMAND")

  # 1. launchctl mutation (load/unload/bootstrap/bootout/enable/disable) — deny while
  #    armed, regardless of target. A self-launched loop may not manage its own launchd
  #    registration (a `launchctl list` status read is NOT a mutation + stays allowed).
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "${SEP}launchctl[[:space:]]+(load|unload|bootstrap|bootout|enable|disable)"; then
    hook_decision deny "autonomy run: launchctl mutation denied — a self-launched loop may not manage its own launchd registration (design §8, ADR 0004)."
  fi

  # 2. a WRITE to the plist/kill-file: a redirection onto the suffix, or a write verb
  #    (cp/mv/rm/tee/install/dd) with the suffix as an operand. A bare read (cat/test)
  #    of the suffix is allowed — only mutations are denied.
  if printf '%s\n' "$STRIPPED" | $_GREP -qE "$ACT_SUFFIXES"; then
    if printf '%s\n' "$STRIPPED" | $_GREP -qE "[>]>?[[:space:]]*[^[:space:]]*$ACT_SUFFIXES|${SEP}(cp|mv|rm|tee|install|dd)([[:space:]]|$)"; then
      hook_decision deny "autonomy run: write to the out-of-repo launchd plist/kill-file denied — a self-launched loop may not rewrite its own cadence or escape the kill-switch (design §8, ADR 0004). Manage it out-of-band."
    fi
  fi
fi

exit 0