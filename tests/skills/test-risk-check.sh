#!/usr/bin/env bash
# Regression test for skills/review/risk-check/SKILL.md's embedded "## Classify" script.
# Extracts the script the same way a user's shell would run it, the same
# pattern as tests/skills/test-ship-merge-codeowners.sh and
# tests/skills/test-cost-report.sh.
#
# Built alongside a deep-audit pass on the sibling CODEOWNER-check command
# this session (2026-08-15) that found zero persisted tests existed for
# either embedded classifier -- only ephemeral /tmp fixture runs at build
# time. This makes the risk-check skill's classifier reproducible too.
#
# Case 6 (KEYWORD_RE case-insensitivity) was verified against the ORIGINAL
# dce81fe classifier and already passed there -- KEYWORD_RE had
# re.IGNORECASE from the first commit. It's general coverage, not a
# regression pin. Case 7 (is_gate_path() case-insensitivity) is the actual
# regression pin: verified it FAILS (returns LOW instead of HIGH) against
# the dce81fe classifier and only passes after 60f368e's fix -- see
# CHANGELOG.md:9453 for the same bug already fixed once elsewhere in this
# repo. Case 8 pins a KNOWN, UNFIXED gap from the last compliance-audit: a
# missing "files" key in the gh pr view response silently degrades to
# no-sensitive-signal. This test does not fix that -- it only makes the
# current behavior visible, so a future change to it is a deliberate
# decision, not an accidental one.
#
# Run standalone: bash tests/skills/test-risk-check.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RISK_CHECK_MD="$ROOT/skills/review/risk-check/SKILL.md"

pass=0
fail=0

assert() {
  local desc="$1" ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

WORK=$(mktemp -d)
trap 'trash "$WORK" 2>/dev/null || true' EXIT

# --- Extract the embedded python3 classifier (invoked as
#     `python3 -c '...' "$PR_JSON"`) ---
python3 - "$RISK_CHECK_MD" "$WORK/classify.py" <<'EXTRACT'
import re, sys
content = open(sys.argv[1]).read()
m = re.search(r"python3 -c '\n(.*?)\n' \"\$PR_JSON\"", content, re.S)
if not m:
    sys.exit("could not locate the embedded risk-check classifier block")
open(sys.argv[2], "w").write(m.group(1))
EXTRACT
if [[ ! -s "$WORK/classify.py" ]]; then
  assert "extracted the embedded risk-check classifier script" 0
  echo "=== 0/1 passed (extraction failed, cannot run any fixture) ===" >&2
  exit 1
fi
python3 -c "import ast; ast.parse(open('$WORK/classify.py').read())" 2>/dev/null
assert "extracted classifier is syntactically valid python" "$([[ $? -eq 0 ]] && echo 1 || echo 0)"

run_classifier() {
  # $1: JSON-encoded gh pr view response
  python3 -c "$(cat "$WORK/classify.py")" "$1" "$ROOT/hooks/gates/lib" 2>/dev/null
}

check_tier() {
  local desc="$1" pr_json="$2" expected="$3"
  local out tier_line got
  out=$(run_classifier "$pr_json")
  tier_line=$(printf '%s\n' "$out" | head -1)
  got=$(printf '%s' "$tier_line" | sed -n 's/.*risk: //p')
  assert "$desc (expected $expected, got '${got:-<empty>}')" "$([[ "$got" == "$expected" ]] && echo 1 || echo 0)"
}

# 1. Sensitive path + tiny diff -> HIGH (floor rule, size doesn't rescue it)
check_tier "sensitive path with a 2-line diff still forces HIGH" \
  '{"number":1,"additions":2,"deletions":0,"changedFiles":1,"files":[{"path":"hooks/gates/foo.sh"}]}' \
  HIGH

# 2. Huge non-sensitive diff -> HIGH (line-count threshold)
check_tier "500-line non-sensitive diff -> HIGH" \
  '{"number":2,"additions":500,"deletions":0,"changedFiles":5,"files":[{"path":"a.py"}]}' \
  HIGH

# 3. Many-files non-sensitive diff -> HIGH (file-count threshold)
check_tier "20-file non-sensitive diff -> HIGH" \
  '{"number":3,"additions":40,"deletions":0,"changedFiles":20,"files":[{"path":"a.py"}]}' \
  HIGH

# 4. Small non-sensitive diff -> LOW
check_tier "20+10 line diff across 2 files -> LOW" \
  '{"number":4,"additions":20,"deletions":10,"changedFiles":2,"files":[{"path":"a.py"}]}' \
  LOW

# 5. Mid-size diff -> MEDIUM
check_tier "100+50 line diff across 6 files -> MEDIUM" \
  '{"number":5,"additions":100,"deletions":50,"changedFiles":6,"files":[{"path":"a.py"}]}' \
  MEDIUM

# 6. Case-insensitive keyword match (general coverage -- was already correct
#    pre-fix, KEYWORD_RE had re.IGNORECASE from the first commit)
check_tier "mixed-case keyword path (AUTHService.ts) -> HIGH" \
  '{"number":6,"additions":1,"deletions":0,"changedFiles":1,"files":[{"path":"src/AUTHService.ts"}]}' \
  HIGH

# 7. Mixed-case gate path -- the real regression pin. Verified this FAILS
#    (returns LOW) against the pre-fix (dce81fe) classifier.
check_tier "mixed-case gate path (Hooks/Gates/evil.sh) -> HIGH" \
  '{"number":7,"additions":1,"deletions":0,"changedFiles":1,"files":[{"path":"Hooks/Gates/evil.sh"}]}' \
  HIGH

# 8. KNOWN GAP, documented not fixed: a missing "files" key degrades silently
# to no-sensitive-signal. `paths = [f.get("path","") for f in d.get("files", [])]`
# defaults to an empty list, so a schema drift where gh omits "files" entirely
# would silently report LOW/MEDIUM instead of surfacing that the sensitive-path
# check never ran. This assertion pins TODAY'S behavior so a future change is
# a deliberate decision, not an accidental one -- it is not asserting this is
# correct.
check_tier "KNOWN GAP: missing 'files' key on a small diff silently reads as LOW, not flagged as unknown" \
  '{"number":8,"additions":10,"deletions":5,"changedFiles":2}' \
  LOW

# 9. Legacy 2-arg invocation must ANNOUNCE the hotspot skip, never drop it
# silently (portability doctrine: feature-detect + announced skip). This is
# also what keeps fixtures 1-8 meaningful: they exercise the base chain with
# the hotspot signal visibly absent, not silently absent.
out9=$(run_classifier '{"number":9,"additions":5,"deletions":0,"changedFiles":1,"files":[{"path":"a.py"}]}')
assert "2-arg invocation announces 'hotspot signal skipped: no history data passed'" \
  "$(printf '%s' "$out9" | /usr/bin/grep -q 'hotspot signal skipped: no history data passed' && echo 1 || echo 0)"

# --- Hotspot fixtures (signal added 2026-08-26, probe-calibrated) ---
# Fixture history: 20 tracked files, decile index = max(0, int(20*0.10)-1) = 1,
# so threshold = 2nd-highest count. hot.py=50 and warm.py=10 sit at/above it;
# the 18 cold files (1 commit each) sit below.
HOT_HIST="$WORK/hist.txt"; HOT_TRACKED="$WORK/tracked.txt"
: > "$HOT_HIST"
for i in $(seq 1 50); do echo "hot.py" >> "$HOT_HIST"; done
for i in $(seq 1 10); do echo "warm.py" >> "$HOT_HIST"; done
for i in $(seq 1 18); do echo "cold$i.py" >> "$HOT_HIST"; done
{ echo "hot.py"; echo "warm.py"; for i in $(seq 1 18); do echo "cold$i.py"; done; } > "$HOT_TRACKED"
# Flat history: same 20 files, 2 commits each -> threshold 2 -> announced skip
FLAT_HIST="$WORK/hist-flat.txt"
: > "$FLAT_HIST"
for i in $(seq 1 20); do echo "cold$i.py" >> "$FLAT_HIST"; echo "cold$i.py" >> "$FLAT_HIST"; done
{ for i in $(seq 1 20); do echo "cold$i.py"; done; } > "$WORK/tracked-flat.txt"

run_classifier_hist() {
  # $1: PR_JSON  $2: hist file  $3: tracked file  $4: total commits
  python3 -c "$(cat "$WORK/classify.py")" "$1" "$ROOT/hooks/gates/lib" "$2" "$3" "$4" 2>/dev/null
}

check_hotspot() {
  # $1 desc  $2 pr_json  $3 hist  $4 tracked  $5 total  $6 expected tier  $7 required substring
  local out tier got
  out=$(run_classifier_hist "$2" "$3" "$4" "$5")
  got=$(printf '%s\n' "$out" | head -1 | sed -n 's/.*risk: //p')
  assert "$1 -- tier (expected $6, got '${got:-<empty>}')" "$([[ "$got" == "$6" ]] && echo 1 || echo 0)"
  assert "$1 -- output names the driver" \
    "$(printf '%s' "$out" | /usr/bin/grep -qF "$7" && echo 1 || echo 0)"
}

# 10. Small diff touching the hot file -> one-step bump LOW->MEDIUM
check_hotspot "hot-file small diff bumps LOW->MEDIUM" \
  '{"number":10,"additions":5,"deletions":0,"changedFiles":1,"files":[{"path":"hot.py"}]}' \
  "$HOT_HIST" "$HOT_TRACKED" 150 MEDIUM "bumped LOW->MEDIUM"

# 11. Mid diff touching the hot file -> one-step bump MEDIUM->HIGH
check_hotspot "hot-file mid diff bumps MEDIUM->HIGH" \
  '{"number":11,"additions":100,"deletions":50,"changedFiles":6,"files":[{"path":"hot.py"},{"path":"cold1.py"}]}' \
  "$HOT_HIST" "$HOT_TRACKED" 150 HIGH "bumped MEDIUM->HIGH"

# 12. Sensitive path already HIGH -> hotspot adds a reason, never a further bump
check_hotspot "sensitive+hot stays HIGH with hotspot as extra reason only" \
  '{"number":12,"additions":2,"deletions":0,"changedFiles":2,"files":[{"path":"hooks/gates/foo.sh"},{"path":"hot.py"}]}' \
  "$HOT_HIST" "$HOT_TRACKED" 150 HIGH "already HIGH, no further bump"

# 13. Cold-only PR with the same history -> no bump, LOW stays LOW
check_hotspot "cold-only small diff stays LOW (no hotspot hit)" \
  '{"number":13,"additions":5,"deletions":0,"changedFiles":1,"files":[{"path":"cold1.py"}]}' \
  "$HOT_HIST" "$HOT_TRACKED" 150 LOW "under the LOW thresholds"

# 14. Young repo (<100 commits) -> announced skip, tier unchanged
check_hotspot "young repo (<100 commits) announces skip, no bump" \
  '{"number":14,"additions":5,"deletions":0,"changedFiles":1,"files":[{"path":"hot.py"}]}' \
  "$HOT_HIST" "$HOT_TRACKED" 3 LOW "not enough history to rank"

# 15. Flat history (top-decile threshold <=2) -> announced skip, tier unchanged
check_hotspot "flat history announces skip, no bump" \
  '{"number":15,"additions":5,"deletions":0,"changedFiles":1,"files":[{"path":"cold1.py"}]}' \
  "$FLAT_HIST" "$WORK/tracked-flat.txt" 150 LOW "flat history"

echo ""
total_t=$((pass + fail))
echo "=== $pass/$total_t passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
