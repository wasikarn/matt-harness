#!/usr/bin/env bash
# 43. Cumulative skill description budget. Check 20 caps each
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
#
# Partial reconciliation, this machine, 2026-08-29: a headless `claude -p
# "/context"` run reported this fleet's real "Skills" listing cost at 16.7k
# TOKENS — ~6.3x this check's own char/4 estimate (2,661 tokens) for the exact
# same 59-skill fleet at the same moment. A same-day Thai-tokenization theory
# for this gap was CHECKED AND REFUTED 2026-08-29 (deep-audit pass): a repo-wide
# grep for Thai script (Unicode 0E00-0E7F) found zero hits anywhere in any of
# the 59 skills/*/SKILL.md or 17 agents/*.md files, frontmatter or body — the
# "34% of descriptions carry Thai" figure this comment previously cited was
# unverified when written and is false. Don't re-cite it. The gap is real and
# still unexplained: candidates are (1) the real listing includes each skill's
# `name` and per-entry formatting overhead, not just the raw `description`
# field this check sums, and (2) the model in that `/context` run had a
# 1,000,000-token window, not the 200,000 this check's default math hardcodes
# — if the platform's "1% of the model's context window" claim is literal, the
# real default budget on a large-context model is far higher than 8000 chars.
# A second theory was checked and ruled out 2026-08-29 too: code.claude.com/docs/en/skills
# documents a real historical bug ("Before v2.1.196, [the /context Skills row]
# counted the full text of every description and could show a value several
# times larger than the configured budget") that would explain an inflated
# reading exactly like this. Ruled out because the measuring machine ran
# Claude Code 2.1.251, well past that fix — the 16.7k figure isn't the old
# bug reappearing. The docs' own suggested diagnostic (`/doctor`, "an estimate
# of the listing's context cost and its biggest contributors") doesn't run
# headlessly (`claude -p "/doctor"` times out with zero output — interactive-
# only) and couldn't be checked from this environment. The gap stays real,
# unexplained, and un-re-explained by either ruled-out theory — don't re-cite
# Thai tokenization OR the v2.1.196 bug as the cause.
# Neither is verified as the actual cause. Net: this check's char/4 arithmetic
# is a rough proxy, not a token-accurate measurement — treat its number as
# directional, and cross-check with a real `/context` run before trusting it
# near the edge of a WARN.
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
for f in "$CLAUDE_DIR/skills"/*/SKILL.md "$CLAUDE_DIR/skills"/*/*/SKILL.md; do
  [ -f "$f" ] || continue
  case "$f" in */skills/_*) continue ;; esac
  desc=$(fm_get "$f" "description" --block)
  _total=$((_total + ${#desc}))
done
_tokens=$((_total / 4))
_budget_tokens=$((BUDGET_CHARS / 4))
info "cumulative skill description budget: ${_total} chars (~${_tokens} tokens) of a ${BUDGET_CHARS}-char (~${_budget_tokens}-token) ceiling [${_budget_source}]"
if [ "$_total" -gt "$BUDGET_CHARS" ]; then
  warn "cumulative skill descriptions are ${_total} chars (~${_tokens} tokens), over the ${BUDGET_CHARS}-char (~${_budget_tokens}-token) listing-budget ceiling [${_budget_source}] — least-invoked surfaces risk silently dropping from the model's context; trim descriptions or split reference content out of the description field"
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
info "cumulative agent description total: ${_agent_total} chars (~${_agent_tokens} tokens) — tracked separately, not summed into the skill ceiling above; no documented budget mechanism confirmed for the Agent-tool listing (2026-08-18)"
unset f desc _total _tokens _budget_tokens BUDGET_CHARS _local_settings _global_settings _frac _v _sf _budget_source _agent_total _agent_tokens
