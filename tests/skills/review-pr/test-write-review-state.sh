#!/usr/bin/env bash
# Unit tests for write-review-state.sh's same-file churn detection
# (convergence_state == "churning", file_streaks, churn_files) — added
# 2026-08-14 after direct forensic analysis of two real >10-round review-pr
# loops (PR #2754/session e34b6832, PR #2768/session 6e7c3bed) found the same
# root cause independently in both: a fix in round N introducing a new,
# different problem in the SAME file in round N+1, which neither the
# tier-count STALLED check nor the file-set REGRESSED check catches (a file
# already in the prior round's finding-set doesn't register as "new").
# Cases 7-10 cover `amend` mode, added the same day after direct-transcript
# root-causing of a separate defect in the same e34b6832 session: the model
# hand-edited its own state JSON twice to self-correct a round-counter bug it
# had introduced by resubmitting a round's data under a new round number just
# to fix a wrong head_sha. Cases 11-13 added by /kbg:deep-audit (2026-08-14):
# an adversarial fresh-context pass on already-shipped amend mode found it had
# no branch-match guard (own-branch amend could silently clobber a different
# branch's round) and no isinstance guard on finding_files (unlike the two
# fields next to it in the same function) — both real, evidence-backed gaps,
# not hypothetical.
# Run standalone: bash tests/skills/review-pr/test-write-review-state.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/review-pr/scripts/write-review-state.sh"
CURRENT_BRANCH="$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

pass=0
fail=0

STATEDIR="$(mktemp -d "${TMPDIR:-/tmp}/test-write-review-state.XXXXXX")"
cleanup() { [ -n "${STATEDIR:-}" ] && trash "$STATEDIR" 2>/dev/null; }
trap cleanup EXIT

FF="$STATEDIR/findings.txt"
STATE_FILE="$STATEDIR/review-last.json"

fresh_series() {
  [ -f "$STATE_FILE" ] && trash "$STATE_FILE" 2>/dev/null
  return 0
}

# Runs one round and captures the state-file JSON. Args mirror the script's
# own positional contract: crit rehunt dispatch_failures sha wt important minor findings_file
run_round() {
  REVIEW_PR_STATE_DIR="$STATEDIR" bash "$SCRIPT" "$@" > /dev/null 2>&1
}

field() {
  # field <top_level_key> [<nested_key>]  — reads a field from STATE_FILE.
  # Two explicit args, not dot-notation: a file path itself contains "."
  # (src/foo.ts), so splitting on "." would misparse the nested lookup key.
  if [ "$#" -ge 2 ]; then
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get(sys.argv[2])
v = v.get(sys.argv[3]) if isinstance(v, dict) else None
print(json.dumps(v))
' "$STATE_FILE" "$1" "$2" 2>/dev/null
  else
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(json.dumps(d.get(sys.argv[2])))
' "$STATE_FILE" "$1" 2>/dev/null
  fi
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

# --- Case 1: positive — same file, 3 consecutive rounds -> churning ---
fresh_series
printf 'src/foo.ts\n' > "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"
assert_eq "case1: round 3 same-file streak -> convergence_state=churning" "$(field convergence_state)" '"churning"'
assert_eq "case1: force_human=true on churning" "$(field force_human)" 'true'
assert_eq "case1: file_streaks records the streak at 3" "$(field file_streaks 'src/foo.ts')" '3'

# --- Case 2: negative control — same file only 2 rounds -> not churning ---
fresh_series
printf 'src/foo.ts\n' > "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"
actual="$(field convergence_state)"
if [ "$actual" != '"churning"' ]; then
  echo "  ✅ case2: round 2 same-file (streak=2, below threshold) -> not churning (got $actual)"
  pass=$((pass + 1))
else
  echo "  ❌ case2: round 2 should not be churning yet, got churning" >&2
  fail=$((fail + 1))
fi

# --- Case 3: clean-wins, fully specified — round 3 still lists the file
# (a surviving Important-only finding after Criticals clear), but is clean.
# Must NOT pass an empty findings file for round 3: that would self-prune the
# streak to {} for an unrelated reason and never exercise the `and not cl`
# guard this case is meant to test. ---
fresh_series
printf 'src/foo.ts\n' > "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"
run_round 0 clean "" sha1 "" 0 0 "$FF"   # round 3: critical=0, file still listed
assert_eq "case3: clean review wins over a live 3-round streak -> converged" "$(field convergence_state)" '"converged"'
assert_eq "case3: force_human=false on a clean review (and-not-cl guard)" "$(field force_human)" 'false'

# --- Case 4: precedence — regressed AND churning true in the same round
# -> regressed wins (more specific: PR #2632's cross-file dominant cause). ---
fresh_series
printf 'src/a.ts\n' > "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"   # round1: a.ts
run_round 1 clean "" sha1 "" 1 0 "$FF"   # round2: a.ts again (streak=2)
printf 'src/a.ts\nsrc/b.ts\n' > "$FF"     # round3: a.ts (streak->3) + NEW b.ts (regressed)
run_round 1 clean "" sha1 "" 1 0 "$FF"
assert_eq "case4: regressed takes precedence over churning" "$(field convergence_state)" '"regressed"'

# --- Case 5: round-1 reset — a fresh series (branch mismatch -> round resets
# to 1) must not inherit a stale file_streaks value from an unrelated prior
# series. ---
fresh_series
cat > "$STATE_FILE" <<'JSON'
{"branch": "some-other-branch", "round": 9, "critical_count": 1, "important_count": 0, "minor_count": 0, "file_streaks": {"src/foo.ts": 8}, "finding_files": ["src/foo.ts"]}
JSON
printf 'src/foo.ts\n' > "$FF"
run_round 1 clean "" sha1 "" 0 0 "$FF"
assert_eq "case5: fresh series (branch mismatch) resets round to 1" "$(field round)" '1'
assert_eq "case5: streak starts at 1, not inherited stale 8" "$(field file_streaks 'src/foo.ts')" '1'

# --- Case 6: mixed path format — a $WT-absolute path (leading "/") in one
# round must normalize to the same identity as a repo-relative report of the
# same file in another round, so neither a spurious `regressed` nor a
# silently-broken streak results. ---
fresh_series
printf 'src/foo.ts\n' > "$FF"
run_round 1 clean "" sha1 "" 1 0 "$FF"     # round1: repo-relative
printf '/src/foo.ts\n' > "$FF"              # round2: same file, leading-slash form
run_round 1 clean "" sha1 "" 1 0 "$FF"
assert_eq "case6: leading-slash path does not trip a spurious regressed" "$(field regressed)" 'false'
assert_eq "case6: leading-slash path still accumulates the same streak (2, not reset)" "$(field file_streaks 'src/foo.ts')" '2'

# --- Case 7: amend — correct a wrong head_sha on the round already in the
# state file, in place, without advancing round or self-comparing (the
# e34b6832/PR #2754 incident: a caller resubmitted round 9's data under round
# 10 just to fix the SHA, which compared round 9 against itself and produced
# a false stalled:true). Amend must leave round/prev_*/stalled/streak intact
# and only change last_sha. ---
fresh_series
printf 'src/foo.ts\n' > "$FF"
run_round 2 clean "" sha_r1 "" 1 0 "$FF"          # round 1 (stand-in for round 8)
run_round 1 clean "" sha_WRONG "" 2 5 "$FF"       # round 2 (stand-in for round 9), wrong sha
BEFORE_STREAK="$(field file_streaks 'src/foo.ts')"
run_round 1 clean "" sha_CORRECT "" 2 5 "$FF" amend
assert_eq "case7: amend keeps round unchanged (does not advance to 3)" "$(field round)" '2'
assert_eq "case7: amend corrects last_sha" "$(field last_sha)" '"sha_CORRECT"'
assert_eq "case7: amend does not self-compare into a false stalled" "$(field stalled)" 'false'
assert_eq "case7: amend carries prev_critical through unchanged" "$(field prev_critical_count)" '2'
assert_eq "case7: amend does not double-count the file streak" "$(field file_streaks 'src/foo.ts')" "$BEFORE_STREAK"

# --- Case 8: amend with no existing state file errors instead of silently
# fabricating a round-1 record. ---
fresh_series
printf 'src/foo.ts\n' > "$FF"
if REVIEW_PR_STATE_DIR="$STATEDIR" bash "$SCRIPT" 1 clean "" sha_x "" 0 0 "$FF" amend > /dev/null 2>&1; then
  echo "  ❌ case8: amend with no prior state should fail, but exited 0" >&2
  fail=$((fail + 1))
else
  echo "  ✅ case8: amend with no prior state file fails instead of fabricating round 1"
  pass=$((pass + 1))
fi

# --- Case 9: amend degrades a boolean count field to "n/a" instead of
# crashing. isinstance(True, int) is True in Python, so a corrupted state
# file's boolean value must not reach int() in the amend-mode reader. ---
fresh_series
cat > "$STATE_FILE" <<JSON
{"branch": "$CURRENT_BRANCH", "round": 2, "prev_critical_count": true, "prev_important_count": 0, "prev_minor_count": 0, "finding_files": [], "file_streaks": {}, "churn_files": []}
JSON
printf 'src/foo.ts\n' > "$FF"
if REVIEW_PR_STATE_DIR="$STATEDIR" bash "$SCRIPT" 1 clean "" sha_x "" 0 0 "$FF" amend > /dev/null 2>&1; then
  assert_eq "case9: amend degrades a boolean prev_critical_count to n/a, not a crash" "$(field prev_critical_count)" '"n/a"'
else
  echo "  ❌ case9: amend should degrade a boolean count field, not exit non-zero" >&2
  fail=$((fail + 1))
fi

# --- Case 10: an unrecognized 9th arg fails closed instead of silently
# switching on amend semantics for a real new round. ---
fresh_series
printf 'src/foo.ts\n' > "$FF"
if REVIEW_PR_STATE_DIR="$STATEDIR" bash "$SCRIPT" 1 clean "" sha_x "" 0 0 "$FF" typo_9th_arg > /dev/null 2>&1; then
  echo "  ❌ case10: an unrecognized 9th arg should fail closed, but exited 0" >&2
  fail=$((fail + 1))
else
  echo "  ✅ case10: an unrecognized 9th arg fails closed instead of silently amending"
  pass=$((pass + 1))
fi

# --- Case 11: amend refuses to clobber a different branch's round. Own-branch
# state is one shared file keyed by nothing but branch name (see the script's
# own header comment) -- the non-amend path already guards this at the
# PREV_BRANCH check; amend had no equivalent, so switching branches and then
# running amend silently adopted the OTHER branch's round/prev_*/streaks onto
# the current branch (found by /kbg:deep-audit, 2026-08-14: no malformed input
# needed, just ordinary multi-branch use). Must fail closed and leave the file
# untouched. ---
fresh_series
cat > "$STATE_FILE" <<'JSON'
{"branch": "some-other-feature-branch", "round": 3, "prev_critical_count": 3, "prev_important_count": 1, "prev_minor_count": 0, "finding_files": ["src/other.ts"], "file_streaks": {"src/other.ts": 3}, "churn_files": ["src/other.ts"]}
JSON
if REVIEW_PR_STATE_DIR="$STATEDIR" bash "$SCRIPT" 1 clean "" sha_x "" 0 0 "$FF" amend > /dev/null 2>&1; then
  echo "  ❌ case11: amend across a branch mismatch should fail, but exited 0" >&2
  fail=$((fail + 1))
else
  echo "  ✅ case11: amend refuses a different branch's round instead of clobbering it"
  pass=$((pass + 1))
fi
assert_eq "case11: refused amend leaves the other branch's record untouched" "$(field branch)" '"some-other-feature-branch"'

# --- Case 12: amend degrades a scalar finding_files (hand-authored corruption,
# same failure class the script's header already documents auditing at ~19%
# of sampled production files) to [] instead of carrying the bad type through
# unmutated -- unlike a normal round, amend never overwrites finding_files
# with a freshly computed list, so a bad type persists silently until fixed.
# file_streaks/churn_files two lines below it already have this isinstance
# guard; finding_files didn't (found by /kbg:deep-audit, 2026-08-14). ---
fresh_series
cat > "$STATE_FILE" <<JSON
{"branch": "$CURRENT_BRANCH", "round": 2, "prev_critical_count": 1, "prev_important_count": 0, "prev_minor_count": 0, "finding_files": "src/foo.ts", "file_streaks": {}, "churn_files": []}
JSON
run_round 1 clean "" sha_x "" 0 0 "$FF" amend
assert_eq "case12: amend degrades a scalar finding_files to [] instead of carrying the raw string through" "$(field finding_files)" '[]'

# --- Case 13: worktree-escape guard still fires when $WT genuinely exists and
# the state dir resolves inside it. Coverage gap found by /kbg:deep-audit
# (2026-08-14): every prior case passed "" for the worktree arg, so the guard
# added in v0.68.275 (the `[ -d "$WT" ]` existence check) had zero direct
# regression coverage of its own live-$WT branch. ---
WT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/test-wt-escape.XXXXXX")"
INSIDE_STATEDIR="$WT_DIR/.scratch"
mkdir -p "$INSIDE_STATEDIR"
if REVIEW_PR_STATE_DIR="$INSIDE_STATEDIR" bash "$SCRIPT" 1 clean "" sha_x "$WT_DIR" 0 0 > /dev/null 2>&1; then
  echo "  ❌ case13: state file inside \$WT should be rejected, but exited 0" >&2
  fail=$((fail + 1))
else
  echo "  ✅ case13: worktree-escape guard still fires when \$WT exists and the state dir resolves inside it"
  pass=$((pass + 1))
fi
trash "$WT_DIR" 2>/dev/null

# --- Case 14: the other half of case 11's new conditional -- PR-by-number
# amend is keyed per PR via $WT, not by branch (mirrors the non-amend path's
# own "PR-by-number is unaffected" carve-out), so a mismatched `branch` field
# in that file must NOT block the amend. Left uncovered, this is the branch a
# future reader would most plausibly "simplify" away by dropping the
# `[ -z "$WT" ]` half of the guard. ---
PR_WT="$(mktemp -d "${TMPDIR:-/tmp}/test-wt-pr14.XXXXXX")"
PR_STATE_FILE="$STATEDIR/review-pr-${PR_WT##*-}.json"
cat > "$PR_STATE_FILE" <<'JSON'
{"branch": "some-other-feature-branch", "round": 2, "prev_critical_count": 1, "prev_important_count": 0, "prev_minor_count": 0, "finding_files": [], "file_streaks": {}, "churn_files": []}
JSON
if REVIEW_PR_STATE_DIR="$STATEDIR" bash "$SCRIPT" 1 clean "" sha_x "$PR_WT" 0 0 "" amend > /dev/null 2>&1; then
  echo "  ✅ case14: PR-by-number amend ignores a mismatched branch field (keyed per PR, not by branch)"
  pass=$((pass + 1))
else
  echo "  ❌ case14: PR-by-number amend should succeed despite branch mismatch, but failed" >&2
  fail=$((fail + 1))
fi
trash "$PR_WT" 2>/dev/null

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
