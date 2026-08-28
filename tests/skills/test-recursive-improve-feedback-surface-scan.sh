#!/usr/bin/env bash
# Regression test for skills/meta/recursive-improve/scripts/feedback-surface-scan.py
# (candidate 2 from docs/research/warp-self-improving-agents-article-audit-2026-08-28.md
# -- clusters type:feedback memories by which repo surface they mention in prose).
# Passes a synthetic dir as the positional memory_dir argument, so this never touches
# the real memory store or needs to fake HOME/git-toplevel resolution.
# Run standalone: bash tests/skills/test-recursive-improve-feedback-surface-scan.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/skills/meta/recursive-improve/scripts/feedback-surface-scan.py"

pass=0
fail=0
check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

mkmem() { # mkmem <dir> <filename> <type> <body>
  mkdir -p "$1"
  cat > "$1/$2" <<EOF
---
name: ${2%.md}
description: test fixture
metadata:
  type: $3
---

$4
EOF
}

echo "=== recursive-improve feedback-surface-scan ==="

# Case 1: memory dir doesn't exist -- graceful, not fatal.
tmp_missing="$(mktemp -d)/does-not-exist"
out=$(python3 "$SCRIPT" "$tmp_missing" 2>&1)
rc=$?
ok=1; [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q "no memory store found" && ok=0
check "missing memory dir -> exits 0, says so plainly" "$ok"

# Case 2: memory dir exists, no feedback-type memories.
tmp_nofeedback="$(mktemp -d)"
mkmem "$tmp_nofeedback" "a.md" "project" "mentions docs/METHODOLOGY.md twice: docs/METHODOLOGY.md"
out=$(python3 "$SCRIPT" "$tmp_nofeedback" 2>&1)
rc=$?
ok=1; [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q "no type:feedback memories found" && ok=0
check "no feedback-type memories -> says so, project-type not miscounted" "$ok"

# Case 3: feedback memories exist but no surface repeats -- no false cluster.
tmp_norepeat="$(mktemp -d)"
mkmem "$tmp_norepeat" "a.md" "feedback" "about docs/METHODOLOGY.md only"
mkmem "$tmp_norepeat" "b.md" "feedback" "about docs/harness-decay-cadence.md only"
out=$(python3 "$SCRIPT" "$tmp_norepeat" 2>&1)
rc=$?
ok=1; [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q "no surface mentioned by 2+" && ok=0
check "feedback memories with no shared surface -> no cluster reported" "$ok"

# Case 4: two feedback memories mention the same REAL, existing path -- clusters.
tmp_cluster="$(mktemp -d)"
mkmem "$tmp_cluster" "a.md" "feedback" "problem traced to docs/METHODOLOGY.md"
mkmem "$tmp_cluster" "b.md" "feedback" "also see docs/METHODOLOGY.md for the rule"
out=$(python3 "$SCRIPT" "$tmp_cluster" 2>&1)
rc=$?
ok=1
[ "$rc" -eq 0 ] && \
  echo "$out" | /usr/bin/grep -q "2 feedback memories scanned" && \
  echo "$out" | /usr/bin/grep -q "docs/METHODOLOGY.md" && \
  echo "$out" | /usr/bin/grep -q "a.md" && \
  echo "$out" | /usr/bin/grep -q "b.md" && ok=0
check "two feedback memories sharing a real path -> clustered together" "$ok"

# Case 5: existence filter -- a stale/nonexistent path mentioned twice must NOT cluster.
# This is the regression this script exists to prevent (empirically, 3/10 of this
# repo's real feedback-memory path mentions were stale when this was built).
tmp_stale="$(mktemp -d)"
mkmem "$tmp_stale" "a.md" "feedback" "about hooks/gates/this-gate-was-deleted-long-ago.sh"
mkmem "$tmp_stale" "b.md" "feedback" "also about hooks/gates/this-gate-was-deleted-long-ago.sh"
out=$(python3 "$SCRIPT" "$tmp_stale" 2>&1)
rc=$?
ok=1; [ "$rc" -eq 0 ] && ! echo "$out" | /usr/bin/grep -q "this-gate-was-deleted-long-ago" && ok=0
check "stale path mentioned by 2 feedback memories -> excluded (existence filter)" "$ok"

trash "$(dirname "$tmp_missing")" "$tmp_nofeedback" "$tmp_norepeat" "$tmp_cluster" "$tmp_stale" 2>/dev/null || true

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
