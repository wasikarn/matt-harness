#!/usr/bin/env bash
# 76. Measurement coverage status freshness (harness gap-audit M14, 2026-09-20).
# The lazy version of the retired `harness-coverage` mechanism:
# docs/reference/measurement-coverage-status.md tracks a handful of
# measurement-dependent gates (G1/H8, H9, the [role:] tag) that have already
# been found, fixed, and lost again once (the telemetry hook itself was
# deleted, then rediscovered missing by this same audit pass 15 days later).
# This check is deliberately shallow -- WARN only, doc drift not a security
# invariant -- it just confirms the file exists and still names the three
# rows this pass populated it with; it does not re-verify each row's
# "current status" claim against the real mechanism (that's what the
# gauntlet's own tests for cost-tracker.sh / skill-usage-telemetry.sh do).
_COVERAGE_DOC="$CLAUDE_DIR/docs/reference/measurement-coverage-status.md"
if [ ! -f "$_COVERAGE_DOC" ]; then
  warn "docs/reference/measurement-coverage-status.md missing -- the lazy harness-coverage tracker (G1/H8, H9, [role:] tag) has no record; see harness gap-audit M14"
else
  for _row in "G1/H8" "H9" '\[role:\]'; do
    /usr/bin/grep -qE "$_row" "$_COVERAGE_DOC" 2>/dev/null || \
      warn "docs/reference/measurement-coverage-status.md is missing its '$_row' row -- a tracked measurement decision was dropped from the coverage list"
  done
  unset _row
fi
unset _COVERAGE_DOC
