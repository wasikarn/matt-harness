#!/usr/bin/env bash
# injection-budget-check unit tests. Uses a fixture $CLAUDE_PLUGIN_ROOT with
# fake hooks/session/{doctrine-bootstrap,memory-health-nudge}.sh scripts that
# emit exactly-sized output, so cap-crossing behavior is tested
# deterministically without depending on the real METHODOLOGY.md's size or
# spawning the real memory-lint.py.
# Run standalone: bash tests/hooks/test-injection-budget-check.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/injection-budget-check.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kbg-injection-budget-test.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

pass=0
fail=0

FAKE_ROOT="$TMP/plugin-root"
mkdir -p "$FAKE_ROOT/hooks/session"

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | command grep -qF "$needle"; then
    echo "  ✅ CONTAINS \"$needle\": $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ EXPECTED \"$needle\" in output but it was absent: $desc" >&2
    echo "     --- output ---" >&2
    printf '%s\n' "$haystack" | sed 's/^/     /' >&2
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | command grep -qF "$needle"; then
    echo "  ❌ UNEXPECTED \"$needle\" in output: $desc" >&2
    echo "     --- output ---" >&2
    printf '%s\n' "$haystack" | sed 's/^/     /' >&2
    fail=$((fail + 1))
  else
    echo "  ✅ ABSENT \"$needle\": $desc"
    pass=$((pass + 1))
  fi
}

write_fixture_hooks() {
  local doctrine_bytes="$1" nudge_bytes="$2"
  cat > "$FAKE_ROOT/hooks/session/doctrine-bootstrap.sh" <<EOF
#!/usr/bin/env bash
python3 -c "print('a' * $doctrine_bytes, end='')"
EOF
  cat > "$FAKE_ROOT/hooks/session/memory-health-nudge.sh" <<EOF
#!/usr/bin/env bash
python3 -c "print('b' * $nudge_bytes, end='')"
EOF
}

run_hook() {
  ( CLAUDE_PLUGIN_ROOT="$FAKE_ROOT" bash "$HOOK" )
}

echo "=== injection-budget-check hook (SessionStart) ==="
echo ""

echo "--- under cap: stays silent ---"
write_fixture_hooks 1000 500
OUT=$(run_hook)
assert_not_contains "well under cap stays silent" "OVER-BUDGET" "$OUT"

echo ""
echo "--- over cap: warns with the real byte total ---"
write_fixture_hooks 20000 5000
OUT=$(run_hook)
assert_contains "over cap fires OVER-BUDGET" "OVER-BUDGET" "$OUT"
assert_contains "warning names the actual combined byte total" "25000B" "$OUT"
assert_contains "warning breaks out doctrine-bootstrap's own byte count" "20000B" "$OUT"
assert_contains "warning breaks out memory-health-nudge's own byte count" "5000B" "$OUT"

echo ""
echo "--- exactly at cap: stays silent (only strictly over warns) ---"
write_fixture_hooks 24576 0
OUT=$(run_hook)
assert_not_contains "exactly-at-cap stays silent" "OVER-BUDGET" "$OUT"

echo ""
echo "--- one byte over cap: warns ---"
write_fixture_hooks 24577 0
OUT=$(run_hook)
assert_contains "one byte over cap still warns" "OVER-BUDGET" "$OUT"

echo ""
echo "--- CLAUDE_PLUGIN_ROOT unset: exits cleanly, no crash ---"
OUT=$(env -u CLAUDE_PLUGIN_ROOT bash "$HOOK" 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  echo "  ✅ PASS: unset CLAUDE_PLUGIN_ROOT exits 0 silently"
  pass=$((pass + 1))
else
  echo "  ❌ FAIL: unset CLAUDE_PLUGIN_ROOT exited $RC with output: $OUT" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
