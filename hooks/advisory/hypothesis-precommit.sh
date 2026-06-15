#!/usr/bin/env bash
# UserPromptSubmit advisory — hypothesis-first gate for investigation prompts.
# When the prompt matches investigation keywords, emits additionalContext prompting
# the operator to commit to ≥3 candidate hypotheses before diving in.
# Never blocks (advisory only, exit 0). Prevents post-hoc rationalisation.
# shellcheck disable=SC2034
HOOK_HONOR_PROFILE_OFF=1
HOOK_ID="hypothesis-precommit"
source "$(dirname "$0")/../_lib.sh" || exit 0
hook_init "$HOOK_ID" || exit 0

PROMPT_TEXT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
INVEST_REGEX='(investigate|diagnose|debug|root[[:space:]-]?cause|why (is|does|did|are)|figure out why|track down)'

if ! printf '%s' "$PROMPT_TEXT" | /usr/bin/grep -iEq "$INVEST_REGEX"; then
  exit 0
fi

MSG="[hypothesis-gate] Investigation detected. Before diving in:\\n"
MSG="${MSG}1. List ≥3 candidate hypotheses for the root cause.\\n"
MSG="${MSG}2. State 2-3 criteria that would confirm or rule out each.\\n"
MSG="${MSG}3. Your conclusion must address every hypothesis — not just the first one the evidence supports.\\n"
MSG="${MSG}This prevents post-hoc rationalisation and convergence on the first plausible answer."

printf '{"additionalContext":"%s"}\n' "$MSG"

PROMPT_PREFIX=$(printf '%s' "$PROMPT_TEXT" | cut -c1-80 | tr -d '"\\')
( journal_append "$HOOK_ID" "hypothesis_gate_fired" \
    "$(printf '{"prompt_prefix":"%s"}' "$PROMPT_PREFIX")" \
    >/dev/null ) || true
exit 0
