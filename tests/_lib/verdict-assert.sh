#!/usr/bin/env bash
# verdict-assert.sh — shared assert_exit/run_selftest/report_verdict trio for
# the 5 check-verdict.py / check-citations.py / plan-verdict-check.py test
# files (tests/skills/test-{compliance-audit,deep-audit,idea-audit}-check-
# verdict.sh, test-idea-audit-check-citations.sh, test-plan-reviewer-
# verdict.sh), which each carried a byte-identical copy of this block.
#
# Not matched by any of scripts/run-gauntlet.sh's test-discovery globs
# (tests/hooks/*.sh, tests/skills/test*.sh, tests/skills/*/test*.sh,
# tests/scripts/test*.sh, tests/evals/test*.sh) -- this lives under
# tests/_lib/, so it is linted (git ls-files '*.sh') but never executed as
# a test itself, same convention as tests/_lib/harness.sh. Source it, don't
# execute it.
#
# Caller contract: set CHECK (path to the python checker under test) before
# calling run_selftest or assert_exit; assert_exit reads $CHECK on every
# call, so a caller that swaps CHECK mid-file changes what later assertions
# check.

pass=0
fail=0

# run_selftest: fail fast if the checker's own --selftest doesn't pass.
run_selftest() {
  python3 "$CHECK" --selftest || { echo "FAIL: $(basename "$CHECK") selftest"; exit 1; }
}

# assert_exit <label> <expected_exit> <stdin_text>: feeds stdin_text to
# $CHECK, compares its exit code to expected_exit, tallies pass/fail.
assert_exit() {
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

# report_verdict <script-label>: prints the tally, a PASS line on a clean
# run, and exits with $fail (0 = every assertion passed).
report_verdict() {
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ] && echo "PASS: $1"
  exit "$fail"
}
