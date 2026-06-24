#!/bin/bash
# UserPromptSubmit: skill-nudge — deterministic command-route miss-detector.
#
# Commands are disable-model-invocation — they NEVER auto-fire, so a heuristic
# nudge is the ONLY bridge for the model to surface a relevant /command when a
# high-precision phrase matches. The hint is NON-BINDING: the model suggests the
# command or states in one line why it doesn't fit (that dismissal makes a miss
# VISIBLE). See [[project_skill_autotrigger_investigation_2026_05_25]].
#
# Skill routes REMOVED 2026-05-31 (decay sweep — [[project_harness_decay_sweep_2026_05_31]]):
# skills CAN auto-fire, and measure-autotrigger showed skill-route nudges ~0%
# acted (model self-triggers or correctly dismisses) vs command-routes 14-29%.
# Nudging toward something the model already invokes natively is pure noise.
# Hook name/env var kept as skill-nudge — rename is a 3-step install change.
#
# Design constraints (precision > recall — a wrong nudge erodes trust):
#   - NUDGE not directive. The model's judgment wins (METHODOLOGY Rule 5).
#   - First-match-wins, single emission — never names two commands.
#   - Only commands with no skill equivalent. Heavyweight ones (incident/hotfix)
#     are deliberately EXCLUDED: a false fire is costly, and their own triggers
#     (P0, "production is down") are specific enough manual stays correct.
#   - LC_ALL=C so `tr`/`grep` are byte-wise: ASCII lowercasing is safe.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=skill-nudge

set -uo pipefail
export LC_ALL=C

HOOK_ID="skill-nudge"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0

# Namespace-mode detection: empty in symlink-farm, 'kbg:' in plugin.
NS="${CLAUDE_PLUGIN_ROOT:+kbg:}"

# Original failed loud on missing jq AND on .prompt parse failure — preserve.
hook_require_prompt
[ -z "$PROMPT" ] && exit 0

# ASCII-lowercase for English matching; no-op for Thai bytes under LC_ALL=C.
LOWERED=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Already naming a command via slash → user is invoking manually, no nudge.
case "$LOWERED" in
  */fix-bug*|*/ship-task*|*/review-pr*|*/post-mortem*) exit 0 ;;
esac

# Dynamic-workflow trigger words (trq212, 2026-06-03) → never nudge. These are
# auto-spawn surfaces for the CC Workflow tool, NOT commands this hook should
# surface. A nudge here would re-route the user to a /command when the workflow
# is what they asked for. Per
# [[feedback_dispatch_skill_capability_gate]]: an auto-spawn trigger that lands
# in a UserPromptSubmit nudge path is the same escalation surface as a
# model-invokable skill with Edit/Write/Bash — exit early to keep the hook
# out of the loop. See ledger row "trq212 dynamic-workflows" 2026-06-04
# (collision #1).
case "$LOWERED" in
  *ultracode*|*workflow*) exit 0 ;;
esac

# A nudge is a hint the model must either act on or explicitly dismiss in one
# line — that dismissal is what makes a miss visible to the user.
command_emit() {
  printf '%s\n' \
    "[skill-nudge] Heuristic match: this prompt looks like a candidate for the '/${NS}$1' command — $2" \
    "If it fits, suggest the user run it via /${NS}$1. If it does NOT fit, say so in one line and proceed with your own approach. This is a hook hint, not a directive — your judgment wins (METHODOLOGY Rule 5)." \
    "Bypass: CLAUDE_DISABLED_HOOKS=skill-nudge"
  exit 0
}

# Routes: most-specific / least-ambiguous first; first match is the ONLY emission.
# All are commands (disable-model-invocation) — they NEVER auto-fire, so a nudge
# is the only bridge. Only commands with no skill equivalent are included.
# English anchored with \b.

# /fix-bug — explicit fix intent (diagnose skill handles ambiguity; this is
# for when the user already wants to fix, not just understand)
printf '%s' "$LOWERED" | grep -qE '\bfix (this |a |the )?bug\b|\bbug[- ]?fix\b|\bdebug and fix\b' \
  && command_emit "fix-bug" "full bug-fix workflow: reproduce → localise → hypothesise → TDD-implement → verify → review."

# /ship-task — build/implement something non-trivial (the general feature/workflow surface)
printf '%s' "$LOWERED" | grep -qE '\b(build|implement|develop|create) (a |this |the )?(new )?feature\b|\bfeature (request|spec|development)\b|\bgreenfield\b' \
  && command_emit "ship-task" "9-step senior-engineer loop: explore → clarify → accept → implement → auto-test → review → fix-loop → ship."

# /review-pr — multi-agent PR review (code-review skill is single-agent diff
# review; this is the comprehensive multi-agent workflow)
printf '%s' "$LOWERED" | grep -qE '\breview (my |this |the )?(pr|pull request|changes)\b|\bpr review\b|\bpull request review\b' \
  && command_emit "review-pr" "multi-agent PR review covering code quality, tests, comments, errors, security, and simplification."

# /address-review — respond to existing PR review comments (no skill equivalent)
printf '%s' "$LOWERED" | grep -qE '\b(address|respond to|apply|fix) (the |my |this )?(pr |pull request )?review (comments?|feedback|threads?)\b|\bresolve review\b|\breview comments? (came back|returned|on my pr)\b' \
  && command_emit "address-review" "triage and respond to open PR review threads: fetch via gh, classify, implement fixes, reply per-thread citing sha, re-request review."

# /post-mortem — document a resolved bug/incident (no skill equivalent)
printf '%s' "$LOWERED" | grep -qE '\b(write|draft|create|need|do) .{0,20}post[- ]?mortem\b|\bpost[- ]?mortem .{0,20}(for|of|after|about|analysis|draft|writeup|report)\b|\bincident report\b' \
  && command_emit "post-mortem" "canonical post-mortem for a resolved bug: reproducible trigger, known mechanism, identified patch, passing validation."

# /ship-task — 9-step senior-engineer loop from explore → clarify → implement → review → ship.
# Triggers when user wants to start a task from scratch with full pipeline discipline.
printf '%s' "$LOWERED" | grep -qE '\b(ready to ship|let.s ship|ship this|ship (the |a |this )?(feature|change|task|fix)|start (a |the )?(new )?task from scratch|full (pipeline|workflow|loop) for)\b' \
  && command_emit "ship-task" "9-step loop: explore → clarify → accept → implement → auto-test → review → fix-loop → ship."

# Explore-first nudge: task-shaped prompts without a /command already named.
# When user describes modifying/extending something without routing to a workflow command,
# nudge toward /ship-task or /fix-bug (both have built-in explore phases).
printf '%s' "$LOWERED" | grep -qE '\b(i need to|we need to|i want to|we want to|can you|please) (implement|change|modify|extend|add|refactor|update) \b' \
  && ! printf '%s' "$LOWERED" | grep -qE '\b/(ship-task|fix-bug|ship-change|review-pr)\b' \
  && command_emit "ship-task" "starts with explore (read-only recon via code-explorer) before any edits — builds in the senior-engineer explore-first discipline."

exit 0
