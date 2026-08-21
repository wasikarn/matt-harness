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

# Bucket-grouping regression guard (2026-08-19 deep-audit follow-up): the
# assertion above diffs two invocations of the SAME code path (witness calls
# inventory-boundary.sh --repo-only internally), so it can never catch a bug
# inside inventory-boundary.sh's own bucket-grouping logic — a flat-table
# revert or a dropped `unbucketed` fallback would reproduce identically on
# both sides and the diff would stay empty. This block runs the generator
# directly against a small fixture and asserts on its actual output.
FIXTURE=$(mktemp -d)
mkdir -p "$FIXTURE/skills/alpha-skill" "$FIXTURE/skills/beta-skill" "$FIXTURE/skills/untagged-skill"
cat > "$FIXTURE/skills/alpha-skill/SKILL.md" <<'EOF'
---
name: alpha-skill
description: fixture skill tagged bucket alpha
bucket: alpha
---
body
EOF
cat > "$FIXTURE/skills/beta-skill/SKILL.md" <<'EOF'
---
name: beta-skill
description: fixture skill tagged bucket beta
bucket: beta
---
body
EOF
cat > "$FIXTURE/skills/untagged-skill/SKILL.md" <<'EOF'
---
name: untagged-skill
description: fixture skill with no bucket key at all
---
body
EOF

FIXTURE_OUT=$(bash "$BOUNDARY" "$FIXTURE" 2>/dev/null)
trash "$FIXTURE" 2>/dev/null || true

if printf '%s\n' "$FIXTURE_OUT" | grep -qx '### alpha' && printf '%s\n' "$FIXTURE_OUT" | grep -qx '### beta'; then
  ok "distinct bucket subheads (### alpha, ### beta) are grouped, not flattened into one table"
else
  bad "expected '### alpha' and '### beta' subheads — generator may have reverted to a flat table:
$FIXTURE_OUT"
fi

if printf '%s\n' "$FIXTURE_OUT" | grep -qx '### unbucketed'; then
  ok "untagged skill falls into '### unbucketed' (visible, not silently dropped)"
else
  bad "no '### unbucketed' heading — an untagged skill would silently vanish from BOUNDARY.md:
$FIXTURE_OUT"
fi

if printf '%s\n' "$FIXTURE_OUT" | grep -A3 '^### alpha$' | grep -q 'alpha-skill' \
  && printf '%s\n' "$FIXTURE_OUT" | grep -A3 '^### beta$' | grep -q 'beta-skill' \
  && printf '%s\n' "$FIXTURE_OUT" | grep -A3 '^### unbucketed$' | grep -q 'untagged-skill'; then
  ok "each skill's row lands under its own bucket heading, not a neighboring one"
else
  bad "a skill's row landed under the wrong bucket heading (or is missing):
$FIXTURE_OUT"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
