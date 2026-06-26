#!/bin/bash
# commit-quality-reminder.sh — non-blocking commit-message quality nudge.
#
# Emits an additionalContext nudge (ECC-style, exit 0 always) when a Bash
# command runs `git commit` (NOT `--amend` — amending is a re-edit of an
# existing message, not a fresh authoring moment worth nagging). Reminds:
# imperative mood, conventional-commit prefix, <=72-char subject, body
# explains WHY not WHAT. Advisory only — never blocks.
#
# Bypass (advisory, non-blocking anyway): CLAUDE_HOOK_PROFILE=off /
# CLAUDE_DISABLED_HOOKS=commit-quality-reminder.

set -uo pipefail

HOOK_ID="commit-quality-reminder"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') 2>/dev/null || exit 0
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(hook_strip_quoted "$COMMAND")
_GREP="command grep"
SEP='(^|[[:space:];&|`(])'
# Allow global git options between `git` and `commit` (mirrors advisory-push-reminder's GOPT).
GOPT='((-c|-C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)[=[:space:]]+[^[:space:]]+[[:space:]]+|(-P|-p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--exec-path|--html-path|--man-path|--info-path)[[:space:]]+)*'

COMMIT_PAT="${SEP}git[[:space:]]+${GOPT}commit([[:space:]]|$)"
AMEND_PAT="${SEP}git[[:space:]]+${GOPT}commit([[:space:]]+[^[:space:]]+)*[[:space:]]+--amend([[:space:]]|$)"

emit() {
  local msg="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg c "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null
  fi
  exit 0
}

if ! printf '%s\n' "$STRIPPED" | $_GREP -qE "$COMMIT_PAT"; then
  exit 0
fi
# Skip `git commit --amend` (and --amend anywhere in the args).
if printf '%s\n' "$STRIPPED" | $_GREP -qE "$AMEND_PAT"; then
  exit 0
fi

emit "[commit-quality-reminder] Writing a commit message? Imperative mood (\"add\" not \"added\"), conventional-commit prefix (feat/fix/refactor/docs/chore/test), subject <=72 chars, body explains WHY not WHAT (the diff already shows what). (Advisory only; ECC-style non-blocking reminder.)"

exit 0