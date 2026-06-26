#!/usr/bin/env bash
# run-gauntlet.sh — parallel gauntlet runner for kbg-harness validation.
#
# Runs the heavy pre-push validation layers concurrently, captures each
# layer's output to its own temp log, prints a summary, and exits with the
# number of failed layers.  Failures include the tail of the offending log.
#
# Usage:
#   bash scripts/run-gauntlet.sh         # full gauntlet: validate + audit + docs + ci + hooks + eval
#   bash scripts/run-gauntlet.sh --fast  # skip the slow critical-hooks suite
#
# Exit codes:
#   0 — all layers passed
#   N — N layer(s) failed (1..6)
#   2 — bad invocation

set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "run-gauntlet: python3 is required for timing and cleanup" >&2
  exit 2
fi

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT" || { echo "run-gauntlet: cannot cd to $REPO_ROOT" >&2; exit 2; }

# Source _lib.sh for journal_append — the gauntlet emits a `gauntlet_run` event on
# completion (ADR 0005 addendum 0005-addendum-manual-push-precondition-waiver.md): the
# computational ship-gate evidence the L5 push leg reads. SHA-bound so the L5 leg can
# require green-for-HEAD (closes the stale-green gap). Graceful degrade: no _lib.sh /
# no jq / no journal_append → silent skip (the gauntlet's exit code is unchanged, so
# non-journaling callers are unaffected). Mirrors l4-quality-gate.sh's sourcing pattern.
_JLIB="$REPO_ROOT/hooks/_lib.sh"
[ -f "$_JLIB" ] && command -v jq >/dev/null 2>&1 && source "$_JLIB" 2>/dev/null || true

FAST=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "run-gauntlet: unknown argument: $arg" >&2
      echo "Usage: $(basename "$0") [--fast]" >&2
      exit 2
      ;;
  esac
done

WORK_TMP=$(mktemp -d "${TMPDIR:-/tmp}/run-gauntlet.XXXXXX")
trap 'rm -rf "$WORK_TMP"' EXIT

# Each layer is stored as parallel arrays (bash 3.x safe; no associative arrays).
declare -a LAYER_NAMES=() LAYER_CMDS=() LAYER_LOGS=() LAYER_PIDS=() LAYER_STARTS=()

now_ms() {
  python3 -c 'import time; print(time.time())'
}

layer_duration() {
  local start="$1" end="$2"
  python3 -c "import sys; print(round(float(sys.argv[2]) - float(sys.argv[1]), 2))" "$start" "$end"
}

run_layer() {
  local name="$1"
  local cmd="$2"
  local log="$WORK_TMP/${name}.log"

  LAYER_NAMES+=("$name")
  LAYER_CMDS+=("$cmd")
  LAYER_LOGS+=("$log")
  LAYER_STARTS+=("$(now_ms)")

  # eval is safe here: the command strings are fixed literals below.
  eval "$cmd" > "$log" 2>&1 &
  LAYER_PIDS+=($!)
}

run_layer "plugin-validate" "claude plugin validate --strict ."
run_layer "audit" "bash skills/harness-audit/scripts/audit.sh ."

# docs-as-tests + supply-chain guard: fast static suites, always-on (not
# skipped in --fast — they are quick greps/counts, unlike the critical-hooks
# suite). docs-as-tests pins manifest prose counts to actual component counts
# (cache-invariant); ci-guard forbids fetch-and-exec in shipped scripts +
# keeps validate.yml a conformance gate (no release train). See tests/docs/
# and tests/ci/.
run_layer "docs-as-tests" "bash tests/docs/run-doc-tests.sh"
run_layer "ci-guard" "bash tests/ci/run-ci-guard.sh"

if [ "$FAST" -eq 0 ]; then
  run_layer "critical-hooks" "bash tests/hooks/runners/test-critical-hooks.sh"
fi

run_layer "eval-gate" "python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate"

TOTAL=${#LAYER_PIDS[@]}
FAILURES=0
FAILING_NAMES=""
SLOWEST_NAME=""
SLOWEST_TIME=0

echo "run-gauntlet: started $TOTAL layer(s) in parallel (tmpdir: $WORK_TMP)"
echo ""

for ((i=0; i<TOTAL; i++)); do
  pid=${LAYER_PIDS[$i]}
  name=${LAYER_NAMES[$i]}
  log=${LAYER_LOGS[$i]}
  cmd=${LAYER_CMDS[$i]}

  if wait "$pid"; then
    rc=0
  else
    rc=$?
  fi

  end=$(now_ms)
  dur=$(layer_duration "${LAYER_STARTS[$i]}" "$end")

  if [ "$rc" -ne 0 ]; then
    status="FAIL"
    FAILURES=$((FAILURES + 1))
    FAILING_NAMES+="${name} "
  else
    status="PASS"
  fi

  printf "  %-18s  %s  exit=%s  time=%ss  log=%s\n" \
    "$name" "$status" "$rc" "$dur" "$log"

  if [ "$(python3 -c "import sys; print('1' if float(sys.argv[1]) > float(sys.argv[2]) else '0')" "$dur" "$SLOWEST_TIME")" = "1" ]; then
    SLOWEST_TIME=$dur
    SLOWEST_NAME=$name
  fi

  if [ "$rc" -ne 0 ]; then
    echo ""
    echo "  --- tail of $name log (last 30 lines) ---"
    tail -n 30 "$log" | sed 's/^/    /'
    echo "  --- end of $name log ---"
    echo ""
  fi
done

echo "run-gauntlet: summary — $FAILURES/$TOTAL layer(s) failed"
echo "run-gauntlet: slowest layer was ${SLOWEST_NAME:-none} at ${SLOWEST_TIME}s"

# gauntlet_run emission RETIRED 2026-06-25 (ADR 0006); the L5 ship-gate consumer
# (push-gate.sh) is gone — gauntlet_run was ship-gate evidence, now advisory-only.
# (The computational validation above is unchanged; only the journal event is dropped.)

exit "$FAILURES"
