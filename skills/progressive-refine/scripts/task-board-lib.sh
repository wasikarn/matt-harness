#!/usr/bin/env bash
# Per-skill wrapper for the plugin-wide task board library.
# Sourced (not executed) by skill-body bash blocks. Resolves the plugin root
# from this file's own path so the skill body only needs:
#   source "${CLAUDE_SKILL_DIR}/scripts/task-board-lib.sh"
__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"
source "${__root}/scripts/task_board_lib.sh"
