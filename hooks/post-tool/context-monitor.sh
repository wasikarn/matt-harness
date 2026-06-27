#!/bin/bash
# Context/scope/loop monitor — ECC ecc-context-monitor.js port (CLAUDE.md §Hook architecture (current profile ladder design)).
# PostToolUse observe-only: tracks files modified this session and the recent
# tool sequence, then surfaces advisory friction when scope or loop thresholds
# trip. Emits additionalContext (a stderr/JSON hint CC shows the agent) and
# exits 0 — NEVER blocks, NEVER mutates the call.
#
# Parity scope (deferred deviations documented inline):
#   ✅ scope:   files_modified_count > 20  → "you've touched N files, consider
#              stepping back / committing a checkpoint"
#   ✅ loop:    same tool_name repeated ≥3 in the last 6 PostToolUse events →
#              "repeating <tool> — is a loop forming? state the goal."
#   ⬜ context%: needs a statusline bridge producer kbg doesn't ship yet
#              (context_remaining_pct). Deferred — gated on KBG_CONTEXT_MONITOR_FILE.
#   ⬜ cost USD: needs a metrics bridge (total_cost_usd). Deferred — same gate.
#
# State: $HOME/.claude/context-monitor/<session>.jsonl — append-only event log
# {ts, tool, file}. Survives compaction; 30-min idle resets (parity ECC).
#
# Off-switches:
#   export CLAUDE_HOOK_PROFILE=minimal   (off under minimal)
#   export CLAUDE_DISABLED_HOOKS=context-monitor
#   export KBG_CONTEXT_MONITOR_DISABLED=1

set -uo pipefail

HOOK_ID="context-monitor"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
# PostToolUse is observe-only; no _sensor_heartbeat (that's a PreToolUse event).
hook_guard_unreadable
hook_require_jq

[ "${KBG_CONTEXT_MONITOR_DISABLED:-0}" = "1" ] && exit 0

STATE_DIR="$HOME/.claude/context-monitor"
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
sid_safe=$(printf '%s' "${SID:-no-sid}" | tr -c 'a-zA-Z0-9_' '_')
STATE_FILE="$STATE_DIR/$sid_safe.jsonl"

# 30-min idle reset: if the log is older than that, truncate it.
if [ -f "$STATE_FILE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$STATE_FILE" 2>/dev/null || echo 0) ))
  [ "$age" -gt 1800 ] && : > "$STATE_FILE" 2>/dev/null
fi

TOOL_NAME="${TOOL:-}"
# file path for Edit/Write/MultiEdit; best-effort
FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // .path // (.edits[0].file_path // empty)' 2>/dev/null)

# Append this event to the session log (one JSON line, atomic append).
now=$(date +%s 2>/dev/null || echo 0)
printf '{"ts":%s,"tool":%s,"file":%s}\n' "$now" \
  "$(printf '%s' "$TOOL_NAME" | jq -Rs . 2>/dev/null)" \
  "$(printf '%s' "$FILE_PATH" | jq -Rs . 2>/dev/null)" \
  >> "$STATE_FILE" 2>/dev/null

# --- scope check: distinct files modified this session ---
SCOPE_THRESHOLD="${KBG_CONTEXT_MONITOR_SCOPE:-20}"
case "$SCOPE_THRESHOLD" in ''|*[!0-9]*) SCOPE_THRESHOLD=20 ;; esac
distinct_files=$(jq -r 'select(.file!="") | .file' "$STATE_FILE" 2>/dev/null | sort -u | wc -l | tr -d ' ')
warn=""
if [ "${distinct_files:-0}" -gt "$SCOPE_THRESHOLD" ]; then
  warn="[context-monitor] You've modified $distinct_files distinct files this session (threshold $SCOPE_THRESHOLD). Consider stepping back: is the change still one coherent unit? Commit a checkpoint before expanding scope further."
fi

# --- loop check: same tool repeated ≥ LOOP_THRESHOLD in the last WINDOW events ---
LOOP_THRESHOLD="${KBG_CONTEXT_MONITOR_LOOP:-3}"
WINDOW="${KBG_CONTEXT_MONITOR_WINDOW:-6}"
case "$LOOP_THRESHOLD" in ''|*[!0-9]*) LOOP_THRESHOLD=3 ;; esac
case "$WINDOW" in ''|*[!0-9]*) WINDOW=6 ;; esac
if [ -z "$warn" ] && [ -n "$TOOL_NAME" ]; then
  # Count occurrences of the current tool in the last WINDOW events.
  recent=$(tail -n "$WINDOW" "$STATE_FILE" 2>/dev/null | jq -r '.tool // empty' 2>/dev/null)
  repeats=$(printf '%s\n' "$recent" | grep -cxF "$TOOL_NAME" 2>/dev/null || echo 0)
  if [ "$repeats" -ge "$LOOP_THRESHOLD" ]; then
    warn="[context-monitor] Tool '$TOOL_NAME' has fired $repeats times in the last $WINDOW operations. Is a loop forming? State the goal in one line before the next $TOOL_NAME."
  fi
fi

# --- context% / cost (deferred; only if an operator wires a bridge file) ---
BRIDGE="${KBG_CONTEXT_MONITOR_FILE:-}"
if [ -z "$warn" ] && [ -n "$BRIDGE" ] && [ -f "$BRIDGE" ]; then
  ctx_pct=$(jq -r '.context_remaining_pct // empty' "$BRIDGE" 2>/dev/null)
  cost=$(jq -r '.total_cost_usd // empty' "$BRIDGE" 2>/dev/null)
  if [ -n "$ctx_pct" ] && [ "$ctx_pct" -lt "${KBG_CONTEXT_MONITOR_CTX_LOW:-25}" ] 2>/dev/null; then
    warn="[context-monitor] Context low: ${ctx_pct}% remaining. Wrap up the current unit; avoid large reads."
  elif [ -n "$cost" ] && [ "$(printf '%s' "$cost" | awk '{print ($1>50)?1:0}' 2>/dev/null)" = "1" ]; then
    warn="[context-monitor] Session cost \$$cost exceeds \$50 — consider whether further spend is justified."
  fi
fi

[ -z "$warn" ] && exit 0

# Observe-only: surface as additionalContext (CC injects into agent context).
# PostToolUse contract (verified code.claude.com/docs/en/hooks 2026-06-26):
# additionalContext MUST live under hookSpecificOutput with the matching
# hookEventName; top-level {"additionalContext":...} is silently ignored.
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' \
  "$(printf '%s' "$warn" | jq -Rs . 2>/dev/null)"
exit 0