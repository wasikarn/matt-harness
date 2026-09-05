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
    for d in "$CLAUDE_DIR/skills"/[!_]*/ "$CLAUDE_DIR/skills"/[!_]*/[!_]*/; do
      [ -d "$d" ] || continue
      n=$(basename "$d")
      case "$n" in *-workspace) continue ;; esac  # gitignored skill-workspace scratch dirs (skill-creator eval workspaces) -- never real skills
      [ -f "${d}SKILL.md" ] && echo "$n"
    done
  fi
  if [ -d "$HOME/.claude/skills" ]; then
    for d in "$HOME/.claude/skills"/[!_]*/ "$HOME/.claude/skills"/[!_]*/[!_]*/; do
      [ -f "${d}SKILL.md" ] && basename "$d"
    done
  fi
  # Plugin-delivered skills (e.g. mattpocock-skills:grilling) live under the
  # plugin cache, not $CLAUDE_DIR/skills or $HOME/.claude/skills — without
  # this glob, any agent referencing a plugin skill by namespaced name
  # false-WARNs here permanently, regardless of whether the plugin is
  # actually installed correctly. nullglob (scoped to this block, restored
  # after) so a non-matching multi-level glob expands to zero words instead
  # of the literal pattern string — an unguarded `[ -d ]` on that literal
  # would fail and, under set -euo pipefail, abort the whole audit script
  # on any machine with no plugin cache yet (checks are sourced, so a
  # global nullglob would otherwise leak into every later check).
  shopt -s nullglob
  # Two depths: flat plugin layouts (skills/<name>/) AND bucketed ones like
  # mattpocock-skills (skills/<bucket>/<name>/). The single-depth glob alone
  # collected BUCKET names ("engineering", "productivity") as known skills —
  # latent false-WARN the moment an agent's skills: array names a matt skill
  # (caught by a 2026-08-10 plan review). Only dirs
  # actually carrying a SKILL.md count, so bucket dirs never leak in.
  for d in "$HOME"/.claude/plugins/cache/*/*/*/skills/[!_]*/ \
           "$HOME"/.claude/plugins/cache/*/*/*/skills/[!_]*/[!_]*/; do
    [ -f "${d}SKILL.md" ] && basename "$d"
  done
  shopt -u nullglob
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

