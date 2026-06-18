#!/usr/bin/env bash
set -euo pipefail
# Per-skill wrapper for ideate-convergence.py.
# Resolves the plugin root from this file's own path so the skill body only
# needs: bash "${CLAUDE_SKILL_DIR}/scripts/convergence.sh" [args]
__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"
exec python3 "${__root}/scripts/ideate-convergence.py" "$@"
