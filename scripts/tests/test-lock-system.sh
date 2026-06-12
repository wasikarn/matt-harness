#!/bin/bash
# test-lock-system.sh — atomic locking system integration tests (vertical slice TDD).
#
# Usage: bash scripts/tests/test-lock-system.sh
# Exit 0 = all pass; exit 1 = one or more failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAIM="$SCRIPT_DIR/lock-claim.sh"
QUERY="$SCRIPT_DIR/lock-query.sh"
RELEASE="$SCRIPT_DIR/lock-release.sh"
REAP="$SCRIPT_DIR/lock-reap.sh"

PASS=0
FAIL=0
FAILS=()

assert() {
  local label="$1" expect="$2" got="$3" out="${4:-}"
  if [ "$got" = "$expect" ]; then
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %s  expected=%q got=%q\n' "$label" "$expect" "$got"
    FAIL=$((FAIL+1))
    FAILS+=("$label  expected=$expect got=$got  out=$out")
  fi
}

assert_contains() {
  local label="$1" substring="$2" haystack="$3"
  if [[ "$haystack" == *"$substring"* ]]; then
    printf '  PASS  %s\n' "$label"
    PASS=$((PASS+1))
  else
    printf '  FAIL  %s  expected to contain=%q\n' "$label" "$substring"
    FAIL=$((FAIL+1))
    FAILS+=("$label  expected_contains=$substring got=$haystack")
  fi
}

SANDBOX=$(mktemp -d -t lock-test)
mkdir -p "$SANDBOX/.claude"
export HOME="$SANDBOX"
export CLAUDE_JOURNAL_PATH="$SANDBOX/.claude/governance-events.jsonl"

echo "=== Tracer: claim a free resource ==="
OUT=$(bash "$CLAIM" --team="test-team" --type=task --resource="API-1" --owner="backend-engineer" --reason="test" 2>&1)
assert "claim free resource" "claimed" "$OUT" "$OUT"

echo "=== Query locked resource ==="
OUT=$(bash "$QUERY" --team="test-team" --type=task --resource="API-1" 2>&1)
assert_contains "query shows locked" '"status":"locked"' "$OUT"

echo "=== Release by owner ==="
OUT=$(bash "$RELEASE" --team="test-team" --type=task --resource="API-1" --owner="backend-engineer" 2>&1)
assert "release by owner" "released" "$OUT" "$OUT"

echo "=== Query released resource ==="
OUT=$(bash "$QUERY" --team="test-team" --type=task --resource="API-1" 2>&1)
assert_contains "query shows free" '"status":"free"' "$OUT"

echo "=== Claim, deny release by wrong owner, release absent ==="
bash "$CLAIM" --team="test-team" --type=task --resource="API-2" --owner="backend-engineer" --reason="test" >/dev/null 2>&1
OUT=$(bash "$RELEASE" --team="test-team" --type=task --resource="API-2" --owner="wrong-owner" 2>&1)
assert "release denied" "release-denied" "$OUT" "$OUT"

OUT=$(bash "$RELEASE" --team="test-team" --type=task --resource="API-999" --owner="backend-engineer" 2>&1)
assert "release absent" "released-absent" "$OUT" "$OUT"

echo "=== File path encoding ==="
OUT=$(bash "$CLAIM" --team="test-team" --type=file --resource="api/users.py" --owner="backend-engineer" --reason="test" 2>&1)
assert "claim file resource" "claimed" "$OUT" "$OUT"
if [ -d "$SANDBOX/.claude/locks/test-team/file--api--users.py" ]; then
  assert "file path encoded dir exists" "ok" "ok"
else
  assert "file path encoded dir exists" "ok" "fail"
fi

echo "=== Stale lock detection ==="
mkdir -p "$SANDBOX/.claude/locks/test-team/task-STALE-1"
cat > "$SANDBOX/.claude/locks/test-team/task-STALE-1/lock.json" <<'EOF'
{"owner":"old-owner","agent_session":"sess-old","acquired_at":"2026-06-11T10:00:00Z","expires_at":"2026-06-11T11:00:00Z","lock_type":"task","resource_id":"STALE-1","reason":"old"}
EOF
OUT=$(bash "$CLAIM" --team="test-team" --type=task --resource="STALE-1" --owner="new-owner" --reason="steal" 2>&1)
assert "claim stale lock" "claimed-stale" "$OUT" "$OUT"

echo "=== Reap stale locks ==="
mkdir -p "$SANDBOX/.claude/locks/test-team/task-STALE-2"
cat > "$SANDBOX/.claude/locks/test-team/task-STALE-2/lock.json" <<'EOF'
{"owner":"old-owner","agent_session":"sess-old","acquired_at":"2026-06-11T10:00:00Z","expires_at":"2026-06-11T11:00:00Z","lock_type":"task","resource_id":"STALE-2","reason":"old"}
EOF
OUT=$(bash "$REAP" --team="test-team" 2>&1)
assert_contains "reap breaks stale" "task-STALE-2" "$OUT"
if [ ! -d "$SANDBOX/.claude/locks/test-team/task-STALE-2" ]; then
  assert "reap removed stale dir" "ok" "ok"
else
  assert "reap removed stale dir" "ok" "fail"
fi

echo "=== Dry-run reap preserves locks ==="
mkdir -p "$SANDBOX/.claude/locks/test-team/task-STALE-3"
cat > "$SANDBOX/.claude/locks/test-team/task-STALE-3/lock.json" <<'EOF'
{"owner":"old-owner","agent_session":"sess-old","acquired_at":"2026-06-11T10:00:00Z","expires_at":"2026-06-11T11:00:00Z","lock_type":"task","resource_id":"STALE-3","reason":"old"}
EOF
OUT=$(bash "$REAP" --team="test-team" --dry-run 2>&1)
assert_contains "dry-run lists stale" "task-STALE-3" "$OUT"
if [ -d "$SANDBOX/.claude/locks/test-team/task-STALE-3" ]; then
  assert "dry-run preserves lock" "ok" "ok"
else
  assert "dry-run preserves lock" "ok" "fail"
fi

echo "=== Malformed lock (no expires_at) ==="
mkdir -p "$SANDBOX/.claude/locks/test-team/task-BAD-1"
printf '%s\n' '{"owner":"bad-owner","agent_session":"sess-bad","acquired_at":"2026-06-11T10:00:00Z","lock_type":"task","resource_id":"BAD-1","reason":"bad"}' > "$SANDBOX/.claude/locks/test-team/task-BAD-1/lock.json"
OUT=$(bash "$CLAIM" --team="test-team" --type=task --resource="BAD-1" --owner="new-owner" --reason="fix" 2>&1)
assert "claim malformed lock" "claimed-stolen" "$OUT" "$OUT"

echo "=== Concurrent race: exactly one winner ==="
RACE_OUT1=$(mktemp -t race-out1)
RACE_OUT2=$(mktemp -t race-out2)
bash "$CLAIM" --team="test-team" --type=task --resource="RACE-1" --owner="agent-1" --reason="race" >"$RACE_OUT1" 2>&1 &
PID1=$!
bash "$CLAIM" --team="test-team" --type=task --resource="RACE-1" --owner="agent-2" --reason="race" >"$RACE_OUT2" 2>&1 &
PID2=$!
wait $PID1
wait $PID2
R1=$(cat "$RACE_OUT1")
R2=$(cat "$RACE_OUT2")
rm -f "$RACE_OUT1" "$RACE_OUT2"
if { [ "$R1" = "claimed" ] && [[ "$R2" == conflict:* ]]; } || { [ "$R2" = "claimed" ] && [[ "$R1" == conflict:* ]]; }; then
  assert "race exactly one winner" "ok" "ok"
else
  assert "race exactly one winner" "ok" "fail" "out1=$R1 out2=$R2"
fi

echo
echo "=== Syntax checks (all scripts) ==="
for script in "$CLAIM" "$QUERY" "$RELEASE" "$REAP"; do
  if [ -f "$script" ] && bash -n "$script"; then
    assert "bash -n $(basename "$script")" "ok" "ok"
  else
    assert "bash -n $(basename "$script")" "ok" "fail"
  fi
done

# Cleanup
trash "$SANDBOX" 2>/dev/null || rm -rf "$SANDBOX"

echo
printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '\nFailures:\n'
  for f in "${FAILS[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
