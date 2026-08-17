#!/usr/bin/env bash
# 56. Cross-pass convergence gate contract — force_human must be present on BOTH
# the writer (write-review-state.sh JSON output) and the reader (ship-merge.md
# Phase 1 step 6 scored gate) (CRIT).
#
# The convergence gate is a two-layer maker/verifier contract: write-review-
# state.sh (the deterministic verifier) computes force_human and writes it into
# the state JSON; ship-merge (the one-way-door reader, disable-model-invocation)
# reads force_human and trips its 40-floor scored gate when true. If either side
# drifts — the writer stops emitting the field, or the reader stops reading it —
# the gate silently degrades to advisory-only: a non-converged review-pr→fix
# loop (the tathep compliance-audit-round-2 >10-round failure this gate closes)
# reaches merge with no computational backstop. Either drift is a safety
# regression, not a doc gap, so CRIT on both.
#
# Bidirectional by design: a one-sided grep (writer-only) would pass while the
# reader silently dropped the read — the same class of fail-open a single
# equality check misses in the fragment integrity guard. Mirrors the verifier-
# contract shape: the field is load-bearing in two files, so both are asserted.
_w="$CLAUDE_DIR/skills/review-pr/scripts/write-review-state.sh"
# ship-merge.md may live flat or directory-form — mirror check 44's own
# path resolution (both are valid per docs/command-authoring-conventions.md).
# Directory-form can push step 6's guard prose into references/*.md (lazy-
# loaded, still part of the shipped reader), so the field-presence grep must
# cover COMMAND.md + its references/ dir, not COMMAND.md alone — a reader
# whose own body has been trimmed below the check's single-file assumption
# is a false CRIT, not a real drift.
_r=""
_r_extra=()
if [ -f "$CLAUDE_DIR/commands/ship-merge.md" ]; then
  _r="$CLAUDE_DIR/commands/ship-merge.md"
elif [ -f "$CLAUDE_DIR/commands/ship-merge/COMMAND.md" ]; then
  _r="$CLAUDE_DIR/commands/ship-merge/COMMAND.md"
  if [ -d "$CLAUDE_DIR/commands/ship-merge/references" ]; then
    for _rf in "$CLAUDE_DIR/commands/ship-merge/references"/*.md; do
      [ -f "$_rf" ] && _r_extra+=("$_rf")
    done
  fi
fi
if [ -f "$_w" ]; then
  /usr/bin/grep -q '"force_human"' "$_w" || \
    crit "write-review-state.sh: JSON output contract lost 'force_human' — the convergence verifier no longer emits the field ship-merge reads; a non-converged review loop reaches merge with no computational backstop"
  /usr/bin/grep -q '"convergence_state"' "$_w" || \
    crit "write-review-state.sh: JSON output contract lost 'convergence_state' — the convergence-state token (converged/regressed/churning/stalled/progressing) is no longer emitted; ship-merge's STOP reason can't name the cause"
  /usr/bin/grep -q '"file_streaks"' "$_w" || \
    crit "write-review-state.sh: JSON output contract lost 'file_streaks' — same-file churn detection reads this as INPUT for the next round's streak count; dropping it from the write silently resets every streak to 0, permanently killing churn detection with no signal anywhere in the gauntlet"
else
  crit "write-review-state.sh: not found at $_w — the convergence verifier is missing entirely"
fi
if [ -f "$_r" ]; then
  /usr/bin/grep -q 'force_human' "$_r" "${_r_extra[@]}" 2>/dev/null || \
    crit "ship-merge.md: Phase 1 step 6 scored gate no longer reads 'force_human' — the one-way-door backstop lost its read of the convergence verdict; a non-converged review can merge regardless of the writer emitting the field"
  # force_human living only in a references/ file is a real read ONLY if
  # COMMAND.md still points there — an orphaned reference (its pointer
  # stub deleted) would pass the grep above while the model never loads it.
  if [ ${#_r_extra[@]} -gt 0 ] && ! /usr/bin/grep -q 'force_human' "$_r" 2>/dev/null; then
    /usr/bin/grep -q 'scored-gate-guards.md' "$_r" || \
      crit "ship-merge/COMMAND.md: force_human lives only in references/scored-gate-guards.md but COMMAND.md's pointer to it is gone — the field is orphaned and never loaded"
  fi
else
  crit "ship-merge command not found at commands/ship-merge.md or commands/ship-merge/COMMAND.md — the merge gate command is missing entirely"
fi