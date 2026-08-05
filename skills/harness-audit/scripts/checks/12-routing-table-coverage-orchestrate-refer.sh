#!/usr/bin/env bash
# 12. Routing table coverage (orchestrate references all agents)
# The agent fleet list lives in reference.md; SKILL.md carries only inline
# examples (SKILL.md:49 points to reference.md). Check both — an agent
# documented in either file counts as covered.
ORCH_SKILL="$CLAUDE_DIR/skills/orchestrate/SKILL.md"
ORCH_REF="$CLAUDE_DIR/skills/orchestrate/reference.md"
if [ -f "$ORCH_SKILL" ]; then
  # Build the set of backtick-wrapped tokens once (was: one grep per agent
  # re-scanning both files -- 19 spawns where 1 pass + array lookups do).
  declare -A _orch_refs=()
  while IFS= read -r _tok; do
    _orch_refs["$_tok"]=1
  done < <(grep -hoE '`[^`]+`' "$ORCH_SKILL" "$ORCH_REF" 2>/dev/null | tr -d '`')
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    agent=$(basename "$f" .md)
    [ -n "${_orch_refs[$agent]:-}" ] || warn "agent '$agent' not referenced in orchestrate routing table"
  done
  unset _orch_refs
fi

