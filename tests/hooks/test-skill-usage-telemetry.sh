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
HEALTH_SH="$ROOT/skills/meta/harness-audit/scripts/health.sh"

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
echo "=== harness-health.py dead-surface panel (#136) ==="
echo ""

# Synthetic fleet: one active + one dead skill, one manual-only (disable-model-invocation)
# skill, one active + one dead agent, and a hooks/ tree with files that must be excluded
# (a __pycache__ file, an underscore-prefixed file) to prove the count mirrors
# checks/01-fleet-count.sh's find filters. Isolated under its own mktemp -d, same
# convention as HP_TMP above — never touches the real repo's own fleet.
DS_TMP="$(mktemp -d)"

mkdir -p "$DS_TMP/.claude-plugin"
cat >"$DS_TMP/.claude-plugin/plugin.json" <<'EOF'
{"name": "mh"}
EOF

mkdir -p "$DS_TMP/skills/active-skill" "$DS_TMP/skills/dead-skill" "$DS_TMP/skills/manual-skill"
cat >"$DS_TMP/skills/active-skill/SKILL.md" <<'EOF'
---
name: active-skill
description: "test fixture, invoked in the last 30d"
---
body
EOF
cat >"$DS_TMP/skills/dead-skill/SKILL.md" <<'EOF'
---
name: dead-skill
description: "test fixture, never invoked"
---
body
EOF
cat >"$DS_TMP/skills/manual-skill/SKILL.md" <<'EOF'
---
name: manual-skill
description: "test fixture, user-typed only"
disable-model-invocation: true
---
body
EOF

mkdir -p "$DS_TMP/agents"
cat >"$DS_TMP/agents/active-agent.md" <<'EOF'
---
name: active-agent
description: "test fixture, invoked in the last 30d"
tools: Read
---
body
EOF
cat >"$DS_TMP/agents/dead-agent.md" <<'EOF'
---
name: dead-agent
description: "test fixture, never invoked"
tools: Read
---
body
EOF

mkdir -p "$DS_TMP/hooks/session" "$DS_TMP/hooks/stop" "$DS_TMP/hooks/__pycache__"
touch "$DS_TMP/hooks/session/foo.sh" "$DS_TMP/hooks/stop/bar.py"
touch "$DS_TMP/hooks/__pycache__/baz.py"   # excluded: __pycache__
touch "$DS_TMP/hooks/_ignored.sh"          # excluded: leading underscore

mkdir -p "$DS_TMP/agents"
cat >"$DS_TMP/agents/stale-agent.md" <<'EOF'
---
name: stale-agent
description: "test fixture, invoked 60d ago -- outside the 30d window"
tools: Read
---
body
EOF

# #136 fix 1 fixtures: a pre-rename kbg:-prefixed row must count toward the
# CURRENT mh: surface (renamed-skill/renamed-agent), but a DIFFERENT
# plugin's row with a colliding stem must NOT (collision-skill/collision-agent)
# -- the discriminating case a naive split(":")[-1] would get wrong.
mkdir -p "$DS_TMP/skills/renamed-skill" "$DS_TMP/skills/collision-skill" "$DS_TMP/skills/preloaded-skill"
cat >"$DS_TMP/skills/renamed-skill/SKILL.md" <<'EOF'
---
name: renamed-skill
description: "test fixture, only invoked under the pre-rename kbg: prefix"
---
body
EOF
cat >"$DS_TMP/skills/collision-skill/SKILL.md" <<'EOF'
---
name: collision-skill
description: "test fixture, a DIFFERENT plugin's x:collision-skill row exists and must not count"
---
body
EOF
cat >"$DS_TMP/skills/preloaded-skill/SKILL.md" <<'EOF'
---
name: preloaded-skill
description: "test fixture, preloaded via an agent's skills: frontmatter, never invoked directly"
---
body
EOF

cat >"$DS_TMP/agents/renamed-agent.md" <<'EOF'
---
name: renamed-agent
description: "test fixture, only invoked under the pre-rename kbg: prefix"
tools: Read
---
body
EOF
cat >"$DS_TMP/agents/collision-agent.md" <<'EOF'
---
name: collision-agent
description: "test fixture, a DIFFERENT plugin's x:collision-agent row exists and must not count"
tools: Read
---
body
EOF
cat >"$DS_TMP/agents/preload-host-agent.md" <<'EOF'
---
name: preload-host-agent
description: "test fixture, preloads mh:preloaded-skill via frontmatter"
tools: Read
skills:
  - mh:preloaded-skill
---
body
EOF

DS_SKILLS_LEDGER="$DS_TMP/skill-usage.jsonl"
DS_COSTS_LEDGER="$DS_TMP/costs.jsonl"
DS_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DS_DAY60="$(date -u -v-60d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '60 days ago' +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "{\"ts\":\"$DS_NOW\",\"session_id\":\"z\",\"skill\":\"mh:active-skill\",\"plugin\":\"mh\"}"
  echo "{\"ts\":\"$DS_NOW\",\"session_id\":\"z2\",\"skill\":\"kbg:renamed-skill\",\"plugin\":\"kbg\"}"
  echo "{\"ts\":\"$DS_NOW\",\"session_id\":\"z3\",\"skill\":\"x:collision-skill\",\"plugin\":\"x\"}"
} >"$DS_SKILLS_LEDGER"
{
  echo "{\"timestamp\":\"$DS_NOW\",\"session_id\":\"z\",\"stream\":\"subagent\",\"agent_type\":\"mh:active-agent\"}"
  echo "{\"timestamp\":\"$DS_DAY60\",\"session_id\":\"z\",\"stream\":\"subagent\",\"agent_type\":\"mh:stale-agent\"}"
  echo "{\"timestamp\":\"$DS_NOW\",\"session_id\":\"z2\",\"stream\":\"subagent\",\"agent_type\":\"kbg:renamed-agent\"}"
  echo "{\"timestamp\":\"$DS_NOW\",\"session_id\":\"z3\",\"stream\":\"subagent\",\"agent_type\":\"x:collision-agent\"}"
} >"$DS_COSTS_LEDGER"

ds_out=$(python3 "$HEALTH_PY" --last 100 --root "$DS_TMP" --skills "$DS_SKILLS_LEDGER" --costs "$DS_COSTS_LEDGER" 2>/dev/null)

if echo "$ds_out" | /usr/bin/grep -qE '\| skill \| mh:dead-skill \|' \
   && echo "$ds_out" | /usr/bin/grep -qE '\| agent \| mh:dead-agent \|' \
   && ! echo "$ds_out" | /usr/bin/grep -qE '\| skill \| mh:active-skill \|' \
   && ! echo "$ds_out" | /usr/bin/grep -qE '\| agent \| mh:active-agent \|'; then
  echo "  ✅ DEAD VS ACTIVE: dead-skill/dead-agent listed, active-skill/active-agent are not"
  pass=$((pass + 1))
else
  echo "  ❌ expected mh:dead-skill + mh:dead-agent listed, mh:active-skill/active-agent absent, got:" >&2
  echo "$ds_out" >&2
  fail=$((fail + 1))
fi

if echo "$ds_out" | /usr/bin/grep -qE '\| agent \| mh:stale-agent \|'; then
  echo "  ✅ AGENT 30d CUTOFF: a row present in costs.jsonl but 60d old still counts as dead (not just 'any row = active')"
  pass=$((pass + 1))
else
  echo "  ❌ expected mh:stale-agent (60d-old costs row, outside the 30d window) to be listed dead, got:" >&2
  echo "$ds_out" >&2
  fail=$((fail + 1))
fi

if ! echo "$ds_out" | /usr/bin/grep -qE '\| skill \| mh:renamed-skill \|' \
   && ! echo "$ds_out" | /usr/bin/grep -qE '\| agent \| mh:renamed-agent \|'; then
  echo "  ✅ #136 FIX 1 ALIAS: a pre-rename kbg:-prefixed row counts as alive for the current mh: surface (skill + agent)"
  pass=$((pass + 1))
else
  echo "  ❌ expected mh:renamed-skill/mh:renamed-agent to be alive via the kbg: alias, got:" >&2
  echo "$ds_out" >&2
  fail=$((fail + 1))
fi

if echo "$ds_out" | /usr/bin/grep -qE '\| skill \| mh:collision-skill \|' \
   && echo "$ds_out" | /usr/bin/grep -qE '\| agent \| mh:collision-agent \|'; then
  echo "  ✅ #136 FIX 1 NEGATIVE CASE: a different plugin's x:collision-skill/x:collision-agent row does NOT mark the mh: counterpart alive"
  pass=$((pass + 1))
else
  echo "  ❌ expected mh:collision-skill/mh:collision-agent to still be listed dead (no cross-plugin leak), got:" >&2
  echo "$ds_out" >&2
  fail=$((fail + 1))
fi

if echo "$ds_out" | /usr/bin/grep -qE '\| skill \| mh:preloaded-skill \| preloaded-by: preload-host-agent'; then
  echo "  ✅ #136 FIX 2 PRELOADED-BY LABEL: a skill only reachable via an agent's skills: frontmatter is labeled, not left blank"
  pass=$((pass + 1))
else
  echo "  ❌ expected mh:preloaded-skill to carry 'preloaded-by: preload-host-agent', got:" >&2
  echo "$ds_out" >&2
  fail=$((fail + 1))
fi

if echo "$ds_out" | /usr/bin/grep -qE '\| skill \| mh:manual-skill \| manual-only'; then
  echo "  ✅ MANUAL-ONLY LABEL: disable-model-invocation skill is noted, not just listed bare"
  pass=$((pass + 1))
else
  echo "  ❌ expected mh:manual-skill row to carry a manual-only note, got:" >&2
  echo "$ds_out" >&2
  fail=$((fail + 1))
fi

if echo "$ds_out" | /usr/bin/grep -qE 'hooks: 2 hook\(s\) in fleet — no invocation ledger exists, source missing'; then
  echo "  ✅ HOOKS SOURCE MISSING: count=2 (excludes __pycache__ and _-prefixed), never a fabricated zero"
  pass=$((pass + 1))
else
  echo "  ❌ expected 'hooks: 2 hook(s) in fleet — no invocation ledger exists, source missing', got:" >&2
  echo "$ds_out" >&2
  fail=$((fail + 1))
fi

ds_json=$(python3 "$HEALTH_PY" --json --last 100 --root "$DS_TMP" --skills "$DS_SKILLS_LEDGER" --costs "$DS_COSTS_LEDGER" 2>/dev/null)
if echo "$ds_json" | jq -e '
     .dead_surfaces.plugin == "mh"
     and (.dead_surfaces.dead_skills | map(.name) | sort) ==
         ["mh:collision-skill", "mh:dead-skill", "mh:manual-skill", "mh:preloaded-skill"]
     and (.dead_surfaces.dead_skills[] | select(.name == "mh:manual-skill") | .manual_only) == true
     and (.dead_surfaces.dead_skills[] | select(.name == "mh:preloaded-skill") | .preloaded_by) == ["preload-host-agent"]
     and (.dead_surfaces.dead_agents | map(.name) | sort) ==
         ["mh:collision-agent", "mh:dead-agent", "mh:preload-host-agent", "mh:stale-agent"]
     and .dead_surfaces.hooks.count == 2
     and .dead_surfaces.hooks.source_missing == true
     and .dead_surfaces.skills_source_missing == false
     and .dead_surfaces.costs_source_missing == false
     and (.dead_surfaces.coverage | contains("preloaded") and contains("typed-slash") and contains("script-run"))
   ' >/dev/null 2>&1; then
  echo "  ✅ JSON PAYLOAD: --json carries dead_surfaces with matching skills/agents/hooks content (incl. #136 fix 1/2/3 fields)"
  pass=$((pass + 1))
else
  echo "  ❌ --json dead_surfaces payload didn't match expected shape, got:" >&2
  echo "$ds_json" >&2
  fail=$((fail + 1))
fi

# #136 fix 3: a missing ledger must report "source missing", never a fabricated
# dead-list -- both markdown and --json paths, both ledgers.
ds_missing_skills_md=$(python3 "$HEALTH_PY" --last 100 --root "$DS_TMP" --skills "$DS_TMP/no-such-skills.jsonl" --costs "$DS_COSTS_LEDGER" 2>/dev/null)
if echo "$ds_missing_skills_md" | /usr/bin/grep -q "skills: source missing:" \
   && ! echo "$ds_missing_skills_md" | /usr/bin/grep -qE '[0-9]+ dead skill\(s\)'; then
  echo "  ✅ #136 FIX 3 SKILLS MISSING (markdown): 'source missing', never a fabricated 'N dead skill(s)'"
  pass=$((pass + 1))
else
  echo "  ❌ expected 'skills: source missing:' and no fabricated dead-skill count, got:" >&2
  echo "$ds_missing_skills_md" >&2
  fail=$((fail + 1))
fi

ds_missing_costs_md=$(python3 "$HEALTH_PY" --last 100 --root "$DS_TMP" --skills "$DS_SKILLS_LEDGER" --costs "$DS_TMP/no-such-costs.jsonl" 2>/dev/null)
if echo "$ds_missing_costs_md" | /usr/bin/grep -q "agents: source missing:" \
   && ! echo "$ds_missing_costs_md" | /usr/bin/grep -qE '[0-9]+ dead agent\(s\)'; then
  echo "  ✅ #136 FIX 3 COSTS MISSING (markdown): 'source missing', never a fabricated 'N dead agent(s)' (worst bug: whole fleet reported dead)"
  pass=$((pass + 1))
else
  echo "  ❌ expected 'agents: source missing:' and no fabricated dead-agent count, got:" >&2
  echo "$ds_missing_costs_md" >&2
  fail=$((fail + 1))
fi

ds_missing_costs_json=$(python3 "$HEALTH_PY" --json --last 100 --root "$DS_TMP" --skills "$DS_SKILLS_LEDGER" --costs "$DS_TMP/no-such-costs.jsonl" 2>/dev/null)
if echo "$ds_missing_costs_json" | jq -e '
     .dead_surfaces.costs_source_missing == true and .dead_surfaces.dead_agents == null
     and .dead_surfaces.skills_source_missing == false and (.dead_surfaces.dead_skills | length) > 0
   ' >/dev/null 2>&1; then
  echo "  ✅ #136 FIX 3 COSTS MISSING (--json): dead_agents is null, not a fabricated full-fleet dead list; --json honors the same guard as markdown"
  pass=$((pass + 1))
else
  echo "  ❌ --json with a missing costs ledger should carry dead_agents: null, got:" >&2
  echo "$ds_missing_costs_json" >&2
  fail=$((fail + 1))
fi

# health.sh's own root resolution (code review, #136 follow-up): the wrapper
# computes __root from ITS OWN file location, not from a passed-in --root, so
# this must actually invoke health.sh (not harness-health.py --root) against
# a fixture laid out at the same relative depth
# (<root>/skills/meta/harness-audit/scripts/health.sh) to catch an off-by-one
# in that path math. A wrong __root here silently resolves to a directory one
# level too shallow, which harness-health.py reads as an EMPTY fleet --
# "0 dead skill(s)" -- not an error, so nothing else would ever catch it.
mkdir -p "$DS_TMP/skills/meta/harness-audit/scripts"
cp "$HEALTH_SH" "$DS_TMP/skills/meta/harness-audit/scripts/health.sh"
cp "$HEALTH_PY" "$DS_TMP/skills/meta/harness-audit/scripts/harness-health.py"
ds_wrapper_out=$(bash "$DS_TMP/skills/meta/harness-audit/scripts/health.sh" --last 100 --skills "$DS_SKILLS_LEDGER" --costs "$DS_COSTS_LEDGER" 2>/dev/null)
if echo "$ds_wrapper_out" | /usr/bin/grep -qE '\| skill \| mh:dead-skill \|'; then
  echo "  ✅ HEALTH.SH ROOT RESOLUTION: wrapper's own __root math finds the fixture fleet (not a fabricated empty all-clear)"
  pass=$((pass + 1))
else
  echo "  ❌ health.sh should resolve __root to the fixture root and list mh:dead-skill, got:" >&2
  echo "$ds_wrapper_out" >&2
  fail=$((fail + 1))
fi

trash "$DS_TMP" 2>/dev/null || true

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
