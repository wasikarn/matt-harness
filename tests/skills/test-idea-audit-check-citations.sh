#!/usr/bin/env bash
# skills/workflow/idea-audit/scripts/check-citations.py: mechanically checks
# attacker findings[]/checked[] evidence strings for a real citation shape.
# Run standalone: bash tests/skills/test-idea-audit-check-citations.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/skills/workflow/idea-audit/scripts/check-citations.py"

python3 "$CHECK" --selftest || { echo "FAIL: check-citations.py selftest"; exit 1; }

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

assert_exit "path:line citation accepted" 0 '{"findings": [{"summary": "s", "evidence": "skills/foo.py:12"}], "checked": []}'
assert_exit "backticked command accepted" 0 '{"findings": [], "checked": [{"claim": "c", "evidence": "ran `git log -1`"}]}'
assert_exit "bare prose rejected" 1 '{"findings": [{"summary": "s", "evidence": "looks correct to me"}], "checked": []}'
assert_exit "un-backticked command rejected (format matters)" 1 '{"findings": [], "checked": [{"claim": "c", "evidence": "ran git diff, exit 0"}]}'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PASS: test-idea-audit-check-citations"
exit "$fail"
