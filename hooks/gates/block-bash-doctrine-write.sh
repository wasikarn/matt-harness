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
source "$(dirname "$0")/../_lib.sh"
# shellcheck disable=SC2034  # HOOK_PROFILES is consumed by _lib.sh hook_init (sourced above)
HOOK_PROFILES="minimal standard strict"  # floor gate: survives a `minimal` session (ADR 0007)
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

# Strip quoted strings and comments so we match shell intent, not the
# literal contents of strings (mirrors block-dangerous-git pattern).
STRIPPED=$(hook_strip_quoted "$COMMAND")

# Doctrine basenames (same set as doctrine-edit-gate Edit/Write hook).
# METHODOLOGY.md (2026-05-20, audit H2), ACLI.md + DBGATE.md (2026-06-10, gate-coverage
# closure) — all load-bearing via CLAUDE.md @import chain. The three governance ADRs
# (0001 delivery path, 0002 autonomy invariant, 0003 L3 bounded-autonomy) added
# 2026-06-21: ADR 0003 is the autonomy architecture keystone — an unguarded
# Bash-redirect rewrite of it would silently move the autonomy boundary.
# Keep aligned with doctrine-edit-gate (audit #41 seam asserts the two sets match).
DOCTRINE_NAMES='(CLAUDE|METHODOLOGY|RTK|ACLI|DBGATE)\.md|settings\.json|\.mcp\.json|mcp-servers\.json|0001-personal-harness-as-plugin\.md|0002-autonomy-invariant\.md|0003-l3-bounded-autonomy\.md'

# Doctrine path: either dotfiles repo claude/, runtime .claude/, or the extracted kbg-harness/ source root.
# Match doctrine files at the root OR nested inside claude/.claude/kbg-harness directories.
DOCTRINE_PATH_RE="(/claude/.*|/\.claude/.*|/kbg-harness/.*)(${DOCTRINE_NAMES})"

# Write-op tokens (shell-statement-boundaries to reduce false positives).
SEP='(^|[[:space:];&|()`])'
WRITE_OPS_RE="${SEP}(>>?[[:space:]]|tee[[:space:]]|sed[[:space:]]+-i|cp[[:space:]]|mv[[:space:]]|install[[:space:]])"

# Both conditions must hold: a write-op token AND a doctrine path.
# Use 'command grep' to resist alias shadowing (matches secret-scan, block-dangerous-git).
if printf '%s\n' "$STRIPPED" | command grep -qE "$WRITE_OPS_RE" && printf '%s\n' "$STRIPPED" | command grep -qE "$DOCTRINE_PATH_RE"; then
  matched=$(printf '%s\n' "$STRIPPED" | command grep -oE "$DOCTRINE_PATH_RE" | head -1)
  hook_decision deny "Bash command writes to doctrine file ($matched). Use Edit/Write tool instead — it routes through doctrine-edit-gate uniformly. Bypass: CLAUDE_DISABLED_HOOKS=block-bash-doctrine-write"
fi

exit 0
