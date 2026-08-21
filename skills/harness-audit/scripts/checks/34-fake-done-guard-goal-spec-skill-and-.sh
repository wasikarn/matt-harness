#!/usr/bin/env bash
# 34. fake-done guard — ship verifier (arXiv 2606.09863, 'confident closing
# language' as a false proxy for verified completion = a task-completion
# command with no verification step). A task-
# execution command that exits without verifying output is the platform entry-
# point for fake-done shortcuts (relaxed tests, swallowed errors, stub returns,
# comment-deletion-as-fix per moonrunnerkc/swarm-orchestrator taxonomy). WARN on
# content regression (command exists but the verify contract is missing).
# (The goal-spec leg was retired with the goal-spec skill in the v0.6.0
# Matt-first simplification; loop Done-when discipline now lives in ship,
# recursive-improve, and eval-harness.)
_ST=$(find "$CLAUDE_DIR/commands/ship" -name "COMMAND.md" 2>/dev/null | head -1 || true)
if [ -f "$_ST" ]; then
  /usr/bin/grep -qi 'verif' "$_ST" 2>/dev/null \
    || warn "commands/ship/COMMAND.md: no verify step found — task-completion command without a verification phase is the primary fake-done entry point (arXiv 2606.09863, 'confident closing language')"
else
  warn "commands/ship/COMMAND.md not found — cannot verify the fake-done verify-step contract holds"
fi
