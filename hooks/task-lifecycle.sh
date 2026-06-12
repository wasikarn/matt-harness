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
# Current scope (v2): log-only for TeammateIdle + TaskCreated. TaskCompleted
# has enforcement as of 2026-06-12 (Phase 2 F7).
#
# Enforcement (Phase 2 F7, 2026-06-12): TaskCompleted gates test-claim
# completion. A teammate that claims "tests pass" / "pytest" / "npm test" /
# "cargo test" / "go test" / "tsc" / "pnpm test" in task_subject or
# task_description, but does NOT include a runnable `validation_command:`
# field, is blocked from completing (exit 2 + stderr feedback). This is
# the post-execution half of the quality pipeline; /team-build's plan
# approval filter (F10) is the pre-execution half. Convention is
# DIFFERENT from PreToolUse: TaskCompleted uses exit 2 + stderr
# (per https://code.claude.com/docs/en/hooks "TaskCompleted" section,
# verified 2026-06-12), NOT exit 0 + JSON `permissionDecision` like
# PreToolUse gates. Exit 2 sends stderr as feedback to the teammate;
# exit 1 is non-blocking and execution continues.
#
# Schema is observable in ~/.claude/team-events/*.jsonl: session_id /
# transcript_path / cwd / hook_event_name / task_id / task_subject /
# task_description (verified 2026-05-20, 410 events / 4 days). The
# `validation_command:` field is custom — teammates that opt into
# passing the gate should include it in the task description body
# (e.g. "validation_command: pytest tests/test_x.py -v").
#
# Deferred (still log-only, add when pain demonstrates need):
#   - TaskCreated     block if description < 30 chars (vendor: "Size tasks appropriately" — too small) or
#                     overlapping file paths across in-progress tasks (vendor: "Avoid file conflicts")
#   - TeammateIdle    block if pending unblocked tasks remain (vendor: "Wait for teammates" — keep working)
#
# Failure mode: TeammateIdle + TaskCreated remain silent (exit 0, log-only).
# TaskCompleted enforces test-claim gate (exit 2 + stderr if claim found
# without validation_command). Always log before exit so the journal
# captures both pass-through and blocked attempts.

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

# Phase 2 F7 enforcement — TaskCompleted test-claim gate.
# Vendor convention: TaskCompleted uses exit 2 + stderr feedback to block
# (per https://code.claude.com/docs/en/hooks § TaskCompleted). Exit 0 = pass,
# exit 1 = non-blocking error (treated as pass-through), exit 2 = block +
# stderr-as-feedback. Distinct from PreToolUse, which uses exit 0 + JSON
# `permissionDecision` on stdout.
#
# Trigger conditions (all must hold):
#   1. hook_event_name == "TaskCompleted"
#   2. task_subject OR task_description matches a test-claim keyword
#   3. NO `validation_command:` field present in either field
#
# Pass-through (exit 0) when:
#   - event is not TaskCompleted (TeammateIdle / TaskCreated stay log-only)
#   - no test-claim keyword present
#   - test-claim keyword present AND validation_command: field is present
#
# Phase 2.3 escape hatch (P2.3, 2026-06-12): the operator can opt OUT of
# enforcement on a per-session basis by setting KBG_ENFORCE_TASK_COMPLETED=0.
# Default is ON (preserves F7's always-on posture + the 12 tests in
# test-critical-hooks.sh that depend on it). Use case: an operator wants
# pure L2 advisory mode (log + journal only, no block) for a session where
# they trust the teammate chain to surface test-claim gaps another way.
# Setting KBG_ENFORCE_TASK_COMPLETED=0 downgrades F7 to log-only for that
# session — the event is still journaled so Phase 4 observe.py still sees
# the gap, but the gate does NOT exit 2. Any other value (unset, "", "1",
# "false", etc.) keeps enforcement ON. ADR 0002 L2/L3 — L2 is the default;
# this env var is the L3 escape hatch.
ENFORCE_TASK_COMPLETED=1
if [ "${KBG_ENFORCE_TASK_COMPLETED:-1}" = "0" ]; then
  ENFORCE_TASK_COMPLETED=0
fi

if [ "$EVENT" = "TaskCompleted" ] && [ "$ENFORCE_TASK_COMPLETED" = 1 ]; then
  TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // ""' 2>/dev/null)
  TASK_DESC=$(printf '%s' "$INPUT" | jq -r '.task_description // ""' 2>/dev/null)
  CLAIM_TEXT=" ${TASK_SUBJECT} ${TASK_DESC} "

  # Test-claim keywords. Case-insensitive (`-i`). Anchored at non-word
  # boundaries so substring matches don't false-positive (e.g. "jest" alone
  # would otherwise match "majestic" / "jesting" / "jestful" in general prose).
  # Multi-word patterns (pytest, npm test, etc.) are safe from substring matches
  # because the second token follows `[[:space:]]+`; bare keywords (jest, tsc)
  # get the explicit boundary class. CLAIM_TEXT is pre-padded with spaces
  # so the boundary class can match at the start/end of subject/description
  # strings (BSD grep -E has no \b word-boundary; the pad + non-word class
  # is the portable equivalent).
  TEST_CLAIM_REGEX='(tests[[:space:]]+pass|npm[[:space:]]+test|cargo[[:space:]]+test|go[[:space:]]+test|tsc[[:space:]]+--noEmit|pnpm[[:space:]]+test|yarn[[:space:]]+test|[^a-zA-Z0-9_](pytest|jest|tsc)[^a-zA-Z0-9_])'

  if printf '%s' "$CLAIM_TEXT" | /usr/bin/grep -iEq "$TEST_CLAIM_REGEX"; then
    # Claim found. Look for the validation_command: field (case-insensitive,
    # tolerates "Validation Command:" / "validation_command: " / etc.).
    if ! printf '%s' "$CLAIM_TEXT" | /usr/bin/grep -iEq 'validation[_[:space:]]command[[:space:]]*:'; then
      # Block. Send stderr feedback to the teammate; the runtime feeds
      # stderr back as the rejection reason. Exit 2 = block per vendor spec.
      cat >&2 <<EOF
TASK-GATE: completion claimed test execution ("tests pass" / "pytest" / "npm test" / "cargo test" / "go test" / "tsc" / "pnpm test" / "yarn test" / "jest") but no \`validation_command:\` field is present in the task subject or description.

Add a runnable \`validation_command: <cmd>\` line to the task description (e.g. \`validation_command: pytest tests/test_x.py -v\`) and re-trigger TaskCompleted. The validation command will be journaled for post-build review.

This gate is Phase 2 F7 (audit 2026-06-12). See .claude/hooks/task-lifecycle.sh for the keyword regex and /team-build for the spawn-prompt template that includes the validation_command field by default.
EOF
      exit 2
    fi
  fi
fi

exit 0
