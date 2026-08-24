#!/usr/bin/env bash
# 47. Command body size outlier — flag command entrypoints large enough to
# warrant a token-optimizer pass or a directory-form split. INFO only, never
# a hard cap: mirrors check 38's threshold for the identical reason (some
# commands are legitimately dense). Same 20K-char threshold as check 38 —
# deliberately not re-derived from the commands/ distribution, since the
# comparison that matters is "would this trip the skill-side check if it
# were a skill," not a separate commands-only baseline.
# Gap this closes: check 38 only globs skills/*/SKILL.md, so a command
# entrypoint has never been mechanically flagged for size regardless of how
# large it grows — confirmed 2026-07-31, commands/address-review.md sat at
# 23,556 chars (over this same threshold) with no check able to see it.
# Scoped to entrypoints only (flat commands/*.md + directory-form
# commands/*/COMMAND.md), matching check 06/30's established glob — a
# references/ file is supporting material, not the entrypoint, and isn't
# what a reader loads on every invocation.
SIZE_THRESHOLD_CHARS=20000
for _f in "$CLAUDE_DIR"/commands/*.md "$CLAUDE_DIR"/commands/*/COMMAND.md; do
  [ -f "$_f" ] || continue
  _chars=$(wc -c < "$_f" | tr -d ' ')
  if [ "$_chars" -gt "$SIZE_THRESHOLD_CHARS" ]; then
    _tokens=$((_chars / 4))
    _rel="${_f#"$CLAUDE_DIR"/}"
    info "'$_rel' is ${_chars} chars (~${_tokens} tokens, fleet threshold ${SIZE_THRESHOLD_CHARS}) — consider a directory-form split (commands/<name>/COMMAND.md + references/, per ship/ideate) or a token-optimizer pass"
  fi
done
unset _f _chars _tokens _rel SIZE_THRESHOLD_CHARS
