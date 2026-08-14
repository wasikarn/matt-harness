#!/usr/bin/env bash
# Unit tests for write-review-state.sh's same-file churn detection
# (convergence_state == "churning", file_streaks, churn_files) — added
# 2026-08-14 after direct forensic analysis of two real >10-round review-pr
# loops (PR #2754/session e34b6832, PR #2768/session 6e7c3bed) found the same
# root cause independently in both: a fix in round N introducing a new,
# different problem in the SAME file in round N+1, which neither the
# tier-count STALLED check nor the file-set REGRESSED check catches (a file
# already in the prior round's finding-set doesn't register as "new").
# Run standalone: bash tests/skills/review-pr/test-write-review-state.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/review-pr/scripts/write-review-state.sh"

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

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
