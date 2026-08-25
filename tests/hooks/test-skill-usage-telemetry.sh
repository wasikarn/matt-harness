#!/usr/bin/env bash
# skill-usage-telemetry unit tests (#90/T11): simulates PostToolUse(Skill)
# payloads and asserts one compact JSONL row lands per invocation with
# {ts, session_id, skill, plugin} — no outcome/success field (see the hook's
# own header for why: no reliable success signal exists for a Skill call).
# Also covers harness-health.py's skill-usage panel: given a synthetic
# skill-usage.jsonl, does it render correct 7d/30d invocation counts split
# by plugin, and does it skip a malformed line without crashing.
# Run standalone: bash tests/hooks/test-skill-usage-telemetry.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/skill-usage-telemetry.sh"
HEALTH_PY="$ROOT/skills/meta/harness-audit/scripts/harness-health.py"

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
echo "=== harness-health.py skill-usage panel ==="
echo ""

HP_TMP="$(mktemp -d)"
SKILLS_LEDGER="$HP_TMP/skill-usage.jsonl"
touch "$HP_TMP/no-costs.jsonl"  # present-but-empty: isolates the skill-usage panel from --costs's own missing-ledger error path
NOW_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DAY3_UTC="$(date -u -v-3d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)"
DAY20_UTC="$(date -u -v-20d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '20 days ago' +%Y-%m-%dT%H:%M:%SZ)"
DAY60_UTC="$(date -u -v-60d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '60 days ago' +%Y-%m-%dT%H:%M:%SZ)"

{
  echo "{\"ts\":\"$NOW_UTC\",\"session_id\":\"a\",\"skill\":\"mh:harness-audit\",\"plugin\":\"mh\"}"
  echo "{\"ts\":\"$DAY3_UTC\",\"session_id\":\"b\",\"skill\":\"mh:harness-audit\",\"plugin\":\"mh\"}"
  echo "{\"ts\":\"$DAY20_UTC\",\"session_id\":\"c\",\"skill\":\"mattpocock-skills:code-review\",\"plugin\":\"mattpocock-skills\"}"
  echo "{\"ts\":\"$DAY60_UTC\",\"session_id\":\"d\",\"skill\":\"mattpocock-skills:code-review\",\"plugin\":\"mattpocock-skills\"}"
  echo "not json"
} >"$SKILLS_LEDGER"

out=$(python3 "$HEALTH_PY" --last 100 --skills "$SKILLS_LEDGER" --costs "$HP_TMP/no-costs.jsonl" 2>/tmp/hp-stderr.$$)
hp_stderr=$(cat /tmp/hp-stderr.$$)
rm -f /tmp/hp-stderr.$$

if echo "$hp_stderr" | /usr/bin/grep -q "skipping malformed line"; then
  echo "  ✅ MALFORMED LINE: warned + skipped, did not crash"
  pass=$((pass + 1))
else
  echo "  ❌ expected a malformed-line warning on stderr, got: $hp_stderr" >&2
  fail=$((fail + 1))
fi

# Adversarial fix (2026-08-25, #90 independent review, reproduced live): a
# SYNTACTICALLY valid row with the WRONG type (ts as a number, not a
# string) passes load_rows()'s JSON-syntax check, then used to crash the
# whole --health command with an uncaught TypeError on the string
# comparison inside render_skill_usage — distinct from the syntax-error
# case above, and previously untested.
TYPE_LEDGER="$HP_TMP/skill-usage-badtype.jsonl"
{
  echo "{\"ts\":12345,\"session_id\":\"x\",\"skill\":\"mh:foo\",\"plugin\":\"mh\"}"
  echo "{\"ts\":\"$NOW_UTC\",\"session_id\":\"y\",\"skill\":\"mh:foo\",\"plugin\":\"mh\"}"
} >"$TYPE_LEDGER"
type_out=$(python3 "$HEALTH_PY" --last 100 --skills "$TYPE_LEDGER" --costs "$HP_TMP/no-costs.jsonl" 2>/tmp/hp-stderr2.$$)
type_rc=$?
type_stderr=$(cat /tmp/hp-stderr2.$$)
rm -f /tmp/hp-stderr2.$$
if [[ "$type_rc" == "0" ]] && echo "$type_stderr" | /usr/bin/grep -qi "non-string" \
   && echo "$type_out" | /usr/bin/grep -qE '\| mh \| mh:foo \| 1 \| 1 \|'; then
  echo "  ✅ NON-STRING ts FIELD: warned + skipped, exit 0, the OTHER valid row still renders (no crash)"
  pass=$((pass + 1))
else
  echo "  ❌ a non-string ts field should warn+skip, not crash (rc=$type_rc):" >&2
  echo "$type_out" >&2
  echo "$type_stderr" >&2
  fail=$((fail + 1))
fi

if echo "$out" | /usr/bin/grep -qE '\| mh \| mh:harness-audit \| 2 \| 2 \|'; then
  echo "  ✅ 7d/30d COUNT: mh:harness-audit shows 2/2 (both rows within 7d and 30d)"
  pass=$((pass + 1))
else
  echo "  ❌ expected mh:harness-audit row '| mh | mh:harness-audit | 2 | 2 |', got:" >&2
  echo "$out" >&2
  fail=$((fail + 1))
fi

if echo "$out" | /usr/bin/grep -qE '\| mattpocock-skills \| mattpocock-skills:code-review \| 0 \| 1 \|'; then
  echo "  ✅ 30d-ONLY COUNT: code-review shows 0/1 (20d-old row counts toward 30d, not 7d; 60d-old row excluded entirely)"
  pass=$((pass + 1))
else
  echo "  ❌ expected code-review row '| mattpocock-skills | mattpocock-skills:code-review | 0 | 1 |', got:" >&2
  echo "$out" >&2
  fail=$((fail + 1))
fi

if echo "$out" | /usr/bin/grep -q "outcome"; then
  echo "  ❌ panel unexpectedly mentions 'outcome' — this is an invocation-count-only panel" >&2
  fail=$((fail + 1))
else
  echo "  ✅ NO OUTCOME IN PANEL: renders counts only, per the #90 scope decision"
  pass=$((pass + 1))
fi

echo ""
out_empty=$(python3 "$HEALTH_PY" --last 5 --skills "$HP_TMP/no-such-ledger.jsonl" --costs "$HP_TMP/no-costs.jsonl" 2>&1)
if echo "$out_empty" | /usr/bin/grep -q "0 rows"; then
  echo "  ✅ EMPTY LEDGER: renders '0 rows' instead of crashing when skill-usage.jsonl doesn't exist yet"
  pass=$((pass + 1))
else
  echo "  ❌ expected '0 rows' fallback for a missing skills ledger, got:" >&2
  echo "$out_empty" >&2
  fail=$((fail + 1))
fi

trash "$HP_TMP" 2>/dev/null || true

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
