#!/usr/bin/env bash
# 60. wiki-ingest's SKILL.md must carry disable-model-invocation: true (CRIT).
# `skills/workflow/wiki-ingest/SKILL.md`'s own reason: mutates the operator's
# personal llm-wiki vault outside this repo — copies into raw/, creates a
# wiki/ page, appends to log.md (and, when the guard allows it, hotcache.md).
# A human must type /mh:wiki-ingest themselves. #36/#40/#45 established the
# CRIT-guard pattern for 3 of the fleet's 10 disable-model-invocation
# carriers; this is one of 7 (checks 58-64) closing the gap for the rest,
# per the 2026-08-30 deep-audit finding.
# CRIT (not WARN, unlike #30's reason-presence check): a silently-dropped
# flag here means the model could mutate the operator's personal llm-wiki
# vault unattended.
_f="$CLAUDE_DIR/skills/workflow/wiki-ingest/SKILL.md"
# Frontmatter-scoped (fm_get), not a raw substring grep over the first 20
# lines — same hardening #36/#40/#45 carry: `head -20 | grep -qF`
# false-negatives if the literal string appears anywhere in the first 20
# lines (e.g. inside `description:` prose) even when the real frontmatter
# key was stripped. fm_get matches `^key:` inside the real `---...---` block
# only, closing that bypass.
if [ -f "$_f" ]; then
  [ "$(fm_get "$_f" disable-model-invocation)" = "true" ] || \
    crit "'$_f': missing 'disable-model-invocation: true' — this is the only mechanism blocking the model from mutating the operator's personal llm-wiki vault (outside this repo) unattended"
else
  crit "wiki-ingest skill not found at skills/workflow/wiki-ingest/SKILL.md — cannot verify the disable-model-invocation flag that is the only mechanism blocking the model from mutating the operator's personal llm-wiki vault unattended"
fi
