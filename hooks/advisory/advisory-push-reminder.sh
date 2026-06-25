#!/bin/bash
# advisory-push-reminder.sh — non-blocking pre-push review reminder (ECC parity).
#
# ECC's pre-bash-git-push-reminder.js emits an advisory nudge before `git push` /
# `gh pr merge` / `gh repo sync` — review is advisory, NOT enforced. This is the
# "review is advisory not enforced" half of the 2026-06-25 ECC-alignment: the old
# push-gate.sh BLOCKED these under an autonomy flag (and, via Gate-2, blanket-denied
# ALL Bash when KBG_REVIEW_DONE=1 had no review_finding — a footgun that paralyzed
# sessions). This hook only reminds, exit 0 always. ECC analogue:
# scripts/hooks/pre-bash-git-push-reminder.js (exit 0, additionalContext).
#
# Bypass (advisory, non-blocking anyway): CLAUDE_HOOK_PROFILE=off /
# CLAUDE_DISABLED_HOOKS=advisory-push-reminder.

set -uo pipefail

HOOK_ID="advisory-push-reminder"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

hook_require_jq

COMMAND=$(printf '%s\n' "$TOOL_INPUT" | jq -r '.command // empty') 2>/dev/null || exit 0
[ -z "$COMMAND" ] && exit 0

STRIPPED=$(hook_strip_quoted "$COMMAND")
_GREP="command grep"
SEP='(^|[[:space:];&|()`])'
# Same global-option allowance as block-dangerous-git: options sit between `git`
# and the subcommand (`git -c k=v push`), so without GOPT the adjacency breaks.
GOPT='((-c|-C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env)[=[:space:]]+[^[:space:]]+[[:space:]]+|(-P|-p|--paginate|--no-pager|--bare|--no-replace-objects|--literal-pathspecs|--glob-pathspecs|--noglob-pathspecs|--icase-pathspecs|--no-optional-locks|--exec-path|--html-path|--man-path|--info-path)[[:space:]]+)*'

PUSH_PAT="${SEP}git[[:space:]]+${GOPT}push([[:space:]]|$)"
GH_SHIP_PAT="${SEP}gh[[:space:]]+(pr[[:space:]]+merge|repo[[:space:]]+sync)"

emit() {
  # Advisory only: additionalContext, never a permissionDecision. exit 0 always.
  local msg="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg c "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}' 2>/dev/null
  fi
  exit 0
}

if printf '%s\n' "$STRIPPED" | $_GREP -qE "$PUSH_PAT"; then
  emit "[advisory-push-reminder] About to run \`git push\`. Review the diff before it reaches origin — once pushed, a bad commit is in reflog/forks/CI. (Advisory only; ECC-style non-blocking reminder. The old push-gate.sh that blanket-blocked Bash under an autonomy flag was retired 2026-06-25.)"
fi

if printf '%s\n' "$STRIPPED" | $_GREP -qE "$GH_SHIP_PAT"; then
  emit "[advisory-push-reminder] About to merge/sync via \`gh\` (server-side, irreversible). Confirm the PR/branch before merging. (Advisory only; ECC-style non-blocking reminder.)"
fi

exit 0