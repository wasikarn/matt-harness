#!/usr/bin/env bash
# scripts/_lib/plan-verdict-check.py: catches plan-reviewer's own documented
# self-contradiction (verdict vs. what the findings' severities imply) mechanically.
# Run standalone: bash tests/skills/test-plan-reviewer-verdict.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/scripts/_lib/plan-verdict-check.py"

python3 "$CHECK" --selftest || { echo "FAIL: plan-verdict-check.py selftest"; exit 1; }

pass=0
fail=0

assert_exit() {
  # $1=label $2=expected_exit $3=stdin_text
  local out code
  out=$(printf '%s' "$3" | python3 "$CHECK" 2>/dev/null)
  code=$?
  if [ "$code" -eq "$2" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1 — expected exit $2, got $code (stdout: $out)"
  fi
}

assert_exit "clean plan accepted" 0 '{"findings": [], "top_blockers_count": 0, "verdict": "production-ready"}'
assert_exit "production-ready with a real blocker rejected" 1 '{"findings": [{"severity": "Critical"}], "top_blockers_count": 1, "verdict": "production-ready"}'
assert_exit "needs-revision with matching Critical/High count accepted" 0 '{"findings": [{"severity": "High"}], "top_blockers_count": 1, "verdict": "needs-revision"}'
assert_exit "not-ready accepted regardless of findings" 0 '{"findings": [{"severity": "Low"}], "top_blockers_count": 0, "verdict": "not-ready"}'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PASS: test-plan-reviewer-verdict"
exit "$fail"
