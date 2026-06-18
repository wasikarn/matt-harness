#!/bin/bash
# ideate-memory-capture.sh — SessionEnd hook that captures kbg:ideate runs
# into a qmd-backed memory collection.
#
# Advisory only. Never blocks. Never mutates the repo. Calls
# scripts/ideate-memory.py to persist each ideate problem + output as a
# markdown file under ~/.claude/state/ideate-memory/ and updates the qmd index.
#
# The persisted files are later searchable via /ideate-search or directly with:
#   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/ideate-memory.py" search "<query>"
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=ideate-memory-capture
#
# Failure mode: silent. Always exit 0.

HOOK_ID="ideate-memory-capture"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

STATE_DIR="${HOME}/.claude/state"
mkdir -p "$STATE_DIR" || exit 0

TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$SESSION_ID_VAL" ] || SESSION_ID_VAL="no-sid"

# No transcript path = nothing to capture (normal for very short sessions).
[ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ] && exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SCRIPT="${PLUGIN_ROOT}/scripts/ideate-memory.py"

# Capture any ideate runs from the transcript synchronously (cheap, depends
# only on transcript size).
if [ -x "${SCRIPT}" ] || [ -f "${SCRIPT}" ]; then
  python3 "$SCRIPT" capture --transcript "$TRANSCRIPT" --session-id "$SESSION_ID_VAL" >/dev/null 2>&1 || true

  # Update + embed the qmd collection so the new runs are eventually searchable.
  # This is done asynchronously because qmd embed can take 10s+ as the collection
  # grows; SessionEnd hooks must return before Claude CLI kills them.
  if command -v qmd >/dev/null 2>&1; then
    nohup python3 "$SCRIPT" index >/dev/null 2>&1 &
  fi
fi

exit 0
