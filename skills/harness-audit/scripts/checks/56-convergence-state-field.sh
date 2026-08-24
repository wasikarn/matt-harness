#!/usr/bin/env bash
# 56. Convergence-state write contract — write-review-state.sh (the
# deterministic verifier) must keep emitting force_human, convergence_state,
# and file_streaks in its state JSON (CRIT).
#
# Writer-only since the matt-harness migration (spec #75, ticket #76): the
# old reader half — ship-merge's Phase 1 scored gate reading force_human at
# the merge door — was removed along with the scored gate itself (ship-merge
# now gates on deterministic sensitive-path classification plus an explicit
# user go/no-go), so the reader-side grep over commands/ship-merge/ was
# dropped here in the same commit or it would CRIT on the new shape. The
# fields are still load-bearing on the writer side: review-pr's own loop
# (should-continue-loop.sh) and review-pr-finish's Phase 7 footer read
# force_human/convergence_state, and file_streaks is INPUT for the next
# round's streak count — dropping it from the write silently resets every
# streak to 0, permanently killing churn detection with no signal anywhere
# in the gauntlet. The closeout ticket (#87) re-derives what remains of this
# contract once the convergence machinery lands its final shape.
_w="$CLAUDE_DIR/skills/review-pr/scripts/write-review-state.sh"
if [ -f "$_w" ]; then
  /usr/bin/grep -q '"force_human"' "$_w" || \
    crit "write-review-state.sh: JSON output contract lost 'force_human' — the convergence verifier no longer emits the field the review-pr loop reads; a non-converged review loop keeps auto-continuing with no computational backstop"
  /usr/bin/grep -q '"convergence_state"' "$_w" || \
    crit "write-review-state.sh: JSON output contract lost 'convergence_state' — the convergence-state token (converged/regressed/churning/stalled/progressing) is no longer emitted; the loop's STOP reason can't name the cause"
  /usr/bin/grep -q '"file_streaks"' "$_w" || \
    crit "write-review-state.sh: JSON output contract lost 'file_streaks' — same-file churn detection reads this as INPUT for the next round's streak count; dropping it from the write silently resets every streak to 0, permanently killing churn detection with no signal anywhere in the gauntlet"
else
  crit "write-review-state.sh: not found at $_w — the convergence verifier is missing entirely"
fi
