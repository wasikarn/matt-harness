#!/usr/bin/env bash
# 23. Name format — skills + agents. code.claude.com/docs/en/skills + /sub-agents:
# name = lowercase letters, digits, hyphens only; max 64 chars. A bad name breaks
# discovery/namespacing. Scaffolds (_*) ship placeholder names — skipped.
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  label=$(basename "$f" .md); [ "$label" = "SKILL" ] && label=$(basename "$(dirname "$f")")
  nm=$(fm_get "$f" "name" --block)
  [ -n "$nm" ] || continue
  if ! printf '%s' "$nm" | grep -qE '^[a-z0-9-]{1,64}$'; then
    crit "'$label' name='$nm' violates format (lowercase/digits/hyphens, <=64 chars)"
  fi
done

