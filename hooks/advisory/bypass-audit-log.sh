#!/bin/bash
# Append-only audit trail of hook bypasses. Fires on every PreToolUse;
# when CLAUDE_DISABLED_HOOKS or CLAUDE_HOOK_PROFILE=off is in effect,
# log the tool invocation with bypass context. Never blocks.
#
# Closes the long-standing audit-trail gap (originally prose-only /
# compensating control). Now structurally enforced.
#
# Log: $HOME/.claude/bypass-audit.log  (tab-separated: ts \t session \t profile \t disabled \t tool \t excerpt)
#
# Bypass: CLAUDE_DISABLED_HOOKS=bypass-audit-log (explicit only).
# This hook DELIBERATELY does NOT honor CLAUDE_HOOK_PROFILE=off — that's
# the most aggressive bypass mode and the one we most need to audit.
# Closes 2026-05-20 audit H1 (PROFILE=off audit blind spot).

HOOK_ID="bypass-audit-log"
# Standard sessions (no bypass) are not logged; we want bypass events only.
# So the lib's PROFILE=off early-exit is NOT the right gate here — we
# short-circuit manually when no bypass is in effect.
# shellcheck disable=SC2034  # read by _lib.sh hook_init (cross-file; shellcheck runs without -x)
HOOK_HONOR_PROFILE_OFF=0
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

# Only log when bypass is in effect. Standard sessions (no bypass) are not logged.
DISABLED="${CLAUDE_DISABLED_HOOKS:-}"
PROFILE_VAL="${CLAUDE_HOOK_PROFILE:-standard}"
if [ -z "$DISABLED" ] && [ "$PROFILE_VAL" = "standard" ]; then
  exit 0
fi

# Fallback: if jq couldn't parse the input at all, surface it so the operator knows the audit log dropped an entry.
if [ -z "$TOOL" ]; then
  printf '%s\t%s\t%s\t[%s]\t%s\t%s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$SID" \
    "$PROFILE_VAL" \
    "${DISABLED:-none}" \
    "malformed-input" \
    "(jq failed to parse hook input)" >> "$HOME/.claude/bypass-audit.log"
  exit 0
fi

# Brief tool-input excerpt (first 100 chars of most-relevant field).
EXCERPT=""
case "$TOOL" in
  Bash)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // ""' 2>/dev/null | tr '\n' ' ' | cut -c1-100)
    ;;
  Edit|Write|MultiEdit)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // ""' 2>/dev/null | cut -c1-100)
    ;;
  WebFetch)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.url // ""' 2>/dev/null | cut -c1-100)
    ;;
  *)
    EXCERPT=$(printf '%s\n' "$TOOL_INPUT" | jq -rc '.' 2>/dev/null | cut -c1-100)
    ;;
esac

printf '%s\t%s\t%s\t[%s]\t%s\t%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$SID" \
  "$PROFILE_VAL" \
  "${DISABLED:-none}" \
  "$TOOL" \
  "$EXCERPT" >> "$HOME/.claude/bypass-audit.log"

# Mirror into the unified governance journal (JOURNAL-SCHEMA: the journal
# replaces the scatter of per-hook TSV logs). Dual-write — governance-summary.py
# still reads the .log. Subshell + `|| true` contains journal_append's exit-2.
( journal_append "$HOOK_ID" "hook_bypass" \
    "$(jq -nc --arg profile "$PROFILE_VAL" --arg disabled "${DISABLED:-none}" --arg tool "$TOOL" --arg excerpt "$EXCERPT" \
       '{profile:$profile,disabled:$disabled,tool:$tool,excerpt:$excerpt}')" >/dev/null 2>&1 ) || true

exit 0
