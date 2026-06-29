#!/usr/bin/env bash
# 25. Agent skills: references resolve to a real skill — repo or installed global
# (~/.claude/skills/). code.claude.com/docs/en/sub-agents: the skills: array
# names skills made available to the agent. A dangling ref (after a rename or
# delete) silently provides nothing. A plugin-scoped ref (plugin:name) resolves
# on its base name.
_known_skills=$(mktemp)
{
  # [!_]*/ skips _-prefixed scaffolds (e.g. _template). Guard each loop with
  # an if so the command group ends with exit 0 even when the directory is
  # missing; with set -euo pipefail the pipeline would otherwise abort here.
  if [ -d "$CLAUDE_DIR/skills" ]; then
    for d in "$CLAUDE_DIR/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done
  fi
  if [ -d "$HOME/.claude/skills" ]; then
    for d in "$HOME/.claude/skills"/[!_]*/; do [ -d "$d" ] && basename "$d"; done
  fi
} | sort -u > "$_known_skills"
while IFS= read -r ref_line; do
  warn "$ref_line"
done < <(
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    # extract the YAML list under `skills:` up to the next top-level key
    awk '
      /^skills:[[:space:]]*$/ { in_s=1; next }
      in_s && /^[[:space:]]+-[[:space:]]+/ { sub(/^[[:space:]]+-[[:space:]]+/,""); sub(/[[:space:]]+$/,""); print; next }
      in_s && /^[^[:space:]]/ { in_s=0 }
    ' "$f" | while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      base="${ref##*:}"   # strip plugin: prefix
      if ! grep -qx "$ref" "$_known_skills" && ! grep -qx "$base" "$_known_skills"; then
        echo "agent '$name' skills: ref '$ref' resolves to no known skill"
      fi
    done
  done
)
rm -f "$_known_skills"

