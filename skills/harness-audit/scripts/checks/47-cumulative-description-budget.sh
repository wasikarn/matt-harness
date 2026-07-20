#!/usr/bin/env bash
# 47. Cumulative skill+command description budget. Check 20 caps each
# description at 1536 chars individually — nothing sums the fleet. Skills and
# commands share one runtime listing budget (docs: "scales at ~1% of the
# model's context window", configurable via SLASH_COMMAND_TOOL_CHAR_BUDGET);
# past the real ceiling, least-invoked descriptions silently drop from context
# with no error (confirmed via multiple community GitHub issues) — the
# skills/ deep-research critique (2026-07-20) found this un-warned failure
# mode invisible with no fleet-wide number tracking it. Threshold is the
# conservative reading (~1% of a 200K window ≈ 2000 tokens ≈ 8000 chars);
# community-measured empirical ceilings run higher (~15-16K chars) but the two
# sources conflict and are unreconciled, so WARN on the conservative line and
# print the running total unconditionally so the trend is visible either way.
# WARN, not CRIT: a full description pool degrades gracefully (silent
# truncation), it is not irrecoverable.
BUDGET_CHARS=8000
_total=0
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/commands"/*.md "$CLAUDE_DIR/commands"/*/COMMAND.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  desc=$(fm_get "$f" "description" --block)
  _total=$((_total + ${#desc}))
done
_tokens=$((_total / 4))
_budget_tokens=$((BUDGET_CHARS / 4))
info "cumulative skill+command description budget: ${_total} chars (~${_tokens} tokens) of a conservative ~${BUDGET_CHARS}-char (~${_budget_tokens}-token) ceiling"
if [ "$_total" -gt "$BUDGET_CHARS" ]; then
  warn "cumulative skill+command descriptions are ${_total} chars (~${_tokens} tokens), over the conservative ~${BUDGET_CHARS}-char (~${_budget_tokens}-token) listing-budget ceiling — least-invoked surfaces risk silently dropping from the model's context; trim descriptions or split reference content out of the description field"
fi
unset f desc _total _tokens _budget_tokens BUDGET_CHARS
