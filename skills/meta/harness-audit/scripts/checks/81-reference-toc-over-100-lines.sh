#!/usr/bin/env bash
# 81. Reference file over 100 lines has a table of contents (skills/).
#
# Anthropic's skill best practices: a file reached from another referenced file may be
# previewed with `head -100`, so a reference file longer than 100 lines needs a "Contents"
# heading near the top to show its full scope. WARN: a completeness risk, not a safety class.
shopt -s nullglob
_toc_candidates=("$CLAUDE_DIR"/skills/*/*.md "$CLAUDE_DIR"/skills/*/*/*.md "$CLAUDE_DIR"/skills/*/references/*.md "$CLAUDE_DIR"/skills/*/*/references/*.md)
shopt -u nullglob
for _f in "${_toc_candidates[@]}"; do
  [ -f "$_f" ] || continue
  [ "$(basename "$_f")" = SKILL.md ] && continue
  [ "$(wc -l < "$_f")" -gt 100 ] || continue
  head -30 "$_f" | grep -qiE '^#{1,3} (table of )?contents' || warn "reference file ${_f#"$CLAUDE_DIR"/} is over 100 lines with no '## Contents' heading in its first 30 lines (a partial head -100 read would miss most of it)"
done
unset _f _toc_candidates
