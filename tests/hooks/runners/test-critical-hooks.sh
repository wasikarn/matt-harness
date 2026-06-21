#!/usr/bin/env bash
# test-critical-hooks — parallel smoke-test runner for the load-bearing
# enforcement hooks.
#
# Covers all 9 PreToolUse enforcement gates plus TaskCompleted F7, journal
# contracts, review fixes, validators, audit #31/#32, orphaned runners, and
# the ideate fan-out structure.
#
# Each sub-suite is a standalone script that sources test-critical-hooks-lib.sh,
# runs its checks against an isolated temp fixture, and emits a parseable
# "SUITE PASS=x FAIL=y" line. This runner executes the sub-suites concurrently,
# aggregates the results, and fails if any sub-suite reported failures.
#
# Usage: bash tests/hooks/runners/test-critical-hooks.sh
# Exit 0 = all pass; exit 1 = one or more failed.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/../../../hooks" && pwd)"
TESTS_DIR="$(dirname "$0")"

# Order matches the old sequential suite; parallel execution does not depend on
# it, but keeping the order in the report makes regressions easy to locate.
SUITES=(
  test-ch-gates.sh
  test-ch-journal.sh
  test-ch-journal-phaseii.sh
  test-ch-review-fixes.sh
  test-ch-verif-validators.sh
  test-ch-harness-audit31.sh
  test-ch-harness-audit32.sh
  test-ch-harness-audit-fixtures.sh
  test-ch-orphaned-runners.sh
  test-ch-ideate-fanout.sh
  test-ch-ideate-session-end.sh
  test-ch-l3.sh
  test-ch-agent-readonly.sh
  test-ch-task-board-lib.sh
  test-ch-cost-capture.sh
  test-ch-learn-capture.sh
)

WORK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-critical-hooks.XXXXXX")
trap 'rm -rf "$WORK_TMP"' EXIT

# Run each sub-suite in its own process so they are isolated and can exploit
# available CPU cores. Capturing output to a per-suite log prevents interleaved
# stdout and lets us print a clean summary.
PIDS=()
for i in "${!SUITES[@]}"; do
  suite="${SUITES[$i]}"
  log="$WORK_TMP/$suite.log"
  bash "$TESTS_DIR/$suite" > "$log" 2>&1 &
  PIDS[$i]=$!
done

TOTAL_PASS=0
TOTAL_FAIL=0
ANY_SUITE_FAIL=0

echo "=== critical hook tests (parallel suites) ==="

for i in "${!SUITES[@]}"; do
  suite="${SUITES[$i]}"
  pid="${PIDS[$i]}"
  log="$WORK_TMP/$suite.log"

  if wait "$pid"; then
    rc=0
  else
    rc=$?
  fi

  # Extract the last SUITE line; if the suite crashed, there may be none.
  summary=$(/usr/bin/grep -E '^SUITE PASS=[0-9]+ FAIL=[0-9]+$' "$log" | tail -1)
  if [ -n "$summary" ]; then
    spass=$(printf '%s' "$summary" | sed -E 's/^SUITE PASS=([0-9]+) FAIL=([0-9]+)$/\1/')
    sfail=$(printf '%s' "$summary" | sed -E 's/^SUITE PASS=([0-9]+) FAIL=([0-9]+)$/\2/')
  else
    spass=0
    sfail=0
    rc=1
  fi

  TOTAL_PASS=$((TOTAL_PASS + spass))
  TOTAL_FAIL=$((TOTAL_FAIL + sfail))

  if [ "$rc" -ne 0 ] || [ "$sfail" -ne 0 ]; then
    ANY_SUITE_FAIL=1
    printf '  ❌ %-34s (exit=%s, pass=%s, fail=%s)\n' "$suite" "$rc" "$spass" "$sfail"
    tail -n 20 "$log" | sed 's/^/      /'
  else
    printf '  ✅ %-34s pass=%s\n' "$suite" "$spass"
  fi
done

echo
echo "=== $TOTAL_PASS passed, $TOTAL_FAIL failed ==="
if [ "$ANY_SUITE_FAIL" -ne 0 ]; then
  echo "FAIL: one or more critical hook suites failed" >&2
  exit 1
fi
echo "✅ all critical hooks enforce as specified"
