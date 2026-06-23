# 36. ideate skill — structural contract (PR2 of ideate-adhd-port). The
# skill is a 2-wave fan-out port from upstream ADHD (docs/research/kbg-vs-adhd.md).
# The structural contract must hold or the next refactor will silently
# collapse the algorithm (the 2026-06-12 44→105-agent failure mode that
# bounded-agent-spawning.md was written to prevent). WARNs (not CRITs) on
# missing pieces: the skill is supposed to have all of them, but a WARN
# surfaces without blocking the audit. The regression fixture
# eval/regressions/ideate-fanout-cap.json is the load-bearing guard;
# this check is the inline fallback for editor / pre-commit visibility.
IDEATE_SKILL="$CLAUDE_DIR/skills/ideate/SKILL.md"
if [ -f "$IDEATE_SKILL" ]; then
  if [ -z "$(fm_get "$IDEATE_SKILL" "name" --block)" ]; then
    warn "ideate skill missing 'name:' in frontmatter"
  elif [ "$(fm_get "$IDEATE_SKILL" "name" --block | tr -d ' ')" != "ideate" ]; then
    warn "ideate skill frontmatter name mismatch"
  fi
  if [ "$(fm_get "$IDEATE_SKILL" "disable-model-invocation" --block | tr -d ' ')" != "false" ]; then
    warn "ideate skill must have disable-model-invocation: false (user opted in to auto-fire on vague open-ended prompts; F8.5 orchestrate is the actual cap)"
  fi
  for sec in "## Pre-flight gate" "## Phase 1" "## Phase 2" "## Frames table" "## 3-axis scoring rubric" "## Isolation invariant"; do
    if ! /usr/bin/grep -qF "$sec" "$IDEATE_SKILL"; then
      warn "ideate skill missing required section: $sec (PR2 contract; locks the 2-wave algorithm shape)"
    fi
  done
else
  warn "skills/ideate/SKILL.md missing — ideate port not landed"
fi

