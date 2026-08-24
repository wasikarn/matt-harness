#!/usr/bin/env bash
# 56. LOC cap on auto-loaded surface files — agents/*.md, commands/*.md,
# commands/*/COMMAND.md, skills/*/SKILL.md must stay <= 200 lines (plain
# `wc -l`, frontmatter and blanks count). Operator rule set 2026-08-23
# (grilling session, 8 settled decisions): these files load whole into
# context on trigger/spawn, so size is a per-use token cost; reference.md /
# references/ sub-files are exempt (on-demand load) and are the intended
# overflow target. WARN, not CRIT: file size is always recoverable, so per
# the deny-vs-advise operating model this advises rather than blocks.
# Coexists with checks 38/47/52 (20K-char INFO) — chars catch dense long
# lines that a line count misses; this check reports chars alongside lines
# so reflowed-but-not-reduced prose stays visible (token load tracks chars,
# not lines).
LOC_CAP=200
for _f in "$CLAUDE_DIR"/agents/*.md \
          "$CLAUDE_DIR"/commands/*.md \
          "$CLAUDE_DIR"/commands/*/COMMAND.md \
          "$CLAUDE_DIR"/skills/[!_]*/SKILL.md; do
  [ -f "$_f" ] || continue
  _lines=$(wc -l < "$_f" | tr -d ' ')
  if [ "$_lines" -gt "$LOC_CAP" ]; then
    _chars=$(wc -c < "$_f" | tr -d ' ')
    _rel=${_f#"$CLAUDE_DIR"/}
    warn "'$_rel' is ${_lines} lines (cap ${LOC_CAP}; ${_chars} chars) — move detail to the surface's reference file (skills: reference.md; commands: references/ via directory form; agents: compress, cuts listed in the commit message)"
  fi
done
unset _f _lines _chars _rel LOC_CAP
