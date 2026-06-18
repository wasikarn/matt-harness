#!/usr/bin/env bash
set -euo pipefail
# Per-skill wrapper for the decommission witness script.
# Resolves the plugin root from this file's own path so the skill body only
# needs: bash "${CLAUDE_SKILL_DIR}/scripts/witness.sh" <sign|verify> --namespace=assert-presence [slug]
__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"
exec bash "${__root}/skills/decommission/scripts/witness.sh" "$@"
