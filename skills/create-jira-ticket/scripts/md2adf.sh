#!/usr/bin/env bash
set -euo pipefail
# Per-skill wrapper for the acli md2adf converter.
# Resolves the plugin root from this file's own path so the skill body only
# needs: bash "${CLAUDE_SKILL_DIR}/scripts/md2adf.sh" <md-file> [args]
__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"
exec python3 "${__root}/skills/acli/scripts/md2adf.py" "$@"
