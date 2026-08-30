#!/usr/bin/env bash
# 36. recursive-improve must carry disable-model-invocation: true (CRIT).
# This is the one safety-load-bearing instance of the flag in the fleet — the
# no-model-self-start invariant (CLAUDE.md's Operating model, under the
# Architecture section: no covert unattended self-repair loop) is enforced for
# recursive-improve ONLY via this flag forcing user-only invocation. Docs
# citing this flag (recursive-improve/SKILL.md's own frontmatter reason,
# docs/agent-tool-patterns.md, and this check's own header) had claimed it
# was "CRIT-guarded by #32" — #32 is `32-reasoning-models-index-drift...sh`,
# an unrelated WARN-only check; the renumbering after the v0.6.0 checklist
# prune (commit 1f708c7) never got a real guard. Found by the 2026-07-01
# deep-verification audit (Decision Coverage / Knowledge Coverage rounds).
# CRIT (not WARN, unlike #30's reason-presence check): a silently-dropped
# flag on this one surface is a safety regression, not a doc gap.
#
# Frontmatter-scoped (fm_get), not a raw substring grep over the first 20
# lines: a `compliance-audit` adversarial pass (2026-07-23) found the prior
# `head -20 | grep -qF` form false-negatives if the literal string
# "disable-model-invocation: true" appears anywhere in the first 20 lines —
# e.g. inside `description:` prose — even when the real frontmatter key was
# actually stripped. fm_get only matches `^key:` inside the real `---...---`
# block, closing that gap.
#
# else branch added 2026-08-30 (deep-audit adversarial pass on the checks
# 58-64 commit): this check and #45 were the only 2 of the fleet's 10
# dedicated CRIT guards with no `else` — a moved/renamed SKILL.md silently
# passed instead of firing CRIT, on the two skills this file's own header
# calls "safety-load-bearing." checks 40/58-64 already had this branch;
# this brings 36/45 in line.
_f="$CLAUDE_DIR/skills/meta/recursive-improve/SKILL.md"
if [ -f "$_f" ]; then
  [ "$(fm_get "$_f" disable-model-invocation)" = "true" ] || \
    crit "'recursive-improve/SKILL.md': missing 'disable-model-invocation: true' — this is the one safety-load-bearing instance of the flag (no-model-self-start invariant); its absence means the CLAUDE.md selection criterion could route unattended dispatch to this skill"
else
  crit "recursive-improve skill not found at skills/meta/recursive-improve/SKILL.md — cannot verify the disable-model-invocation flag that is the one safety-load-bearing instance of the flag (no-model-self-start invariant)"
fi
