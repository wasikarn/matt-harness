#!/usr/bin/env bash
# skill-usage-telemetry unit tests (#90/T11): simulates PostToolUse(Skill)
# payloads and asserts one compact JSONL row lands per invocation with
# {ts, session_id, skill, plugin} — no outcome/success field (see the hook's
# own header for why: no reliable success signal exists for a Skill call).
# Run standalone: bash tests/hooks/test-skill-usage-telemetry.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/skill-usage-telemetry.sh"

pass=0
fail=0

TMP_HOME="$(mktemp -d)"
trap 'trash "$TMP_HOME" 2>/dev/null || true' EXIT
LOG_FILE="$TMP_HOME/.local/share/kbg/metrics/skill-usage.jsonl"

run_hook() {
  local payload="$1"
  HOME="$TMP_HOME" bash -c "echo '$payload' | '$HOOK'"
}

echo "=== skill-usage-telemetry hook (PostToolUse: Skill) ==="
echo ""

payload='{"session_id":"sess-1","hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"mh:harness-audit"}}'
run_hook "$payload" >/tmp/sut-stdout.$$ 2>/tmp/sut-stderr.$$
rc=$?
stdout_content=$(cat /tmp/sut-stdout.$$)
rm -f /tmp/sut-stdout.$$ /tmp/sut-stderr.$$

if [[ "$rc" == "0" && -z "$stdout_content" ]]; then
  echo "  ✅ SILENT + exit 0: mh: skill invocation"
  pass=$((pass + 1))
else
  echo "  ❌ expected silent exit 0 but rc=$rc stdout=<$stdout_content>" >&2
  fail=$((fail + 1))
fi

if [[ -f "$LOG_FILE" ]] && jq -e '.skill == "mh:harness-audit" and .plugin == "mh" and .session_id == "sess-1"' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ LOGGED: row has correct skill/plugin/session_id"
  pass=$((pass + 1))
else
  echo "  ❌ LOG MISMATCH: expected a row with skill=mh:harness-audit plugin=mh" >&2
  fail=$((fail + 1))
fi

if jq -e 'has("outcome") | not' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ NO OUTCOME FIELD: schema is invocation-count-only, per the #90 scope decision"
  pass=$((pass + 1))
else
  echo "  ❌ row unexpectedly carries an outcome field — this schema was deliberately dropped" >&2
  fail=$((fail + 1))
fi

payload2='{"session_id":"sess-1","hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"mattpocock-skills:code-review"}}'
run_hook "$payload2" >/dev/null 2>&1
if [[ "$(wc -l <"$LOG_FILE" | tr -d ' ')" == "2" ]] && jq -e 'select(.skill == "mattpocock-skills:code-review") | .plugin == "mattpocock-skills"' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ APPENDS + PLUGIN SPLIT: second invocation adds a row, plugin derived from the skill's namespace prefix"
  pass=$((pass + 1))
else
  echo "  ❌ expected 2 rows with correct plugin split, got $(wc -l <"$LOG_FILE" | tr -d ' ') lines" >&2
  fail=$((fail + 1))
fi

payload3='{"session_id":"sess-1","hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{}}'
run_hook "$payload3" >/dev/null 2>&1
if jq -e 'select(.skill == "unknown") | .plugin == "unnamespaced"' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ MISSING FIELD FALLBACK: no tool_input.skill -> skill 'unknown', plugin 'unnamespaced', still appends"
  pass=$((pass + 1))
else
  echo "  ❌ missing tool_input.skill should fall back to skill=unknown plugin=unnamespaced" >&2
  fail=$((fail + 1))
fi

# Adversarial fixes (2026-08-25, #90 independent review): tool_input.skill
# present but the WRONG type used to throw inside split(":") -- a jq error
# swallowed by 2>/dev/null, silently DROPPING the row entirely rather than
# falling back to "unknown" like the missing-key case does.
payload_badtype='{"session_id":"sess-1","hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":42}}'
lines_before=$(wc -l <"$LOG_FILE" | tr -d ' ')
run_hook "$payload_badtype" >/dev/null 2>&1
lines_after=$(wc -l <"$LOG_FILE" | tr -d ' ')
if [[ "$lines_after" == "$((lines_before + 1))" ]] && jq -e 'select(.skill == "unknown" and .plugin == "unnamespaced")' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ WRONG-TYPE SKILL: a non-string tool_input.skill (a number) still appends a row (skill=unknown), not silently dropped"
  pass=$((pass + 1))
else
  echo "  ❌ a non-string tool_input.skill should append a fallback row, not vanish silently (before=$lines_before after=$lines_after)" >&2
  fail=$((fail + 1))
fi

# Unnamespaced skill (no ":" at all -- several real skills in this fleet
# have no plugin prefix, e.g. "design", "run", "init"). Previously fell
# through split(":")[0] to plugin == skill, showing up in the health panel
# as its own fake single-skill "plugin".
payload_unnamespaced='{"session_id":"sess-1","hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"design"}}'
run_hook "$payload_unnamespaced" >/dev/null 2>&1
if jq -e 'select(.skill == "design") | .plugin == "unnamespaced"' "$LOG_FILE" >/dev/null 2>&1; then
  echo "  ✅ UNNAMESPACED SKILL: a colon-free skill name reports plugin='unnamespaced', not plugin==skill"
  pass=$((pass + 1))
else
  echo "  ❌ an unnamespaced skill name should report plugin='unnamespaced', not collapse plugin==skill" >&2
  fail=$((fail + 1))
fi

# Malformed payload must not crash the hook or corrupt the log.
run_hook 'not json' >/tmp/sut-stdout2.$$ 2>/tmp/sut-stderr2.$$
rc=$?
rm -f /tmp/sut-stdout2.$$ /tmp/sut-stderr2.$$
if [[ "$rc" == "0" ]]; then
  echo "  ✅ EXIT 0: malformed payload doesn't crash the hook"
  pass=$((pass + 1))
else
  echo "  ❌ malformed payload exited $rc, expected 0" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
