#!/usr/bin/env bash
# Per-skill wrapper: resolves the plugin root from this file's location and
# delegates to the top-level harness-coverage script. Keeps the skill body
# self-contained under ${CLAUDE_SKILL_DIR}.
set -euo pipefail

__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"

exec python3 "${__root}/scripts/evals/harness-coverage.py" "$@"
