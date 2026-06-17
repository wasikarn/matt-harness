#!/bin/bash
# PostToolUse:Bash - review-pr-marker consumer.
#
# Goal: when a /review-pr session is active, catch the moment Claude commits
# changes and remind it to update the PR (or open one if no PR# was captured).
# skill-nudge + auto-review-nudge already cover the prompt-level "review PR N"
# trigger; this hook covers the OUTBOUND side - "you just committed, did you
# link it to the PR you were reviewing?"
#
# State (set by /review-pr skill on Phase 1 start, cleared on Phase 7 cleanup):
#   $STATE_DIR/review-pr-active  (default $HOME/.claude/state/)
#   Format: "pr=<int-or-empty>\nts=<unix-seconds>\n"
#
# Trigger (high-precision per Phase 2 user choice - PostToolUse:Bash):
#   tool_name  == "Bash"
#   AND command matches `git commit`
#   AND marker file exists
#   AND marker mtime < 30 min
#
# Side effects: stdout text only, exit 0. Never blocks the commit.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=review-pr-marker

set -uo pipefail
export LC_ALL=C

HOOK_ID="review-pr-marker"
STATE_DIR="${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}"
MARKER="$STATE_DIR/review-pr-active"
TTL_SECONDS=1800

source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

# Original soft-failed silently on missing jq (exit 0) — preserve.
command -v jq >/dev/null 2>&1 || exit 0

# Only act on Bash tool calls; lib already extracted $TOOL.
[ "$TOOL" = "Bash" ] || exit 0

# .tool_input.command is hook-specific; pull it directly (lib doesn't cover it).
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

# Marker gate (cheap)
[ -f "$MARKER" ] || exit 0

# Strip quoted strings + comments (block-dangerous-git convention).
STRIPPED=$(hook_strip_quoted "$COMMAND")

# Match `git commit` at start, after a separator, or end.
# Anchor at start, or require a separator before. The separator class covers
# ; & | and space - the common real-world joins before a fresh `git commit`.
GIT_COMMIT_RE='(^|[ ;&|])git[ ]+commit([ ]|$)'
if ! printf '%s' "$STRIPPED" | command grep -qE "$GIT_COMMIT_RE"; then
  exit 0
fi

# TTL check: marker mtime must be within last 30 min.
# GNU stat uses `-c %Y`; BSD stat uses `-f %m`. Try GNU first so Linux doesn't
# accidentally accept BSD's `--file-system` mode, which exits 0 with garbage.
MTIME=$(stat -c %Y "$MARKER" 2>/dev/null || stat -f %m "$MARKER" 2>/dev/null) || exit 0
NOW=$(date +%s)
AGE=$(( NOW - MTIME ))
[ "$AGE" -ge 0 ] && [ "$AGE" -lt "$TTL_SECONDS" ] || exit 0

# Parse optional PR# from marker
PR_LINE=$(grep -E '^pr=' "$MARKER" 2>/dev/null || true)
PR_NUMBER=$(printf '%s' "$PR_LINE" | sed -E 's/^pr=//' | tr -d ' ' | tr -d '\t')

if [ -n "$PR_NUMBER" ] && printf '%s' "$PR_NUMBER" | grep -qE '^[0-9]+$' && [ "$PR_NUMBER" -gt 0 ]; then
  CONTEXT="PR #$PR_NUMBER is still open"
  ACTION="link this commit to PR #$PR_NUMBER (push branch, or comment on the PR)"
else
  CONTEXT="a /review-pr session is active (no PR# captured - branch review)"
  ACTION="open a PR for the current branch before the session ends"
fi

printf '%s\n' \
  "[review-pr-marker] Heuristic match: git commit fired while $CONTEXT." \
  "$ACTION. This is a hook hint, not a directive (METHODOLOGY Rule 5)." \
  "Bypass: CLAUDE_DISABLED_HOOKS=review-pr-marker"

exit 0
