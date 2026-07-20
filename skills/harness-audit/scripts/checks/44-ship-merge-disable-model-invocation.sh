#!/usr/bin/env bash
# 44. ship-merge.md must carry disable-model-invocation: true (CRIT).
# `commands/ship-merge.md` executes a server-side `gh pr merge` — an
# irreversible external action (CLAUDE.md's Operating model, under
# §Architecture: deny the irrecoverable set computationally). The flag is
# the ONLY mechanism enforcing that only a human-typed `/ship-merge` can
# trigger it (there is no PreToolUse hook matching `gh pr merge` — confirmed
# by the 2026-07-20 ship-merge deep-research pass; the entire irreversibility
# posture rests on this frontmatter line). #39 CRIT-guards recursive-improve
# only; this check closes the matching gap for ship-merge's own flag.
# CRIT (not WARN, unlike #30's reason-presence check): a silently-dropped
# flag here means the model could self-invoke a real PR merge.
_f="$CLAUDE_DIR/commands/ship-merge.md"
if [ -f "$_f" ]; then
  head -20 "$_f" | grep -qF 'disable-model-invocation: true' || \
    crit "'commands/ship-merge.md': missing 'disable-model-invocation: true' — this is the only mechanism blocking the model from self-invoking a server-side PR merge; its absence means the model could trigger an irreversible external action unattended"
fi
