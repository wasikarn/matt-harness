#!/usr/bin/env bash
# skills/review/compliance-audit/scripts/check-verdict.py: validates the
# dispatched verifier's return value and computes `pass` deterministically.
# Run standalone: bash tests/skills/test-compliance-audit-check-verdict.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$ROOT/skills/review/compliance-audit/scripts/check-verdict.py"

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

good='{"requirements": [{"id": "R1", "verdict": "CONFORMS", "note": "", "accepted": null}], "gauntlet": {"command": "bash gauntlet.sh", "sha": "abc", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'
assert_exit "well-formed all-CONFORMS verdict accepted" 0 "$good"
assert_exit "empty requirements rejected (vacuous-pass guard)" 1 '{"requirements": [], "gauntlet": {"command": "", "sha": "", "exit_code": 0, "output_tail": ""}, "scope_ok": true, "unexpected_files": []}'
assert_exit "extra invented field rejected" 1 '{"requirements": [], "gauntlet": {"command": "c", "sha": "s", "exit_code": 0, "output_tail": ""}, "scope_ok": true, "unexpected_files": [], "notes": "x"}'
assert_exit "DEVIATED with accepted null rejected" 1 '{"requirements": [{"id": "R1", "verdict": "DEVIATED", "note": "n", "accepted": null}], "gauntlet": {"command": "c", "sha": "s", "exit_code": 0, "output_tail": ""}, "scope_ok": true, "unexpected_files": []}'
assert_exit "NEEDS-DECISION escalation, not malformed" 2 "Can't tell safely.
NEEDS-DECISION does the pinned SHA still check out?"

decoy='{"requirements": [{"id": "R1", "verdict": "MISSING", "note": "", "accepted": null}], "gauntlet": {"command": "c", "sha": "s", "exit_code": 1, "output_tail": ""}, "scope_ok": false, "unexpected_files": []}'
assert_exit "decoy verdict ahead of the real one rejected as ambiguous" 1 "Example: $decoy
Actual: $good"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PASS: test-compliance-audit-check-verdict"
exit "$fail"
