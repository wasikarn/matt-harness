#!/usr/bin/env bash
# model-bench.sh — run claude plugin eval against two subject models and diff the scores.
# See SKILL.md for usage. Orchestration only; parsing/report logic lives in model-bench-diff.py
# (kept out of this file per a recorded incident: embedded python in bash can brick Bash
# tool calls repo-wide on a stray apostrophe — GH #146).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIFF_PY="$SCRIPT_DIR/model-bench-diff.py"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  model-bench.sh <model-a> <model-b> [-- <claude plugin eval args>]
  model-bench.sh --diff-only --label-a <name> --label-b <name> <a>/aggregate-result.json <b>/aggregate-result.json
EOF
}

# has_flag <flag-name> <args...> — true if --flag or --flag=... appears among the args.
has_flag() {
  local flag="$1"; shift
  local arg
  for arg in "$@"; do
    case "$arg" in
      "$flag"|"$flag"=*) return 0 ;;
    esac
  done
  return 1
}

if [ "${1:-}" = "--diff-only" ]; then
  shift
  python3 "$DIFF_PY" "$@"
  exit $?
fi

if [ $# -lt 2 ]; then
  usage >&2
  exit 1
fi

MODEL_A="$1"
MODEL_B="$2"
shift 2

EXTRA_ARGS=()
if [ "${1:-}" = "--" ]; then
  shift
  EXTRA_ARGS=("$@")
fi

DEFAULT_ARGS=()
has_flag --ablation "${EXTRA_ARGS[@]:-}" || DEFAULT_ARGS+=(--ablation none)
has_flag --threshold "${EXTRA_ARGS[@]:-}" || DEFAULT_ARGS+=(--threshold 0)
has_flag --max-cost-usd "${EXTRA_ARGS[@]:-}" || DEFAULT_ARGS+=(--max-cost-usd 5)

cd "$ROOT" || exit 1
mkdir -p evals/results
BENCH_DIR="$(mktemp -d "evals/results/model-bench-XXXXXX")"

DIR_A="$BENCH_DIR/a"
DIR_B="$BENCH_DIR/b"
mkdir -p "$DIR_A" "$DIR_B"

run_arm() {
  local model="$1" out_dir="$2"
  claude plugin eval . --model "$model" --output-dir "$out_dir" --no-publish \
    "${DEFAULT_ARGS[@]:-}" "${EXTRA_ARGS[@]:-}"
  local status=$?
  # exit 1 (--threshold) and 2 (--max-cost-usd abort) still wrote a valid result file — proceed.
  # Anything else is an unexpected failure for this arm.
  if [ "$status" -ne 0 ] && [ "$status" -ne 1 ] && [ "$status" -ne 2 ]; then
    echo "model-bench: arm ($model) failed unexpectedly, exit $status" >&2
    return "$status"
  fi
  return 0
}

run_arm "$MODEL_A" "$DIR_A" || exit $?
run_arm "$MODEL_B" "$DIR_B" || exit $?

RESULT_A="$(find "$DIR_A" -name aggregate-result.json | head -n1)"
RESULT_B="$(find "$DIR_B" -name aggregate-result.json | head -n1)"

if [ -z "$RESULT_A" ] || [ -z "$RESULT_B" ]; then
  echo "model-bench: missing aggregate-result.json for one or both arms (A: ${RESULT_A:-<none>}, B: ${RESULT_B:-<none>})" >&2
  exit 1
fi

python3 "$DIFF_PY" --label-a "$MODEL_A" --label-b "$MODEL_B" "$RESULT_A" "$RESULT_B"
