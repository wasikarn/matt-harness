#!/bin/bash
# Pre-edit doctrine gate — escalate Edit/Write/MultiEdit on doctrine docs
# to user confirmation. Reduces pattern-matching errors on load-bearing
# files (CLAUDE.md / METHODOLOGY.md / RTK.md / settings.json / .mcp.json).
#
# Codified after 2026-05-18 incident — agent propagated invalid skill IDs
# into doc tables + silently deleted runtime-active settings keys based
# on schema absence, both from pattern-matching without ground-truth
# verification. Iron rule: every factual claim about a file/skill/API/
# vendor behavior must trace to a tool-call result in the current turn.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=doctrine-edit-gate

set -uo pipefail

HOOK_ID="doctrine-edit-gate"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

# jq is mandatory for the file_path parse below; if missing, fail loud.
if ! command -v jq >/dev/null 2>&1; then
  echo "[$HOOK_ID] ERROR: jq not found — cannot parse hook input" >&2
  exit 1
fi

FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse file_path from input" >&2
  exit 1
}

case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

[ -z "$FILE_PATH" ] && exit 0

DIR=$(dirname "$FILE_PATH")
BASE=$(basename "$FILE_PATH")

# Doctrine path: must be under a `claude/`, `.claude/`, or the extracted `kbg-harness/`
# source root directory (post-plugin-extraction, the 4 @import docs are real there).
case "$DIR" in
  */claude|*/claude/*|*/.claude|*/.claude/*|*/kbg-harness|*/kbg-harness/*) ;;
  *) exit 0 ;;
esac

# Doctrine basenames — match exactly. settings.json + .mcp.json added
# 2026-05-18 after agent silently deleted a runtime-active `theme` key
# based on JSON-schema absence (same pattern-matching failure mode).
# METHODOLOGY.md added 2026-05-20 (audit H2) — load-bearing via CLAUDE.md
# @METHODOLOGY.md import; needs same edit-gate protection as CLAUDE.md.
# mcp-servers.json added 2026-06-04 (renamed from .mcp.json) — tracked MCP
# source registered to user scope by install.sh; keep .mcp.json gated too.
# ACLI.md and DBGATE.md added 2026-06-10 — Atlassian operation gate and
# database-write gate respectively, both load-bearing doctrine via CLAUDE.md
# @import chain; same pattern-matching-error risk as METHODOLOGY/RTK.
case "$BASE" in
  CLAUDE.md|METHODOLOGY.md|RTK.md|ACLI.md|DBGATE.md|settings.json|.mcp.json|mcp-servers.json)
    hook_decision ask "Doctrine edit detected: ${FILE_PATH}. These files are load-bearing across every session. Confirm this edit is intentional and verified."
    ;;
esac

exit 0
