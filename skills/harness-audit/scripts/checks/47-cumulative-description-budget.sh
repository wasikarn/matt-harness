#!/usr/bin/env bash
# 47. Cumulative skill+command description budget. Check 20 caps each
# description at 1536 chars individually — nothing sums the fleet. Skills and
# commands share one runtime listing budget (docs: "scales at ~1% of the
# model's context window", configurable via SLASH_COMMAND_TOOL_CHAR_BUDGET or
# skillListingBudgetFraction); past the real ceiling, least-invoked
# descriptions silently drop from context with no error (confirmed via
# multiple community GitHub issues) — the skills/ deep-research critique
# (2026-07-20) found this un-warned failure mode invisible with no fleet-wide
# number tracking it.
#
# The threshold reflects whatever is ACTUALLY configured for this run, not a
# blind guess: SLASH_COMMAND_TOOL_CHAR_BUDGET env (a fixed-char override) wins
# if set; else skillListingBudgetFraction from settings, project-local
# (.claude/settings.local.json) taking precedence over the user's global
# (~/.claude/settings.json) — Claude Code's own most-specific-wins precedence,
# not a merge (see the skill-listing-budget-mechanics memory, 2026-06-25);
# else the platform default of 1% of a 200K-token window (≈8000 chars).
# Community-measured empirical ceilings run higher (~15-16K chars) than the
# 1%-of-200K math but the two sources conflict and are unreconciled, so an
# unconfigured install still gets the conservative 8000-char line — only a
# real, on-disk configuration override changes the threshold. WARN, not CRIT:
# a full description pool degrades gracefully (silent truncation), it is not
# irrecoverable.
_local_settings="$REPO_ROOT/.claude/settings.local.json"
_global_settings="$HOME/.claude/settings.json"
_frac=""
for _sf in "$_local_settings" "$_global_settings"; do
  [ -f "$_sf" ] || continue
  _v=$(python3 -c "
import json
try:
    d = json.load(open('$_sf'))
    v = d.get('skillListingBudgetFraction')
    print(v if v is not None else '')
except Exception:
    print('')
" 2>/dev/null)
  if [ -n "$_v" ]; then _frac="$_v"; break; fi
done
if [ -n "${SLASH_COMMAND_TOOL_CHAR_BUDGET:-}" ]; then
  # Validate as a plain non-negative integer before it ever reaches
  # $(( )) arithmetic below — an unvalidated value there is bash
  # arithmetic-eval injection via array-subscript expansion (found
  # 2026-08-06). Same guard shape as the retired write-review-state.sh's PREV_ROUND.
  case "$SLASH_COMMAND_TOOL_CHAR_BUDGET" in
    ''|*[!0-9]*)
      BUDGET_CHARS=8000
      _budget_source="platform default (SLASH_COMMAND_TOOL_CHAR_BUDGET set but not a plain integer, ignored)"
      ;;
    *)
      BUDGET_CHARS="$SLASH_COMMAND_TOOL_CHAR_BUDGET"
      _budget_source="SLASH_COMMAND_TOOL_CHAR_BUDGET env override"
      ;;
  esac
elif [ -n "$_frac" ]; then
  # $_frac passed via argv, never spliced into the -c source string —
  # splicing let a crafted skillListingBudgetFraction value execute
  # arbitrary Python (found 2026-08-06).
  BUDGET_CHARS=$(python3 -c '
import sys
try:
    print(int(200000 * float(sys.argv[1]) * 4))
except Exception:
    print(8000)
' "$_frac" 2>/dev/null || echo 8000)
  _budget_source="skillListingBudgetFraction=${_frac}"
else
  BUDGET_CHARS=8000
  _budget_source="platform default, 1% of a 200K window"
fi
_total=0
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/commands"/*.md "$CLAUDE_DIR/commands"/*/COMMAND.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  desc=$(fm_get "$f" "description" --block)
  _total=$((_total + ${#desc}))
done
_tokens=$((_total / 4))
_budget_tokens=$((BUDGET_CHARS / 4))
info "cumulative skill+command description budget: ${_total} chars (~${_tokens} tokens) of a ${BUDGET_CHARS}-char (~${_budget_tokens}-token) ceiling [${_budget_source}]"
if [ "$_total" -gt "$BUDGET_CHARS" ]; then
  warn "cumulative skill+command descriptions are ${_total} chars (~${_tokens} tokens), over the ${BUDGET_CHARS}-char (~${_budget_tokens}-token) listing-budget ceiling [${_budget_source}] — least-invoked surfaces risk silently dropping from the model's context; trim descriptions or split reference content out of the description field"
fi
# Agent (Agent-tool) descriptions, tracked separately, NOT summed into the
# ceiling above. Confirmed 2026-08-18: neither SLASH_COMMAND_TOOL_CHAR_BUDGET
# nor skillListingBudgetFraction appears on any official Claude Code docs
# page (checked skills.md, sub-agents.md, settings.md, env-vars.md directly)
# — both are community-discovered only, and every source found describes
# them as scoped to the skill/command listing specifically. Nothing confirms
# the separate "Available agent types for the Agent tool" listing shares
# this budget, or has any documented budget at all. Reporting agent
# description chars as their own INFO figure closes the actual gap (this
# total was uncounted by any check) without asserting an unverified shared
# ceiling — merging it into BUDGET_CHARS above would ship a plausible-
# sounding but unconfirmed claim into a gate script.
_agent_total=0
for f in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$f" ] || continue
  desc=$(fm_get "$f" "description" --block)
  _agent_total=$((_agent_total + ${#desc}))
done
_agent_tokens=$((_agent_total / 4))
info "cumulative agent description total: ${_agent_total} chars (~${_agent_tokens} tokens) — tracked separately, not summed into the skill+command ceiling above; no documented budget mechanism confirmed for the Agent-tool listing (2026-08-18)"
unset f desc _total _tokens _budget_tokens BUDGET_CHARS _local_settings _global_settings _frac _v _sf _budget_source _agent_total _agent_tokens
