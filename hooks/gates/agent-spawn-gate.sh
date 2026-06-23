#!/bin/bash
# agent-spawn-gate.sh — PreToolUse gate that intercepts ad-hoc one-shot Agent spawns.
#
# Problem: the Agent tool creates persistent teammates that do not self-terminate.
# A one-shot read-only spawn (blueprint, audit, research map) that the parent
# forgets to stop will block the next session exit with "Background work is
# running". This gate asks the operator to confirm any Agent spawn that does not
# look like an approved multi-agent team workflow.
#
# Allow-list (no gate): prompts/descriptions that carry team workflow markers
#   - /team-build, /team-plan, /team-cleanup, /wave-status
#   - plan_slug: or task_id: embedding
#   - "orchestrate", "workflow", "teardown", "TaskStop", "Agent Teams"
#
# Ask-list (gate): prompts/descriptions that look like bounded read-only passes
#   - "blueprint", "audit", "research", "map", "survey", "bounded pass"
#   - "read and summarize", "check this", "verify this", "analyze this"
#   - "one-shot", "spawned for", "staff engineer ... agent"
#
# Default: ask (safe). A session can opt out with:
#   export CLAUDE_DISABLED_HOOKS=agent-spawn-gate
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=agent-spawn-gate

set -u

HOOK_ID="agent-spawn-gate"
source "$(dirname "$0")/../_lib.sh" || {
    echo "[${HOOK_ID}] ERROR: cannot source _lib.sh" >&2
    exit 1
}
set -o pipefail
hook_init "$HOOK_ID" || exit 0
hook_guard_unreadable

# We only gate the Agent tool.
[ "${TOOL:-}" = "Agent" ] || hook_decision none "tool is not Agent"

# Build a single normalized text blob from description + prompt.
# One jq fork (was two) reading TOOL_INPUT once — byte-identical output:
# jq string interpolation joins the two fields with the same single space that
# `printf '%s %s' "$desc" "$prompt"` did. The jq only runs when TOOL="Agent",
# which itself requires jq present + a valid JSON envelope (hook_guard_unreadable
# short-circuits every other path), so the failure-mode edge case is unreachable.
PROMPT_TEXT=$(printf '%s' "$TOOL_INPUT" | jq -r '"\(.description // "") \(.prompt // "")"' 2>/dev/null | tr '[:upper:]' '[:lower:]')

# Allow-list: explicit multi-agent team workflows already have their own
# approval gates (/team-build F10, /team-plan Q&A). Let them through.
ALLOW_PATTERNS='(\/team-(build|plan|cleanup)|\/wave-status|plan_slug:|task_id:|orchestrate|workflow|teardown|taskstop|agent teams)'
if printf '%s' "$PROMPT_TEXT" | /usr/bin/grep -iqE "$ALLOW_PATTERNS"; then
    hook_decision none "Agent spawn matches an approved team workflow allow-list"
fi

# Ask-list: bounded read-only / one-shot patterns are exactly the failure mode.
ASK_PATTERNS='(blueprint|audit|research|survey|map|bounded pass|read and summarize|check this|verify this|analyze this|one-shot|spawned for|staff engineer.*agent|implement.*agent|subagent.*task|read-only pass)'
if printf '%s' "$PROMPT_TEXT" | /usr/bin/grep -iqE "$ASK_PATTERNS"; then
    hook_decision ask "Agent spawn looks like a one-shot read-only pass. Persistent teammates do not self-terminate. Confirm this is intentional and that you have a teardown plan, or use inline Read/Bash/python3 instead."
fi

# Background agents are especially likely to be forgotten.
RUN_BG=$(printf '%s' "$TOOL_INPUT" | jq -r '.run_in_background // false' 2>/dev/null)
if [ "$RUN_BG" = "true" ]; then
    hook_decision ask "Agent spawn is backgrounded. Background teammates persist until explicitly stopped and block session exit. Confirm this is intentional."
fi

# Default safe: any Agent spawn that is not obviously a team workflow asks.
hook_decision ask "Agent tool creates persistent teammates. Confirm this spawn is intentional and that you will stop it after consuming the output."
