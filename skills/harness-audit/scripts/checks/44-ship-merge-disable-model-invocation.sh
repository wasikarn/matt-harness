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
# Command file lives at one of two paths per code.claude.com/docs/en/slash-commands
# — same migration this repo already used for ship/address-review/ideate:
# - commands/ship-merge.md              (legacy flat form)
# - commands/ship-merge/COMMAND.md      (subdir form)
_f=""
[ -f "$CLAUDE_DIR/commands/ship-merge.md" ] && _f="$CLAUDE_DIR/commands/ship-merge.md"
[ -f "$CLAUDE_DIR/commands/ship-merge/COMMAND.md" ] && _f="$CLAUDE_DIR/commands/ship-merge/COMMAND.md"
if [ -n "$_f" ]; then
  head -20 "$_f" | grep -qF 'disable-model-invocation: true' || \
    crit "'$_f': missing 'disable-model-invocation: true' — this is the only mechanism blocking the model from self-invoking a server-side PR merge; its absence means the model could trigger an irreversible external action unattended"
else
  crit "ship-merge command not found at commands/ship-merge.md or commands/ship-merge/COMMAND.md — cannot verify the disable-model-invocation flag that is the only mechanism blocking the model from self-invoking a server-side PR merge"
fi
