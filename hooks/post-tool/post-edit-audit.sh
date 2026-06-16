#!/bin/bash
# Post-edit async audit — background scan after Edit/Write for common issues.
# Fires async so it doesn't block the user's next turn.
#
# Checks (best-effort, not blocking):
#   - console.log / debugger / alert() left in JS/TS
#   - TODO / FIXME / HACK without ticket reference
#   - Large file additions (>500 lines in single edit)
#   - .only() in test files
#
# Log: $HOME/.claude/post-edit-audit.log
# Bypass: CLAUDE_DISABLED_HOOKS=post-edit-audit

set -uo pipefail

HOOK_ID="post-edit-audit"
# Post-edit doesn't honor PROFILE=off (matches original — soft advisory).
# shellcheck disable=SC2034  # read by _lib.sh hook_init (cross-file; shellcheck runs without -x)
HOOK_HONOR_PROFILE_OFF=0
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

LOG="$HOME/.claude/post-edit-audit.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

# Extract file path from Edit/Write tool_input
FILE=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || exit 0
[ -z "$FILE" ] && exit 0

TS=$(date '+%Y-%m-%dT%H:%M:%S')
ISSUES=""

# Check 1: console.log / debugger / alert in JS/TS
if [[ "$FILE" =~ \.(js|ts|jsx|tsx|mjs|cjs)$ ]]; then
  if [ -f "$FILE" ]; then
    BAD=$(grep -nE 'console\.(log|warn|error|debug)\(|debugger;?|alert\(' "$FILE" 2>/dev/null | head -5)
    if [ -n "$BAD" ]; then
      ISSUES="${ISSUES}LEFT_BEHIND:${BAD//$'\n'/; }; "
    fi
  fi
fi

# Check 2: TODO/FIXME/HACK without reference
if [ -f "$FILE" ]; then
  BAD_TODO=$(grep -nE 'TODO[[:space:]]*\(|FIXME[[:space:]]*\(|HACK[[:space:]]*\(' "$FILE" 2>/dev/null | head -3)
  if [ -n "$BAD_TODO" ]; then
    ISSUES="${ISSUES}UNREFERENCED_TODO:${BAD_TODO//$'\n'/; }; "
  fi
fi

# Check 3: .only() in test files
if [[ "$FILE" =~ \.(test|spec)\.(js|ts|jsx|tsx)$ ]]; then
  if [ -f "$FILE" ]; then
    ONLY=$(grep -nE '\.(only|skip)\(' "$FILE" 2>/dev/null | head -3)
    if [ -n "$ONLY" ]; then
      ISSUES="${ISSUES}TEST_ONLY:${ONLY//$'\n'/; }; "
    fi
  fi
fi

# Check 4: large additions
if [ -f "$FILE" ]; then
  LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)
  if [ "$LINES" -gt 500 ]; then
    ISSUES="${ISSUES}LARGE_FILE:${LINES}lines; "
  fi
fi

# Append to log
if [ -n "$ISSUES" ]; then
  printf '%s\t%s\t%s\t%s\n' "$TS" "$SID" "$FILE" "$ISSUES" >> "$LOG"
  # Emit a terminal notification (non-blocking advisory)
  printf '\033]9;%s\007' "post-edit audit: issues in $FILE" >&2
fi

exit 0
