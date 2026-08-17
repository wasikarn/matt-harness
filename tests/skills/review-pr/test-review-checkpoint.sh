#!/usr/bin/env bash
# Unit tests for write-review-checkpoint.sh / read-review-checkpoint.sh — the
# intermediate state-checkpoint pair the 3-skill review-pr chain (review-pr ->
# review-pr-tier -> review-pr-finish) uses to survive a compaction event
# between skill invocations. Every stop case asserts BOTH the exit code AND
# the reason token (not exit code alone), same discipline as
# test-should-continue-loop.sh.
#
# Also asserts (per a plan-reviewer High finding, 2026-08-17): the writer's
# REAL stdout path is never "review-pr-"-prefixed. A version of this test
# that only hardcodes a "review-checkpoint-42.json" fixture filename in
# test-convergence-merge-gate.sh (that test also exists — see there) never
# calls the real writer, so it would stay green even if a future refactor to
# write-review-checkpoint.sh silently reintroduced the "review-pr-"-prefixed
# collision correction #1 already caught once during planning. This
# assertion is what makes the regression durable rather than a copied
# string.
#
# Run standalone: bash tests/skills/review-pr/test-review-checkpoint.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WRITE="$ROOT/skills/review-pr/scripts/write-review-checkpoint.sh"
READ="$ROOT/skills/review-pr/scripts/read-review-checkpoint.sh"

pass=0
fail=0

STATEDIR="$(mktemp -d "${TMPDIR:-/tmp}/test-review-checkpoint.XXXXXX")"
cleanup() { [ -n "${STATEDIR:-}" ] && trash "$STATEDIR" 2>/dev/null; }
trap cleanup EXIT

SHA="abc123"

assert_eq() {
  local desc="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc: expected '$expected', got '$actual'" >&2
    fail=$((fail + 1))
  fi
}

# write_payload <file> <json> — writes a payload fixture.
write_payload() { printf '%s' "$2" > "$1"; }

# do_write <phase> <sha> <payload_json> — invokes the writer, captures exit
# code + the printed path. Sets $W_EXIT and $W_PATH.
do_write() {
  local phase="$1" sha="$2" payload="$3"
  local pf out
  pf="$STATEDIR/payload-$$.json"
  write_payload "$pf" "$payload"
  out=$(REVIEW_PR_STATE_DIR="$STATEDIR" bash "$WRITE" "$phase" "$sha" "" "$pf" 2>/dev/null)
  W_EXIT=$?
  W_PATH="$out"
  command rm -f "$pf" 2>/dev/null
}

# do_read <expected_phase> <expected_sha> — invokes the reader, captures exit
# code + reason (stop path) or the JSON (ok path). Sets $R_EXIT, $R_REASON,
# $R_JSON.
do_read() {
  local phase="$1" sha="$2"
  local out first rest
  out=$(REVIEW_PR_STATE_DIR="$STATEDIR" bash "$READ" "$phase" "$sha" 2>/dev/null)
  R_EXIT=$?
  first=$(printf '%s\n' "$out" | sed -n '1p')
  rest=$(printf '%s\n' "$out" | sed -n '2,$p')
  if [ "$first" = "ok" ]; then
    R_REASON=""
    R_JSON="$rest"
  else
    R_REASON="$(printf '%s\n' "$rest" | sed -n 's/^reason=//p')"
    R_JSON=""
  fi
}

reset_state() { command rm -f "$STATEDIR/review-checkpoint-last.json" 2>/dev/null || true; }

# --- Case 1: filename-structure assertion — the writer's real output path
# must never start with "review-pr-" (would collide with
# convergence-merge-gate.sh's review-pr-*.json glob and permanently block
# merges). Checked against the REAL script's actual stdout, not a hardcoded
# string, per the plan-reviewer finding this test exists to close. ---
reset_state
do_write 2 "$SHA" '{"base_sha":"deadbeef","jira_ticket":null}'
assert_eq "case1: phase-2 write succeeds" "$W_EXIT" "0"
case "$(basename "$W_PATH")" in
  review-pr-*)
    echo "  ❌ case1: writer's output path '$W_PATH' starts with 'review-pr-' — would collide with convergence-merge-gate.sh's glob" >&2
    fail=$((fail + 1))
    ;;
  *)
    echo "  ✅ case1: writer's output path does not start with 'review-pr-'"
    pass=$((pass + 1))
    ;;
esac

# --- Case 2: merge-not-clobber — a phase-4 write must preserve phase-2's
# base_sha, not overwrite the file wholesale. ---
reset_state
do_write 2 "$SHA" '{"base_sha":"deadbeef","jira_ticket":null}'
do_write 4 "$SHA" '{"agent_findings":[{"a":1}],"dispatch_failures":""}'
assert_eq "case2: phase-4 write succeeds" "$W_EXIT" "0"
GOT_BASE_SHA=$(python3 -c "import json; print(json.load(open('$STATEDIR/review-checkpoint-last.json'))['base_sha'])")
assert_eq "case2: base_sha survives the phase-4 merge (not clobbered)" "$GOT_BASE_SHA" "deadbeef"

# --- Case 3: happy path — write through phase 5, read back with matching
# expected_phase + sha -> ok. ---
reset_state
do_write 2 "$SHA" '{"base_sha":"deadbeef","jira_ticket":null}'
do_write 4 "$SHA" '{"agent_findings":[],"dispatch_failures":""}'
do_write 5 "$SHA" '{"tier_list":[{"file":"a.ts"}]}'
do_read 5 "$SHA"
assert_eq "case3: happy path (exit)" "$R_EXIT" "0"
assert_eq "case3: happy path (no reason)" "$R_REASON" ""

# --- Case 4: missing-checkpoint (no file at all) ---
reset_state
do_read 5 "$SHA"
assert_eq "case4: missing checkpoint (exit)" "$R_EXIT" "1"
assert_eq "case4: missing checkpoint (reason)" "$R_REASON" "missing-checkpoint"

# --- Case 5: malformed-checkpoint (not JSON, and valid-JSON-non-object) ---
reset_state
printf 'not json at all' > "$STATEDIR/review-checkpoint-last.json"
do_read 5 "$SHA"
assert_eq "case5a: corrupt JSON (exit)" "$R_EXIT" "1"
assert_eq "case5a: corrupt JSON (reason)" "$R_REASON" "malformed-checkpoint"

for payload in '[]' '"hello"' 'null' '42'; do
  printf '%s' "$payload" > "$STATEDIR/review-checkpoint-last.json"
  do_read 5 "$SHA"
  assert_eq "case5b: non-object JSON ($payload) (exit)" "$R_EXIT" "1"
  assert_eq "case5b: non-object JSON ($payload) (reason)" "$R_REASON" "malformed-checkpoint"
done

# --- Case 6: stale-checkpoint-phase — EXACT equality, not >=. A checkpoint
# left at phase=5 by a completed PRIOR review (same branch, HEAD unmoved)
# must still reject a caller expecting phase=4 -- this is the live hole a >=
# comparison would leave open, found by the plan-reviewer pass. ---
reset_state
do_write 2 "$SHA" '{"base_sha":"deadbeef","jira_ticket":null}'
do_write 4 "$SHA" '{"agent_findings":[],"dispatch_failures":""}'
do_write 5 "$SHA" '{"tier_list":[]}'
do_read 4 "$SHA"
assert_eq "case6: phase=5 on disk, caller expects 4 -> stop (exit)" "$R_EXIT" "1"
assert_eq "case6: phase=5 on disk, caller expects 4 -> stale-checkpoint-phase, not ok" "$R_REASON" "stale-checkpoint-phase"

# --- Case 7: stale-sha — head_sha on disk differs from what the caller holds ---
reset_state
do_write 2 "$SHA" '{"base_sha":"deadbeef","jira_ticket":null}'
do_read 2 "different-sha"
assert_eq "case7: sha mismatch (exit)" "$R_EXIT" "1"
assert_eq "case7: sha mismatch (reason)" "$R_REASON" "stale-sha"

# --- Case 8: malformed-checkpoint-fields — a required field for the
# expected phase is missing or the wrong type. ---
reset_state
do_write 2 "$SHA" '{"base_sha":"deadbeef","jira_ticket":null}'
do_read 4 "$SHA"
assert_eq "case8a: phase-4 fields required but only phase-2 written (exit)" "$R_EXIT" "1"
assert_eq "case8a: phase-4 fields required but only phase-2 written (reason)" "$R_REASON" "stale-checkpoint-phase"
# (phase mismatch fires before the field check, by design — first-match-wins,
# same as should-continue-loop.sh's ordering)

reset_state
do_write 2 "$SHA" '{"base_sha":"deadbeef","jira_ticket":null}'
do_write 4 "$SHA" '{"agent_findings":"not-a-list","dispatch_failures":""}'
do_read 4 "$SHA"
assert_eq "case8b: agent_findings wrong type (exit)" "$R_EXIT" "1"
assert_eq "case8b: agent_findings wrong type (reason)" "$R_REASON" "malformed-checkpoint-fields"

echo ""
echo "=== review-checkpoint: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
