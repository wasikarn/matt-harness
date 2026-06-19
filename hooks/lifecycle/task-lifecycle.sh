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
# Embedding convention — plan_slug: / task_id:
# Teammates that opt into task board tracking should include these fields in
# the task description (same embedding style as validation_command:):
#   plan_slug: <plan-directory-name>
#   task_id:   <task-key-in-board.json>
# Example:
#   plan_slug: health-endpoint
#   task_id: API-1
# The hook extracts these via case-insensitive grep over task_subject +
# task_description, then sources scripts/task_board_lib.sh to update the
# runtime board. Missing fields = no board update (backward compatible).
#
# Deferred (still log-only, add when pain demonstrates need):
#   - TaskCreated     block if description < 30 chars (vendor: "Size tasks appropriately" — too small) or
#                     overlapping file paths across in-progress tasks (vendor: "Avoid file conflicts")
#   - TeammateIdle    block (exit 2) if pending unblocked tasks remain (vendor: "Wait for
#                     teammates" — keep working) — IMPLEMENTED via heartbeat scan (Phase 3,
#                     2026-06-12). Inverse case: when the board shows ALL tasks completed,
#                     journal a teammate_teardown_ready advisory (exit 0) so the lead reaps
#                     idle teammates via /team-build Step 8 instead of leaving them to linger.
#
# Failure mode: TaskCreated stays silent (exit 0, log-only). TeammateIdle exits 2 on
# stale-heartbeat-with-pending, journals teammate_teardown_ready when the build is
# complete, else exit 0.
# TaskCompleted enforces test-claim gate (exit 2 + stderr if claim found
# without validation_command). Always log before exit so the journal
# captures both pass-through and blocked attempts.

set -u

HOOK_ID="task-lifecycle"
# P0: fail loud if _lib.sh missing — undefined functions would silently exit 0
source "$(dirname "$0")/../_lib.sh" || {
    echo "[task-lifecycle] ERROR: cannot source _lib.sh" >&2
    exit 1
}
set -o pipefail
hook_init "$HOOK_ID" || exit 0

# Extract event name from stdin JSON (vendor canonical: hook_event_name field).
# Uses jq for consistency with the other hooks; falls back to "unknown" on
# parse failure or missing field.
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // "unknown"' 2>/dev/null)
EVENT="${EVENT:-unknown}"

LOG_DIR="${HOME}/.claude/team-events"
LOG_FILE="${LOG_DIR}/$(date -u +%Y-%m-%d).jsonl"
# P0: fail loud on unwritable log dir — silent exit 0 drops events
mkdir -p "$LOG_DIR" || {
    echo "[task-lifecycle] ERROR: cannot create log dir $LOG_DIR" >&2
    exit 1
}

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

# [POLYFILL] Task board integration — helpers
_kbg_extract_field() {
  local text="$1" field="$2"
  # P0: anchor with word boundary so "some_plan_slug:" doesn't match field "plan_slug"
  printf '%s' "$text" | grep -iE "(^|[[:space:]])${field}[[:space:]]*:" | head -1 | sed -E "s/.*(^|[[:space:]])${field}[[:space:]]*:[[:space:]]*//I; s/[[:space:]]+$//"
}

_kbg_heartbeat_stale() {
  local file="$1"
  local threshold="${2:-300}"
  python3 -c 'import datetime, json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    ts = data.get("last_heartbeat", "")
    if not ts:
        sys.exit(1)
    ts = ts.replace("Z", "+00:00")
    hb = datetime.datetime.fromisoformat(ts)
    now = datetime.datetime.now(datetime.timezone.utc)
    diff = (now - hb).total_seconds()
    sys.exit(0 if diff > int(sys.argv[2]) else 1)
except Exception:
    sys.exit(1)
  # P0: removed stderr suppression — python3 failures must propagate as errors
' "$file" "$threshold"
}

# [POLYFILL] Task board integration — TaskCreated
if [ "$EVENT" = "TaskCreated" ]; then
  TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // ""' 2>/dev/null)
  TASK_DESC=$(printf '%s' "$INPUT" | jq -r '.task_description // ""' 2>/dev/null)
  TASK_TEXT=" ${TASK_SUBJECT} ${TASK_DESC} "
  PLAN_SLUG=$(_kbg_extract_field "$TASK_TEXT" "plan_slug")
  TID=$(_kbg_extract_field "$TASK_TEXT" "task_id")

  if [ -n "$PLAN_SLUG" ] && [ -n "$TID" ]; then
    TASK_BOARD_LIB="$(dirname "$0")/../../scripts/task_board_lib.sh"
    if [ -f "$TASK_BOARD_LIB" ]; then
      # shellcheck source=../../scripts/task_board_lib.sh
      source "$TASK_BOARD_LIB"
      PLAN_DIR="${HOME}/.claude/tasks/${PLAN_SLUG}"
      if [ -f "${PLAN_DIR}/board.json" ]; then
        # P0: timeout 10s (was 5s) to match Python default and avoid flaky timeouts under load
        if kbg_lock_acquire "$PLAN_DIR" 10; then
          if BOARD=$(kbg_board_read "$PLAN_DIR") && [ -n "$BOARD" ]; then
            NEW_BOARD=$(printf '%s' "$BOARD" | jq --arg tid "$TID" --arg now "$TS" '
              if .tasks[$tid] and .tasks[$tid].status == "pending" then
                .tasks[$tid].status = "in_progress"
                | .tasks[$tid].claimed_at = $now
                | .updated_at = $now
              else
                .
              end
            ')
            kbg_board_write "$PLAN_DIR" "$NEW_BOARD"
          fi
          # P0: explicit release before else path; EXIT trap is backstop, not primary
          kbg_lock_release "$PLAN_DIR"
        else
          # P0: lock timeout was silently skipping board update
          echo "[task-lifecycle] WARN: lock timeout for $PLAN_DIR; skipping board update for $TID" >&2
        fi
      fi
    fi
  fi
fi

# Exit reason vocabulary (ADR 0002 §L12 — named for observability, not for automation).
# Only "blocked" is enforced today; the others are future-compatible placeholders.
# kbg never runs autonomous loops (ADR 0002), so stalled/degrading/timeout are
# not yet wired but are reserved so any future bounded loop can adopt the taxonomy.
#   blocked   — explicit human-actionable blocker (e.g. test-claim without validation_command)
#   stalled   — (future) no-progress detected across N iterations
#   degrading — (future) output quality declining
#   timeout   — (future) wall-clock limit exceeded
#   complete  — exit 0 path (normal completion)

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
TASK-GATE[blocked]: completion claimed test execution ("tests pass" / "pytest" / "npm test" / "cargo test" / "go test" / "tsc" / "pnpm test" / "yarn test" / "jest") but no \`validation_command:\` field is present in the task subject or description.

Add a runnable \`validation_command: <cmd>\` line to the task description (e.g. \`validation_command: pytest tests/test_x.py -v\`) and re-trigger TaskCompleted. The validation command will be journaled for post-build review.

This gate is Phase 2 F7 (audit 2026-06-12). See hooks/lifecycle/task-lifecycle.sh for the keyword regex and /team-build for the spawn-prompt template that includes the validation_command field by default.
EOF
      exit 2
    fi
  fi
fi

# [POLYFILL] Task board integration — TaskCompleted
if [ "$EVENT" = "TaskCompleted" ]; then
  # Re-use TASK_SUBJECT / TASK_DESC if already parsed in F7 block
  if [ -z "${TASK_SUBJECT:-}" ] || [ -z "${TASK_DESC:-}" ]; then
    TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // ""' 2>/dev/null)
    TASK_DESC=$(printf '%s' "$INPUT" | jq -r '.task_description // ""' 2>/dev/null)
  fi
  TASK_TEXT=" ${TASK_SUBJECT} ${TASK_DESC} "
  PLAN_SLUG=$(_kbg_extract_field "$TASK_TEXT" "plan_slug")
  TID=$(_kbg_extract_field "$TASK_TEXT" "task_id")

  if [ -n "$PLAN_SLUG" ] && [ -n "$TID" ]; then
    TASK_BOARD_LIB="$(dirname "$0")/../../scripts/task_board_lib.sh"
    if [ -f "$TASK_BOARD_LIB" ]; then
      # shellcheck source=../../scripts/task_board_lib.sh
      source "$TASK_BOARD_LIB"
      PLAN_DIR="${HOME}/.claude/tasks/${PLAN_SLUG}"
      if [ -f "${PLAN_DIR}/board.json" ]; then
        # P0: timeout 10s (was 5s) to match Python default and avoid flaky timeouts under load
        if kbg_lock_acquire "$PLAN_DIR" 10; then
          if BOARD=$(kbg_board_read "$PLAN_DIR") && [ -n "$BOARD" ]; then
            NEW_BOARD=$(printf '%s' "$BOARD" | jq --arg tid "$TID" --arg now "$TS" '
              if .tasks[$tid] then
                .tasks[$tid].status = "completed"
                | .tasks[$tid].completed_at = $now
                | .updated_at = $now
              else
                .
              end
            ')
            kbg_board_write "$PLAN_DIR" "$NEW_BOARD"
            kbg_recompute_blocked "$PLAN_DIR"
          fi
          # P0: explicit release before else path; EXIT trap is backstop, not primary
          kbg_lock_release "$PLAN_DIR"
        else
          # P0: lock timeout was silently skipping board update
          echo "[task-lifecycle] WARN: lock timeout for $PLAN_DIR; skipping board update for $TID" >&2
        fi
      fi
    fi
  fi
fi

# [POLYFILL] Task board integration — TeammateIdle
if [ "$EVENT" = "TeammateIdle" ]; then
  TASK_TEXT="$INPUT"
  PLAN_SLUG=$(_kbg_extract_field "$TASK_TEXT" "plan_slug")
  CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)

  IDLE_BLOCKED=0
  IDLE_PLAN=""
  TEARDOWN_READY=0
  TEARDOWN_PLAN=""

  _kbg_check_plan_idle() {
    local pdir="$1"
    local hb_dir="${pdir}/heartbeat"
    [ -d "$hb_dir" ] || return 1
    local any_stale=0
    for hb in "$hb_dir"/*.json; do
      [ -f "$hb" ] || continue
      if _kbg_heartbeat_stale "$hb" 300; then
        any_stale=1
        break
      fi
    done
    if [ "$any_stale" = 1 ]; then
      local bfile="${pdir}/board.json"
      if [ -f "$bfile" ]; then
        if jq -e '([.tasks[]? | select(.status == "pending")] | length) > 0' "$bfile" >/dev/null 2>&1; then
          return 0
        fi
      fi
    fi
    return 1
  }

  # Teardown-ready advisory (ADR 0002 — journal-only, NEVER stops the teammate).
  # When a teammate goes idle and the board shows every task completed (nothing
  # left pending/in_progress/blocked), the build is done. We journal a
  # teammate_teardown_ready signal so the lead (/team-build Step 8) and
  # /wave-status can observe "build complete, teammates idle → reap" instead of
  # teammates lingering forever on a SendMessage that never arrives. The actual
  # TaskStop is the lead's job — a hook that stopped agents itself would be the
  # autonomous mutation the autonomy invariant forbids.
  _kbg_plan_complete() {
    local bfile="$1/board.json"
    [ -f "$bfile" ] || return 1
    jq -e '(.tasks | length) > 0 and ([.tasks[]? | select(.status != "completed")] | length) == 0' "$bfile" >/dev/null 2>&1
  }

  if [ -n "$PLAN_SLUG" ]; then
    PLAN_DIR="${HOME}/.claude/tasks/${PLAN_SLUG}"
    if _kbg_check_plan_idle "$PLAN_DIR"; then
      IDLE_BLOCKED=1
      IDLE_PLAN="$PLAN_SLUG"
    elif _kbg_plan_complete "$PLAN_DIR"; then
      TEARDOWN_READY=1
      TEARDOWN_PLAN="$PLAN_SLUG"
    fi
  elif [ -n "$CWD" ]; then
    TASKS_DIR="${CWD}/.claude/tasks"
    if [ -d "$TASKS_DIR" ]; then
      for pdir in "$TASKS_DIR"/*; do
        [ -d "$pdir" ] || continue
        # SC2168: 'local' is only valid in functions; use plain assignment here
        pname=$(basename "$pdir")
        if _kbg_check_plan_idle "$pdir"; then
          IDLE_BLOCKED=1
          IDLE_PLAN="$pname"
          break
        elif _kbg_plan_complete "$pdir"; then
          # Note, don't break: a later plan may still have pending work to block on.
          TEARDOWN_READY=1
          TEARDOWN_PLAN="$pname"
        fi
      done
    fi
  fi

  if [ "$IDLE_BLOCKED" = 1 ]; then
    cat >&2 <<EOF
TeammateIdle blocked: stale heartbeat detected for plan '${IDLE_PLAN}' and pending unblocked tasks remain. Resume work or explicitly release your claimed task.
EOF
    exit 2
  elif [ "$TEARDOWN_READY" = 1 ]; then
    # Advisory only: the lead reaps via /team-build Step 8; we never stop the teammate here.
    journal_append "$HOOK_ID" "teammate_teardown_ready" "$(jq -nc --arg plan "$TEARDOWN_PLAN" '{plan: $plan, trigger: "TeammateIdle"}')" >/dev/null 2>&1 || true
  fi
fi

exit 0
