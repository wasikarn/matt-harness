#!/bin/bash
# Behavioral tests for review-pr-marker.sh (PostToolUse:Bash + state).
# Scaffold mirrors test-nudge.sh: stdin JSON → bash $HOOK → assert behaviour.
#
# The hook has TWO responsibilities:
#   1. CONSUMER: PostToolUse:Bash — when command matches `git commit` AND
#      $STATE_DIR/review-pr-active exists AND mtime < 30 min, emit a nudge
#      reminding the model that PR #N is still open. Else: silent.
#   2. LIFECYCLE: this test fixture also exercises the marker helpers
#      (write_marker, clear_marker, is_active) so the red phase covers both.
#
# Design constraints (per Phase 2 plan + auto-review-nudge precedent):
#   - Strictly additive to auto-review-nudge / skill-nudge (nudge text only,
#     not a second banner on a different surface).
#   - 30-minute TTL on marker — review session window. Stale flag = ignored.
#   - Never blocks the commit (PostToolUse, exit 0 always).
#   - Marker file = $STATE_DIR/review-pr-active (sibling of evidence-trail.log,
#     config-change.log, etc.).
#
# State dir for tests: $TMPDIR/review-pr-marker-test/state (cleaned on exit).

set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/post-tool/review-pr-marker.sh"
TEST_STATE="/tmp/review-pr-marker-test-$$/state"
mkdir -p "$TEST_STATE"

# Override state dir for testing — hook reads $REVIEW_PR_STATE_DIR if set.
export REVIEW_PR_STATE_DIR="$TEST_STATE"

cleanup() {
  rm -rf "/tmp/review-pr-marker-test-$$"
}
trap cleanup EXIT

emit_bash() {
  local cmd="$1"
  python3 -c "
import json, sys
print(json.dumps({
  'tool_name': 'Bash',
  'session_id': 'test-sid',
  'tool_input': {'command': sys.argv[1]}
}))
" "$cmd"
}

assert_fires() {
  local label="$1" cmd="$2"
  local out
  out=$(emit_bash "$cmd" | bash "$HOOK" 2>&1) || true
  if echo "$out" | grep -q "Heuristic match"; then
    printf '  ✅ %-55s fired\n' "$label"
  else
    printf '  ❌ %-55s expected=FIRE got silent\n   out: %s\n' "$label" "$out"
  fi
}

assert_silent() {
  local label="$1" cmd="$2"
  local out
  out=$(emit_bash "$cmd" | bash "$HOOK" 2>&1) || true
  if [ -z "$out" ] || ! echo "$out" | grep -q "Heuristic match"; then
    printf '  ✅ %-55s silent\n' "$label"
  else
    printf '  ❌ %-55s expected=SILENT got:\n   %s\n' "$label" "$out"
  fi
}

# --- write_marker helper (this is the piece /review-pr SKILL.md will call) ---
write_marker() {
  local pr_number="${1:-}"
  local marker="$TEST_STATE/review-pr-active"
  if [ -n "$pr_number" ]; then
    printf 'pr=%s\nts=%s\n' "$pr_number" "$(date -u +%s)" > "$marker"
  else
    printf 'ts=%s\n' "$(date -u +%s)" > "$marker"
  fi
}

clear_marker() {
  rm -f "$TEST_STATE/review-pr-active"
}

stale_marker() {
  # Write a marker with mtime 60 min ago
  local marker="$TEST_STATE/review-pr-active"
  printf 'pr=42\nts=%s\n' "$(date -u +%s)" > "$marker"
  touch -t "$(date -v-60M -u +%Y%m%d%H%M.%S 2>/dev/null || date -u -d '60 minutes ago' +%Y%m%d%H%M.%S)" "$marker" 2>/dev/null || true
}

echo "=== HIT (marker fresh + git commit) ==="
write_marker 123
assert_fires "marker PR #123 fresh + git commit"  "git commit -m 'fix bug'"
assert_fires "marker PR #123 fresh + git commit + push" "git commit -am 'fix' && git push"
clear_marker
write_marker ""  # branch review (no PR#)
assert_fires "branch marker fresh + git commit"   "git commit -m 'wip'"

echo
echo "=== MISS (no marker) ==="
clear_marker
assert_silent "no marker + git commit"             "git commit -m 'wip'"
assert_silent "no marker + any bash"               "ls -la"

echo
echo "=== MISS (stale marker, > 30 min) ==="
stale_marker
assert_silent "60min-old marker + git commit"      "git commit -m 'wip'"

echo
echo "=== MISS (marker fresh but no git commit) ==="
write_marker 99
assert_silent "marker fresh + ls"                  "ls -la"
assert_silent "marker fresh + git status"          "git status"
assert_silent "marker fresh + git push (no commit)" "git push origin develop"
assert_silent "marker fresh + git add"             "git add foo.txt"
clear_marker

echo
echo "=== bypass (CLAUDE_DISABLED_HOOKS) ==="
write_marker 1
out=$(emit_bash "git commit -m 'x'" | CLAUDE_DISABLED_HOOKS=review-pr-marker bash "$HOOK" 2>&1) || true
if [ -z "$out" ] || ! echo "$out" | grep -q "Heuristic match"; then
  echo "  ✅ bypass env disables hook"
else
  echo "  ❌ bypass env did not disable: $out"
fi
clear_marker

echo
echo "=== non-Bash tool input stays silent (defence) ==="
out=$(printf '{"tool_name":"Edit","session_id":"x","tool_input":{"file_path":"/tmp/x"}}\n' | bash "$HOOK" 2>&1) || true
if [ -z "$out" ] || ! echo "$out" | grep -q "Heuristic match"; then
  echo "  ✅ non-Bash tool input: silent"
else
  echo "  ❌ non-Bash should be silent: $out"
fi
