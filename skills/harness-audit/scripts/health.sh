#!/usr/bin/env bash
# Per-mode wrapper for `kbg:harness-audit --health`. Resolves the plugin root
# from this file's location and delegates to the governance-journal query
# script. Keeps the skill body self-contained under ${CLAUDE_SKILL_DIR}.
set -euo pipefail

__src="${BASH_SOURCE[0]:-$0}"
__dir="$(cd "$(dirname "$__src")" && pwd)"
__root="$(cd "${__dir}/../../.." && pwd)"

exec python3 "${__root}/skills/harness-audit/scripts/harness-health.py" "$@"
