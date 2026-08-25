#!/usr/bin/env bash
# 6. commands/ regression guard (repurposed 2026-08-25, #112 — this slot used
# to be frontmatter-completeness for commands/, obsolete once commands/
# retired as a surface type entirely; the old commands-side check was fully
# subsumed by check 05's skills-side equivalent, so nothing is lost).
# Every command in this repo converted to a skill (spec #101, tickets
# #102-112) on the stated rationale that mattpocock-skills has no commands/
# concept and matt-harness should converge with it. If commands/ ever
# reappears — a stray file survives a bad merge, a future contributor
# reintroduces the pattern out of habit — that's a silent regression back to
# the two-surface-type split this migration deliberately eliminated. CRIT:
# this is a structural-drift class, not doc-rot — the whole point of the
# migration was "one surface type," so any commands/ content means that
# invariant broke.
if [ -d "$CLAUDE_DIR/commands" ] && find "$CLAUDE_DIR/commands" -mindepth 1 -type f 2>/dev/null | grep -q .; then
  crit "commands/ directory contains files — commands/ was retired as a surface type 2026-08-25 (#112); convert any new file here to a skill under skills/ instead"
fi
