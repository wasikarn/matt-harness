#!/usr/bin/env bash
# command-root-anchor.sh — matcher-less SessionStart hook
#
# Commands are single markdown files with no official ${CLAUDE_COMMAND_DIR}
# variable. To keep command bash blocks from relying on repo-relative paths
# (which break when the plugin runs in a foreign project CWD), this hook
# bridges the hook-only ${CLAUDE_PLUGIN_ROOT} variable into the session as
# KBG_PLUGIN_ROOT via CLAUDE_ENV_FILE.
#
# Command markdown should reference bundled scripts with:
#   bash "${KBG_PLUGIN_ROOT}/scripts/..."
#   python3 "${KBG_PLUGIN_ROOT}/scripts/..."
#   PYTHONPATH="${KBG_PLUGIN_ROOT}" python3 -c "from scripts.task_board_lib import ..."
#
# This is the only place the hook-only ${CLAUDE_PLUGIN_ROOT} is intentionally
# exported to the broader session; command bodies should not name
# ${CLAUDE_PLUGIN_ROOT} directly.
#
# Fails safe: exits 0 silently if plugin root or env file is unavailable.
set -uo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || exit 0
[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0

# Normalize: strip trailing slash so command prose can always use
# "${KBG_PLUGIN_ROOT}/scripts/..." without producing double slashes.
ROOT="${ROOT%/}"

printf 'export KBG_PLUGIN_ROOT=%s\n' "$ROOT" >> "$CLAUDE_ENV_FILE"
