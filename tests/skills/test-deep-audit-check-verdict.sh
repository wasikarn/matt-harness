#!/usr/bin/env bash
# skills/review/deep-audit/scripts/check-verdict.py: validates the Claude-
# fallback checker's return value from presence-only to full shape/type
# validity, and distinguishes a valid NEEDS-DECISION escalation from a
# rejected/malformed verdict.
# Run standalone: bash tests/skills/test-deep-audit-check-verdict.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/skills/review/deep-audit/scripts/check-verdict.py"

python3 "$CHECK" --selftest || { echo "FAIL: check-verdict.py selftest"; exit 1; }

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

good='{"pass": true, "findings": [], "scope_ok": true, "unexpected_files": []}'
assert_exit "well-formed verdict accepted" 0 "$good"
assert_exit "extra invented field rejected" 1 '{"pass": true, "findings": [], "scope_ok": true, "unexpected_files": [], "notes": "x"}'
assert_exit "pass as string rejected" 1 '{"pass": "mostly", "findings": [], "scope_ok": true, "unexpected_files": []}'
assert_exit "scope_ok null rejected" 1 '{"pass": true, "findings": [], "scope_ok": null, "unexpected_files": []}'
assert_exit "malformed findings item rejected" 1 '{"pass": false, "findings": [{"issue": "x"}], "scope_ok": true, "unexpected_files": []}'
assert_exit "NEEDS-DECISION escalation, not malformed" 2 "I can't tell safely.
NEEDS-DECISION does gate X apply to Y?"

decoy='{"pass": false, "findings": [], "scope_ok": false, "unexpected_files": []}'
real='{"pass": true, "findings": [{"summary": "s", "evidence": "e"}], "scope_ok": true, "unexpected_files": []}'
assert_exit "decoy verdict ahead of the real one rejected as ambiguous" 1 "Example shape: $decoy
Actual result: $real"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PASS: test-deep-audit-check-verdict"
exit "$fail"
