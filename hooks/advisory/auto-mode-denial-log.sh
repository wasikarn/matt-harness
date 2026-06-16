#!/bin/bash
# PermissionDenied hook — append-only audit trail of auto-mode classifier denials.
# Fires when the auto-mode classifier blocks a tool call (hard_deny, soft_deny,
# or ask-escalation that the user declined). Captures what was blocked, why,
# and when — closing the silent-denial gap.
#
# Log: $HOME/.claude/auto-mode-denials.log
#   (tab-separated: ts \t session \t tool \t action \t reason \t excerpt)
#
# Design: read-only / never blocks. The hook itself cannot override the denial.
# Emits terminalSequence (OSC 9 desktop notification) on every denial — 2.1.141+.
# Bypass: CLAUDE_DISABLED_HOOKS=auto-mode-denial-log
#
# Related: [[feedback_auto_mode_operational_notes]] (fact 10: 3 consecutive
# denials OR 20 total per session → pause + prompt)

set -uo pipefail

HOOK_ID="auto-mode-denial-log"
LOG="$HOME/.claude/auto-mode-denials.log"
# This hook DELIBERATELY does NOT honor CLAUDE_HOOK_PROFILE=off (matches
# the original) — every denial is recorded even when the user is in
# "off" mode so the audit stream can't be silenced.
# shellcheck disable=SC2034  # read by _lib.sh hook_init (cross-file; shellcheck runs without -x)
HOOK_HONOR_PROFILE_OFF=0
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0

# Graceful fallback if jq missing (matches original semantics).
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "no-sid" \
    "unknown" \
    "denied" \
    "hook-jq-missing" \
    "" >> "$LOG"
  exit 0
fi

REASON=$(printf '%s\n' "$INPUT" | jq -r '.reason // "classifier-deny"' 2>/dev/null)

# Excerpt: command for Bash, file_path for Edit/Write/Read, url for WebFetch
EXCERPT=""
case "$TOOL" in
  Bash)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // ""' 2>/dev/null | tr '\n' ' ' | cut -c1-120)
    ;;
  Edit|Write|MultiEdit|Read)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // ""' 2>/dev/null | cut -c1-120)
    ;;
  WebFetch|WebSearch)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.url // ""' 2>/dev/null | cut -c1-120)
    ;;
  Skill)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.skill // ""' 2>/dev/null | cut -c1-120)
    ;;
  Agent)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.name // ""' 2>/dev/null | cut -c1-120)
    ;;
  *)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -rc '.' 2>/dev/null | cut -c1-120)
    ;;
esac

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$SID" \
  "$TOOL" \
  "denied" \
  "$REASON" \
  "$EXCERPT" >> "$LOG"

# Emit desktop notification via terminalSequence (OSC 9 — iTerm2, Terminal.app, etc.)
# Requires Claude Code 2.1.141+ to route terminalSequence without a controlling TTY.
NOTIFY_TOOL=$(printf '%s' "$TOOL" | sed 's/"/\\"/g')
NOTIFY_REASON=$(printf '%s' "$REASON" | sed 's/"/\\"/g')
printf '{"terminalSequence": "\\u001b]9;Auto-mode blocked: %s (%s)\\u0007"}\n' "$NOTIFY_TOOL" "$NOTIFY_REASON"

exit 0
