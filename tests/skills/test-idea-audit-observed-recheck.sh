#!/usr/bin/env bash
# Issue #390: idea-audit's attacker skipped every claim Agent A tagged
# "Yes — observed directly", so the maker's own label decided what the checker
# never re-checked. Doc check: the attacker brief must require an independent
# re-check of a sample of those claims, and must no longer exempt them outright.
# Run standalone: bash tests/skills/test-idea-audit-observed-recheck.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BRIEF="$ROOT/skills/workflow/idea-audit/references/attacker-brief.md"
fail=0
ok() { echo "  PASS: $1"; }
bad() { echo "  FAIL: $1"; fail=1; }

if /usr/bin/grep -q 'tagged anything other than "Yes — observed directly"' "$BRIEF" \
  && ! /usr/bin/grep -q 'observed directly" claims too' "$BRIEF"; then
  bad "brief exempts observed-directly claims with no re-check"
else
  ok "brief does not exempt observed-directly claims"
fi
if /usr/bin/grep -q 'observed directly" claims too' "$BRIEF" \
  && /usr/bin/grep -q 'Re-check at least 2 of them yourself' "$BRIEF"; then
  ok "brief requires re-checking a sample of observed-directly claims"
else
  bad "brief has no sample re-check of observed-directly claims"
fi

[ "$fail" -eq 0 ] && echo "PASS" || echo "FAIL"
exit "$fail"
