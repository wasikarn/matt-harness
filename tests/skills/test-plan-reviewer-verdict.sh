#!/usr/bin/env bash
# scripts/_lib/plan-verdict-check.py: catches plan-reviewer's own documented
# self-contradiction (verdict vs. what the findings' severities imply) mechanically.
# Run standalone: bash tests/skills/test-plan-reviewer-verdict.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC2034  # used by assert_exit/run_selftest in the sourced lib below
CHECK="$ROOT/scripts/_lib/plan-verdict-check.py"
# shellcheck source=../_lib/verdict-assert.sh
source "$ROOT/tests/_lib/verdict-assert.sh"

run_selftest

assert_exit "clean plan accepted" 0 '{"findings": [], "top_blockers_count": 0, "verdict": "production-ready"}'
assert_exit "production-ready with a real blocker rejected" 1 '{"findings": [{"severity": "Critical"}], "top_blockers_count": 1, "verdict": "production-ready"}'
assert_exit "needs-revision with matching Critical/High count accepted" 0 '{"findings": [{"severity": "High"}], "top_blockers_count": 1, "verdict": "needs-revision"}'
assert_exit "not-ready accepted regardless of findings" 0 '{"findings": [{"severity": "Low"}], "top_blockers_count": 0, "verdict": "not-ready"}'

report_verdict "test-plan-reviewer-verdict"
