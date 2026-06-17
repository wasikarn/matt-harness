#!/usr/bin/env bash
# run-tests.sh — verify memory-lint action mode against in-repo fixtures.
#
# Per feedback_verification_fixture_must_live_in_repo.md, fixtures live in the
# repo (not /tmp) for reproducibility. Each fixture is a self-contained memory
# dir; the test asserts the action-mode plan matches the expected class mix.
#
# Exit 0 = all pass, 1 = at least one failure.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LINT="python3 $HERE/../../skills/memory-lint/scripts/memory-lint.py"

pass=0
fail=0
fail_msgs=()

# ── clean ──────────────────────────────────────────────────────────────
# Expect: detector clean + action mode "no actions proposed"
echo "── clean ──"
out=$(cd "$HERE/fixtures/clean" && $LINT . --json 2>&1)
if echo "$out" | grep -q '"findings": \[\]'; then
    echo "  detector: PASS (no findings)"
    pass=$((pass+1))
else
    echo "  detector: FAIL"
    fail_msgs+=("clean: detector found unexpected findings")
    fail=$((fail+1))
fi

out=$(cd "$HERE/fixtures/clean" && echo "n" | $LINT . --auto-archive --dry-run 2>&1)
if echo "$out" | grep -q "No actions proposed"; then
    echo "  action-mode: PASS (no actions)"
    pass=$((pass+1))
else
    echo "  action-mode: FAIL"
    fail_msgs+=("clean: action mode should print 'No actions proposed'")
    fail=$((fail+1))
fi

# ── superseded ─────────────────────────────────────────────────────────
# Expect: 1 Class A move, 0 Class B/C
echo "── superseded ──"
out=$(cd "$HERE/fixtures/superseded" && echo "n" | $LINT . --auto-archive --dry-run --json 2>&1)
a_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['A_stale_superseded']))" 2>/dev/null || echo "ERR")
if [ "$a_count" = "1" ]; then
    echo "  class A: PASS (1 file marked stale-superseded)"
    pass=$((pass+1))
else
    echo "  class A: FAIL (expected 1, got $a_count)"
    fail_msgs+=("superseded: expected Class A count=1, got $a_count")
    fail=$((fail+1))
fi
b_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['B_near_budget_collapse']))" 2>/dev/null || echo "ERR")
c_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['C_dangling_link_rewrite']))" 2>/dev/null || echo "ERR")
if [ "$b_count" = "0" ] && [ "$c_count" = "0" ]; then
    echo "  class B+C: PASS (0 + 0)"
    pass=$((pass+1))
else
    echo "  class B+C: FAIL (B=$b_count, C=$c_count, expected 0+0)"
    fail_msgs+=("superseded: expected B=0,C=0, got B=$b_count,C=$c_count")
    fail=$((fail+1))
fi

# ── dangling ──────────────────────────────────────────────────────────
# Expect: 1 Class C rewrite to ledger
echo "── dangling ──"
out=$(cd "$HERE/fixtures/dangling" && echo "n" | $LINT . --auto-archive --dry-run --json 2>&1)
a_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['A_stale_superseded']))" 2>/dev/null || echo "ERR")
b_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['B_near_budget_collapse']))" 2>/dev/null || echo "ERR")
c_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['C_dangling_link_rewrite']))" 2>/dev/null || echo "ERR")
if [ "$a_count" = "0" ] && [ "$b_count" = "0" ] && [ "$c_count" = "1" ]; then
    echo "  classes A/B/C: PASS (0/0/1)"
    pass=$((pass+1))
else
    echo "  classes: FAIL (A=$a_count, B=$b_count, C=$c_count, expected 0/0/1)"
    fail_msgs+=("dangling: expected A=0,B=0,C=1, got A=$a_count,B=$b_count,C=$c_count")
    fail=$((fail+1))
fi
# Verify the rewrite target is the ledger
ledger_target=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['classes']['C_dangling_link_rewrite'][0]['new'])" 2>/dev/null || echo "ERR")
if [ "$ledger_target" = "[[project_external_evals_ledger]]" ]; then
    echo "  ledger target: PASS ($ledger_target)"
    pass=$((pass+1))
else
    echo "  ledger target: FAIL (got $ledger_target)"
    fail_msgs+=("dangling: expected ledger target, got $ledger_target")
    fail=$((fail+1))
fi

# ── near-budget ───────────────────────────────────────────────────────
# Expect: 60 Class B pointer rewrites (12 topics × 5 dup lines each)
echo "── near-budget ──"
out=$(cd "$HERE/fixtures/near-budget" && echo "n" | $LINT . --auto-archive --dry-run --json 2>&1)
a_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['A_stale_superseded']))" 2>/dev/null || echo "ERR")
b_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['B_near_budget_collapse']))" 2>/dev/null || echo "ERR")
c_count=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['classes']['C_dangling_link_rewrite']))" 2>/dev/null || echo "ERR")
if [ "$a_count" = "0" ] && [ "$c_count" = "0" ] && [ "$b_count" -ge "12" ]; then
    echo "  classes A/B/C: PASS (0/$b_count/0, B >= 12)"
    pass=$((pass+1))
else
    echo "  classes: FAIL (A=$a_count, B=$b_count, C=$c_count, expected 0/>=12/0)"
    fail_msgs+=("near-budget: expected A=0,B>=12,C=0, got A=$a_count,B=$b_count,C=$c_count")
    fail=$((fail+1))
fi

# ── summary ───────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════"
echo "  pass: $pass  fail: $fail"
echo "═══════════════════════════════════════"
if [ "$fail" -gt 0 ]; then
    for msg in "${fail_msgs[@]}"; do
        echo "  - $msg"
    done
    exit 1
fi
echo "All fixture tests passed."
exit 0
