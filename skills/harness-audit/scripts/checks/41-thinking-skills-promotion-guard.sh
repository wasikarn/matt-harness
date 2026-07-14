#!/usr/bin/env bash
# 41. Thinking-skills promotion guard — no docs/reference/thinking-skills
# model may cross into the auto-discovered skills/ tree without deliberately
# clearing the evaluation-first bar reasoning-models.md documents ("External
# verification", 2026-07-14). Upstream cc-thinking-skills ships its own
# auto-selecting `thinking-model-router` skill with no `disable-model-
# invocation` gate; kbg's actual protection against that exact failure mode
# is this directory boundary (docs/reference/, never skills/), not a
# content-level safeguard. WARN, not CRIT — a promoted directory is trivially
# reversible (delete it), matching check 32's severity for the same doctrine
# file's drift, not check 39's irrecoverable-loop class.
shopt -s nullglob
_thinking_promoted=("$CLAUDE_DIR"/skills/thinking-*)
shopt -u nullglob
for _tp in "${_thinking_promoted[@]}"; do
  warn "thinking-skills promotion: $(basename "$_tp") exists under skills/ — a docs/reference/thinking-skills model (or a skill named after one) crossed into the auto-discovered tree; clear the evaluation-first bar in docs/reference/reasoning-models.md's 'External verification' section first"
done
unset _thinking_promoted _tp
