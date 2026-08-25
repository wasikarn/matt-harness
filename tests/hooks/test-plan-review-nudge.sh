#!/usr/bin/env bash
# plan-review-nudge unit tests: simulates PostToolUse/ExitPlanMode JSON
# payloads and asserts stdout output (JSON with additionalContext) vs
# silence (nudge skipped). The hook never blocks, so all tests expect exit 0.
# Run standalone: bash tests/hooks/test-plan-review-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/plan-review-nudge.sh"

pass=0
fail=0

# Build a PostToolUse/ExitPlanMode payload. Real CC payloads carry the
# approved plan text at tool_response.plan (confirmed via hooks.md,
# 2026-07-22) -- not tool_input, which is typically empty for ExitPlanMode.
approved_payload() {
  python3 -c '
import sys, json
plan = sys.argv[1]
print(json.dumps({
    "tool_name": "ExitPlanMode",
    "tool_response": {"plan": plan, "filePath": "/tmp/fake-plan.md"},
}, ensure_ascii=False))
' "$1"
}

echo "=== plan-review-nudge hook (PostToolUse:ExitPlanMode) ==="
echo ""
echo "--- approved plan with content (must emit nudge JSON, exit 0) ---"
out=$(approved_payload "# A real plan
## Context
Some plan body." | bash "$HOOK" 2>/dev/null)
rc=$?
if [[ "$rc" == "0" ]] \
   && printf '%s' "$out" | /usr/bin/grep -q '"additionalContext"' \
   && printf '%s' "$out" | /usr/bin/grep -q "mh:plan-reviewer" \
   && printf '%s' "$out" | /usr/bin/grep -q '"hookEventName": "PostToolUse"'; then
  echo "  ✅ NUDGE: approved plan with content emits valid additionalContext JSON"
  pass=$((pass + 1))
else
  echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi

# Output must be valid JSON, not just grep-matched text.
if printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  echo "  ✅ VALID JSON: nudge output parses cleanly"
  pass=$((pass + 1))
else
  echo "  ❌ INVALID JSON: <$(printf '%s' "$out" | head -c 200)>" >&2
  fail=$((fail + 1))
fi

echo ""
echo "--- silent cases (must stay silent, exit 0) ---"

silent_case() {
  local desc="$1" payload="$2"
  local out rc
  out=$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)
  rc=$?
  if [[ "$rc" == "0" && -z "$out" ]]; then
    echo "  ✅ SILENT: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ SILENT EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

silent_case "empty tool_response.plan" \
  '{"tool_name":"ExitPlanMode","tool_response":{"plan":""}}'
silent_case "missing tool_response entirely" \
  '{"tool_name":"ExitPlanMode"}'
silent_case "malformed JSON" \
  'not json at all'
silent_case "empty stdin" \
  ""

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
