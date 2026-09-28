#!/usr/bin/env bash
# skills/workflow/idea-audit/scripts/check-citations.py: mechanically checks
# attacker findings[]/checked[] evidence strings for a real citation shape.
# Run standalone: bash tests/skills/test-idea-audit-check-citations.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC2034  # used by assert_exit/run_selftest in the sourced lib below
CHECK="$ROOT/skills/workflow/idea-audit/scripts/check-citations.py"
# shellcheck source=../_lib/verdict-assert.sh
source "$ROOT/tests/_lib/verdict-assert.sh"

run_selftest

assert_exit "path:line citation accepted" 0 '{"findings": [{"summary": "s", "evidence": "skills/foo.py:12"}], "checked": []}'
assert_exit "backticked command accepted" 0 '{"findings": [], "checked": [{"claim": "c", "evidence": "ran `git log -1`"}]}'
assert_exit "bare prose rejected" 1 '{"findings": [{"summary": "s", "evidence": "looks correct to me"}], "checked": []}'
assert_exit "un-backticked command rejected (format matters)" 1 '{"findings": [], "checked": [{"claim": "c", "evidence": "ran git diff, exit 0"}]}'

report_verdict "test-idea-audit-check-citations"
