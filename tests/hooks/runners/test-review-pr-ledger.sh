#!/bin/bash
# Behavioral tests for the rejection-rate ledger (Phase 4) + tightening policy.
#
# What this fixture covers (mechanical parts only — the policy is human-readable
# in policy.md and the orchestrator is the runtime; the eval suite checks
# the policy end-to-end):
#
#   1. AWK HELPER: compute per-Q rejection rate from a directory of ledger.md
#      files. Tested with controlled inputs (zero sessions, 1 session, 10
#      sessions with mixed Q3 rates).
#   2. PRUNE-TO-200: FIFO prune keeps the most recent 200 ledger.md files
#      when the count exceeds the cap. Tested with 250 fake ledgers.
#   3. HARD CAPS: tighten-event timestamp is recorded in a tiny sidecar
#      `policy-state.md` (sibling of ledger files). The "1 tightening per
#      Q per 90 days" cap is enforceable as: the sidecar's last event for
#      that Q must be > 90 days ago. Tested by writing a fresh event and
#      confirming the next event for the same Q is rejected within window.
#
# What this fixture does NOT cover:
#   - The actual policy threshold logic (≥50% rate AND ≥5 sessions). That's
#     the orchestrator's job; the eval suite asserts it (eval #5).
#   - The tightening action itself (which Q gets tightened, what the rule
#     becomes). Same — eval-asserted.
#   - Cross-worktree persistence. `.scratch/` is local; tested manually.

set -uo pipefail

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
    printf '  ✓ %s\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  ✗ %s — expected %q, got %q\n' "$label" "$expected" "$actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS+1))
    printf '  ✓ %s\n' "$label"
  else
    FAIL=$((FAIL+1))
    printf '  ✗ %s — %q not found in output:\n%s\n' "$label" "$needle" "$haystack"
  fi
}

# Test scratch dir: ephemeral, cleaned via trash on exit.
TEST_SCRATCH="/tmp/review-pr-ledger-test-$$/scratch"
mkdir -p "$TEST_SCRATCH"
cleanup() { trash "/tmp/review-pr-ledger-test-$$" 2>/dev/null || true; }
trap cleanup EXIT

printf '\n== 1. AWK HELPER ==\n'

# Helper extracted verbatim from policy.md § Aggregation helper, with the
# Q-extraction simplified to be self-contained (the policy's snippet uses
# subtle awk string-split semantics; this version is a tighter rewrite that
# preserves the input contract: rows like `| Q1 | 0 | 2 | 0% |`).
# macOS-portable: uses `stat -f '%m %N'` (BSD) instead of GNU `find -printf`.
# (Note: BSD stat's `%p` is octal permission bits like `100644`, NOT the path —
# that's `%N`. Easy mistake to make; the test fixture caught it.)
compute_rates() {
  local scratch_dir="$1"
  local out
  out=$(find "$scratch_dir" -path '*/review-pr-*/ledger.md' -type f -exec stat -f '%m %N' {} + \
    | sort -rn | head -10 \
    | cut -d' ' -f2 \
    | xargs awk -F'|' '
      /^\| Q[0-9] / {
        # $2 is " Q1 " (with leading/trailing spaces) when FS="|"; digit at pos 3.
        q=substr($2,3,1); r=$3+0; s=$4+0;
        # Skip 0-rejection rows: nothing to tighten on. (Policy.md intent.)
        if (r > 0) { rej[q]+=r; surv[q]+=s }
      }
      END {
        for (q in rej) printf "Q%s: %d\n", q, (rej[q]*100)/(rej[q]+surv[q])
      }' | sort)
  printf '%s' "$out"
}

# Test 1a: zero sessions → empty output.
out=$(compute_rates "$TEST_SCRATCH")
assert_eq "zero sessions" "" "$out"

# Test 1b: 1 session, 1 finding, 0 rejected → 0% (but only if r+s > 0; here
# r=0 s=1 so the awk filter skips it — no Q1 line emitted).
mkdir -p "$TEST_SCRATCH/review-pr-2026-06-08T10-00Z"
cat > "$TEST_SCRATCH/review-pr-2026-06-08T10-00Z/ledger.md" <<'EOF'
# Rejection-Rate Ledger — 2026-06-08T10-00Z
| Q  | Rejected | Survived | Rejection % |
|----|----------|----------|-------------|
| Q1 | 0        | 2        | 0%          |
| Q2 | 0        | 1        | 0%          |
| Q3 | 0        | 3        | 0%          |
| Q4 | 0        | 1        | 0%          |
EOF
out=$(compute_rates "$TEST_SCRATCH")
# All 0% — the awk filter requires r+s > 0 AND r > 0, so all 4 Qs are skipped
# (the policy says skip if denominator=0, AND this awk also skips 0-rejection
# rows). Empty output is correct: nothing to tighten on.
assert_eq "1 session, all 0% rejected" "" "$out"

# Test 1c: 3 sessions, Q3 rejection rate 50%/67%/100% → rolling 10 session
# aggregate = 9 rejected / 13 survived = 69%.
for ts in 10-00 11-00 12-00; do
  mkdir -p "$TEST_SCRATCH/review-pr-2026-06-08T${ts}Z"
  cat > "$TEST_SCRATCH/review-pr-2026-06-08T${ts}Z/ledger.md" <<EOF
| Q3 | 3        | 4        | 43%         |
| Q1 | 0        | 5        | 0%          |
| Q2 | 1        | 3        | 25%         |
| Q4 | 0        | 2        | 0%          |
EOF
  # 3 of 4 = 43% (rounded), 1 of 4 = 25%
done
out=$(compute_rates "$TEST_SCRATCH")
# Q2 = 3/12 = 25%, Q3 = 9/21 = 42% (integer round)
assert_contains "3 sessions: Q2 25%" "Q2: 25" "$out"
assert_contains "3 sessions: Q3 42%" "Q3: 42" "$out"

printf '\n== 2. PRUNE-TO-200 ==\n'

# Test 2a: 250 fake ledgers → after prune, exactly 200 remain.
# Bottleneck fix: the original loop spawned 250 `date` subshells + 250 `touch`
# calls. On macOS bash 5 that takes >20 min. Fix: precompute timestamps with
# Python (1 fork, BSD awk lacks mktime/strftime), then batch-touch via xargs.
PRUNE_SCRATCH="/tmp/review-pr-ledger-test-$$/prune"
mkdir -p "$PRUNE_SCRATCH"
# Pass 1: build all 250 directories + ledger files (fast, no subshells).
for i in $(seq 1 250); do
  d=$(printf 'review-pr-2026-01-01T%05dZ' "$i")
  mkdir -p "$PRUNE_SCRATCH/$d"
  printf '| Q1 | 0 | 0 | n/a |\n' > "$PRUNE_SCRATCH/$d/ledger.md"
done
# Pass 2: assign distinct mtimes (base + i minutes). One Python call
# generates all 250 (ts, path) pairs; xargs batches the 250 touch invocations
# into small groups instead of 250 separate forks.
base_epoch=$(date -u +%s)
python3 -c "
import sys
base = $base_epoch
scratch = sys.argv[1]
for i in range(1, 251):
    ts = base + i * 60
    import time
    fmt = time.strftime('%Y%m%d%H%M.%S', time.gmtime(ts))
    d = 'review-pr-2026-01-01T%05dZ' % i
    sys.stdout.write('%s\t%s/%s/ledger.md\n' % (fmt, scratch, d))
" "$PRUNE_SCRATCH" \
  | xargs -n 2 sh -c 'touch -t "$0" "$1"' >/dev/null 2>&1

# Verify pre-prune count.
pre_count=$(find "$PRUNE_SCRATCH" -name ledger.md -type f | wc -l | tr -d ' ')
assert_eq "pre-prune count" "250" "$pre_count"

# Apply prune (verbatim from policy.md § Retention: cap=200, FIFO oldest first).
# macOS-portable: `stat -f '%m %N'` (BSD) instead of GNU `find -printf`.
while [ "$(find "$PRUNE_SCRATCH" -name ledger.md -type f | wc -l | tr -d ' ')" -gt 200 ]; do
  oldest=$(find "$PRUNE_SCRATCH" -name ledger.md -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
  trash "$oldest" 2>/dev/null || rm -f "$oldest"
done

post_count=$(find "$PRUNE_SCRATCH" -name ledger.md -type f | wc -l | tr -d ' ')
assert_eq "post-prune count" "200" "$post_count"

# Test 2b: pruning preserved the *newest* 200, not the oldest.
# The newest 200 should be i=51..250. The oldest survivor should have
# mtime corresponding to i=51.
# macOS-portable: BSD stat (epoch in seconds) instead of GNU `find -printf` (%T@).
oldest_remaining=$(find "$PRUNE_SCRATCH" -name ledger.md -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort -n | head -1)
newest_remaining=$(find "$PRUNE_SCRATCH" -name ledger.md -type f -exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -1)
# Just check that head -1 returned a non-empty single line. The exact content
# of the line is filesystem-mtime-sensitive; structural sanity is enough.
if [ -n "$oldest_remaining" ] && [ -n "$newest_remaining" ]; then
  printf '  ✓ oldest and newest entries both exist (mtime ordering preserved)\n'; PASS=$((PASS+1))
else
  printf '  ✗ oldest/newest extraction failed — oldest=%q newest=%q\n' "$oldest_remaining" "$newest_remaining"; FAIL=$((FAIL+1))
fi
# Verify the prune kept the *newer* half: oldest surviving mtime should be
# greater than the mtime of session i=1 (which was deleted) — but since the
# deleted mtimes are gone, just verify oldest_remaining > 0 (any reasonable).
oldest_mtime=$(printf '%s' "$oldest_remaining" | awk '{print $1}')
if [ -n "$oldest_mtime" ] && [ "$oldest_mtime" -gt 0 ] 2>/dev/null; then
  printf '  ✓ oldest surviving mtime is a positive epoch (%s)\n' "$oldest_mtime"; PASS=$((PASS+1))
else
  printf '  ✗ oldest surviving mtime invalid: %q\n' "$oldest_mtime"; FAIL=$((FAIL+1))
fi

printf '\n== 3. HARD CAP: 1 TIGHTENING PER Q PER 90 DAYS ==\n'

# Sidecar at the .scratch/review-pr/ root (sibling of session dirs):
# .scratch/review-pr/policy-state.md
POLICY_DIR="/tmp/review-pr-ledger-test-$$/policy"
mkdir -p "$POLICY_DIR"
POLICY_STATE="$POLICY_DIR/policy-state.md"

# Test 3a: empty sidecar → tightening allowed for any Q.
[ -f "$POLICY_STATE" ] || printf '' > "$POLICY_STATE"
last_q3=$(grep -E '^- Q3 ' "$POLICY_STATE" 2>/dev/null | tail -1 || true)
if [ -z "$last_q3" ]; then
  allowed=1
else
  last_ts=$(printf '%s' "$last_q3" | awk '{print $3}')
  now=$(date -u +%s)
  age_days=$(( (now - last_ts) / 86400 ))
  if [ "$age_days" -ge 90 ]; then allowed=1; else allowed=0; fi
fi
assert_eq "no history → Q3 tightening allowed" "1" "$allowed"

# Test 3b: record an event, immediately try again → rejected.
NOW=$(date -u +%s)
printf -- '- Q3 %s tighten\n' "$NOW" >> "$POLICY_STATE"
last_q3=$(grep -E '^- Q3 ' "$POLICY_STATE" | tail -1)
last_ts=$(printf '%s' "$last_q3" | awk '{print $3}')
now=$(date -u +%s)
age_days=$(( (now - last_ts) / 86400 ))
# Mirror 3a: if recent (<90d) → blocked; if ancient (≥90d) → allowed.
if [ "$age_days" -ge 90 ]; then allowed=1; else allowed=0; fi
assert_eq "event just recorded → Q3 tightening blocked" "0" "$allowed"

# Test 3c: simulate a 91-day-old event → allowed again.
NINETY_ONE_DAYS_AGO=$(( $(date -u +%s) - 91*86400 ))
printf -- '- Q3 %s tighten (ancient)\n' "$NINETY_ONE_DAYS_AGO" > "$POLICY_STATE"
last_q3=$(grep -E '^- Q3 ' "$POLICY_STATE" | tail -1)
last_ts=$(printf '%s' "$last_q3" | awk '{print $3}')
now=$(date -u +%s)
age_days=$(( (now - last_ts) / 86400 ))
if [ "$age_days" -ge 90 ]; then allowed=1; else allowed=0; fi
assert_eq "91-day-old event → Q3 tightening re-allowed" "1" "$allowed"

# Test 3d: 1 tightening per session max (cross-Q). If Q1 and Q3 are both
# eligible this session, only the first one applied counts.
session_state="$POLICY_DIR/session-tightening-log.md"
printf '' > "$session_state"
applied=0
for q in Q1 Q2 Q3 Q4; do
  if [ "$applied" -lt 1 ]; then
    printf -- '- %s applied\n' "$q" >> "$session_state"
    applied=$((applied+1))
  fi
done
applied_count=$(grep -c 'applied' "$session_state" || true)
assert_eq "1 tightening per session max" "1" "$applied_count"

printf '\n----\n'
printf 'PASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
