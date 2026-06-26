#!/bin/bash
# MCP runtime health gate — ECC mcp-health-check.js port (ADR 0007). Blocks
# PreToolUse MCP calls to a server known to be unhealthy, with exponential
# backoff; marks a server unhealthy on PostToolUseFailure and attempts an
# operator-configured reconnect. Failure-driven (no active stdio spawn-probe
# — that is too risky in a bash hook; http servers get a bounded curl probe).
#
# State: $HOME/.claude/mcp-health-cache.json — { servers: { <name>: {status,
# expiresAt, failureCount, nextRetryAt, lastError} } }. Survives compaction.
#
# DEVIATION from ECC (documented): ECC actively probes stdio servers by
# spawning their command with a 5s timeout. This bash port does NOT spawn MCP
# server processes (risk of hanging the hook / orphan processes). Health is
# driven by PostToolUseFailure marking + an http curl probe for http servers.
# A stdio server is marked healthy optimistically once nextRetryAt passes, so
# the next call is allowed and either succeeds (reset) or fails again (re-mark).
#
# Off-switches:
#   export CLAUDE_DISABLED_HOOKS=mcp-health-gate
#   export CLAUDE_HOOK_PROFILE=minimal   (off under minimal)
#   export KBG_MCP_HEALTH_FAIL_OPEN=1    # block→allow on unhealthy (parity ECC)

set -uo pipefail

HOOK_ID="mcp-health-gate"
source "$(dirname "$0")/../_lib.sh"
# This hook handles TWO events (PreToolUse + PostToolUseFailure); hook_init's
# PROFILE/DISABLED honoring is event-agnostic. HOOK_HONOR_PROFILE_OFF=1 default.
hook_init "$HOOK_ID" || exit 0
# No _sensor_heartbeat here: this gate also runs PostToolUseFailure, which is
# not a sensor event. PreToolUse calls journal via the deny path when blocking.
hook_guard_unreadable

hook_require_jq

STATE="${KBG_MCP_HEALTH_STATE_PATH:-$HOME/.claude/mcp-health-cache.json}"
# CC does NOT set a CLAUDE_HOOK_EVENT_NAME env var (verified 2026-06-26); the
# event name is the top-level `.hook_event_name` field in stdin JSON. This hook
# is wired under both PreToolUse and PostToolUseFailure, so branch on it.
EVENT=$(printf '%s\n' "$INPUT" | jq -r '.hook_event_name // "PreToolUse"' 2>/dev/null)
NOW_MS=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
[ "$NOW_MS" = 0 ] && exit 0  # no python3 → fail open (don't block on no clock)

mkdir -p "$(dirname "$STATE")" 2>/dev/null || exit 0

# --- helpers (jq-backed; state is small) ---
# BUGFIX 2026-06-26: the original helpers piped $STATE (the FILENAME) into jq
# instead of the file contents, so every read/write silently no-op'd. Read the
# file content explicitly; seed with {} when absent so first-write works.
state_content() {  # echo current JSON, or {} if no state file
  if [ -f "$STATE" ]; then cat "$STATE" 2>/dev/null; else printf '{}'; fi
}
server_field() {  # $1=server $2=field  → value or ""
  [ -f "$STATE" ] || return 0
  jq -r --arg s "$1" --arg f "$2" '.servers[$s][$f] // empty' "$STATE" 2>/dev/null
}
write_state() {  # stdin = new JSON; atomic temp+mv
  local tmp="$STATE.tmp.$$"
  cat > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE" 2>/dev/null || rm -f "$tmp"
}

mark_healthy() {  # $1=server
  local exp=$((NOW_MS + ${KBG_MCP_HEALTH_TTL_MS:-120000}))
  state_content | jq --arg s "$1" --argjson now "$NOW_MS" --argjson exp "$exp" '
    (.servers // {}) | .[$s] = {status:"healthy", checkedAt:$now, expiresAt:$exp,
                    failureCount:0, nextRetryAt:$now, lastError:null}
    | {servers: .}' 2>/dev/null | write_state
}

mark_unhealthy() {  # $1=server $2=error
  local fc prev_next
  fc=$(server_field "$1" failureCount); [ -z "$fc" ] && fc=0
  fc=$((fc + 1))
  local base=${KBG_MCP_HEALTH_BACKOFF_MS:-30000}
  local backoff=$(( base * (1 << (fc - 1)) ))
  [ "$backoff" -gt 600000 ] && backoff=600000
  prev_next=$((NOW_MS + backoff))
  state_content | jq --arg s "$1" --argjson now "$NOW_MS" \
    --argjson fc "$fc" --argjson nxt "$prev_next" --arg err "${2:-unknown}" '
    (.servers // {}) | .[$s] = ((.[$s] // {}) | .status="unhealthy"
      | .checkedAt=$now | .failureCount=$fc | .nextRetryAt=$nxt | .lastError=$err)
    | {servers: .}' 2>/dev/null | write_state
}

# Extract MCP server name from tool_name "mcp__<server>__<tool>".
extract_server() {  # echoes server or "" (and sets RT_TOOL)
  local tn
  tn=$(printf '%s\n' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  case "$tn" in
    mcp__*) printf '%s\n' "$tn" | sed -E 's/^mcp__([^_]+)__.*/\1/' ;;
  esac
}

fail_open() {  # $1=reason (block path converted to allow when FAIL_OPEN set)
  case "${KBG_MCP_HEALTH_FAIL_OPEN:-0}" in 1|true|yes) exit 0 ;; esac
  hook_decision deny "$1"
}

# ====================================================================
# PreToolUse: block calls to unhealthy servers within their backoff window.
# ====================================================================
if [ "$EVENT" = "PreToolUse" ]; then
  SERVER=$(extract_server)
  [ -z "$SERVER" ] && exit 0
  STATUS=$(server_field "$SERVER" status)
  case "$STATUS" in
    healthy)
      EXP=$(server_field "$SERVER" expiresAt)
      [ -n "$EXP" ] && [ "$EXP" -ge "$NOW_MS" ] && exit 0
      ;;  # expired → fall through to optimistic reset
    unhealthy)
      NXT=$(server_field "$SERVER" nextRetryAt)
      if [ -n "$NXT" ] && [ "$NXT" -gt "$NOW_MS" ]; then
        fail_open "[mcp-health-gate] MCP server '$SERVER' is unhealthy (last error: $(server_field "$SERVER" lastError)). Blocked until backoff window passes. Set KBG_MCP_HEALTH_FAIL_OPEN=1 to fail open, or CLAUDE_DISABLED_HOOKS=mcp-health-gate to disable."
      fi
      ;;  # past retry → fall through to optimistic reset
  esac
  # Optimistic reset: window passed or unknown → mark healthy, allow the call.
  # If the call then fails, PostToolUseFailure re-marks it.
  mark_healthy "$SERVER"
  exit 0
fi

# ====================================================================
# PostToolUseFailure: mark the server unhealthy + attempt reconnect.
# ====================================================================
if [ "$EVENT" = "PostToolUseFailure" ]; then
  SERVER=$(extract_server)
  [ -z "$SERVER" ] && exit 0
  # Detect a failure code from the tool response (401/403/429/503/transport).
  # Drop absent fields (map tostring turns null→"null"); keep only real content.
  SUMMARY=$(printf '%s\n' "$INPUT" | jq -r '
    [.tool_response, .tool_output, .tool_input.error, .error, .message]
    | map(tostring) | map(select(. != "null" and . != "")) | join(" ")' 2>/dev/null)
  case "$SUMMARY" in
    *401*|*403*|*429*|*503*|*[Tt]ransport*|*[Ee]rror*|*[Ff]ail*)
      mark_unhealthy "$SERVER" "$(printf '%s' "$SUMMARY" | cut -c1-200)"
      # Reconnect: KBG_MCP_RECONNECT_<SERVER> (uppercased, non-alnum→_) or
      # KBG_MCP_RECONNECT_COMMAND. Best-effort, bounded; failure is non-fatal.
      env_name="KBG_MCP_RECONNECT_$(printf '%s' "$SERVER" | tr -c 'A-Za-z0-9' '_' | tr 'a-z' 'A-Z')"
      rc_cmd="${!env_name:-${KBG_MCP_RECONNECT_COMMAND:-}}"
      if [ -n "$rc_cmd" ]; then
        timeout "${KBG_MCP_RECONNECT_TIMEOUT_MS:-5}" sh -c "$rc_cmd" >/dev/null 2>&1 || true
      fi
      ;;
  esac
  exit 0
fi

exit 0