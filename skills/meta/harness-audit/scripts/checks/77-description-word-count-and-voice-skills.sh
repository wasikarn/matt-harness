#!/usr/bin/env bash
# 77. Description word count + third-person voice — skills, agents.
# skill-authoring-conventions.md: "Description cap: 25 words, third person." mh's own
# token-budget rule (descriptions load on every Task spawn) — distinct from check 20
# (1536-char runtime truncation limit) and check 43 (cumulative listing budget); neither
# of those checks word count or voice. WARN only: a style convention, not a runtime cap.
PRON_PATTERN='\b(I|I'\''m|I'\''ve|my|mine|we|we'\''re|we'\''ve|our|ours|us|you|you'\''re|your|yours)\b'
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  label=$(basename "$f" .md); [ "$label" = "SKILL" ] && label=$(basename "$(dirname "$f")")
  desc=$(fm_get "$f" "description" --block)
  [ -z "$desc" ] && continue
  words=$(printf '%s' "$desc" | wc -w | tr -d ' ')
  if [ "$words" -gt 25 ]; then
    warn "'$label' description is $words words (>25; skill-authoring-conventions.md caps it — trim or move detail into the body)"
  fi
  if printf '%s' "$desc" | /usr/bin/grep -iEq "$PRON_PATTERN"; then
    warn "'$label' description uses first/second-person phrasing — skill-authoring-conventions.md requires third person"
  fi
done
