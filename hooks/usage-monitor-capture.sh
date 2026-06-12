#!/usr/bin/env bash
# usage-monitor-capture.sh — SessionEnd capture for nested-team token cost.
# Reads the session transcript, extracts claude_code.llm_request and
# claude_code.tool spans with agent_id / parent_agent_id attributes
# (vendor v2.1.139/145), appends one JSONL line per session to
# ~/.claude/usage/<project-slug>.jsonl.
#
# Strictly read-only + opt-in:
#   - Gated on KBG_USAGE_MONITOR=1; without it, exits 0 immediately.
#   - Best-effort: any failure logs to auto-mode-denial-log.sh and exits 0.
#   - Never blocks session end.
#
# Bypass (matches session-summary.sh pattern):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=usage-monitor-capture
#
# Honors ADR 0002 (autonomy invariant): L2-only, no enforcement, no gate.
# This is the D9 resolution from 2026-06-12 (passive monitor, owner chose A).

HOOK_ID="usage-monitor-capture"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

# Opt-in gate. Without the env var, do nothing.
if [ "${KBG_USAGE_MONITOR:-}" != "1" ]; then
  exit 0
fi

# Read session metadata from the hook input (same pattern as session-summary.sh:14-16).
CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
TRANSCRIPT=$(printf '%s\n' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID_VAL=$(printf '%s\n' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
REASON=$(printf '%s\n' "$INPUT" | jq -r '.reason // empty' 2>/dev/null)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# If there's no transcript, there's nothing to capture. Don't log — this is
# normal for `/clear` and other short sessions.
[ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ] && exit 0

# Extract span records from the transcript. The vendor's
# claude_code.llm_request and claude_code.tool spans include:
#   - agent_id          (the sub-agent making the call, or null for the main agent)
#   - parent_agent_id   (the agent that spawned this one, null for top-level)
#   - input_tokens / output_tokens (from llm_request)
#   - tool_name (from tool spans)
# The exact field names follow vendor v2.1.139/145 — see the
# article-revalidation-2026-06-12 delta for the verified text.
SPANS=$(jq -c '
  [.messages[]?
    | select(.type == "tool_use" or .type == "assistant")
    | select(.agent_id or .parent_agent_id or .tool_name or .input_tokens)
    | {
        agent_id:          (.agent_id // null),
        parent_agent_id:   (.parent_agent_id // null),
        tool_name:         (.tool_name // null),
        input_tokens:      (.input_tokens // 0),
        output_tokens:     (.output_tokens // 0),
        ts:                (.timestamp // null)
      }
  ]
' "$TRANSCRIPT" 2>/dev/null)

# If the extraction failed or returned nothing useful, skip quietly.
if [ -z "$SPANS" ] || [ "$SPANS" = "[]" ] || [ "$SPANS" = "null" ]; then
  exit 0
fi

# Project-slug: same scheme as session-summary.sh:11.
SLUG=$(printf '%s\n' "$CWD" | sed 's|^/||; s|/|-|g' | tr '[:upper:]' '[:lower:]' | cut -c1-80)
USAGE_DIR="${HOME}/.claude/usage"
USAGE_FILE="${USAGE_DIR}/${SLUG}.jsonl"

# P1: fail loud on mkdir failure instead of silently dropping usage data.
if ! mkdir -p "$USAGE_DIR" 2>/dev/null; then
  echo "[$HOOK_ID] ERROR: cannot create usage directory $USAGE_DIR" >&2
  exit 0  # still best-effort — never block session end
fi

# Aggregate the spans into one JSONL line per session.
# Schema (one line per session):
#   { "session_id": "...", "ts": "...", "reason": "...",
#     "cwd": "...", "spans": [ {agent_id, parent_agent_id, ...} ] }
# P1: fail loud on jq write failure instead of silently dropping usage data.
if ! jq -nc \
  --arg session_id "$SESSION_ID_VAL" \
  --arg ts "$TIMESTAMP" \
  --arg reason "$REASON" \
  --arg cwd "$CWD" \
  --argjson spans "$SPANS" \
  '{
    session_id: $session_id,
    ts:         $ts,
    reason:     $reason,
    cwd:        $cwd,
    spans:      $spans
  }' >> "$USAGE_FILE" 2>/dev/null; then
  echo "[$HOOK_ID] ERROR: failed to write usage data to $USAGE_FILE" >&2
fi

# Always exit 0 — capture failures never block session end.
exit 0
