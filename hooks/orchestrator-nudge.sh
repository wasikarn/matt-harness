#!/bin/bash
# UserPromptSubmit: orchestrator-nudge — delegation-posture forcing function.
#
# Patches an observed failure mode (user, 2026-05-25): the agent defaults to
# doing decomposable work serially inline instead of routing independent slices
# to sub-agents and reviewing their output — so nobody holds the overview and
# throughput is bottlenecked on one serial worker. Passive memory recall did
# not fix it (memory is background context that competes with ~40 entries and
# is forgotten at the exact moment a task arrives). A deterministic hook fires
# regardless of whether the model "remembers" the posture.
# See [[feedback_narrate_delegate_decision]].
#
# Design constraints (cloned from skill-nudge.sh — precision > recall, a wrong
# nudge erodes trust):
#   - NUDGE not directive. The model's judgment wins (METHODOLOGY Rule 5).
#   - First-match-wins, single emission.
#   - Fires only on UNIQUE decomposability markers (iteration-over-a-set,
#     comprehensive breadth, path-overlap). Deliberately avoids "audit"/
#     "remove"/"delete" words that iron-rule-reminder.sh and skill-nudge.sh
#     already match — no double-banner on the same prompt.
#   - Inline stays correct for genuinely-sequential or unreviewable work; the
#     nudge says so, it does not push delegation for its own sake (Rule 2).
#   - LC_ALL=C so tr/grep are byte-wise: ASCII lowercasing is safe, Thai passes through.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=orchestrator-nudge

set -uo pipefail
export LC_ALL=C

HOOK_ID="orchestrator-nudge"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

# Namespace-mode detection: empty in symlink-farm, 'kbg:' in plugin.
NS="${CLAUDE_PLUGIN_ROOT:+kbg:}"

# Original failed loud on missing jq AND on .prompt parse failure — preserve.
hook_require_prompt
[ -z "$PROMPT" ] && exit 0

# ASCII-lowercase for English matching; no-op for Thai bytes under LC_ALL=C.
LOWERED=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Already orchestrating/delegating explicitly → user directed it, no nudge.
case "$LOWERED" in
  */orchestrate*) exit 0 ;;
esac

# A nudge is a hint the model must either act on or explicitly dismiss in one
# line — that dismissal is what makes the routing decision visible to the user.
emit() {
  printf '%s\n' \
    "[orchestrator-nudge] Heuristic match ($1): this prompt looks decomposable into independent units — a candidate for PARALLEL delegation, not serial inline work." \
    "Consider: decompose → route independent slices to sub-agents / Explore / specialists in ONE batch → review their output → own the integration. Keep inline ONLY if genuinely sequential (step N+1 needs step N) or you can't review the result. Narrate the routing choice in one line. This is a hook hint, not a directive — your judgment wins (METHODOLOGY Rule 5)." \
    "Bypass: CLAUDE_DISABLED_HOOKS=orchestrator-nudge"
  exit 0
}

# Namespace-aware command names for orchestrate and address-review suggestions.
orchestrate_cmd="/${NS}orchestrate"
address_review_cmd="/${NS}address-review"

# Routes: most-specific first; first match is the ONLY emission. English anchored with \b.

# Single source of truth for the two pattern groups, so the lists can't drift apart.
# NOUNS = work units that get iterated over (the parallelisable shape).
NOUNS='files?|modules?|components?|services?|repos?|repositor(y|ies)|packages?|endpoints?|director(y|ies)|folders?|tests?|functions?|scripts?|hooks?|skills?|agents?|commands?|pages?|routes?|tables?|models?'
# SCOPE = broad containers that imply many areas. A breadth marker WITHOUT a scope noun
# is just a thoroughness adjective ("comprehensive analysis of this function" is
# single-artifact, not fan-out), so the comprehensive route requires one.
SCOPE='codebase|code ?base|project|system|ecosystem|pipeline|test ?suite|suite|repos?|repositor(y|ies)|stack|architecture|monorepo|infrastructure|platform|applications?|app'

# Iteration over an independent set — the canonical parallelisable shape.
# A bare "all the X" is too broad ("run all the tests", "are all the files committed"),
# so the set-quantifier (all|every|each) must be governed by EITHER a distributive
# preposition OR a per-item work verb. "run"/"are" are deliberately not work verbs;
# "audit" is omitted to avoid double-firing with iron-rule-reminder.sh.
printf '%s' "$LOWERED" | grep -qE "\b(for each|for every|one (for |per )?each)\b|\b(across|over|through|throughout|for|on|in) (all|every|each) (of )?(the |these |those )?($NOUNS)\b|\b(refactor|update|migrate|rewrite|review|test|document|implement|check|port|convert|generate|create|fix|optimi[sz]e|analy[sz]e|map|trace) (all|every|each) (of )?(the |these |those )?($NOUNS)\b" \
  && emit "iteration-over-set"

# Comprehensive / breadth markers — fire ONLY when a breadth signal governs a multi-area
# SCOPE noun, so single-artifact "review the full diff" / "refactor the entire class"
# stay silent (the breadth word alone is a quality adjective, not a decomposability signal).
printf '%s' "$LOWERED" | grep -qE "\b(comprehensive|end[- ]to[- ]end|exhaustive)\b.{0,40}\b($SCOPE)\b|\b(review|analy[sz]e|investigate|compare|refactor|migrate|map|trace|rewrite) (the )?(entire|whole|full|complete) ($SCOPE)\b" \
  && emit "comprehensive-breadth"

# Path-overlap route — fires when the prompt mentions file paths that resolve
# into ≥2 bounded-contexts per the mirror table in DOMAINS.md. Catches the
# case where a user says "fix the bug in app/api/users.py AND update the
# runbook AND ship it" — three contexts, one prompt, must route not inline.
# SYNC: keep PATH_PATTERNS in lockstep with `claude/DOMAINS.md` ## Path → Context.
PATH_PATTERNS='
claude/commands/feature-dev|Execution
claude/commands/fix-bug|Execution
claude/commands/deep-dive|Execution
claude/skills/diagnose|Execution
claude/skills/migrate|Execution
claude/skills/perf|Execution
claude/skills/research-brief|Execution
claude/skills/tdd|Execution
claude/skills/ship-change|Orchestration
claude/skills/orchestrate|Orchestration
claude/skills/inventory|Orchestration
claude/skills/harness-audit|Orchestration
claude/skills/clarify-first|Orchestration
claude/skills/backend-dev|Implementation
claude/agents/|Implementation
app/|Implementation
src/|Implementation
packages/|Implementation
services/|Implementation
lib/|Implementation
claude/skills/review-pr|Quality
claude/skills/security-auditor|Quality
claude/skills/critical-eval|Quality
claude/skills/probe|Quality
tests/|Quality
claude/skills/adr|Communication
claude/commands/address-review|Communication
claude/commands/status-update|Communication
claude/commands/post-mortem|Communication
docs/|Communication
claude/skills/incident|Emergency
claude/skills/hotfix|Emergency
runbooks/|Emergency
claude/skills/acli|Integration
claude/skills/assert-presence|Integration
claude/skills/decommission|Integration
claude/skills/memory-lint|Integration
claude/skills/semantic-code|Integration
claude/commands/ship-merge|Integration
claude/commands/ship-release|Integration
.scratch/|Integration
'

# contexts_for_paths <lowered-prompt> — echo distinct contexts hit (newline-separated).
# Substring match against the prompt; threshold is checked by the caller (≥2).
contexts_for_paths() {
  printf '%s\n' "$PATH_PATTERNS" | awk -F'|' -v p="$1" '
    NF==2 && index(p, $1) { print $2 }
  ' | sort -u
}

# Path-shaped token: anything containing a slash with at least 2 segments, OR
# a glob with `**`/`*.ext`. We grep to avoid running the awk on prompts that
# contain zero paths (cheap reject).
printf '%s' "$LOWERED" | grep -qE '([a-z0-9_.-]+/){1,}[a-z0-9_.-]+|\*\*?/[^ ]+' || exit 0

# Collect contexts; if ≥2 distinct, fire the path-overlap nudge.
CONTEXTS=$(contexts_for_paths "$LOWERED")
CTX_COUNT=$(printf '%s\n' "$CONTEXTS" | grep -c . 2>/dev/null || echo 0)
if [ "${CTX_COUNT:-0}" -ge 2 ]; then
  CTX_LIST=$(printf '%s\n' "$CONTEXTS" | paste -sd ',' -)
  printf '%s\n' \
    "[orchestrator-nudge] Heuristic match (path-overlap): the prompt's file paths span ≥2 bounded-contexts: $CTX_LIST." \
    "Consider: route each context's slice to its owning agent/skill (Execution → /${NS}fix-bug, Quality → /${NS}review-pr, Communication → ${address_review_cmd}, Integration → /${NS}ship-merge) instead of doing it all inline. If the work IS genuinely cross-context, ${orchestrate_cmd} is the right primitive. This is a hook hint, not a directive — your judgment wins (METHODOLOGY Rule 5)." \
    "Bypass: CLAUDE_DISABLED_HOOKS=orchestrator-nudge"
  exit 0
fi

exit 0
