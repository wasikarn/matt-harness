#!/bin/bash
# Block Bash commands that WRITE to doctrine files via shell redirect,
# tee, sed -i, cp, mv, install. Closes the Bash-bypass route around
# doctrine-edit-gate (which only catches Edit/Write/MultiEdit tools).
#
# This is NOT airtight — Python/perl/dd one-liners with file I/O are
# not caught. Intent is to flag common shell write patterns; sophisticated
# bypasses still possible and acceptable per METHODOLOGY Rule 2
# (Simplicity first — don't over-engineer).
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=block-bash-doctrine-write

set -uo pipefail

HOOK_ID="block-bash-doctrine-write"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

# jq is mandatory for the command parse below; if missing, fail loud.
if ! command -v jq >/dev/null 2>&1; then
  echo "[$HOOK_ID] ERROR: jq not found — cannot parse hook input" >&2
  exit 1
fi

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

# Strip quoted strings and comments so we match shell intent, not the
# literal contents of strings (mirrors block-dangerous-git pattern).
STRIPPED=$(hook_strip_quoted "$COMMAND")

# Doctrine basenames (same set as doctrine-edit-gate Edit/Write hook).
# METHODOLOGY.md added 2026-05-20 (audit H2); HARNESS.md added 2026-06-10 (Phase 3);
# ACLI.md and DBGATE.md added 2026-06-10 (gate-coverage closure) — all load-bearing
# via CLAUDE.md @import chain. Keep aligned with doctrine-edit-gate.
DOCTRINE_NAMES='(CLAUDE|METHODOLOGY|RTK|HARNESS|ACLI|DBGATE)\.md|settings\.json|\.mcp\.json|mcp-servers\.json'

# Doctrine path: either dotfiles repo claude/ or runtime .claude/
DOCTRINE_PATH_RE="(/claude/(${DOCTRINE_NAMES})|/\.claude/(${DOCTRINE_NAMES}))"

# Write-op tokens (shell-statement-boundaries to reduce false positives).
SEP='(^|[[:space:];&|()`])'
WRITE_OPS_RE="${SEP}(>>?[[:space:]]|tee[[:space:]]|sed[[:space:]]+-i|cp[[:space:]]|mv[[:space:]]|install[[:space:]])"

# Both conditions must hold: a write-op token AND a doctrine path.
# Use 'command grep' to resist alias shadowing (matches secret-scan, block-dangerous-git).
if echo "$STRIPPED" | command grep -qE "$WRITE_OPS_RE" && echo "$STRIPPED" | command grep -qE "$DOCTRINE_PATH_RE"; then
  matched=$(echo "$STRIPPED" | command grep -oE "$DOCTRINE_PATH_RE" | head -1)
  hook_decision deny "Bash command writes to doctrine file ($matched). Use Edit/Write tool instead — it routes through doctrine-edit-gate uniformly. Bypass: CLAUDE_DISABLED_HOOKS=block-bash-doctrine-write"
fi

exit 0
