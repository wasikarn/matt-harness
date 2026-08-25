#!/usr/bin/env bash
# 40. ship-merge's SKILL.md must carry disable-model-invocation: true (CRIT).
# `skills/ship-merge/SKILL.md` executes a server-side `gh pr merge` — an
# irreversible external action (CLAUDE.md's Operating model, under
# §Architecture: deny the irrecoverable set computationally). The flag is
# the ONLY mechanism enforcing that only a human-typed `mh:ship-merge` can
# trigger it (there is no PreToolUse hook matching `gh pr merge` — confirmed
# by the 2026-07-20 ship-merge deep-research pass; the entire irreversibility
# posture rests on this frontmatter line). #36 CRIT-guards recursive-improve
# only; this check closes the matching gap for ship-merge's own flag.
# CRIT (not WARN, unlike #30's reason-presence check): a silently-dropped
# flag here means the model could self-invoke a real PR merge.
# Repointed from commands/ship-merge/COMMAND.md to skills/ship-merge/SKILL.md
# 2026-08-25 (#103, commands→skills convergence, spec #101) — the surface
# moved, the risk and the enforcement mechanism did not.
_f="$CLAUDE_DIR/skills/ship-merge/SKILL.md"
# Frontmatter-scoped (fm_get), not a raw substring grep over the first 20
# lines — same hardening #36/#45 got in the 2026-07-23 compliance-audit pass:
# `head -20 | grep -qF` false-negatives if the literal string appears anywhere
# in the first 20 lines (e.g. inside `description:` prose) even when the real
# frontmatter key was stripped. #40 was missed in that pass (found by the
# 2026-08-14 fleet breadth sweep). fm_get matches `^key:` inside the real
# `---...---` block only, closing the latent bypass.
if [ -f "$_f" ]; then
  [ "$(fm_get "$_f" disable-model-invocation)" = "true" ] || \
    crit "'$_f': missing 'disable-model-invocation: true' — this is the only mechanism blocking the model from self-invoking a server-side PR merge; its absence means the model could trigger an irreversible external action unattended"
else
  crit "ship-merge skill not found at skills/ship-merge/SKILL.md — cannot verify the disable-model-invocation flag that is the only mechanism blocking the model from self-invoking a server-side PR merge"
fi
