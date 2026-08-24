#!/usr/bin/env bash
# 45. score-decision must carry disable-model-invocation: true (CRIT).
# score-decision is the fleet's other safety-load-bearing instance of the flag
# (on-demand formal Decision Scoring, METHODOLOGY Rule 14) — until this check,
# only recursive-improve (#36) had a CRIT guard; score-decision relied on
# check #30's WARN-only reason-presence check, which confirms a `-reason`
# field exists but does not catch the flag itself disappearing. Found by the
# kbg:plan-reviewer adversarial pass on the 2026-07-23 skill-improvement batch
# plan: skill-creator's own description-optimizer rewrites SKILL.md
# frontmatter, and that rewrite step runs against score-decision in this
# plan's batch A3 with no gate protecting the flag. Mirrors #36's shape
# exactly — same CRIT rationale: a silently-dropped flag on this surface is a
# safety regression, not a doc gap.
#
# Frontmatter-scoped (fm_get), not a raw substring grep over the first 20
# lines: a `compliance-audit` adversarial pass (2026-07-23) on THIS check
# found the prior `head -20 | grep -qF` form false-negatives if the literal
# string "disable-model-invocation: true" appears anywhere in the first 20
# lines — e.g. inside `description:` prose — even when the real frontmatter
# key was actually stripped. fm_get only matches `^key:` inside the real
# `---...---` block, closing that gap. Same fix applied to #36 (the check
# this one mirrors) in the same pass.
_f="$CLAUDE_DIR/skills/score-decision/SKILL.md"
if [ -f "$_f" ]; then
  [ "$(fm_get "$_f" disable-model-invocation)" = "true" ] || \
    crit "'score-decision/SKILL.md': missing 'disable-model-invocation: true' — this is the fleet's other safety-load-bearing instance of the flag (on-demand formal Decision Scoring); its absence means this skill could become model-invocable with no error anywhere in the pipeline"
fi
