#!/usr/bin/env bash
# run-test.sh — prove audit #41 (doctrine gate seam) FIRES on injected drift.
# The block-bash stub drops DBGATE; the doctrine-edit stub keeps all 8. The
# audit MUST emit the seam-drift WARN and name the missing file (DBGATE) in the
# diff. This is the regression guard the seam never had: revert the #41 check
# and this test goes red.
set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
AUDIT="$REPO_ROOT/skills/harness-audit/scripts/audit.sh"
FIXTURE="$REPO_ROOT/tests/harness-audit/fixtures/doctrine-seam-repo"

if [ ! -f "$AUDIT" ]; then
  echo "FAIL: audit.sh not found at $AUDIT" >&2
  exit 1
fi

out="$(bash "$AUDIT" "$FIXTURE" 2>&1)"

# Assert on the stable message text (findings are numbered in emission order, so
# the positional finding-ID is not stable — grep the message, like plugin-repo).
if ! printf '%s\n' "$out" | grep -q "doctrine gate seam DRIFT"; then
  echo "FAIL: audit #41 did NOT flag the injected doctrine-gate drift" >&2
  printf '%s\n' "$out" | tail -8 >&2
  exit 1
fi

# The diff must name the drifted file so the operator knows WHAT drifted.
if ! printf '%s\n' "$out" | grep "doctrine gate seam DRIFT" | grep -q "DBGATE"; then
  echo "FAIL: #41 fired but did not name the drifted file (DBGATE) in the diff" >&2
  printf '%s\n' "$out" | grep "doctrine gate seam" >&2
  exit 1
fi

echo "PASS: doctrine-seam-repo — audit #41 flags injected drift (DBGATE missing from block-bash gate)"
exit 0
