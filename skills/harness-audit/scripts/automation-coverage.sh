#!/usr/bin/env bash
# Automation Coverage Score (ACS) — the measurement spine for the score-gated
# automation work. A deterministic classifier that enumerates the loop decision
# points FROM THE CODE and classifies each as G (score-gated auto-act), H
# (human-gated), X (one-way door, correctly human), or J (judgment-bound).
#
# This is a REPORTING script, not a harness-audit check: it prints the score and
# exits 0 always (never CRITs, never gates). Run it before a change (baseline)
# and after; the delta is the demonstrated improvement — measured from the code,
# not asserted from memory ("ไม่ใช่คิดมโน"). The enumeration is grep-based so a
# missing or invented site shows up; the G/H/X/J label per site is a curated
# table below that changes only when the code changes.
#
# Doctrine (CLAUDE.md §Architecture "unifying crux"): the auto-act decision must
# come from a deterministic gate reading objective state, never the model's
# self-reported confidence. G-branches are exactly the places a deterministic
# condition lets the model proceed (or a PreToolUse gate auto-allows) without a
# human AskUserQuestion. The model's own confidence is never a G-branch.
set -uo pipefail

CLAUDE_DIR="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}}"

# Colors off (this prints to stdout, may be piped).
_g=0; _h=0; _x=0; _j=0
_merge_dims_gated=0; _merge_dims_total=2   # clean, CI

emit() { printf '%s\n' "$1"; }

# --- G-branch detection (grep markers in the actual files) -------------------
# Each block greps a specific file for the deterministic condition that lets the
# model proceed without asking. Presence => G; absence => the site is H/absent.

# 1. convergence-merge-gate: clean==true → allow (merge one-way door, clean dim).
_gate="$CLAUDE_DIR/hooks/gates/convergence-merge-gate.sh"
if [ -f "$_gate" ] && /usr/bin/grep -q 'clean is True' "$_gate"; then
  emit "G  convergence-merge-gate.sh  clean==true → allow raw gh pr merge  (merge-door: clean)"
  _g=$((_g + 1)); _merge_dims_gated=$((_merge_dims_gated + 1))
fi

# 2. convergence-merge-gate: CI dimension (Slice 1). Detected by the gh pr checks
#    call inside the gate's python. Absent before Slice 1.
if [ -f "$_gate" ] && /usr/bin/grep -q 'gh pr checks' "$_gate"; then
  emit "G  convergence-merge-gate.sh  CI all-green → allow  (merge-door: CI)"
  _g=$((_g + 1)); _merge_dims_gated=$((_merge_dims_gated + 1))
fi

# review-pr's own markers may live in SKILL.md or the 2 sibling skills its
# 3-way chain hands off to (review-pr-tier, review-pr-finish) — grep all 3 so
# a marker that moved during the split doesn't silently drop from this report
# with no signal anywhere else (this script never CRITs).
_rp="$CLAUDE_DIR/skills/review-pr/SKILL.md"
_rp_extra=()
for _rpf in "$CLAUDE_DIR/skills/review-pr-tier/SKILL.md" "$CLAUDE_DIR/skills/review-pr-finish/SKILL.md"; do
  [ -f "$_rpf" ] && _rp_extra+=("$_rpf")
done

# 3. review-pr Phase 6 own-branch: all-zero → "Clean pass, proceeding" (skip ask).
if [ -f "$_rp" ] && /usr/bin/grep -q 'Clean pass, proceeding' "$_rp" "${_rp_extra[@]}" 2>/dev/null; then
  emit "G  review-pr-finish/SKILL.md  Phase 6 all-zero tiers → proceed (skip ask)"
  _g=$((_g + 1))
fi

# 4. review-pr Phase 6 own-branch: Minor-only → auto-proceed (Slice 3). Detected
#    by the widened skip marker. Absent before Slice 3.
if [ -f "$_rp" ] && /usr/bin/grep -q 'ACS:minor-only-auto-proceed' "$_rp" "${_rp_extra[@]}" 2>/dev/null; then
  emit "G  review-pr-finish/SKILL.md  Phase 6 Minor-only (0 Critical, 0 Important) → auto-proceed"
  _g=$((_g + 1))
fi

# 5. review-pr Phase 1: clear-analysis → auto-Parallel (Slice 2). Detected by the
#    auto-decide marker. Absent before Slice 2.
if [ -f "$_rp" ] && /usr/bin/grep -q 'ACS:auto-parallel' "$_rp" "${_rp_extra[@]}" 2>/dev/null; then
  emit "G  review-pr/SKILL.md  Phase 1 unambiguous analysis → auto-Parallel (skip ask)"
  _g=$((_g + 1))
fi

# --- Advisory G (verifier demotion — already shipped, NOT an auto-act/escalate
#     decision; counted separately so the ACS auto-act count matches the plan) --
_demote=0
if [ -f "$_rp" ] && /usr/bin/grep -q 'confidence.*0\.8\|0\.8.*confidence' "$_rp" "${_rp_extra[@]}" 2>/dev/null; then
  _demote=1
  emit "G* review-pr-tier/SKILL.md  Phase 5 step 3.5 verifier demotion (confidence≥0.8 + isReal=false) — advisory, already shipped, not counted in ACS auto-act"
fi

# --- H / X / J inventory (curated — the honest ceiling) ----------------------
# These are the human-gated / one-way-door / judgment-bound sites that stay human
# by doctrine. Counted for the full picture; excluded from the automatable ratio.
emit ""
emit "Human-gated / one-way-door / judgment-bound (stay human by doctrine):"

# H: disable-model-invocation surfaces (model can't invoke — human-only).
_dm_count=0
if [ -f "$CLAUDE_DIR/commands/ship-merge.md" ] || [ -f "$CLAUDE_DIR/commands/ship-merge/COMMAND.md" ]; then _dm_count=$((_dm_count + 1)); emit "H  ship-merge.md             disable-model-invocation (human-only scored gate)"; fi
# (ship-release, ship, post-mortem, iterate-skill, recursive-improve, address-review,
#  ask-kbg, ideate-search, wiki-ingest, compliance-audit, score-decision — all H by
#  doctrine; listed compactly, not exhaustively grepped to keep the script readable.)

# X: one-way doors (external/irreversible writes) — review-pr submit, address-review
#    auto-resolve, incident mitigation. Correctly human.
emit "X  review-pr Phase 6B/7 submit      external write (post review to a PR)"
emit "X  address-review Phase 5 auto-resolve  external write (resolve reviewer thread)"
emit "X  incident mitigation              irreversible — only escalate auto-selectable"

# J: judgment-bound — fix-bug Phase 3/4, address-review triage. Not deterministically
#    computable; can never be G without re-treading the L2–L5 ladder.
emit "J  fix-bug Phase 3/4                judgment (hypothesis, fix-shape)"
emit "J  address-review Phase 2 triage    judgment (thread classification)"

# --- Score -------------------------------------------------------------------
emit ""
emit "========================================"
emit "Automation Coverage Score (ACS)"
emit "========================================"
emit "G  (score-gated auto-act):       $_g"
emit "G* (advisory G, already shipped): $_demote  [not counted in ACS]"
emit "Merge-door dimensions gated:     $_merge_dims_gated / $_merge_dims_total  (clean, CI)"
emit ""
emit "ACS = $_g auto-act G-branches  +  merge-door $_merge_dims_gated/$_merge_dims_total"
emit ""
emit "Run this script before a change (baseline) and after; the delta is the"
emit "demonstrated improvement, measured from the code — not imagined."