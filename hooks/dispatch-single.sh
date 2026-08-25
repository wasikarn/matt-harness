#!/usr/bin/env bash
# Thin profile/kill-switch filter for every non-PreToolUse hook (SessionStart,
# UserPromptSubmit, Stop, SessionEnd, InstructionsLoaded). PreToolUse gates
# never route through here -- see dispatch-pretooluse.sh, which has no
# profile concept at all (every PreToolUse hook today is a deny-gate, always
# on by construction, not tiered).
#
# Usage: dispatch-single.sh <id> <tier> <real-script-path> [args passed to
# the real script -- none of the current 19 registrations pass any, but this
# keeps the wrapper transparent if a future one does].
#
# Each registration keeps its own hooks.json entry (async/timeout/matcher
# attributes untouched) -- this only inserts a filter in front of the
# "command" the entry already ran, so per-hook async/timeout semantics
# (e.g. stop:cost-tracker's async:true vs stop:stale-task-nudge's synchronous
# same-turn requirement) are preserved exactly as today.
#
# Tiers, ordinal: minimal(0) < standard(1) < strict(2). An entry fires when
# its own tier <= $MH_HOOK_PROFILE's tier. Default profile is "strict" so an
# unset env var reproduces today's exact behavior -- nothing was ever
# filtered before this ticket, so the default must keep it that way.
set -uo pipefail

_id="$1"; _tier="$2"; _script="$3"; shift 3 || true

_rank() {
  case "$1" in
    minimal) echo 0 ;;
    standard) echo 1 ;;
    strict) echo 2 ;;
    *) echo 0 ;;
  esac
}

IFS=',' read -ra _disabled <<< "${MH_DISABLED_HOOKS:-}"
for _d in "${_disabled[@]}"; do
  [ "$_d" = "$_id" ] && exit 0
done

_current="${MH_HOOK_PROFILE:-strict}"
if [ "$(_rank "$_tier")" -gt "$(_rank "$_current")" ]; then
  exit 0
fi

exec bash "$_script" "$@"
