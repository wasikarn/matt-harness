#!/usr/bin/env bash
set -euo pipefail
# Per-skill wrapper for orchestrate-dispatch.py.
# Resolves the plugin root from this file's own path so the skill body only
# needs: bash "${CLAUDE_SKILL_DIR}/scripts/dispatch.sh" <spec.yml> [flags]
__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"
exec python3 "${__root}/scripts/orchestrate-dispatch.py" "$@"
