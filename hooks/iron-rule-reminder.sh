#!/bin/bash
# UserPromptSubmit: inject METHODOLOGY rule reminders (1 Think before
# coding, 2 Simplicity first, 3 Surgical changes) into Claude's context
# when the user prompt contains risk-trigger words. Catches the root
# cause of the 2026-05-18 TDD-shorthand + theme-deletion regressions:
# agent reads "audit"/"normalize"/"remove" then starts pattern-matching
# before any verification tool call.
#
# Mechanism: vendor docs verbatim — "For UserPromptSubmit ... hooks,
# anything you write to stdout is added to Claude's context." Exit 0.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=iron-rule-reminder

set -uo pipefail

HOOK_ID="iron-rule-reminder"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

# Original failed loud on missing jq AND on .prompt parse failure — preserve.
hook_require_prompt
[ -z "$PROMPT" ] && exit 0

LOWERED=$(printf '%s\n' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Risk triggers via regex word boundaries — `\b` matches both ends symmetrically,
# fixing the prior asymmetric whitespace anchors ("remove " caught "remove the"
# but not line-end "...remove"; " delete" inverse). Word boundary covers both
# "delete the" and "please delete" without separate patterns.
#
# Bilingual coverage (Thai trigger words for the same intent) is left as a
# future enhancement — current triggers cover the EN baseline.
TRIGGER_RE='\b(audit|remove|delete|normalize|drop|consolidate|simplify|tighten|unify)\b|\b(fix all|refactor all)\b|\bclean[- ]?up\b'

if ! printf '%s' "$LOWERED" | grep -qE "$TRIGGER_RE"; then
  exit 0
fi

cat <<'EOF'
[iron-rule-reminder] Risk-trigger word detected. METHODOLOGY rules that apply:

Rule 1 (Think before coding) — every factual claim about a file/skill/API/
vendor behavior must trace to a tool call IN THIS TURN. "Following the
existing pattern" must spot-check the pattern's source of truth first.
"Schema absence" ≠ "no-op" — vendor docs lag features.

Rule 2 (Simplicity first) + Rule 3 (Surgical changes) — answer ONLY what
was specifically asked. No scope expansion based on "what they really mean".
If you spot a related issue, FLAG it; don't silently fix.

Before delete/remove/normalize on configs or doctrine: verify with vendor
docs (WebFetch) / runtime evidence (Read, Bash) first.

This reminder fires from a hook; bypass: CLAUDE_DISABLED_HOOKS=iron-rule-reminder
EOF

exit 0
