#!/usr/bin/env bash
# 49. score-decision must carry disable-model-invocation: true (CRIT).
# score-decision is the fleet's other safety-load-bearing instance of the flag
# (on-demand formal Decision Scoring, METHODOLOGY Rule 14) — until this check,
# only recursive-improve (#39) had a CRIT guard; score-decision relied on
# check #30's WARN-only reason-presence check, which confirms a `-reason`
# field exists but does not catch the flag itself disappearing. Found by the
# kbg:plan-reviewer adversarial pass on the 2026-07-23 skill-improvement batch
# plan: skill-creator's own description-optimizer rewrites SKILL.md
# frontmatter, and that rewrite step runs against score-decision in this
# plan's batch A3 with no gate protecting the flag. Mirrors #39's shape
# exactly — same CRIT rationale: a silently-dropped flag on this surface is a
# safety regression, not a doc gap.
_f="$CLAUDE_DIR/skills/score-decision/SKILL.md"
if [ -f "$_f" ]; then
  head -20 "$_f" | grep -qF 'disable-model-invocation: true' || \
    crit "'score-decision/SKILL.md': missing 'disable-model-invocation: true' — this is the fleet's other safety-load-bearing instance of the flag (on-demand formal Decision Scoring); its absence means this skill could become model-invocable with no error anywhere in the pipeline"
fi
