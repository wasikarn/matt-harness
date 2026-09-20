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

good='{"requirements": [{"id": "R1", "verdict": "CONFORMS", "note": "", "accepted": null}], "gauntlet": {"command": "bash gauntlet.sh", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'
assert_exit "well-formed all-CONFORMS verdict accepted" 0 "$good"
assert_exit "empty requirements rejected (vacuous-pass guard)" 1 '{"requirements": [], "gauntlet": {"command": "", "sha": "", "exit_code": 0, "output_tail": ""}, "scope_ok": true, "unexpected_files": []}'
assert_exit "extra invented field rejected" 1 '{"requirements": [], "gauntlet": {"command": "c", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": [], "notes": "x"}'
assert_exit "DEVIATED with accepted null rejected" 1 '{"requirements": [{"id": "R1", "verdict": "DEVIATED", "note": "n", "accepted": null}], "gauntlet": {"command": "c", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'
assert_exit "NEEDS-DECISION escalation, not malformed" 2 "Can't tell safely.
NEEDS-DECISION does the pinned SHA still check out?"

decoy='{"requirements": [{"id": "R1", "verdict": "MISSING", "note": "", "accepted": null}], "gauntlet": {"command": "c", "sha": "abc1234", "exit_code": 1, "output_tail": "ok"}, "scope_ok": false, "unexpected_files": []}'
assert_exit "decoy verdict ahead of the real one rejected as ambiguous" 1 "Example: $decoy
Actual: $good"

# M3 (harness gap-audit, 2026-09-20): a sanctioned DEVIATED needs a real citation in its note.
assert_exit "DEVIATED+accepted with a citation-shaped note accepted" 0 '{"requirements": [{"id": "R1", "verdict": "DEVIATED", "note": "see `git diff HEAD~1`", "accepted": true}], "gauntlet": {"command": "c", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'
assert_exit "DEVIATED+accepted with a bare-prose note rejected" 1 '{"requirements": [{"id": "R1", "verdict": "DEVIATED", "note": "looked fine to me", "accepted": true}], "gauntlet": {"command": "c", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'

# M4: UNVERIFIABLE is a real verdict, never passes on its own.
assert_exit "UNVERIFIABLE accepted as a valid (non-passing) verdict" 0 '{"requirements": [{"id": "R1", "verdict": "UNVERIFIABLE", "note": "", "accepted": null}], "gauntlet": {"command": "c", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'
assert_exit "UNVERIFIABLE with a stray accepted bool rejected" 1 '{"requirements": [{"id": "R1", "verdict": "UNVERIFIABLE", "note": "", "accepted": true}], "gauntlet": {"command": "c", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'

# M5: gauntlet.sha must be a real commit-SHA shape; command/output_tail must not be blank.
assert_exit "non-hex gauntlet.sha rejected" 1 '{"requirements": [{"id": "R1", "verdict": "CONFORMS", "note": "", "accepted": null}], "gauntlet": {"command": "c", "sha": "not-a-sha", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'
assert_exit "blank gauntlet.command rejected" 1 '{"requirements": [{"id": "R1", "verdict": "CONFORMS", "note": "", "accepted": null}], "gauntlet": {"command": "   ", "sha": "abc1234", "exit_code": 0, "output_tail": "ok"}, "scope_ok": true, "unexpected_files": []}'

# M5: the orchestrating skill's pinned SHA (passed as an explicit CLI arg) is
# the source of truth -- a mismatching gauntlet.sha is rejected even on an
# otherwise schema-valid object.
mismatch_out=$(printf '%s' "$good" | python3 "$CHECK" deadbeef0 2>&1 >/dev/null)
mismatch_rc=$?
if [ "$mismatch_rc" -eq 1 ] && printf '%s' "$mismatch_out" | /usr/bin/grep -q "does not match the pinned SHA"; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: pinned-SHA mismatch rejected — expected exit 1 with a pinned-SHA message, got $mismatch_rc: $mismatch_out"
fi

match_out=$(printf '%s' "$good" | python3 "$CHECK" abc1234)
match_rc=$?
if [ "$match_rc" -eq 0 ] && printf '%s' "$match_out" | /usr/bin/grep -q '"pass": true'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: pinned-SHA match accepted — expected exit 0 with pass:true, got $match_rc: $match_out"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PASS: test-compliance-audit-check-verdict"
exit "$fail"
