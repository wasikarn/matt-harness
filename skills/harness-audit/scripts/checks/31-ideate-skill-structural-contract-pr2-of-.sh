#!/usr/bin/env bash
# 31. ideate command — structural contract (PR2 of ideate-adhd-port). The
# surface is now a slash command (`/ideate`) ported from the upstream ADHD skill
# (docs/research/kbg-vs-adhd.md). The structural contract must hold or the next
# refactor will silently collapse the algorithm (the 2026-06-12 44→105-agent
# failure mode that bounded-agent-spawning.md was written to prevent). WARNs
# (not CRITs) on missing pieces. This check IS the sole guard now — the
# former regression fixture eval/regressions/ideate-fanout-cap.json (and the
# whole eval/ tree) was deleted in the 2026-06-27 owner-authorized reset
# (c452102); this check survived as the inline editor / pre-commit guard.
# Command file lives at one of two paths per code.claude.com/docs/en/slash-commands:
# - commands/ideate.md                              (legacy flat form)
# - commands/ideate/COMMAND.md                      (subdir form for supporting files)
IDEATE_CMD=""
[ -f "$CLAUDE_DIR/commands/ideate.md" ] && IDEATE_CMD="$CLAUDE_DIR/commands/ideate.md"
[ -f "$CLAUDE_DIR/commands/ideate/COMMAND.md" ] && IDEATE_CMD="$CLAUDE_DIR/commands/ideate/COMMAND.md"
if [ -f "$IDEATE_CMD" ]; then
  if [ -z "$(fm_get "$IDEATE_CMD" "name" --block)" ]; then
    warn "ideate command missing 'name:' in frontmatter"
  elif [ "$(fm_get "$IDEATE_CMD" "name" --block | tr -d ' ')" != "ideate" ]; then
    warn "ideate command frontmatter name mismatch"
  fi
  if [ "$(fm_get "$IDEATE_CMD" "disable-model-invocation" --block | tr -d ' ')" != "false" ]; then
    warn "ideate command must have disable-model-invocation: false (user opted in to auto-fire on vague open-ended prompts; F8.5 orchestrate is the actual cap)"
  fi
  for sec in "## Pre-flight gate" "## Phase 1" "## Phase 2" "## Frames table" "## 3-axis scoring rubric" "## Isolation invariant"; do
    if ! /usr/bin/grep -qF "$sec" "$IDEATE_CMD"; then
      warn "ideate command missing required section: $sec (PR2 contract; locks the 2-wave algorithm shape)"
    fi
  done
else
  warn "commands/ideate.md missing — ideate port not landed"
fi

