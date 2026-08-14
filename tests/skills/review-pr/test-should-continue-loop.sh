#!/usr/bin/env bash
# Unit tests for should-continue-loop.sh — the ADR 0009 bounded auto-loop's
# continue/stop decision script. Every case asserts BOTH the exit code AND
# the `reason` token (not exit code alone): a plan-reviewer pass on this
# implementation (2026-08-14) found that routing the legitimate round-ceiling
# stop through the same reason as a corrupted force_human field would
# misdirect the operator at the exact hard-stop the ADR depends on for
# correct judgment — exit-code-only assertions would not have caught that.
# Run standalone: bash tests/skills/review-pr/test-should-continue-loop.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/review-pr/scripts/should-continue-loop.sh"

pass=0
fail=0

STATEDIR="$(mktemp -d "${TMPDIR:-/tmp}/test-should-continue-loop.XXXXXX")"
cleanup() { [ -n "${STATEDIR:-}" ] && trash "$STATEDIR" 2>/dev/null; }
trap cleanup EXIT

STATE_FILE="$STATEDIR/review-last.json"
SHA="abc123"

# write <json> — replaces the state file's content for the next call.
write() { printf '%s' "$1" > "$STATE_FILE"; }

# run [expected_sha] — invokes the script, captures exit code + reason.
# Sets $GOT_EXIT and $GOT_REASON ("" when the script printed no reason line,
# i.e. the continue path).
run() {
  local expected="${1:-$SHA}"
  local out
  out=$(REVIEW_PR_STATE_DIR="$STATEDIR" bash "$SCRIPT" "$expected" 2>/dev/null)
  GOT_EXIT=$?
  GOT_REASON="$(printf '%s\n' "$out" | sed -n 's/^reason=//p')"
}

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

# assert_stop <desc> <reason> — runs, asserts exit 1 AND the reason token.
assert_stop() {
  local desc="$1" want_reason="$2"
  run
  assert_eq "$desc (exit)" "$GOT_EXIT" "1"
  assert_eq "$desc (reason)" "$GOT_REASON" "$want_reason"
}

# assert_continue <desc> — runs, asserts exit 0 and no reason line.
assert_continue() {
  local desc="$1"
  run
  assert_eq "$desc (exit)" "$GOT_EXIT" "0"
  assert_eq "$desc (reason)" "$GOT_REASON" ""
}

base() {
  # base <round> <force_human> <convergence_state> <finding_files_json>
  printf '{"last_sha":"%s","review_mode":"own-branch","round":%s,"force_human":%s,"convergence_state":"%s","finding_files":%s}' \
    "$SHA" "$1" "$2" "$3" "$4"
}

# --- Case 1: progressing + force_human=false + own-branch -> continue ---
write "$(base 2 false progressing '["a.ts"]')"
assert_continue "case1: progressing, force_human=false -> continue"

# --- Case 2: each non-progressing convergence_state -> stop, reason == state ---
for state in converged regressed churning stalled; do
  write "$(base 3 false "$state" '["a.ts"]')"
  assert_stop "case2: convergence_state=$state -> stop" "$state"
done

# --- Case 3: ceiling — progressing + force_human=true -> stop, reason=ceiling
# (NOT malformed-force-human — the plan-reviewer's High finding #1). ---
write "$(base 5 true progressing '["a.ts"]')"
assert_stop "case3: progressing + force_human=true -> ceiling, not malformed" "ceiling"

# --- Case 4: no state file at all -> stop, missing-state ---
rm_state() { command rm -f "$STATE_FILE" 2>/dev/null || true; }
rm_state
assert_stop "case4: missing state file -> missing-state" "missing-state"

# --- Case 4b: state file exists but is corrupt JSON -> stop, malformed-state ---
printf 'not json at all' > "$STATE_FILE"
assert_stop "case4b: corrupt JSON -> malformed-state" "malformed-state"

# --- Case 5: last_sha mismatch -> stop, stale-sha ---
write "$(base 2 false progressing '["a.ts"]')"
run "different-sha"
assert_eq "case5: last_sha mismatch (exit)" "$GOT_EXIT" "1"
assert_eq "case5: last_sha mismatch (reason)" "$GOT_REASON" "stale-sha"

# --- Case 6: force_human missing / non-boolean -> stop, malformed-force-human ---
printf '{"last_sha":"%s","review_mode":"own-branch","round":2,"convergence_state":"progressing","finding_files":["a.ts"]}' "$SHA" > "$STATE_FILE"
assert_stop "case6a: force_human missing -> malformed-force-human" "malformed-force-human"
printf '{"last_sha":"%s","review_mode":"own-branch","round":2,"force_human":"nope","convergence_state":"progressing","finding_files":["a.ts"]}' "$SHA" > "$STATE_FILE"
assert_stop "case6b: force_human non-boolean -> malformed-force-human" "malformed-force-human"

# --- Case 7: convergence_state missing / unrecognized -> stop, malformed-convergence-state ---
printf '{"last_sha":"%s","review_mode":"own-branch","round":2,"force_human":false,"finding_files":["a.ts"]}' "$SHA" > "$STATE_FILE"
assert_stop "case7a: convergence_state missing -> malformed-convergence-state" "malformed-convergence-state"
write "$(base 2 false bogus-state '["a.ts"]')"
assert_stop "case7b: convergence_state unrecognized -> malformed-convergence-state" "malformed-convergence-state"

# --- Case 8: non-clean (via progressing), round>=2, finding_files empty/absent
# -> stop, no-findings-nonclean (the hole the ADR doesn't name). ---
write "$(base 2 false progressing '[]')"
assert_stop "case8a: round 2, empty finding_files -> no-findings-nonclean" "no-findings-nonclean"
printf '{"last_sha":"%s","review_mode":"own-branch","round":2,"force_human":false,"convergence_state":"progressing"}' "$SHA" > "$STATE_FILE"
assert_stop "case8b: round 2, finding_files absent entirely -> no-findings-nonclean" "no-findings-nonclean"

# --- Case 9: round 1, empty finding_files -> continue (guard doesn't fire pre-round-2) ---
write "$(base 1 false progressing '[]')"
assert_continue "case9: round 1, empty finding_files -> continue (guard not yet active)"

# --- Case 10: round missing / non-integer -> stop, malformed-round ---
printf '{"last_sha":"%s","review_mode":"own-branch","force_human":false,"convergence_state":"progressing","finding_files":["a.ts"]}' "$SHA" > "$STATE_FILE"
assert_stop "case10a: round missing -> malformed-round" "malformed-round"
printf '{"last_sha":"%s","review_mode":"own-branch","round":"two","force_human":false,"convergence_state":"progressing","finding_files":["a.ts"]}' "$SHA" > "$STATE_FILE"
assert_stop "case10b: round non-integer -> malformed-round" "malformed-round"

# --- Case 11: reviewer-flow (pr-by-number) -> stop, reviewer-flow, even when
# otherwise progressing/force_human=false (the plan-reviewer's High finding #5). ---
printf '{"last_sha":"%s","review_mode":"pr-by-number","round":2,"force_human":false,"convergence_state":"progressing","finding_files":["a.ts"]}' "$SHA" > "$STATE_FILE"
assert_stop "case11: review_mode=pr-by-number -> reviewer-flow, never auto-continues" "reviewer-flow"

echo ""
echo "=== should-continue-loop.sh: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
