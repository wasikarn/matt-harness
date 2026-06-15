#!/bin/bash
# PostToolUse:Bash — post-witness-memory nudge.
#
# When a witness is SIGNED (assert-presence / decommission via witness.sh sign),
# a significant decision just landed: a fix pinned, or a component removed. That
# is the moment to capture the *rationale* into memory — the witness records
# WHAT (code present/absent), never WHY. Closes the operation-flow invariant
# "every mistake/decision becomes memory or process improvement" and the
# "codify taste/judgment into reusable artifacts" insight.
#
# skill-nudge / auto-review-nudge cover the inbound (prompt) side; this covers
# the outbound side — "you just signed a witness, did you capture why?".
# Mirrors review-pr-marker.sh (PostToolUse:Bash, stdout nudge, never blocks).
#
# Trigger (PostToolUse:Bash):
#   tool_name == "Bash"
#   AND command matches `witness.sh sign`
#
# Side effects: stdout text only (model-facing nudge) + audit log. Never blocks.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=post-witness-memory

set -uo pipefail
export LC_ALL=C

HOOK_ID="post-witness-memory"
source "$(dirname "$0")/_lib.sh"
# Honors PROFILE=off (default) — an advisory nudge should go quiet when the
# user minimizes hooks. Matches review-pr-marker.sh (the PostToolUse:Bash analog).
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

# Soft-fail silently on missing jq (matches review-pr-marker convention).
command -v jq >/dev/null 2>&1 || exit 0

# Only act on Bash tool calls; lib already extracted $TOOL.
[ "$TOOL" = "Bash" ] || exit 0

# .tool_input.command is hook-specific; pull it directly (lib doesn't cover it).
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

# Strip quoted strings + comments so we match shell intent, not string contents
# (block-dangerous-git / review-pr-marker convention).
STRIPPED=$(hook_strip_quoted "$COMMAND")

# Match a `witness.sh sign` invocation (assert-presence or decommission share
# the same script). `verify` and other subcommands are intentionally ignored.
printf '%s' "$STRIPPED" | command grep -qE 'witness\.sh[[:space:]]+sign' || exit 0

# Best-effort: pull the namespace for a sharper nudge (falls back to "witness").
NS=$(printf '%s' "$COMMAND" | sed -nE 's/.*--namespace=([a-z][a-z-]*).*/\1/p')
[ -n "$NS" ] || NS="witness"

hook_audit_log post-witness-memory "$TOOL" "$NS"

printf '%s\n' \
  "[post-witness-memory] You just signed a '$NS' witness — a significant decision just landed." \
  "Capture the WHY into memory (the witness records what is present/absent, not why): write a memory entry with the decision rationale, the file:line it touched, and a reproducible fixture (e.g. a 'git show <sha>:<file>' a later session can re-run). Add the one-line pointer in MEMORY.md." \
  "Skip if this change is trivial or already captured. Hook hint, not a directive (METHODOLOGY Rule 5)." \
  "Bypass: CLAUDE_DISABLED_HOOKS=post-witness-memory"

exit 0
