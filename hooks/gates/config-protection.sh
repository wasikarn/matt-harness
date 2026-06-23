#!/bin/bash
# Config-protection gate — escalate Edit/Write/MultiEdit on an EXISTING linter/
# formatter config file to user confirmation. Agents weaken these to make
# checks pass instead of fixing the source; this steers them back.
#
# First-time creation is allowed (no existing config to weaken — legitimate
# bootstrap). Only modification of a pre-existing config is gated.
#
# Ported from affaan-m/ECC scripts/hooks/config-protection.js (2026-05-30),
# adapted to the doctrine-edit-gate.sh idiom: permissionDecision=ask, not a
# hard exit-2 block, so a deliberate config edit can be confirmed in-context.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=config-protection

set -uo pipefail

HOOK_ID="config-protection"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


hook_require_jq

FILE_PATH=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.file_path // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse file_path from input" >&2
  exit 1
}

case "$TOOL" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

[ -z "$FILE_PATH" ] && exit 0

BASE=$(basename "$FILE_PATH")

# Protected linter/formatter config basenames (ported from ECC PROTECTED_FILES).
# pyproject.toml is deliberately EXCLUDED — it mixes project metadata with
# linter config, so gating it would block legitimate dependency edits.
case "$BASE" in
  .eslintrc|.eslintrc.js|.eslintrc.cjs|.eslintrc.json|.eslintrc.yml|.eslintrc.yaml|\
  eslint.config.js|eslint.config.mjs|eslint.config.cjs|eslint.config.ts|eslint.config.mts|eslint.config.cts|\
  .prettierrc|.prettierrc.js|.prettierrc.cjs|.prettierrc.json|.prettierrc.yml|.prettierrc.yaml|\
  prettier.config.js|prettier.config.cjs|prettier.config.mjs|\
  biome.json|biome.jsonc|\
  .ruff.toml|ruff.toml|\
  .shellcheckrc|.stylelintrc|.stylelintrc.json|.stylelintrc.yml|\
  .markdownlint.json|.markdownlint.yaml|.markdownlintrc) ;;
  *) exit 0 ;;
esac

# Allow first-time creation — no existing config to weaken. Only gate a
# modification of a pre-existing config. `-e` follows symlinks; `-L` also
# catches a dangling symlink at the protected path (still an existing entry).
if [ ! -e "$FILE_PATH" ] && [ ! -L "$FILE_PATH" ]; then
  exit 0
fi

# Narrow the ceremony (2026-06-16): a full Write of an existing config is a
# whole-file replacement — suspicious enough to confirm. But an Edit/MultiEdit
# is a targeted change, and a version bump or typo fix should not trip a
# confirmation every time. The gate can't diff, so it keys off rule-relaxation
# signals in the NEW text only (disabling/loosening a rule). jq absent → keep
# asking (safe default); post-edit-audit journals every config edit regardless.
case "$TOOL" in
  Edit|MultiEdit)
    if command -v jq >/dev/null 2>&1; then
      _change=$(printf '%s' "$TOOL_INPUT" | jq -r '(.new_string // "") + " " + ((.edits // []) | map(.new_string // "") | join(" "))' 2>/dev/null)
      _relax='"?(off|none)"?|disable|eslint-disable|stylelint-disable|"rules"[[:space:]]*:[[:space:]]*\{\}|noImplicitAny|skipLibCheck|allowJs|ignorePatterns|--no-verify|:[[:space:]]*false'
      printf '%s' "$_change" | command grep -qiE "$_relax" || exit 0
    fi
    ;;
esac

hook_decision ask "Editing existing linter/formatter config: ${FILE_PATH}. Agents often weaken these to make checks pass instead of fixing the source. Confirm this change is intentional, not a workaround."
