#!/usr/bin/env bash
# 61. address-review's SKILL.md must carry disable-model-invocation: true (CRIT).
# `skills/review/address-review/SKILL.md`'s own reason: external write — posts
# replies to GitHub PR review threads. #36/#40/#45 established the CRIT-guard
# pattern for 3 of the fleet's 10-at-the-time disable-model-invocation carriers;
# this was one of 7 (checks 58-64) closing the gap for the rest, per the
# 2026-08-30 deep-audit finding. Fleet is 6 carriers now — checks 58-60/63
# retired with their carrier skills, 2026-09-01.
# CRIT (not WARN, unlike #30's reason-presence check): a silently-dropped
# flag here means the model could post GitHub PR review replies unattended —
# an external, public write.
_f="$CLAUDE_DIR/skills/review/address-review/SKILL.md"
# Frontmatter-scoped (fm_get), not a raw substring grep over the first 20
# lines — same hardening #36/#40/#45 carry: `head -20 | grep -qF`
# false-negatives if the literal string appears anywhere in the first 20
# lines (e.g. inside `description:` prose) even when the real frontmatter
# key was stripped. fm_get matches `^key:` inside the real `---...---` block
# only, closing that bypass.
if [ -f "$_f" ]; then
  [ "$(fm_get "$_f" disable-model-invocation)" = "true" ] || \
    crit "'$_f': missing 'disable-model-invocation: true' — this is the only mechanism blocking the model from posting GitHub PR review replies unattended, an external public write"
else
  crit "address-review skill not found at skills/review/address-review/SKILL.md — cannot verify the disable-model-invocation flag that is the only mechanism blocking the model from posting GitHub PR review replies unattended"
fi
