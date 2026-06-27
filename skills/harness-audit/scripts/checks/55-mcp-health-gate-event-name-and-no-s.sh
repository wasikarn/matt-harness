# 55. mcp-health-gate event-name contract (CLAUDE.md §Hook architecture (current profile ladder design)) — this gate is wired under
# TWO events (PreToolUse:mcp__.* and PostToolUseFailure), so it MUST branch on
# stdin `.hook_event_name`. There is NO `CLAUDE_HOOK_EVENT_NAME` env var (verified
# contract #3) — branching on the non-existent env var silently makes both
# branches fall through and the gate never marks/retries. The positive contract
# (reads .hook_event_name) is the load-bearing assertion; the negative (no
# CODE-LINE branch on CLAUDE_HOOK_EVENT_NAME) guards the regression where a
# re-import re-adds the env branch. Comments are stripped before both greps:
# the file's header documents both the env-var's non-existence AND the
# `.hook_event_name` field, so a comment-only mention must not satisfy the
# positive check nor trip the negative one. CRIT: the failure mode is the gate
# silently no-opping across both wired events.
_F=$(find "$CLAUDE_DIR/hooks" -type f -name "mcp-health-gate.sh" 2>/dev/null | head -1)
if [ -f "$_F" ]; then
  _code=$(sed '/^[[:space:]]*#/d' "$_F" 2>/dev/null)
  printf '%s\n' "$_code" | /usr/bin/grep -qE '\.hook_event_name' \
    || crit "mcp-health-gate.sh: does not read .hook_event_name from stdin — a CLAUDE_HOOK_EVENT_NAME env branch silently no-ops both wired events (CLAUDE.md §Hook architecture (current profile ladder design) contract #3)"
  if printf '%s\n' "$_code" | /usr/bin/grep -qE 'CLAUDE_HOOK_EVENT_NAME'; then
    crit "mcp-health-gate.sh: code branches on CLAUDE_HOOK_EVENT_NAME — that env var does not exist (CLAUDE.md §Hook architecture (current profile ladder design) contract #3); use stdin .hook_event_name"
  fi
fi