#!/usr/bin/env bash
# l4-quality-gate.sh — the L4 model-as-gate (design §7, ADR 0004 #3).
#
# Invoked AFTER run-gauntlet.sh (which runs first, unconditionally — a model verdict
# never substitutes for a computational check). An LLM "good enough" verdict on ONE
# allowlisted prose skill can VETO a green (force an extra rollback) but NEVER bless
# a red. Fail-CLOSED: a missing / erroring / unparseable verdict resolves to rollback.
# The judge is invoked READ-ONLY (no Write/Edit). Trial scope = l4-quality-trial.txt.
#
# Veto-only is the safe direction: the model can force MORE caution (an extra
# rollback), never less (never convert red→green). The computational gauntlet + the
# R3 per-cycle cage re-assert still run every cycle — a holed cage forces STOP even
# when the model verdict is green (the §10 non-circularity proof).
#
# Args: <gauntlet-result: green|red> [<skill-name>]
# Stdout: green | rollback | red
# Exit:  0 (green) | 20 (rollback) | 21 (red) — the loop treats non-green as revert.
# KBG_QUALITY_JUDGE_CMD overrides the judge command (tests inject a fake); the default
# invokes a read-only claude CLI on the allowlisted skill.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRIAL="$SCRIPT_DIR/l4-quality-trial.txt"
RESULT="${1:-}"
SKILL="${2:-}"

# Source _lib.sh ONLY for journal_append (the verdict is part of the Gate-2 audit
# trail, design §10 — no hook_init; this is not a PreToolUse hook). _lib.sh only
# DEFINES functions at source time (no side effects).
_JLIB="$(cd "$SCRIPT_DIR/../.." && pwd)/hooks/_lib.sh"
SID="${CLAUDE_SESSION_ID:-no-sid}"
[ -f "$_JLIB" ] && command -v jq >/dev/null 2>&1 && source "$_JLIB" 2>/dev/null || true
_journal() {  # <verdict> <detail>
  command -v journal_append >/dev/null 2>&1 || return 0
  journal_append "l4-quality-gate" "quality_gate" \
    "{\"verdict\":\"$1\",\"gauntlet\":\"$RESULT\",\"skill\":\"$SKILL\",\"detail\":\"$2\"}" \
    >/dev/null 2>&1 || true
}

# 1. Never bless a red — short-circuit BEFORE any model invocation.
if [ "$RESULT" = "red" ]; then
  printf 'red\n'
  _journal "red" "gauntlet red — model never invoked (never bless red)"
  exit 21
fi
# Unknown gauntlet result → fail-closed (no model blessing an unknown state).
if [ "$RESULT" != "green" ]; then
  printf 'rollback\n'
  _journal "rollback" "unknown gauntlet result '$RESULT' — fail-closed"
  exit 20
fi

# 2. Trial scope: the skill must be in the allowlist. Not allowlisted → fail-closed
#    (the model does not bless anything outside the trial scope).
if [ -z "$SKILL" ] || [ ! -f "$TRIAL" ] || ! grep -qxF "$SKILL" "$TRIAL" 2>/dev/null; then
  printf 'rollback\n'
  _journal "rollback" "skill '$SKILL' not in the trial allowlist — fail-closed"
  exit 20
fi

# 3. Invoke the read-only judge. Default: claude -p --allowedTools Read (NO Write/Edit
#    — the #49 audit asserts the default grants no mutation tool). KBG_QUALITY_JUDGE_CMD
#    overrides (tests inject a deterministic fake).
JUDGE_CMD="${KBG_QUALITY_JUDGE_CMD:-claude -p --allowedTools Read --max-turns 1}"
_verdict=$(printf 'Is the %s skill prose clear, correct, and good enough to keep as-is? Reply with exactly NOT_GOOD or GOOD.\n' "$SKILL" \
           | eval "$JUDGE_CMD" 2>/dev/null) || _verdict=""

# 4. Parse — order matters: NOT_GOOD before GOOD (NOT_GOOD contains GOOD). Anything
#    missing / unparseable / empty → rollback (fail-closed). The model can ONLY
#    confirm a green (GOOD) or veto it (NOT_GOOD) — it cannot produce a red→green.
case "$_verdict" in
  *NOT_GOOD*)
    printf 'rollback\n'
    _journal "rollback" "model vetoed the green (NOT_GOOD) — extra rollback"
    exit 20 ;;
  *GOOD*)
    printf 'green\n'
    _journal "green" "model confirmed the green (GOOD)"
    exit 0 ;;
  *)
    printf 'rollback\n'
    _journal "rollback" "model verdict missing/unparseable — fail-closed"
    exit 20 ;;
esac