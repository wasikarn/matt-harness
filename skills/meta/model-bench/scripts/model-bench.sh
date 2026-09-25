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
  model-bench.sh <model-a>[@effort] <model-b>[@effort] [-- <claude plugin eval args>]
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

# parse_arm <spec> -> sets ARM_MODEL / ARM_EFFORT (ARM_EFFORT empty for a bare model). The CLI's
# own --effort flag never reaches an eval child (verified live, 2026-09-25); CLAUDE_CODE_EFFORT_LEVEL
# set on the child's own environment does, so that's what a bare arm must NOT set (leave the
# ambient env exactly as today) and an @effort arm must set for that one invocation only.
parse_arm() {
  local spec="$1" rest
  case "$spec" in
    *@*@*)
      echo "model-bench: '$spec' has more than one '@' -- use <model>[@effort]" >&2
      return 1 ;;
  esac
  if [ "${spec#*@}" = "$spec" ]; then
    ARM_MODEL="$spec"; ARM_EFFORT=""
    return 0
  fi
  ARM_MODEL="${spec%%@*}"
  rest="${spec#*@}"
  if [ -z "$ARM_MODEL" ] || [ -z "$rest" ]; then
    echo "model-bench: '$spec' is malformed -- use <model>[@effort], not a bare '@', '@effort', or 'model@'" >&2
    return 1
  fi
  case "$rest" in
    low|medium|high|xhigh|max) ARM_EFFORT="$rest" ;;
    *)
      echo "model-bench: '$spec' has an unknown effort '$rest' -- must be one of low|medium|high|xhigh|max" >&2
      return 1 ;;
  esac
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

MODEL_A_SPEC="$1"
MODEL_B_SPEC="$2"
shift 2

parse_arm "$MODEL_A_SPEC" || { usage >&2; exit 1; }
MODEL_A="$ARM_MODEL"; EFFORT_A="$ARM_EFFORT"
parse_arm "$MODEL_B_SPEC" || { usage >&2; exit 1; }
MODEL_B="$ARM_MODEL"; EFFORT_B="$ARM_EFFORT"

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
  local model="$1" effort="$2" out_dir="$3"
  local spec="$model"
  [ -n "$effort" ] && spec="$model@$effort"
  {
    echo "arm: $spec"
    echo "model: $model"
    echo "effort: ${effort:-<inherit session effort>}"
    echo "claude_version: $(claude --version 2>&1)"
    echo "timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -n "$effort" ]; then
      echo "command: CLAUDE_CODE_EFFORT_LEVEL=$effort claude plugin eval . --model $model --output-dir $out_dir --no-publish ${DEFAULT_ARGS[*]:-} ${EXTRA_ARGS[*]:-}"
    else
      echo "command: claude plugin eval . --model $model --output-dir $out_dir --no-publish ${DEFAULT_ARGS[*]:-} ${EXTRA_ARGS[*]:-}"
    fi
  } > "$out_dir/arm-meta.txt"

  if [ -n "$effort" ]; then
    CLAUDE_CODE_EFFORT_LEVEL="$effort" claude plugin eval . --model "$model" --output-dir "$out_dir" --no-publish \
      "${DEFAULT_ARGS[@]:-}" "${EXTRA_ARGS[@]:-}"
  else
    claude plugin eval . --model "$model" --output-dir "$out_dir" --no-publish \
      "${DEFAULT_ARGS[@]:-}" "${EXTRA_ARGS[@]:-}"
  fi
  local status=$?
  # exit 1 (--threshold) and 2 (--max-cost-usd abort) still wrote a valid result file — proceed.
  # Anything else is an unexpected failure for this arm.
  if [ "$status" -ne 0 ] && [ "$status" -ne 1 ] && [ "$status" -ne 2 ]; then
    echo "model-bench: arm ($spec) failed unexpectedly, exit $status" >&2
    return "$status"
  fi
  return 0
}

run_arm "$MODEL_A" "$EFFORT_A" "$DIR_A" || exit $?
run_arm "$MODEL_B" "$EFFORT_B" "$DIR_B" || exit $?

RESULT_A="$(find "$DIR_A" -name aggregate-result.json | head -n1)"
RESULT_B="$(find "$DIR_B" -name aggregate-result.json | head -n1)"

if [ -z "$RESULT_A" ] || [ -z "$RESULT_B" ]; then
  echo "model-bench: missing aggregate-result.json for one or both arms (A: ${RESULT_A:-<none>}, B: ${RESULT_B:-<none>})" >&2
  exit 1
fi

python3 "$DIFF_PY" --label-a "$MODEL_A_SPEC" --label-b "$MODEL_B_SPEC" "$RESULT_A" "$RESULT_B"
