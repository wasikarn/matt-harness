#!/usr/bin/env bash
# 57. Suggested-next-step footer shape drift. A skill that mentions
# "suggested next step" at all (case-insensitive) must carry the marker in
# its canonical form somewhere in the file: an optionally-numbered, bolded,
# standalone line — `**Suggested next step:**` or `4. **Suggested next
# step:**`. docs/skill-authoring-conventions.md's "Suggested next step
# footers" section documents the canonical shape (copy
# skills/review/pr/SKILL.md's footer); this check exists because a 2026-08-30
# audit found 8 of 11 footer-carrying skills had drifted into one of: an
# unbolded/lowercase marker, an H2 heading, branches inline in prose on the
# marker's own line, or the marker buried mid-sentence.
#
# Deliberately narrow, matching checks 37/46's own scope discipline: this
# does NOT decide which skills *should* carry a footer (that's a semantic
# eligibility call the doctrine's own "skip reference/pattern/catalog and
# terminal workflows" carve-out already reserves for the author, not a
# mechanical check) — it only checks that a footer already present is
# well-formed. File-level, not per-occurrence: a file need only contain the
# canonical line ONCE to pass, even if the phrase "suggested next step"
# appears again elsewhere as ordinary report-content prose (e.g.
# build-fix/SKILL.md's "with a suggested next step per issue" — legitimate
# prose describing a per-finding field, not itself a footer; a per-line rule
# would make that phrasing an unfixable warn).
#
# Scope: skills/*/SKILL.md and skills/*/*/SKILL.md only — deliberately
# narrower than 37/46's scan list. agents/*.md is excluded on purpose:
# agents/build-error-resolver.md:193's "Suggested next steps for unresolved
# issues" is a pluralized report-content instruction, not a footer, and
# would false-positive under this rule. docs/reference/*.md and
# skills/*/references/*.md are excluded too — the convention is scoped to a
# skill's own Output/Summary phase, not to prose that merely discusses the
# convention (this check's own presence in
# skills/meta/harness-audit/SKILL.md would otherwise self-trigger, mirroring
# check 34's harness-audit self-reference exclusion).
# WARN, not CRIT — advisory, matching 37/46's severity.
for _f in "$CLAUDE_DIR"/skills/*/SKILL.md "$CLAUDE_DIR"/skills/*/*/SKILL.md; do
  [ -f "$_f" ] || continue
  case "$_f" in */skills/harness-audit/*|*/skills/*/harness-audit/*) continue ;; esac
  grep -qi 'suggested next step' "$_f" 2>/dev/null || continue
  grep -qE '^([0-9]+\. )?\*\*Suggested next step:\*\*$' "$_f" 2>/dev/null && continue
  warn "suggested-next-step footer shape drift in ${_f#"$CLAUDE_DIR"/}: mentions 'suggested next step' but no line matches the canonical '**Suggested next step:**' marker (docs/skill-authoring-conventions.md)"
done
unset _f
