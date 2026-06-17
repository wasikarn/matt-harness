#!/bin/bash
# Block alias / shell-function shadowing of safety-relevant binaries.
#
# Threat: agent runs `alias git='git --no-verify'` or `git() { ... }` in
# a Bash command; subsequent `git commit` silently routes through the
# shadowed alias/function. Hook inspecting `git commit` sees benign
# arguments — `--no-verify` is invisible.
#
# Closes round-4 audit major: alias shadowing of safety-relevant binaries.
#
# Decision: ASK — legitimate aliases exist (paging preference, quiet flags),
# so user confirms each redefinition.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=block-alias-shadowing

set -uo pipefail

HOOK_ID="block-alias-shadowing"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input.command" >&2
  exit 1
}
[ -z "$COMMAND" ] && exit 0

# Strip quoted strings + comments so we match shell intent, not literal
# contents. Mirrors block-dangerous-git pattern.
STRIPPED=$(hook_strip_quoted "$COMMAND")

_GREP="command grep"

# Safety-relevant binaries — redefining these can hide --no-verify,
# --insecure, --ignore-scripts and similar safety-bypass flags.
BINARIES='git|curl|wget|npm|pip|pip3|brew|gh|aws|gcloud|az|docker|kubectl|terraform|cargo|helm|doctl|heroku|op|vault'

SEP='(^|[[:space:];&|()`])'

# `alias <binary>=` form. Quoted assignment content is already stripped.
ALIAS_PATTERN="${SEP}alias[[:space:]]+(${BINARIES})="

# Shell function forms:
#   name() { ... }
#   name () { ... }
#   function name { ... }
#   function name() { ... }
FN_PAREN_PATTERN="${SEP}(${BINARIES})[[:space:]]*\(\)[[:space:]]*\{"
FN_KEYWORD_PATTERN="${SEP}function[[:space:]]+(${BINARIES})([[:space:]]*\(\))?[[:space:]]*\{"

# Check alias form
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$ALIAS_PATTERN"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "alias[[:space:]]+(${BINARIES})=[^;]*" | head -1 | xargs)
  hook_decision ask "alias shadowing of safety-relevant binary: '$matched'. Aliasing $BINARIES can hide --no-verify / --insecure / --ignore-scripts. Confirm intent."
fi

# Check function forms
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$FN_PAREN_PATTERN"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "(${BINARIES})[[:space:]]*\(\)[[:space:]]*\{" | head -1 | xargs)
  hook_decision ask "shell-function shadowing of safety-relevant binary: '$matched ...'. Confirm intent."
fi

if printf '%s\n' "$STRIPPED" | $_GREP -qE "$FN_KEYWORD_PATTERN"; then
  matched=$(printf '%s\n' "$STRIPPED" | $_GREP -oE "function[[:space:]]+(${BINARIES})[^{]*\{" | head -1 | xargs)
  hook_decision ask "shell-function shadowing (function-keyword) of safety-relevant binary: '$matched ...'. Confirm intent."
fi

exit 0
