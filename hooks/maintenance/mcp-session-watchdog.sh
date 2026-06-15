#!/usr/bin/env bash
# SessionStart advisory — probes MCP connections on startup/resume.
# Emits additionalContext warning if any MCP is degraded or broken.
# Non-blocking: exit 0 always. Operator must reauth manually (ADR 0002).
# shellcheck disable=SC2034
HOOK_HONOR_PROFILE_OFF=1
HOOK_ID="mcp-session-watchdog"
source "$(dirname "$0")/../_lib.sh" || exit 0
hook_init "$HOOK_ID" || exit 0

SCRIPT_DIR="$(dirname "$0")/../../scripts"
if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$SCRIPT_DIR/auth-health-check.py" ]; then
  exit 0
fi

RESULT=$(python3 "$SCRIPT_DIR/auth-health-check.py" --json 2>/dev/null) || true
EXIT_CODE=$?
[ "$EXIT_CODE" -eq 0 ] && exit 0  # All healthy — silent pass

# Degraded (1) or broken (2) — emit additionalContext warning visible at session start
SUMMARY=$(printf '%s' "$RESULT" | jq -r \
  '[.checks[] | select(.status != "healthy" and .status != "not_applicable") | .name + ": " + .summary] | join(", ")' \
  2>/dev/null || echo "unknown")
LABEL="degraded"
[ "$EXIT_CODE" -eq 2 ] && LABEL="BROKEN"

printf '{"additionalContext":"⚠️ MCP health %s — %s. Run: bash scripts/auth-health-check.py"}\n' \
  "$LABEL" "$SUMMARY"

( journal_append "$HOOK_ID" "mcp_health_warning" \
    "$(printf '{"exit_code":%d,"summary":"%s"}' "$EXIT_CODE" \
       "$(printf '%s' "$SUMMARY" | tr -d '"')")" \
    >/dev/null ) || true
exit 0
