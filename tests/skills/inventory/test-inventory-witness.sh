#!/usr/bin/env bash
# test-inventory-witness.sh — inventory-witness.sh must call inventory-boundary.sh
# with --repo-only so its output is the canonical, host-independent snapshot
# documented as committable/diffable-in-CI (2026-08-17 bug sweep: the flag was
# missing, so witness silently emitted the host-dependent live-merged view
# instead — confirmed live, diffing --repo-only vs no-flag output is ~380 lines).
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
WITNESS="$HERE/../../../skills/inventory/scripts/inventory-witness.sh"
BOUNDARY="$HERE/../../../skills/inventory/scripts/inventory-boundary.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== inventory-witness self-test ==="

WITNESS_OUT=$(mktemp)
bash "$WITNESS" "$WITNESS_OUT" >/dev/null 2>&1
REPO_ONLY_OUT=$(mktemp)
bash "$BOUNDARY" --repo-only > "$REPO_ONLY_OUT" 2>/dev/null

# Strip the "_Generated: <timestamp>_" line — it legitimately differs by a
# second or two between the two separate invocations below; that is clock
# skew, not the regression this test guards against.
if diff -q <(grep -v '^_Generated: ' "$WITNESS_OUT") <(grep -v '^_Generated: ' "$REPO_ONLY_OUT") >/dev/null; then
  ok "inventory-witness.sh output matches inventory-boundary.sh --repo-only (canonical mode)"
else
  bad "inventory-witness.sh output diverges from --repo-only mode — missing the flag regression:
$(diff "$WITNESS_OUT" "$REPO_ONLY_OUT" | head -10)"
fi
rm -f "$WITNESS_OUT" "$REPO_ONLY_OUT"

echo ""
echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
