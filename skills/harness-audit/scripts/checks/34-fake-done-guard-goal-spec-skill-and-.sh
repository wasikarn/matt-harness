# 34. fake-done guard — goal-spec skill + ship-task verifier (arXiv 2606.10209
# §3 failure modes: Ralph Wiggum loop = no goal spec on disk, agent re-plans
# the same step on every resume; confident garbage = task-completion skill with
# no verification step). Two legs: (a) goal-spec skill MUST exist — without it,
# the harness has no mechanism to write PROMPT.md "Done when" criteria before a
# loop, so agents satisfy a missing contract by faking completion; (b) ship-task
# command MUST reference a verify step — a task-execution command that exits
# without verifying output is the platform entry-point for fake-done shortcuts
# (relaxed tests, swallowed errors, stub returns, comment-deletion-as-fix per
# moonrunnerkc/swarm-orchestrator taxonomy). CRIT on structural absence (missing
# skill = gap in the harness itself); WARN on content regression (skill or
# command exists but the verify contract is missing from its body).
_GS=$(find "$CLAUDE_DIR/skills/goal-spec" -name "SKILL.md" 2>/dev/null | head -1)
if [ ! -f "$_GS" ]; then
  crit "goal-spec skill absent — loops have no PROMPT.md 'Done when' anchor; agents re-plan the same step on resume (Ralph Wiggum loop, arXiv 2606.10209 §3). Add skills/goal-spec/SKILL.md."
else
  /usr/bin/grep -qi 'done when' "$_GS" 2>/dev/null \
    || warn "goal-spec/SKILL.md: 'Done when' section missing — goal-spec without verifiable exit criteria leaves agents free to fake completion"
fi
_ST=$(find "$CLAUDE_DIR/commands/ship-task" -name "COMMAND.md" 2>/dev/null | head -1)
if [ -f "$_ST" ]; then
  /usr/bin/grep -qi 'verif' "$_ST" 2>/dev/null \
    || warn "commands/ship-task/COMMAND.md: no verify step found — task-completion command without a verification phase is the primary fake-done entry point (arXiv 2606.10209 §3 'confident garbage')"
fi