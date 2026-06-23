# 12. Routing table coverage (orchestrate references all agents)
# The agent fleet list lives in reference.md; SKILL.md carries only inline
# examples (SKILL.md:49 points to reference.md). Check both — an agent
# documented in either file counts as covered.
ORCH_SKILL="$CLAUDE_DIR/skills/orchestrate/SKILL.md"
ORCH_REF="$CLAUDE_DIR/skills/orchestrate/reference.md"
if [ -f "$ORCH_SKILL" ]; then
  for f in "$CLAUDE_DIR/agents"/*.md; do
    [ -f "$f" ] || continue
    agent=$(basename "$f" .md)
    if ! grep -hq "\`$agent\`" "$ORCH_SKILL" "$ORCH_REF" 2>/dev/null; then
      warn "agent '$agent' not referenced in orchestrate routing table"
    fi
  done
fi

