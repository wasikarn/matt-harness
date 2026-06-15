#!/bin/bash
# Log every WebFetch URL to a per-session audit trail. Supports
# METHODOLOGY Rule 1 (Think before coding) — verifiable record of "what
# external sources did the agent consult before claiming a fact?".
# Never blocks; append-only.
#
# Log: ~/.claude/evidence-trail.log  (tab-separated: ts \t session \t tool \t url)
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=evidence-trail-log

HOOK_ID="evidence-trail-log"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

case "$TOOL" in
  WebFetch|WebSearch) ;;
  *) exit 0 ;;
esac

URL=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.url // .query // empty' 2>/dev/null)
[ -z "$URL" ] && exit 0

hook_audit_log evidence-trail "$TOOL" "$URL"
exit 0
