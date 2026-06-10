#!/bin/bash
# Session summary hook — append a small handoff note at SessionEnd.
# Output: ~/.claude/sessions/<project-slug>.md (append-only, plain markdown).
#
# Bypass (matches block-dangerous-git.sh pattern):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=session-summary
#
# Failure mode: best-effort. Always exit 0 so a broken summary never blocks
# session end.

HOOK_ID="session-summary"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
SLUG=$(echo "$CWD" | sed 's|^/||; s|/|-|g' | tr '[:upper:]' '[:lower:]' | cut -c1-80)

SESSIONS_DIR="${HOME}/.claude/sessions"
mkdir -p "$SESSIONS_DIR" 2>/dev/null
SUMMARY_FILE="${SESSIONS_DIR}/${SLUG}.md"

TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
REASON=$(echo "$INPUT" | jq -r '.reason // empty' 2>/dev/null)
SESSION_ID_VAL=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null)
STATUS=$(git -C "$CWD" status --short 2>/dev/null | head -10)
COMMITS=$(git -C "$CWD" log --oneline -3 2>/dev/null)

{
  echo ""
  echo "## ${TIMESTAMP}${BRANCH:+ · ${BRANCH}}"
  [ -n "$REASON" ]     && echo "_reason: ${REASON}_"
  [ -n "$SESSION_ID_VAL" ] && echo "_session: ${SESSION_ID_VAL}_"
  echo "_cwd: ${CWD}_"
  echo ""
  if [ -n "$STATUS" ]; then
    echo "**Working copy:**"
    echo '```'
    echo "$STATUS"
    echo '```'
  fi
  if [ -n "$COMMITS" ]; then
    echo "**Recent commits:**"
    echo '```'
    echo "$COMMITS"
    echo '```'
  fi
  [ -n "$TRANSCRIPT" ] && echo "**Transcript:** \`${TRANSCRIPT}\`"
  echo ""
  echo "---"
} >> "$SUMMARY_FILE" 2>/dev/null

exit 0
