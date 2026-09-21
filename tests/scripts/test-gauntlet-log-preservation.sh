#!/usr/bin/env bash
# test-gauntlet-log-preservation.sh — regression for GH #158: a flaky gauntlet
# failure's log must survive so it can be diagnosed, and the printed output
# must be the full failing layer, not a 40-line tail that can hide an earlier
# failure (run_hook_tests() reported PASS-only tails while the real failure
# scrolled off the top, per #158's own repro).
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
GAUNTLET="$ROOT/scripts/run-gauntlet.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== gauntlet log preservation on failure (GH #158) ==="

TRAP_CMD=$(sed -n "s/^trap '\(.*\)' EXIT\$/\1/p" "$GAUNTLET" | head -1)
if [ -z "$TRAP_CMD" ]; then
  bad "run-gauntlet.sh has no top-level EXIT trap to extract"
else
  ok "extracted EXIT trap command"

  PASS_LOG=$(mktemp -d)
  ( LOG="$PASS_LOG"; fail=0; : "$LOG"; eval "trap '$TRAP_CMD' EXIT" )
  if [ -d "$PASS_LOG" ]; then
    bad "log dir survived a passing run (should be trashed): $PASS_LOG"
    trash "$PASS_LOG" 2>/dev/null || true
  else
    ok "log dir is cleaned up after a passing run (fail=0)"
  fi

  FAIL_LOG=$(mktemp -d)
  ( LOG="$FAIL_LOG"; fail=1; : "$LOG"; eval "trap '$TRAP_CMD' EXIT" )
  if [ -d "$FAIL_LOG" ]; then
    ok "log dir survives a failing run (fail=1), not silently trashed"
  else
    bad "log dir was trashed even though fail=1 (original #158 gap)"
  fi
  trash "$FAIL_LOG" 2>/dev/null || true
fi

# report() must print the whole failing layer's log, not tail -n 40 — a
# real failure earlier than the last 40 lines must not be hidden.
REPORT_BODY=$(sed -n '/^report()/,/^}/p' "$GAUNTLET")
if [ -z "$REPORT_BODY" ]; then
  bad "could not extract report() from run-gauntlet.sh"
else
  LOGDIR=$(mktemp -d)
  { echo "first-line-marker-must-survive"; seq 2 50; } >"$LOGDIR/tests"
  out=$(cd "$ROOT" && bash -c "
    LOG=$LOGDIR
    fail=0
    $REPORT_BODY
    report tests 0
    false
  " 2>&1 || true)
  trash "$LOGDIR" 2>/dev/null || true
  if printf '%s\n' "$out" | /usr/bin/grep -q "first-line-marker-must-survive"; then
    ok "report() prints the full failing log, not a 40-line tail"
  else
    bad "report() dropped the top of a >40-line failing log (tail -n 40 regression)"
  fi
fi

echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
