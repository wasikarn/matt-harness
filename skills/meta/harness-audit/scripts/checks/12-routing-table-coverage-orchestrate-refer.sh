#!/usr/bin/env bash
# 12. Routing table coverage (orchestrate references all agents)
# The agent fleet list lives in reference.md; SKILL.md carries only inline
# examples (SKILL.md:49 points to reference.md). Check both — an agent
# documented in either file counts as covered.
ORCH_SKILL="$CLAUDE_DIR/skills/workflow/orchestrate/SKILL.md"
ORCH_REF="$CLAUDE_DIR/skills/workflow/orchestrate/reference.md"
if [ -f "$ORCH_SKILL" ]; then
  _agent_names=()
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    _agent_names+=("$(basename "$f" .md)")
  done
  if [ "${#_agent_names[@]}" -gt 0 ]; then
    # One grep alternating over every agent name (was: one grep PER agent
    # re-scanning both files -- 19 spawns where 1 does). Same substring-match
    # semantics as the original per-agent `grep -hq "\`$agent\`"` -- a single
    # alternated pattern, not a pre-tokenized set, so adjacent-backtick
    # constructs (e.g. `` `ab`agent` ``) still match exactly as before.
    _alt=$(IFS='|'; echo "${_agent_names[*]}")
    declare -A _orch_refs=()
    while IFS= read -r _tok; do
      _orch_refs["$_tok"]=1
    done < <(grep -ohE "\`($_alt)\`" "$ORCH_SKILL" "$ORCH_REF" 2>/dev/null | tr -d '`')
    for agent in "${_agent_names[@]}"; do
      [ -n "${_orch_refs[$agent]:-}" ] || warn "agent '$agent' not referenced in orchestrate routing table"
    done
    unset _orch_refs
  fi
  unset _agent_names _alt
fi

