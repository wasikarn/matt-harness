#!/bin/bash
# task-lifecycle.sh — observability for agent-team lifecycle events.
#
# Wired into settings.json under TeammateIdle / TaskCreated / TaskCompleted.
# Receives JSON event payload via stdin per Claude Code hook convention.
# Event name extracted from `hook_event_name` field in stdin JSON (canonical
# per https://code.claude.com/docs/en/hooks — vendor does NOT export this
# as an env var).
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=task-lifecycle
#
# Current scope (v1): log-only, non-blocking. Foundation for future
# enforcement (exit 2 = block + send feedback to lead/teammate; exit 0 = pass).
#
# Upgrade path (add when pain demonstrates need):
#   - TaskCreated     block if description < 30 chars (vendor: "Size tasks appropriately" — too small) or
#                     overlapping file paths across in-progress tasks (vendor: "Avoid file conflicts")
#   - TaskCompleted   block if claim "tests pass" but no test command observable
#                     in event payload
#   - TeammateIdle    block if pending unblocked tasks remain (vendor: "Wait for teammates to finish" — keep working)
#
# Schema is observable in ~/.claude/team-events/*.jsonl: session_id /
# transcript_path / cwd / hook_event_name / task_id / task_subject /
# task_description (verified 2026-05-20, 410 events / 4 days). Enforcement
# remains deferred per METHODOLOGY: "build when pain demonstrates need" —
# log-only until specific failure modes warrant blocking.
#
# Failure mode: silent. Always exit 0; never block team progress.

set -u

HOOK_ID="task-lifecycle"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

# Extract event name from stdin JSON (vendor canonical: hook_event_name field).
# Uses jq for consistency with the other hooks; falls back to "unknown" on
# parse failure or missing field.
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)
EVENT="${EVENT:-unknown}"

LOG_DIR="${HOME}/.claude/team-events"
LOG_FILE="${LOG_DIR}/$(date -u +%Y-%m-%d).jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Append a structured event line. jq -c keeps the payload on one line and
# escapes everything correctly. If jq fails (malformed JSON), fall back to a
# raw-string entry so the event isn't lost.
ENTRY=$(printf '%s' "$INPUT" | jq -c --arg ts "$TS" --arg event "$EVENT" '{ts: $ts, event: $event, payload: .}' 2>/dev/null)
if [ -n "$ENTRY" ]; then
  printf '%s\n' "$ENTRY" >> "$LOG_FILE" 2>/dev/null
else
  jq -nc --arg ts "$TS" --arg event "$EVENT" --arg raw "$INPUT" \
    '{ts: $ts, event: $event, payload: {raw: $raw}}' >> "$LOG_FILE" 2>/dev/null
fi

exit 0
