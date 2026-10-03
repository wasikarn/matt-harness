#!/usr/bin/env bash
# test-gauntlet-failed-summary.sh — regression for GH #387: a red gauntlet run
# must name the failing test files. CI logs ran to 3284 lines with 49 sections
# and no line said which file failed. Pulls run_hook_tests() out of the script
# (same style as test-gauntlet-log-preservation.sh) with hook_test_files()
# stubbed to two fixtures, one passing and one failing; never runs the gauntlet.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
GAUNTLET="$ROOT/scripts/run-gauntlet.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }
safe_trash() { [ -n "${1:-}" ] && trash "$1" 2>/dev/null; return 0; }

echo "=== gauntlet names failing test files (GH #387) ==="

BODY=$(sed -n '/^run_hook_tests()/,/^}/p' "$GAUNTLET")
FIX=$(mktemp -d)
if [ -z "$BODY" ]; then
  bad "could not extract run_hook_tests() from run-gauntlet.sh"
elif [ -z "$FIX" ]; then
  bad "mktemp -d failed for the fixture dir"
else
  printf 'exit 0\n' >"$FIX/test-green.sh"
  printf 'exit 1\n' >"$FIX/test-red.sh"
  out=$(bash -c "
    $BODY
    hook_test_files() { printf '%s\n' '$FIX/test-green.sh' '$FIX/test-red.sh'; }
    run_hook_tests
  " 2>&1)
  rc=$?
  line=$(printf '%s\n' "$out" | /usr/bin/grep '^failing:')
  if [ "$rc" -ne 0 ]; then
    ok "layer still exits non-zero when a file fails (rc=$rc)"
  else
    bad "layer exited 0 with a failing file"
  fi
  if printf '%s\n' "$line" | /usr/bin/grep -qF "$FIX/test-red.sh"; then
    ok "a 'failing:' line names the failing file"
  else
    bad "no 'failing:' line naming $FIX/test-red.sh; got: <$line>"
  fi
  if printf '%s\n' "$line" | /usr/bin/grep -qF "test-green.sh"; then
    bad "the 'failing:' line also names the passing file: <$line>"
  else
    ok "the 'failing:' line leaves out the passing file"
  fi
fi
safe_trash "$FIX"

# The final FAILED message is the tail of a CI log, so it must repeat the list
# from the tests layer's log. Run the script's closing if-block on a fixture LOG.
TAIL=$(sed -n '/^if \[ "\$fail" -eq 0 \]/,/^fi/p' "$GAUNTLET")
LOGDIR=$(mktemp -d)
if [ -z "$TAIL" ]; then
  bad "could not extract the closing if-block from run-gauntlet.sh"
elif [ -z "$LOGDIR" ]; then
  bad "mktemp -d failed for the log dir"
else
  printf -- '--- tests/x.sh\nnoise\nfailing: tests/scripts/test-red.sh\n' >"$LOGDIR/tests"
  out=$(bash -c "LOG='$LOGDIR'; fail=1; $TAIL" 2>&1)
  last=$(printf '%s\n' "$out" | tail -n 1)
  if printf '%s\n' "$last" | /usr/bin/grep -qF 'failing: tests/scripts/test-red.sh'; then
    ok "the last line of a failed run repeats the failing: list"
  else
    bad "the last line of a failed run does not name the file: <$last>"
  fi
fi
safe_trash "$LOGDIR"

echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
