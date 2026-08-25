#!/usr/bin/env bash
# Advisory (#97): PostToolUseFailure sensor for MCP tool call failures.
# Purely passive -- observes failures Claude Code already surfaces via the
# PostToolUseFailure event. Never probes server reachability, never
# auto-reconnects. ECC built a fuller version of this exact idea (HTTP
# probing, exponential backoff, active reconnect, 720 LoC) and their own
# team later marked it low adoption signal: "the harness already retries
# failed MCP calls; this solves a problem Claude Code already handles."
# This stays a thin observer on top of that existing retry behavior.
#
# Verified against the official docs (2026-08-25, #97): PostToolUseFailure
# is a DISTINCT hook event from PostToolUse (not a field inside it) --
# fires "when a tool that started executing fails: the tool threw an error,
# or an MCP tool returned an error result." Payload carries tool_name,
# tool_input, tool_use_id, and a top-level `error` string
# (code.claude.com/docs/en/hooks#posttoolusefailure-input).
#
# Window is TIME-based (last N seconds), not a call-count ring buffer like
# loop-repeat-nudge.sh's "last 5 calls" -- this hook only fires on failures,
# so every invocation is already a failure; the question isn't "how often
# among recent calls" but "is this server currently unhealthy right now,"
# which is a rate-over-time question. Dedup-on-message-content (not a raw
# counter) mirrors loop-repeat-nudge.sh's rationale: re-emitting on every
# single failure past threshold is the exact anti-pattern ECC's own notes
# flag.
#
# ponytail: unbounded per-session file growth under
# $HOME/.local/share/kbg/mcp-failure-nudge/ (one .ring + one .lastmsg per
# unique session/server combo, ever), same precedent as
# instructions-loaded-journal.sh and skill-usage-telemetry.sh -- rotate/trim
# manually if it grows large.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

WINDOW_SECONDS="${MH_MCP_FAILURE_WINDOW_SECONDS:-300}"
THRESHOLD="${MH_MCP_FAILURE_THRESHOLD:-3}"

payload=$(cat)
[ -n "$payload" ] || exit 0

session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null) || exit 0
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
error_text=$(printf '%s' "$payload" | jq -r '.error // ""' 2>/dev/null) || exit 0

# MCP tools only -- a failing Bash command or Edit is out of scope; this
# sensor is specifically about MCP server health.
case "$tool_name" in
  mcp__*) ;;
  *) exit 0 ;;
esac

# Parse the server slug out of mcp__<server>__<tool> -- same naming pattern
# atlassian-mcp-gate.sh already relies on (there it's regex-matched for a
# yes/no check; here it's extracted because failures need a per-server
# bucket, not just a boolean).
rest="${tool_name#mcp__}"
server="${rest%%__*}"
[ -n "$server" ] || exit 0

# session_id/server are model/session-controlled -- sanitize before they
# become part of a filesystem path (same convention as loop-repeat-nudge.sh).
session_safe="${session_id//[^A-Za-z0-9_-]/_}"
server_safe="${server//[^A-Za-z0-9_-]/_}"

state_dir="$HOME/.local/share/kbg/mcp-failure-nudge"
mkdir -p "$state_dir" 2>/dev/null
ring_file="$state_dir/${session_safe}-${server_safe}.ring"
msg_file="$state_dir/${session_safe}-${server_safe}.lastmsg"

# MH_MCP_FAILURE_NOW is a test-only clock override (real callers never set
# it) -- time-windowed logic can't be exercised deterministically against
# the real clock without either sleeping 300s in a test or injecting "now".
now="${MH_MCP_FAILURE_NOW:-$(date +%s 2>/dev/null)}" || exit 0
echo "$now" >> "$ring_file" 2>/dev/null

# Keep only timestamps within the trailing window.
cutoff=$((now - WINDOW_SECONDS))
tmp_ring="$ring_file.tmp.$$"
awk -v cutoff="$cutoff" '$1 >= cutoff' "$ring_file" > "$tmp_ring" 2>/dev/null && mv "$tmp_ring" "$ring_file"

count=$(wc -l < "$ring_file" 2>/dev/null | tr -d ' ')
count="${count:-0}"

if [ "$count" -lt "$THRESHOLD" ]; then
  # Failure rate (if any) has settled -- clear the dedupe marker so a LATER
  # burst re-fires instead of staying suppressed for the rest of the session.
  rm -f "$msg_file" 2>/dev/null
  exit 0
fi

# Cap the echoed error -- the docs' own example shows a full multi-line
# stderr dump, and this must not inject an unbounded blob into additionalContext.
error_excerpt=$(printf '%s' "$error_text" | head -c 200 | tr '\n' ' ')

message="[mh:mcp-failure-nudge] MCP server '$server' has failed ${THRESHOLD}+ times in the last ${WINDOW_SECONDS}s (latest: ${error_excerpt}) -- observational only, Claude Code's own retry already applies; consider whether this server needs attention."

if [ -f "$msg_file" ] && [ "$(cat "$msg_file" 2>/dev/null)" = "$message" ]; then
  exit 0
fi
printf '%s' "$message" > "$msg_file" 2>/dev/null

jq -nc --arg ctx "$message" '
  { hookSpecificOutput: { hookEventName: "PostToolUseFailure", additionalContext: $ctx } }
'
exit 0
