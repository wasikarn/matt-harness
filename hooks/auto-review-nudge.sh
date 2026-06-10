#!/bin/bash
# UserPromptSubmit: auto-review-nudge — miss-detector for /review-pr.
#
# skill-nudge already catches explicit slash invocations ("/review-pr ...")
# and direct prose matches ("review my PR"). This hook targets the gap where
# the user clearly wants a comprehensive multi-agent review but the model
# would otherwise start writing inline agents itself.
#
# Trigger (high-precision per Phase 3 user choice):
#   prompt contains: review
#                 AND (pr | pull request)
#                 AND (#\d+ | comprehensive | multi-agent | "all aspects")
#   …within ~80 chars of each other.
# Slash invocations ("/review-pr") are no-op here — skill-nudge owns those.
#
# Side effect: stdout text only, exit 0. No state, no log, no marker.
# The model either acts on the hint or dismisses it in one line.
#
# Bypass:
#   export CLAUDE_DISABLED_HOOKS=auto-review-nudge

set -uo pipefail
export LC_ALL=C

HOOK_ID="auto-review-nudge"
source "$(dirname "$0")/_lib.sh"
# UserPromptSubmit fires regardless of PROFILE (matches original — nudge hooks
# never honored PROFILE=off short-circuit).
# shellcheck disable=SC2034  # read by _lib.sh hook_init (cross-file; shellcheck runs without -x)
HOOK_HONOR_PROFILE_OFF=0
hook_init "$HOOK_ID" || exit 0

# Namespace-mode detection: empty in symlink-farm, 'kbg:' in plugin.
NS="${CLAUDE_PLUGIN_ROOT:+kbg:}"

[ -z "$PROMPT" ] && exit 0

# ASCII-lowercase for English matching; Thai bytes are unaffected under LC_ALL=C.
LOWERED=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Slash invocation → skill-nudge owns this. Stay silent to avoid double-emit.
case "$LOWERED" in
  */review-pr*) exit 0 ;;
esac

# High-precision trigger: STRICTLY ADDITIVE to skill-nudge.
# skill-nudge already covers `\breview (my|this|the)? (pr|pull request)\b` —
# any prompt that skill-nudge fires on, we MUST stay silent on (no double-banner,
# per orchestrator-nudge.sh:19-20 nudge-architecture convention).
# The actual gap skill-nudge misses: a request for a *comprehensive multi-agent
# review* (not just any "review the PR"). So we require review+pr+one of:
#   comprehensive | multi-agent | "all aspects"
# Bare "review PR 123" is owned by skill-nudge; "comprehensive review of PR 123"
# is ours.
if printf '%s' "$LOWERED" | grep -qE '\breview\b' \
   && printf '%s' "$LOWERED" | grep -qE '\b(pr|pull[- ]request)\b' \
   && printf '%s' "$LOWERED" | grep -qE '\b(comprehensive|multi[- ]agent|all aspects)\b'; then
  printf '%s\n' \
    "[auto-review-nudge] Heuristic match: this prompt looks like a candidate for the '/${NS}review-pr' command — comprehensive multi-agent PR review (code, tests, comments, errors, security, simplification)." \
    "If it fits, suggest the user run it via /${NS}review-pr. If it does NOT fit, say so in one line and proceed with your own approach. This is a hook hint, not a directive — your judgment wins (METHODOLOGY Rule 5)." \
    "Bypass: CLAUDE_DISABLED_HOOKS=auto-review-nudge"
fi

exit 0
