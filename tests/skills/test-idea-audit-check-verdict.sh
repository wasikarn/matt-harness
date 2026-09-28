#!/usr/bin/env bash
# skills/workflow/idea-audit/scripts/check-verdict.py: validates the
# attacker/fallback's return value from presence-only to full shape/type
# validity, and distinguishes a valid NEEDS-DECISION escalation from a
# rejected/malformed verdict. Added 2026-09-20 (harness gap-audit M2),
# mirrors tests/skills/test-deep-audit-check-verdict.sh for idea-audit's
# own 3-key {pass, findings[], checked[]} contract (no scope_ok/
# unexpected_files -- this attacker never touches the repo).
# Run standalone: bash tests/skills/test-idea-audit-check-verdict.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC2034  # used by assert_exit/run_selftest in the sourced lib below
CHECK="$ROOT/skills/workflow/idea-audit/scripts/check-verdict.py"
# shellcheck source=../_lib/verdict-assert.sh
source "$ROOT/tests/_lib/verdict-assert.sh"

run_selftest

checked='[{"claim": "c", "evidence": "e"}]'
good='{"contract_version": 1, "pass": true, "findings": [], "checked": '"$checked"'}'
assert_exit "well-formed verdict accepted" 0 "$good"
assert_exit "extra invented field rejected (scope_ok doesn't belong here)" 1 '{"contract_version": 1, "pass": true, "findings": [], "checked": '"$checked"', "scope_ok": true}'
assert_exit "pass as string rejected" 1 '{"contract_version": 1, "pass": "mostly", "findings": [], "checked": '"$checked"'}'
assert_exit "malformed findings item rejected" 1 '{"contract_version": 1, "pass": false, "findings": [{"issue": "x"}], "checked": '"$checked"'}'
assert_exit "empty checked rejected (vacuous-pass guard)" 1 '{"contract_version": 1, "pass": true, "findings": [], "checked": []}'
assert_exit "blank findings.summary rejected" 1 '{"contract_version": 1, "pass": false, "findings": [{"summary": "  ", "evidence": "e"}], "checked": '"$checked"'}'
assert_exit "blank checked.evidence rejected" 1 '{"contract_version": 1, "pass": true, "findings": [], "checked": [{"claim": "c", "evidence": ""}]}'
assert_exit "NEEDS-DECISION escalation, not malformed" 2 "I can't tell safely.
NEEDS-DECISION does the source's own citation hold up?"

decoy='{"contract_version": 1, "pass": false, "findings": [], "checked": '"$checked"'}'
real='{"contract_version": 1, "pass": true, "findings": [{"summary": "s", "evidence": "e"}], "checked": '"$checked"'}'
assert_exit "decoy verdict ahead of the real one rejected as ambiguous" 1 "Example shape: $decoy
Actual result: $real"

report_verdict "test-idea-audit-check-verdict"
