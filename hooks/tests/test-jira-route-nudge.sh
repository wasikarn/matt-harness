#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in payload strings is intentional
# jira-route-nudge unit tests: simulates UserPromptSubmit JSON payloads and
# asserts stdout output (nudge fired) vs silence (nudge skipped). The hook
# never blocks, so all tests expect exit 0.
# Run standalone: bash hooks/tests/test-jira-route-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/jira-route-nudge.sh"

pass=0
fail=0

user_prompt_payload() {
  python3 -c '
import sys, json
prompt = sys.argv[1]
print(json.dumps({"tool_name": "UserPromptSubmit", "prompt": prompt}))
' "$1"
}

test_nudge() {
  local desc="$1" prompt="$2"
  local out
  out=$(echo "$(user_prompt_payload "$prompt")" | bash "$HOOK" 2>/dev/null)
  local rc=$?
  if [[ "$rc" == "0" && -n "$out" ]]; then
    echo "  ✅ NUDGE: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ NUDGE EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

test_silent() {
  local desc="$1" prompt="$2"
  local out
  out=$(echo "$(user_prompt_payload "$prompt")" | bash "$HOOK" 2>/dev/null)
  local rc=$?
  if [[ "$rc" == "0" && -z "$out" ]]; then
    echo "  ✅ SILENT: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ SILENT EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== jira-route-nudge hook (UserPromptSubmit) ==="
echo ""
echo "--- Jira/Confluence work (must nudge) ---"
test_nudge "create a Jira ticket"          "create a Jira ticket for this bug"
test_nudge "confluence page mention"       "write a Confluence page for the spec"
test_nudge "TP- ticket key"                "update TP-809 with the fix"
test_nudge "case-insensitive JIRA"         "check JIRA for related issues"
test_nudge "acli mention with jira"        "run acli to post this to jira"

echo ""
echo "--- unrelated work (must stay silent) ---"
test_silent "unrelated feature request"    "add a logout button"
test_silent "generic ticket word alone"    "create a ticket for the printer"
test_silent "empty prompt"                 ""
test_silent "short typo fix"               "fix typo in README"

echo ""
empty_out=$(echo "" | bash "$HOOK" 2>/dev/null)
empty_rc=$?
if [[ "$empty_rc" == "0" && -z "$empty_out" ]]; then
  echo "  ✅ SILENT: empty stdin"
  pass=$((pass + 1))
else
  echo "  ❌ SILENT EXPECTED but rc=$empty_rc stdout=<$(printf '%s' "$empty_out" | head -c 80)>: empty stdin" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
