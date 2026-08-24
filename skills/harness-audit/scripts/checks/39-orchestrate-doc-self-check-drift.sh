#!/usr/bin/env bash
# 39. Doc-embedded self-check assertions against orchestrate/SKILL.md go stale
# (docs/common-mistakes.md embeds `grep -c "<pattern>" .../orchestrate/SKILL.md`
# snippets asserting a count > 0; nothing re-ran them when SKILL.md changed —
# found live 2026-07-17 via a requirement-analyst trial on the v0.58.5
# token-optimizer pass: it moved content between SKILL.md and reference.md and
# nobody had actually re-checked these assertions since). Extracts the pattern
# from the doc itself rather than hardcoding it a second time, so a future
# self-check added to the doc is covered without editing this check. WARN, not
# CRIT — doc-rot, not a build break. Same defect class as checks 35 and 37
# (dead-script/dead-kbg-reference doc-rot; the old check 38 covering the
# same class was retired 2026-08-25, ticket 87).
ORCH_SKILL="$CLAUDE_DIR/skills/orchestrate/SKILL.md"
MISTAKES_DOC="$CLAUDE_DIR/docs/common-mistakes.md"
if [ -f "$ORCH_SKILL" ] && [ -f "$MISTAKES_DOC" ]; then
  while IFS= read -r _pattern; do
    [ -z "$_pattern" ] && continue
    _count=$(grep -c -- "$_pattern" "$ORCH_SKILL" 2>/dev/null || true)
    if [ "${_count:-0}" -eq 0 ]; then
      warn "docs/common-mistakes.md self-check 'grep -c \"$_pattern\" orchestrate/SKILL.md' now returns 0 — the doc's own asserted count no longer holds (doc-rot)"
    fi
  done < <(grep -oE 'grep -c "[^"]+" "[^"]*orchestrate/SKILL\.md"' "$MISTAKES_DOC" | sed -E 's/^grep -c "([^"]+)".*/\1/')
fi
unset ORCH_SKILL MISTAKES_DOC _pattern _count
