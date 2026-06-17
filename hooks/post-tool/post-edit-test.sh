#!/bin/bash
# PostToolUse:Edit|Write — async per-edit test runner (Computational/Feedback cell).
# Advisory only (async: true) — failure logs and notifies, never blocks.
#
# Closes the "Step 6" gap from the 9-step senior-engineer loop: the article requires
# a hook that runs the project's test suite after every file edit so failing tests
# surface immediately, not at ship time.
#
# Detection order (first match wins):
#   1. .claude/test-runner   — explicit project override (one-line command)
#   2. package.json + "test" script → npm test
#   3. pytest.ini / setup.cfg / pyproject.toml[tool.pytest] → python3 -m pytest -x -q
#   4. No match → exit 0 silently (project has not opted in)
#
# kbg-harness self-test: create .claude/test-runner with:
#   bash tests/hooks/runners/test-critical-hooks.sh 2>&1 | tail -5
#
# Log: $HOME/.claude/post-edit-test.log
# Bypass: CLAUDE_DISABLED_HOOKS=post-edit-test

set -uo pipefail

HOOK_ID="post-edit-test"
# shellcheck disable=SC2034  # read by _lib.sh hook_init (cross-file; shellcheck runs without -x)
HOOK_HONOR_PROFILE_OFF=0
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

LOG="$HOME/.claude/post-edit-test.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

FILE=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || exit 0
[ -z "$FILE" ] && exit 0

# Locate project root (git root or CWD).
ROOT=$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null || dirname "$FILE")

TS=$(date '+%Y-%m-%dT%H:%M:%S')
TEST_CMD=""

# 1. Explicit project override.
if [ -f "$ROOT/.claude/test-runner" ]; then
  TEST_CMD=$(head -1 "$ROOT/.claude/test-runner")
fi

# 2. package.json with test script.
if [ -z "$TEST_CMD" ] && [ -f "$ROOT/package.json" ]; then
  HAS_TEST=$(jq -r '.scripts.test // empty' "$ROOT/package.json" 2>/dev/null)
  [ -n "$HAS_TEST" ] && TEST_CMD="npm test --prefix \"$ROOT\" 2>&1"
fi

# 3. pytest marker.
if [ -z "$TEST_CMD" ]; then
  if [ -f "$ROOT/pytest.ini" ] || [ -f "$ROOT/setup.cfg" ]; then
    TEST_CMD="python3 -m pytest -x -q \"$ROOT\" 2>&1"
  elif [ -f "$ROOT/pyproject.toml" ] && grep -q '\[tool.pytest' "$ROOT/pyproject.toml" 2>/dev/null; then
    TEST_CMD="python3 -m pytest -x -q \"$ROOT\" 2>&1"
  fi
fi

# No test framework detected — project has not opted in.
[ -z "$TEST_CMD" ] && exit 0

OUTPUT=$(eval "$TEST_CMD" 2>&1 | tail -20) || true
EXIT_CODE=$?

printf '%s\t%s\t%s\texitcode=%s\t%s\n' "$TS" "$SID" "$FILE" "$EXIT_CODE" "${OUTPUT//$'\n'/ | }" >> "$LOG"

if [ "$EXIT_CODE" -ne 0 ]; then
  printf '\033]9;%s\007' "post-edit-test: tests FAILED after editing $(basename "$FILE") — check ~/.claude/post-edit-test.log" >&2
fi

exit 0
