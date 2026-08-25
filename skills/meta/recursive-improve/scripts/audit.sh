#!/usr/bin/env bash
# Per-skill wrapper: resolves the plugin root from this file's location and
# delegates to the sibling harness-audit script. Keeps the skill body
# self-contained under ${CLAUDE_SKILL_DIR}.
set -euo pipefail

__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"

# Default to the plugin root when called without arguments, so the audit
# works from any project CWD rather than resolving '.' against the operator's
# current directory.
exec bash "${__root}/skills/meta/harness-audit/scripts/audit.sh" "${@:-${__root}}"
