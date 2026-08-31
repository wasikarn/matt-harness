#!/usr/bin/env bash
# Advisory (#99): PostToolUse loop-repetition sensor. Purely mechanical
# signal, no model judgment -- ADR 0006 line: this counts identical
# {tool, params} pairs, it never judges "is this spinning" or "is this
# productive". Matches kbg's advisory-sensor contract (compute a number,
# journal/nudge, never gate). Runs alongside the two other live PostToolUse
# advisories (plan-review-nudge, compliance-audit-nudge -- both registered in
# hooks.json; an earlier version of this header wrongly claimed they were
# retired, corrected 2026-09-01) -- this is a different, independently-
# motivated signal from either.
#
# Design source: ECC's ecc-context-monitor.js (cited on #99) field-tested a
# "3 identical calls in last 5" threshold and a message-content dedupe (not
# a raw counter) to avoid re-firing the same warning on every subsequent
# call once a loop is already flagged. Ported here without its metrics-
# bridge dependency, which this repo doesn't have.
#
# ponytail: unbounded per-session file growth under
# $HOME/.local/share/kbg/loop-nudge/ (one .ring + one .lastmsg per unique
# session/tool/params combo, ever), same precedent as
# instructions-loaded-journal.sh and skill-usage-telemetry.sh -- rotate/trim
# manually if it grows large.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

WINDOW="${MH_LOOP_REPEAT_WINDOW:-5}"
THRESHOLD="${MH_LOOP_REPEAT_THRESHOLD:-3}"

payload=$(cat)
[ -n "$payload" ] || exit 0

session_id=$(printf '%s' "$payload" | jq -r '.session_id // "default"' 2>/dev/null) || exit 0
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // "unknown"' 2>/dev/null) || exit 0

# session_id/tool_name are model/session-controlled, not a trusted source --
# sanitize before they become part of a filesystem path (same convention as
# hooks/stop/stale-task-nudge.sh's taskId handling).
session_safe="${session_id//[^A-Za-z0-9_-]/_}"
tool_safe="${tool_name//[^A-Za-z0-9_-]/_}"

# Canonicalize tool_input (sorted keys) before hashing so key-order
# differences in an otherwise-identical call don't dodge detection.
checksum=$(printf '%s' "$payload" | jq -S -c '.tool_input // {}' 2>/dev/null | cksum | awk '{print $1}')
[ -n "$checksum" ] || exit 0
entry="${tool_name}|${checksum}"

state_dir="$HOME/.local/share/kbg/loop-nudge"
mkdir -p "$state_dir" 2>/dev/null
ring_file="$state_dir/${session_safe}.ring"
# Keyed by the exact (tool, checksum) pair, not tool name alone -- otherwise
# an intervening call to the SAME tool with DIFFERENT params would clear the
# dedupe marker for an unrelated, still-ongoing repeat of this one (checksum
# is already digits-only from cksum, no sanitizing needed).
msg_file="$state_dir/${session_safe}-${tool_safe}-${checksum}.lastmsg"

echo "$entry" >> "$ring_file" 2>/dev/null
tmp_ring="$ring_file.tmp.$$"
tail -n "$WINDOW" "$ring_file" > "$tmp_ring" 2>/dev/null && mv "$tmp_ring" "$ring_file"

count=$(grep -c -F -x -- "$entry" "$ring_file" 2>/dev/null)
count="${count:-0}"

if [ "$count" -lt "$THRESHOLD" ]; then
  # Loop (if any) has resolved -- clear the dedupe marker so a LATER
  # recurrence of this same tool re-fires instead of staying suppressed
  # for the rest of the session.
  rm -f "$msg_file" 2>/dev/null
  exit 0
fi

# Message deliberately omits the live count (stays "$THRESHOLD+", not the
# growing exact number) -- an exact counter in the text would change every
# call and defeat the dedupe-on-content check below (the exact anti-pattern
# ECC's own notes flag: re-emitting ~20 times when only a counter moved).
message="[mh:loop-repeat-nudge] Tool '$tool_name' has been called with identical parameters ${THRESHOLD}+ times in the last ${WINDOW} calls -- check whether this is making forward progress before continuing."

if [ -f "$msg_file" ] && [ "$(cat "$msg_file" 2>/dev/null)" = "$message" ]; then
  exit 0
fi
printf '%s' "$message" > "$msg_file" 2>/dev/null

jq -nc --arg ctx "$message" '
  { hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $ctx } }
'
exit 0
