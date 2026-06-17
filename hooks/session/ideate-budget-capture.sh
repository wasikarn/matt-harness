#!/bin/bash
# ideate-budget-capture.sh — SessionEnd hook that counts kbg:ideate invocations
# from the session transcript and appends one JSONL row per calendar day to
# ~/.claude/state/ideate-usage.jsonl. The companion SessionStart hook
# ideate-rotate.sh reads that file and warns when the daily threshold is crossed.
#
# This is advisory-only feedback (ADR 0002 / CLAUDE.md §"LLM-judge circularity").
# It never blocks SessionEnd and never emits a permissionDecision.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=ideate-budget-capture
#
# Failure mode: silent. Always exit 0.

HOOK_ID="ideate-budget-capture"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

STATE_DIR="${HOME}/.claude/state"
USAGE_FILE="${STATE_DIR}/ideate-usage.jsonl"
mkdir -p "$STATE_DIR" || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID_VAL" ] || SESSION_ID_VAL="no-sid"

# No transcript path = nothing to count (normal for very short sessions).
[ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ] && exit 0

# Count invocations of the ideate skill. Vendor tool spans for Skill use contain
# tool_name == "Skill" and input.skill == "ideate". We also count explicit user
# utterances of "/ideate" as an invocation signal, because a user typing the
# slash command may not always reach the Skill tool in the transcript.
INVOCATIONS=$(jq -c '
  [
    .messages[]? |
    select(.type == "tool_use" and .tool_name == "Skill") |
    select(.input? .skill == "ideate")
  ] | length +
  [
    .messages[]? |
    select(.type == "user") |
    select(.content? | type == "string" and test("(^|[[:space:]])/ideate"; "i"))
  ] | length
' "$TRANSCRIPT" 2>/dev/null) || INVOCATIONS=0

[ -n "$INVOCATIONS" ] || INVOCATIONS=0
[ "$INVOCATIONS" -eq 0 ] 2>/dev/null && exit 0

DATE=$(date -u +%Y-%m-%d)

# Append the count. Collapse multiple invocations in the same session into one
# row keyed by session+date so a long ideate loop does not bloat the file, while
# still preserving per-session observability. A later jq aggregation sums them.
if ! jq -nc \
  --arg date "$DATE" \
  --arg session_id "$SESSION_ID_VAL" \
  --argjson invocations "$INVOCATIONS" \
  '{date: $date, session_id: $session_id, invocations: $invocations}' >> "$USAGE_FILE" 2>/dev/null; then
  echo "[$HOOK_ID] ERROR: failed to append ideate usage to $USAGE_FILE" >&2
fi

exit 0
