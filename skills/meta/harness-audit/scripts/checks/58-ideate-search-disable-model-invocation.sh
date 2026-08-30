#!/usr/bin/env bash
# 58. ideate-search's SKILL.md must carry disable-model-invocation: true (CRIT).
# `skills/meta/ideate-search/SKILL.md`'s own reason: "This is a user-only skill.
# The model should never invoke it unprompted; the user explicitly asks for a
# memory search." The flag is the only mechanism enforcing that. #36/#40/#45
# established the CRIT-guard pattern for 3 of the fleet's 10 disable-model-
# invocation carriers; this is one of 7 (checks 58-64) closing the gap for
# the rest, per the 2026-08-30 deep-audit finding.
# CRIT (not WARN, unlike #30's reason-presence check): a silently-dropped
# flag here means the model could self-invoke a qmd memory search unprompted.
_f="$CLAUDE_DIR/skills/meta/ideate-search/SKILL.md"
# Frontmatter-scoped (fm_get), not a raw substring grep over the first 20
# lines — same hardening #36/#40/#45 carry: `head -20 | grep -qF`
# false-negatives if the literal string appears anywhere in the first 20
# lines (e.g. inside `description:` prose) even when the real frontmatter
# key was stripped. fm_get matches `^key:` inside the real `---...---` block
# only, closing that bypass.
if [ -f "$_f" ]; then
  [ "$(fm_get "$_f" disable-model-invocation)" = "true" ] || \
    crit "'$_f': missing 'disable-model-invocation: true' — this is the only mechanism blocking the model from self-invoking a qmd memory search unprompted"
else
  crit "ideate-search skill not found at skills/meta/ideate-search/SKILL.md — cannot verify the disable-model-invocation flag that is the only mechanism blocking the model from self-invoking a qmd memory search unprompted"
fi
