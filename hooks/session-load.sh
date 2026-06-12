#!/bin/bash
# Session-load — SessionStart companion to session-summary.sh.
# Reads the most recent entry from ~/.claude/sessions/<project-slug>.md and
# prints it to stdout wrapped in <previous-session-summary>...</> so Claude
# Code injects it as context. Completes the save→load handoff cycle.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=session-load
#
# Failure mode: silent. Always exit 0; never block SessionStart.

HOOK_ID="session-load"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
SLUG=$(printf '%s\n' "$CWD" | sed 's|^/||; s|/|-|g' | tr '[:upper:]' '[:lower:]' | cut -c1-80)

SUMMARY_FILE="${HOME}/.claude/sessions/${SLUG}.md"

# Bail silently if no summary file or file is empty
[ -s "$SUMMARY_FILE" ] || exit 0

# Age-based stale-state check (pattern lifted from oh-my-claudecode v4.14.0
# deep-dive analysis — see wiki/ai-agents/oh-my-claudecode-v4.14.0-deep-dive.md):
# if the last session entry is older than MAX_AGE_DAYS (default 14), inject a
# stale marker instead of the full summary so Claude knows the context exists
# but is likely out of date. Configurable via env var; 0 disables the check.
MAX_AGE_DAYS="${CLAUDE_SESSION_SUMMARY_MAX_AGE_DAYS:-14}"

if [ "$MAX_AGE_DAYS" -gt 0 ] 2>/dev/null; then
  if [ "$(uname -s)" = "Darwin" ]; then
    MTIME=$(stat -f %m "$SUMMARY_FILE" 2>/dev/null)
  else
    MTIME=$(stat -c %Y "$SUMMARY_FILE" 2>/dev/null)
  fi
  if [ -n "$MTIME" ]; then
    NOW=$(date +%s)
    AGE_SECONDS=$((NOW - MTIME))
    MAX_AGE_SECONDS=$((MAX_AGE_DAYS * 86400))
    if [ "$AGE_SECONDS" -gt "$MAX_AGE_SECONDS" ]; then
      AGE_DAYS=$((AGE_SECONDS / 86400))
      printf '<previous-session-summary status="stale" age-days="%d">\nLast session in this project was %d days ago — context likely outdated. Re-check git state before relying on prior decisions.\n</previous-session-summary>\n' "$AGE_DAYS" "$AGE_DAYS"
      exit 0
    fi
  else
    # Both stat branches failed (unrecognised OS or missing file) — surface so operator can debug.
    printf 'session-load: could not stat %s (uname=%s)\n' "$SUMMARY_FILE" "$(uname -s)" >&2
  fi
fi

# Extract just the LAST entry: everything from the final "## " heading to EOF.
# Awk accumulator resets on each "## " heading; END prints what survived.
LAST_ENTRY=$(awk '/^## / { entry = "" } { entry = entry $0 ORS } END { print entry }' "$SUMMARY_FILE")

[ -z "$LAST_ENTRY" ] && exit 0

printf '<previous-session-summary>\n%s</previous-session-summary>\n' "$LAST_ENTRY"

exit 0
