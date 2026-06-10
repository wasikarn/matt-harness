#!/bin/bash
# Behavioral tests for auto-review-nudge.sh (UserPromptSubmit).
# Mirrors test-nudge.sh scaffold: stdin JSON {prompt:...} → bash $HOOK →
# assert output contains "Heuristic match" + the route name "auto-review-nudge".
#
# Cycle 2 (GREEN) — implemented; tests pass on the actual gap cases.
# Cycle 3 (REFACTOR) — tightened to be strictly additive to skill-nudge.
#
# Design constraint (per code-reviewer Important #1, 2026-06-08):
#   auto-review-nudge MUST be strictly additive to skill-nudge. If skill-nudge
#   already fires on a prompt, auto-review-nudge stays silent (no double-banner,
#   matches orchestrator-nudge.sh:19-20 convention).

set -uo pipefail

HOOK_AUTO=/Users/kobig/Codes/Personals/dotfiles/claude/hooks/auto-review-nudge.sh
HOOK_SKILL=/Users/kobig/Codes/Personals/dotfiles/claude/hooks/skill-nudge.sh

emit() {
  local prompt="$1"
  printf '{"prompt":%s}\n' "$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
}

# Run a prompt through BOTH hooks and return concatenated output.
both_hooks() {
  local prompt="$1"
  local out_a out_s
  out_a=$(emit "$prompt" | bash "$HOOK_AUTO" 2>&1) || true
  out_s=$(emit "$prompt" | bash "$HOOK_SKILL" 2>&1) || true
  printf 'AUTO:%s\nSKILL:%s\n' "$out_a" "$out_s"
}

# Strictly-additive rule: auto-review-nudge fires iff skill-nudge stays silent.
# This is the regression test for the double-emit bug.
assert_no_double_fire() {
  local label="$1" prompt="$2"
  local combined auto_fires skill_fires
  combined=$(both_hooks "$prompt")
  auto_fires=$(printf '%s' "$combined" | grep -c "AUTO:.*Heuristic match" || true)
  skill_fires=$(printf '%s' "$combined" | grep -c "SKILL:.*Heuristic match" || true)
  if [ "$auto_fires" -eq 0 ] || [ "$skill_fires" -eq 0 ]; then
    printf '  ✅ %-55s no-double-fire (auto=%d skill=%d)\n' "$label" "$auto_fires" "$skill_fires"
  else
    printf '  ❌ %-55s DOUBLE-FIRE (auto=%d skill=%d)\n' "$label" "$auto_fires" "$skill_fires"
  fi
}

assert_fires() {
  local label="$1" prompt="$2"
  local out
  out=$(emit "$prompt" | bash "$HOOK_AUTO" 2>&1) || true
  if echo "$out" | grep -q "Heuristic match" && echo "$out" | grep -q "auto-review-nudge"; then
    printf '  ✅ %-55s fired\n' "$label"
  else
    printf '  ❌ %-55s expected=FIRE got silent\n   out: %s\n' "$label" "$out"
  fi
}

assert_silent() {
  local label="$1" prompt="$2"
  local out
  out=$(emit "$prompt" | bash "$HOOK_AUTO" 2>&1) || true
  if [ -z "$out" ] || ! echo "$out" | grep -q "Heuristic match"; then
    printf '  ✅ %-55s silent\n' "$label"
  else
    printf '  ❌ %-55s expected=SILENT got:\n   %s\n' "$label" "$out"
  fi
}

echo "=== strictly-additive HIT (comprehensive/multi-agent/all aspects) ==="
assert_fires "comprehensive review of this PR"        "comprehensive review of this PR"
assert_fires "multi-agent review on PR 456"           "multi-agent review on PR 456"
assert_fires "review pull request 789 all aspects"    "review pull request 789 all aspects"

echo
echo "=== strictly-additive MISS (owned by skill-nudge) ==="
assert_silent "review my PR (skill-nudge owns)"        "review my PR"
assert_silent "review this PR (skill-nudge owns)"      "review this PR"
assert_silent "review PR 123 for security (skill-nudge owns)" "review PR 123 for security"
assert_silent "review my code (no PR noun)"            "review my code"
assert_silent "fix the PR template (no review)"        "fix the PR template"
assert_silent "write tests for the user model"         "write tests for the user model"
assert_silent "Thai prompt with no PR context"         "ช่วย review code หน่อย"

echo
echo "=== no-double-fire regression (the Important #1 fix) ==="
assert_no_double_fire "comprehensive review of PR 123"   "comprehensive review of PR 123"
assert_no_double_fire "multi-agent review on PR 456"      "multi-agent review on PR 456"
assert_no_double_fire "review all aspects of pull request 789" "review all aspects of pull request 789"
assert_no_double_fire "review my PR (skill-nudge only)"   "review my PR"
assert_no_double_fire "comprehensive code review"          "comprehensive code review"

echo
echo "=== bypass (CLAUDE_DISABLED_HOOKS) ==="
out=$(emit "comprehensive review of this PR" | CLAUDE_DISABLED_HOOKS=auto-review-nudge bash "$HOOK_AUTO" 2>&1) || true
if [ -z "$out" ] || ! echo "$out" | grep -q "Heuristic match"; then
  echo "  ✅ bypass env disables hook"
else
  echo "  ❌ bypass env did not disable: $out"
fi

echo
echo "=== slash-invocation (skill-nudge owns it) ==="
out=$(emit "/review-pr 123" | bash "$HOOK_AUTO" 2>&1) || true
if [ -z "$out" ] || ! echo "$out" | grep -q "Heuristic match"; then
  echo "  ✅ slash invocation stays silent"
else
  echo "  ❌ slash invocation should not double-fire: $out"
fi
