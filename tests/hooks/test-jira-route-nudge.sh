#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in payload strings is intentional
# jira-route-nudge unit tests: simulates UserPromptSubmit JSON payloads and
# asserts stdout output (nudge fired) vs silence (nudge skipped). The hook
# never blocks, so all tests expect exit 0.
# Run standalone: bash tests/hooks/test-jira-route-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/advisory/jira-route-nudge.sh"

pass=0
fail=0

# The hook feature-detects the jira-acli plugin cache and skips silently when
# absent (#94) -- fake it present so the "must nudge" assertions below don't
# depend on whether this runner actually has jira-acli installed.
FAKE_JIRA_CACHE="$(mktemp -d)"
trap 'rm -rf "$FAKE_JIRA_CACHE"' EXIT
export MH_JIRA_ACLI_CACHE="$FAKE_JIRA_CACHE"

user_prompt_payload() {
  # ensure_ascii=False mirrors CC's real payload: Node JSON.stringify writes
  # UTF-8 directly (not \uXXXX escapes), so the hook sees real Thai bytes.
  python3 -c '
import sys, json
prompt = sys.argv[1]
print(json.dumps({"tool_name": "UserPromptSubmit", "prompt": prompt}, ensure_ascii=False))
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
test_nudge "file a Jira bug (EN verb)"     "file a Jira bug for the login regression"
test_nudge "search Jira (read verb)"       "search Jira for related tickets"
test_nudge "export JQL from jira"          "export JQL from jira"
test_nudge "Thai create jira story"        "สร้าง jira story ใหม่สำหรับ login"
test_nudge "Thai edit confluence"          "แก้ confluence page ส่วน scope"
test_nudge "Thai move ticket status"       "ย้ายสถานะ TP-809 เป็น Done"

echo ""
echo "--- unrelated work (must stay silent) ---"
test_silent "unrelated feature request"    "add a logout button"
test_silent "generic ticket word alone"    "create a ticket for the printer"
test_silent "empty prompt"                 ""
test_silent "short typo fix"               "fix typo in README"
test_silent "bare jira no verb"            "what does jira look like"
test_silent "meta: know the plugin (FP1)"  "บอกให้ claude รู้จัก plugins jira-acli เหมือน @RTK ดีมั้ย"
test_silent "meta: use plugin power (FP2)" "ทำอย่างไรให้ CC ใช้ plugin jira-acli ให้เต็มประสิทธิภาพ"
test_silent "meta: jira-acli plugin skill" "the jira-acli plugin skill hook config"
test_silent "meta: matt-harness + jira"    "matt-harness and jira-acli are both plugins"
test_silent "meta: kbg-harness + jira"     "kbg-harness and jira-acli are both plugins"

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
echo "--- jira-acli not installed (must stay silent regardless of content) ---"
NOT_INSTALLED_CACHE="$FAKE_JIRA_CACHE/nonexistent"
out=$(MH_JIRA_ACLI_CACHE="$NOT_INSTALLED_CACHE" bash -c "echo '$(user_prompt_payload "create a Jira ticket for this bug")' | bash '$HOOK'" 2>/dev/null)
rc=$?
if [[ "$rc" == "0" && -z "$out" ]]; then
  echo "  ✅ SILENT: jira-acli plugin cache absent"
  pass=$((pass + 1))
else
  echo "  ❌ SILENT EXPECTED but rc=$rc stdout=<$(printf '%s' "$out" | head -c 80)>: jira-acli plugin cache absent" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
