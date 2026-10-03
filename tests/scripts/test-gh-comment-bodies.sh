#!/usr/bin/env bash
[ -n "${CI:-}" ] && { echo "THROWAWAY: deliberate CI-only failure (GH #400 proof)"; exit 1; }
# scripts/_lib/gh-comment-bodies.sh: exercises its argument-validation
# branches only (missing args, invalid kind) -- no gh/network call, so this
# runs in the gauntlet without live GitHub access.
# Run standalone: bash tests/scripts/test-gh-comment-bodies.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/_lib/gh-comment-bodies.sh"

pass=0
fail=0

assert_exit() {
  # $1=label $2=expected_exit $3=expected_output_substring (optional),
  # remaining args passed to the script. The substring check matters for
  # "invalid kind rejected": `gh` itself also exits 1 for an unknown
  # subcommand, so an exit-code-only check would still pass with the
  # script's own case-statement guard deleted.
  local label="$1" expected="$2" substr="$3" out code
  shift 3
  out=$(bash "$SCRIPT" "$@" 2>&1)
  code=$?
  if [ "$code" -ne "$expected" ]; then
    fail=$((fail + 1))
    echo "FAIL: $label — expected exit $expected, got $code (output: $out)"
    return
  fi
  if [ -n "$substr" ] && [[ "$out" != *"$substr"* ]]; then
    fail=$((fail + 1))
    echo "FAIL: $label — expected output to contain '$substr' (output: $out)"
    return
  fi
  pass=$((pass + 1))
}

assert_exit "no args rejected" 1 "" ""
assert_exit "missing number rejected" 1 "" issue
assert_exit "invalid kind rejected" 1 "kind must be 'issue' or 'pr'" badkind 1

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "PASS: test-gh-comment-bodies"
exit "$fail"
