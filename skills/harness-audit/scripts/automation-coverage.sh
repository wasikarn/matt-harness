#!/usr/bin/env bash
# Automation Coverage Score (ACS) — the measurement spine for the score-gated
# automation work. A deterministic classifier that enumerates the loop decision
# points FROM THE CODE and classifies each as G (score-gated auto-act), H
# (human-gated), X (one-way door, correctly human), or J (judgment-bound).
#
# This is a REPORTING script, not a harness-audit check: it prints the score and
# exits 0 always (never CRITs, never gates). Run it before a change (baseline)
# and after; the delta is the demonstrated improvement — measured from the code,
# not asserted from memory. The enumeration is grep-based so a
# missing or invented site shows up; the G/H/X/J label per site is a curated
# table below that changes only when the code changes.
#
# Doctrine (CLAUDE.md §Architecture "unifying crux"): the auto-act decision must
# come from a deterministic gate reading objective state, never the model's
# self-reported confidence. G-branches are exactly the places a deterministic
# condition lets the model proceed (or a PreToolUse gate auto-allows) without a
# human AskUserQuestion. The model's own confidence is never a G-branch.
#
# 2026-08-24 (#82): the review pipeline (review-pr/-tier/-finish skills,
# convergence-merge-gate.sh, review-pr-loop-gate.sh) was retired — it carried
# every G-branch and both merge-door dimensions this script used to detect, so
# the G section below is empty by design until a new score-gated site ships.
# `mattpocock-skills:code-review` is the review surface now.
set -uo pipefail

CLAUDE_DIR="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_DIR:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}}"

# Colors off (this prints to stdout, may be piped).
_g=0; _h=0; _x=0; _j=0

emit() { printf '%s\n' "$1"; }

# --- G-branch detection (grep markers in the actual files) -------------------
# Each block greps a specific file for the deterministic condition that lets the
# model proceed without asking. Presence => G; absence => the site is H/absent.
# Currently empty: the retired review pipeline held all shipped G-branches.
# When a new score-gated site ships, add its grep block here (see git history
# of this file for the review-pipeline examples).

# --- H / X / J inventory (curated — the honest ceiling) ----------------------
# These are the human-gated / one-way-door / judgment-bound sites that stay human
# by doctrine. Counted for the full picture; excluded from the automatable ratio.
emit "Human-gated / one-way-door / judgment-bound (stay human by doctrine):"

# 1. H: disable-model-invocation surfaces (model can't invoke — human-only).
if [ -f "$CLAUDE_DIR/skills/ship-merge/SKILL.md" ]; then
  emit "H  ship-merge/SKILL.md       disable-model-invocation (human-only merge flow)"
  _h=$((_h + 1))
fi
# (ship-release, post-mortem, recursive-improve, address-review,
#  ideate-search, wiki-ingest, tiered-pipeline, score-decision — all H by
#  doctrine; listed compactly, not exhaustively grepped to keep the script readable.)

# 2. X: one-way doors (external/irreversible writes) — correctly human.
emit "X  address-review Phase 5 auto-resolve  external write (resolve reviewer thread)"
emit "X  incident mitigation              irreversible — only escalate auto-selectable"

# 3. J: judgment-bound — diagnosing-bugs Phase 3/5, address-review triage. Not
#    deterministically computable; can never be G without re-treading the L2–L5 ladder.
emit "J  diagnosing-bugs Phase 3/5       judgment (hypothesis ranking, fix shape)"
emit "J  address-review Phase 2 triage    judgment (thread classification)"

# --- Score -------------------------------------------------------------------
emit ""
emit "========================================"
emit "Automation Coverage Score (ACS)"
emit "========================================"
emit "G  (score-gated auto-act):       $_g"
emit ""
emit "ACS = $_g auto-act G-branches"
emit ""
emit "Run this script before a change (baseline) and after; the delta is the"
emit "demonstrated improvement, measured from the code — not imagined."
