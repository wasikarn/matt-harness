#!/bin/bash
# test-cleanup-bak-ttl — smoke tests for the SessionStart TTL gate.
#
# Verifies the four contract properties documented in cleanup-bak-ttl.sh:
#   1. Stale .bak files are reported (positive case)
#   2. Allowlisted test fixtures (hooks.json.test.bak etc.) are skipped
#   3. Profile bypass (CLAUDE_BAK_TTL_PROFILE=off) and per-hook disable
#      (CLAUDE_DISABLED_HOOKS=cleanup-bak-ttl) both silence the hook
#   4. TTL=0 disables the check without firing
#
# Method: direct invocation with HOME override pointing at a tmp sandbox
# (trash, not rm -rf, for cleanup — see feedback_use_trash_not_rm).
# No real ~/.claude/ files are touched.
#
# Usage: bash hooks/tests/test-cleanup-bak-ttl.sh
# Exit 0 = all pass; exit 1 = one or more failed.

HOOK="$(cd "$(dirname "$0")/.." && pwd)/maintenance/cleanup-bak-ttl.sh"
[ -x "$HOOK" ] || { echo "FATAL: $HOOK not executable" >&2; exit 1; }

PASS=0
FAIL=0
FAILS=()

# Build a fresh sandbox with 3 stale .bak + 1 allowlisted fixture.
# mktemp -d gives us a private HOME; we override HOME so the hook scans
# only the sandbox, never the real ~/.claude/.
# Portability: use an explicit `…/prefix.XXXXXX` template, NOT `mktemp -d -t prefix`.
# BSD/macOS accepts `-t prefix` (no X's), but GNU/Linux rejects it ("too few X's")
# → empty output → sandbox at "/.claude" → mkdir denied → count=0 → CI-only fail.
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/bak-ttl-test.XXXXXX")/.claude
mkdir -p "$SANDBOX/plugins/cache/kobig"
touch -t 202501010000 "$SANDBOX/test1.bak"  # ~526 days
touch -t 202504010000 "$SANDBOX/test2.bak"  # ~436 days
touch -t 202505010000 "$SANDBOX/plugins/cache/kobig/test3.bak"  # ~406 days
touch -t 202401010000 "$SANDBOX/plugins/cache/kobig/hooks.json.test.bak"  # fixture — should be skipped
ROOT="$(dirname "$SANDBOX")"

assert() {
  local label="$1" expect="$2" got="$3" out="$4"
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %s  expected=%q got=%q\n' "$label" "$expect" "$got"
    FAIL=$((FAIL+1))
    FAILS+=("$label  expected=$expect got=$got  out=$out")
  fi
}

run() {
  HOME="$ROOT" "$@" bash "$HOOK" </dev/null
}

echo "=== 1. stale .bak reported (count=3, fixture skipped) ==="
OUT=$(HOME="$ROOT" CLAUDE_BAK_TTL_DAYS=1 bash "$HOOK" </dev/null)
COUNT=$(printf '%s' "$OUT" | grep -oE 'count="[0-9]+"' | head -1 | grep -oE '[0-9]+')
assert "count is 3 (fixture skipped)" "3" "$COUNT" "$OUT"
if printf '%s' "$OUT" | grep -q "hooks.json.test.bak"; then
  assert "fixture NOT in output" "no" "yes" "$OUT"
else
  assert "fixture NOT in output" "no" "no" "$OUT"
fi
if printf '%s' "$OUT" | grep -q "test1.bak"; then
  assert "test1.bak IS in output" "yes" "yes" "$OUT"
else
  assert "test1.bak IS in output" "yes" "no" "$OUT"
fi

echo
echo "=== 2. silent when no .bak present ==="
EMPTY=$(mktemp -d "${TMPDIR:-/tmp}/bak-ttl-test.XXXXXX")/.claude
mkdir -p "$EMPTY"
OUT=$(HOME="$(dirname "$EMPTY")" CLAUDE_BAK_TTL_DAYS=1 bash "$HOOK" </dev/null)
assert "empty sandbox is silent" "" "$OUT" "$OUT"

echo
echo "=== 3. bypass mechanisms ==="
OUT=$(HOME="$ROOT" CLAUDE_BAK_TTL_DAYS=1 CLAUDE_BAK_TTL_PROFILE=off bash "$HOOK" </dev/null)
assert "PROFILE=off silences hook" "" "$OUT" "$OUT"

OUT=$(HOME="$ROOT" CLAUDE_BAK_TTL_DAYS=1 CLAUDE_DISABLED_HOOKS=cleanup-bak-ttl bash "$HOOK" </dev/null)
assert "CLAUDE_DISABLED_HOOKS silences hook" "" "$OUT" "$OUT"

OUT=$(HOME="$ROOT" CLAUDE_BAK_TTL_DAYS=0 bash "$HOOK" </dev/null)
assert "TTL=0 silences hook" "" "$OUT" "$OUT"

echo
echo "=== 4. exit code is always 0 (never block SessionStart) ==="
HOME="$ROOT" CLAUDE_BAK_TTL_DAYS=1 bash "$HOOK" </dev/null; RC=$?
assert "exit code on stale path" "0" "$RC" ""
HOME="$ROOT" CLAUDE_BAK_TTL_DAYS=1 CLAUDE_BAK_TTL_PROFILE=off bash "$HOOK" </dev/null; RC=$?
assert "exit code on bypass path" "0" "$RC" ""

echo
echo "=== 5. syntax check ==="
if bash -n "$HOOK"; then
  assert "bash -n" "ok" "ok" ""
else
  assert "bash -n" "ok" "fail" ""
fi

# Cleanup sandbox via trash (allow-listed; rm -rf is deny-blocked).
trash "$ROOT" "$(dirname "$EMPTY")" 2>/dev/null

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n'
  for f in "${FAILS[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
