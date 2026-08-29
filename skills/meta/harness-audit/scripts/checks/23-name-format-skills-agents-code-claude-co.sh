#!/usr/bin/env bash
# 23. Name format — skills + agents. code.claude.com/docs/en/skills + /sub-agents:
# name = lowercase letters, digits, hyphens only; max 64 chars. A bad name breaks
# discovery/namespacing. Scaffolds (_*) ship placeholder names — skipped.
# Reserved-word ban (platform.claude.com/docs/en/agents-and-tools/agent-skills/
# best-practices.md, verified 2026-08-29): name must not contain "anthropic" or
# "claude". No separate XML-tag check is needed here — the char-class regex below
# already excludes XML tags from name; that ban is real for description too, just
# not checked (check 20's own char-limit is a separate, deliberately unresolved gap).
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  label=$(basename "$f" .md); [ "$label" = "SKILL" ] && label=$(basename "$(dirname "$f")")
  nm=$(fm_get "$f" "name" --block)
  [ -n "$nm" ] || continue
  if ! printf '%s' "$nm" | grep -qE '^[a-z0-9-]{1,64}$'; then
    crit "'$label' name='$nm' violates format (lowercase/digits/hyphens, <=64 chars)"
  fi
  if printf '%s' "$nm" | grep -qE 'anthropic|claude'; then
    crit "'$label' name='$nm' contains a reserved word (anthropic/claude — official Agent Skills spec)"
  fi
done

