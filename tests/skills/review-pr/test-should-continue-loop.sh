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

# --- Case 4c: state file is valid JSON but not a top-level object (array,
# string, null, number) -> stop, malformed-state, not an uncaught exception.
# Found by a compliance-audit adversarial pass (2026-08-14): these parse fine
# under json.load but have no .get() to read fields from. ---
for payload in '[]' '"hello"' 'null' '42'; do
  printf '%s' "$payload" > "$STATE_FILE"
  assert_stop "case4c: non-object JSON ($payload) -> malformed-state, not a crash" "malformed-state"
done

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

# --- Case 12: finding_files present but wrong type (not a list, not null) ->
# stop, malformed-finding-files -- distinct from absent/empty, which are not
# errors (case8/case9). Found by a deep-audit pass (2026-08-14): the original
# code silently coerced ANY non-list value to [] and kept going at round<2. ---
for round_ceil_check in 0 1 2; do
  for payload in '"corrupted"' '{}' '42' 'true'; do
    printf '{"last_sha":"%s","review_mode":"own-branch","round":%s,"force_human":false,"convergence_state":"progressing","finding_files":%s}' \
      "$SHA" "$round_ceil_check" "$payload" > "$STATE_FILE"
    assert_stop "case12: finding_files=$payload at round=$round_ceil_check -> malformed-finding-files" "malformed-finding-files"
  done
done

# --- Case 13: verdict persistence (2026-08-21, feeds gate:skill:review-pr-loop).
# The script writes loop_decision/loop_reason back into the state file after
# printing — and MUST NOT change the stdout/exit contract even when it can't. ---

# 13a: stop verdict persisted with its reason token
write "$(base 5 true progressing '["a.ts"]')"
run
assert_eq "case13a: ceiling stop persists loop_decision" \
  "$(python3 -c 'import json;d=json.load(open("'"$STATE_FILE"'"));print(d.get("loop_decision"),d.get("loop_reason"))')" \
  "stop ceiling"

# 13b: continue verdict persisted with empty reason
write "$(base 1 false progressing '["a.ts"]')"
run
assert_eq "case13b: continue persists loop_decision" \
  "$(python3 -c 'import json;d=json.load(open("'"$STATE_FILE"'"));print(d.get("loop_decision"),repr(d.get("loop_reason")))')" \
  "continue ''"

# 13c: malformed state file is NOT rewritten (persist skipped, bytes identical)
write '{broken json'
before="$(cat "$STATE_FILE")"
run
assert_eq "case13c: malformed state left untouched (exit)" "$GOT_EXIT" "1"
assert_eq "case13c: malformed state left untouched (reason)" "$GOT_REASON" "malformed-state"
assert_eq "case13c: malformed state left untouched (bytes)" "$(cat "$STATE_FILE")" "$before"

# 13e: missing state — persist must not conjure a file into existence
rm -f "$STATE_FILE"
run
assert_eq "case13e: missing state still stops (exit)" "$GOT_EXIT" "1"
assert_eq "case13e: missing state still stops (reason)" "$GOT_REASON" "missing-state"
if [ -f "$STATE_FILE" ]; then created="yes"; else created="no"; fi
assert_eq "case13e: persist created no file" "$created" "no"

# 13f: off-label caller (wrong sha — e.g. the read-only /review-dashboard
# passing a remote headRefOid) must NOT clobber an armed persisted verdict:
# overwriting loop_reason="regressed" with "stale-sha" would silently dis-arm
# gate:skill:review-pr-loop (blind-spot find 2026-08-22).
write "$(base 3 false regressed '["a.ts"]')"
run                    # matching sha → persists loop_decision=stop, loop_reason=regressed
run "remote-tip-sha"   # stale-sha path — stdout contract holds, persist must skip
assert_eq "case13f: stale-sha run still stops (exit)" "$GOT_EXIT" "1"
assert_eq "case13f: stale-sha run still stops (reason)" "$GOT_REASON" "stale-sha"
assert_eq "case13f: armed verdict survives an off-label caller" \
  "$(python3 -c 'import json;d=json.load(open("'"$STATE_FILE"'"));print(d.get("loop_decision"),d.get("loop_reason"))')" \
  "stop regressed"

# 13d: read-only state dir — stdout/exit contract unchanged (the plan-review
# High finding: a persist failure must never flip a continue into a stop)
write "$(base 1 false progressing '["a.ts"]')"
chmod a-w "$STATEDIR"
run
chmod u+w "$STATEDIR"
assert_eq "case13d: read-only dir, continue still continues (exit)" "$GOT_EXIT" "0"
assert_eq "case13d: read-only dir, continue still continues (reason)" "$GOT_REASON" ""

echo ""
echo "=== should-continue-loop.sh: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
