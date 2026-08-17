#!/usr/bin/env bash
# 59. Bounded auto-loop decision script contract — should-continue-loop.sh
# must exist, be invoked by review-pr-finish's SKILL.md, and retain its
# load-bearing fail-closed fields (CRIT).
#
# Retargeted 2026-08-17 from review-pr/SKILL.md to review-pr-finish/SKILL.md:
# the 3-way review-pr -> review-pr-tier -> review-pr-finish split moved
# Phase 7 (where the invocation lives) into the new review-pr-finish skill.
# The script itself (checked below as $_s) did not move.
#
# ADR 0009 (docs/research/adr-0009-bounded-review-fix-auto-loop.md) requires
# the review→fix auto-continue decision to be computational (a shell script),
# never re-derived in SKILL.md prose — that re-derivation was the unenforceable
# sync-seam the ADR's Implementation requirements section exists to close. If
# the script goes missing, or SKILL.md stops calling it, the loop either can't
# run at all or (worse) a future edit quietly reintroduces prose re-derivation
# alongside it with no machine-check of consistency between the two.
#
# The script's own fail-closed checks (last_sha staleness, force_human/
# convergence_state type validation, the finding_files-empty guard) are what
# stop the auto-loop from continuing on a corrupted or ambiguous state — the
# exact class of incident ADR 0009 residual risk #6 documents happening twice
# in production via hand-edited state JSON. Losing any of these silently
# reopens that risk under unattended auto-continue, where nobody is present to
# notice the loop kept going.
#
# check 56 already asserts write-review-state.sh (the writer) still emits
# force_human/convergence_state; this is the reader-side half of that same
# bidirectional pair, for the field READS should-continue-loop.sh does. A
# one-sided grep (writer-only) would pass while the reader silently stopped
# validating the field it reads.
#
# This check asserts the script is INVOKED only — it cannot assert the old
# decision-tree prose is fully gone from SKILL.md (a negative grep would
# false-positive on the legitimate footer-message prose that still references
# round/convergence_state/etc. for rendering, per the ADR's own concession).
_s="$CLAUDE_DIR/skills/review-pr/scripts/should-continue-loop.sh"
_m="$CLAUDE_DIR/skills/review-pr-finish/SKILL.md"

if [ -f "$_s" ]; then
  /usr/bin/grep -q 'last_sha' "$_s" || \
    crit "should-continue-loop.sh: lost its 'last_sha' staleness check — the auto-loop can no longer detect it's reading a stale/wrong-round state file, and may continue on data from a different round"
  /usr/bin/grep -q 'force_human' "$_s" || \
    crit "should-continue-loop.sh: lost its 'force_human' read — the auto-loop can no longer detect the round-ceiling/regressed/churn hard-stop signal write-review-state.sh computes"
  /usr/bin/grep -q 'convergence_state' "$_s" || \
    crit "should-continue-loop.sh: lost its 'convergence_state' read — the auto-loop can no longer distinguish converged/regressed/churning/stalled/progressing, the ADR's literal continue condition"
  /usr/bin/grep -q 'finding_files' "$_s" || \
    crit "should-continue-loop.sh: lost its 'finding_files' empty-set guard — a non-clean round with no tracked findings can auto-continue with regressed/churning detection silently disabled (the hole neither the ADR nor write-review-state.sh names)"
else
  crit "should-continue-loop.sh: not found at $_s — the auto-loop's decision script is missing entirely; ADR 0009's bounded auto-continue cannot run"
fi

if [ -f "$_m" ]; then
  /usr/bin/grep -q 'should-continue-loop.sh' "$_m" || \
    crit "review-pr-finish/SKILL.md: Phase 7 never calls should-continue-loop.sh — the auto-loop's decision script exists but nothing invokes it, so the loop can't run and any surviving decision-tree prose would be the ONLY thing deciding continue/stop again (the sync-seam ADR 0009 exists to close)"
else
  crit "review-pr-finish/SKILL.md: not found at $_m — the review-pr-finish skill file is missing entirely"
fi
