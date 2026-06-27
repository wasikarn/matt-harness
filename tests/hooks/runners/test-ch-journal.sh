# shellcheck disable=SC1090,SC1091,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-journal.sh — standalone suite run by test-critical-hooks.sh
# Covers: C1 evidence journal (A-K) and C1 Phase II (L1-BB).

# --- C1 evidence journal: journal_append contract + consumer dedup ---
# Each case asserts a load-bearing invariant (JOURNAL-SCHEMA.md) that would fail
# if the logic regressed: nested shape, redaction, fail-loud, concurrency
# atomicity (the reason there is no flock), cross-stream dedup (no double count).
echo
echo "--- C1 evidence journal: journal_append + dedup ---"
JLIB="$HOOKS/_lib.sh"
JPATH="$FIXTURE/journal.jsonl"

# (A) envelope structure — nested {id,ts,session,hook,event,source,fields{}}, no top-level category,
# AND the function echoes the minted id on stdout (Phase II linkage: the journaler's
# `verdict.subject_id` is captured this way). Stdout id MUST equal the file's .id.
( source "$JLIB"; SID="jtest"; CLAUDE_JOURNAL_PATH="$JPATH"
  journal_append "config-change-log" "config_change" '{"path":"/x","source":"ide"}' ) > "$FIXTURE/jout.txt" 2>/dev/null
JE=$(cat "$FIXTURE/jout.txt")
FJID=$(jq -r .id "$JPATH")
if jq -e '.id and .ts and .session=="jtest" and .hook=="config-change-log" and .event=="config_change" and .source=="journal_append" and .fields.path=="/x" and (has("category")|not)' "$JPATH" >/dev/null 2>&1 \
   && [ -n "$JE" ] && [ "$JE" = "$FJID" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s nested envelope + id echo (stdout == file.id)\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s envelope/id-echo wrong: stdout=%s file_id=%s\n' "journal_append" "$JE" "$FJID"
fi

# (B) deny-list redaction — secret-ish KEY or string VALUE → [redacted]; safe field untouched
: > "$JPATH"
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$JPATH"
  journal_append "x" "config_change" '{"password":"hunter2","detail":"token=sk-abc","path":"/safe"}' )
if jq -e '.fields.password=="[redacted]" and .fields.detail=="[redacted]" and .fields.path=="/safe"' "$JPATH" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s deny-list redacts secret key+value, keeps safe field\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s redaction failed: %s\n' "journal_append" "$(cat "$JPATH")"
fi

# (C) missing jq → exit 2 (fail-loud, never a silent drop). PATH is a dir holding
# ONLY the non-jq binaries journal_append could need (python3/mkdir/dirname), so
# jq is GUARANTEED absent — the mutation "exit 2 → exit 0" cannot survive this
# (no self-skip branch that would mask it on a box where jq sits beside python3).
JBIN="$FIXTURE/jbin"; mkdir -p "$JBIN"
for b in python3 mkdir dirname; do ln -sf "$(command -v "$b")" "$JBIN/$b" 2>/dev/null; done
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$JPATH"; PATH="$JBIN"; journal_append "x" "e" '{}' ); jrc=$?
if [ "$jrc" = 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s missing jq → exit 2 (fail-loud)\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s missing jq → exit %s (want 2)\n' "journal_append" "$jrc"
fi

# (D) concurrency — 50×20 parallel appends of ~820-byte lines → all 1000 valid JSON,
# unique ids (proves O_APPEND atomicity at these sizes; this is why no flock).
: > "$JPATH"
for p in $(seq 1 50); do
  ( source "$JLIB"; SID="p$p"; CLAUDE_JOURNAL_PATH="$JPATH"
    pad=$(printf 'x%.0s' $(seq 1 700))
    for i in $(seq 1 20); do journal_append "h$p" "config_change" '{"path":"/p'"$p"'/'"$i"'","pad":"'"$pad"'"}'; done ) &
done
wait
jtot=$(wc -l < "$JPATH" | tr -d ' ')
jval=$(while IFS= read -r l; do printf '%s' "$l" | jq -e . >/dev/null 2>&1 && echo 1; done < "$JPATH" | wc -l | tr -d ' ')
juniq=$(jq -r '.id' "$JPATH" 2>/dev/null | sort -u | wc -l | tr -d ' ')
if [ "$jtot" = 1000 ] && [ "$jval" = 1000 ] && [ "$juniq" = 1000 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s 50×20 concurrent → 1000/1000 valid JSON, unique ids\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s concurrency lines=%s valid=%s uniq=%s (want 1000/1000/1000)\n' "journal_append" "$jtot" "$jval" "$juniq"
fi

# (E) consumer dedup — identical (hook,ts_second,category) in TSV + JSONL → counted once
GS="$HOOKS/../scripts/governance/governance-summary.py"
DHOME="$FIXTURE/dedup-home"; mkdir -p "$DHOME/.claude"
printf '%s\n' '{"id":"1-config-change-log-aa","ts":"2026-06-08T12:00:00.500Z","session":"s","hook":"config-change-log","event":"config_change","source":"journal_append","fields":{"path":"/x/foo","source":"ide"}}' > "$DHOME/.claude/governance-events.jsonl"
printf '2026-06-08T12:00:00Z\ts\tide\t/x/foo\n' > "$DHOME/.claude/config-change.log"
if [ -f "$GS" ] && HOME="$DHOME" python3 "$GS" 2>/dev/null | grep -q "cross-stream duplicate"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s consumer dedups TSV+JSONL twin → counted once\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s dedup did not fire (double-count risk)\n' "governance-summary"
fi

# (F) redaction recurses arrays AND catches secret SHAPES (not just flat word keys).
# Shapes are built at runtime so this test file carries no real-looking token
# (same hygiene as the secret-scan cases above; a literal would trip secret-scan).
fake_sk="sk-$(printf 'b%.0s' $(seq 1 24))"               # sk- + 24 = OpenAI-ish shape
fake_aws="AKIA$(printf 'C%.0s' $(seq 1 16))"             # AKIA + 16 upper = AWS shape
: > "$JPATH"
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$JPATH"
  journal_append "x" "config_change" '{"logs":["tok='"$fake_sk"'","ok"],"aws":"'"$fake_aws"'","safe":"hello"}' )
if jq -e '.fields.logs[0]=="[redacted]" and .fields.logs[1]=="ok" and .fields.aws=="[redacted]" and .fields.safe=="hello"' "$JPATH" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s redaction recurses arrays + catches secret shapes\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s array/shape redaction failed: %s\n' "journal_append" "$(cat "$JPATH")"
fi

# (F2) malformed fields_json → exit 2 + nothing written (the "never silent-drop" invariant)
( source "$JLIB"; SID=s; CLAUDE_JOURNAL_PATH="$FIXTURE/jbad.jsonl"; journal_append "x" "e" 'not valid json' ); jbrc=$?
if [ "$jbrc" = 2 ] && [ ! -s "$FIXTURE/jbad.jsonl" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s malformed fields_json → exit 2, no partial write\n' "journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s malformed: rc=%s wrote=%s\n' "journal_append" "$jbrc" "$([ -s "$FIXTURE/jbad.jsonl" ] && echo yes || echo no)"
fi

# (G) consumer fail-loud on a corrupt JSONL line: warns with line number, no crash
CHOME="$FIXTURE/chome"; mkdir -p "$CHOME/.claude"
printf '%s\n%s\n%s\n' \
  '{"id":"1-h-a","ts":"2026-06-08T12:00:00.0Z","session":"s","hook":"h","event":"config_change","source":"journal_append","fields":{"path":"/a"}}' \
  '{ not valid json' \
  '{"id":"2-h-b","ts":"2026-06-08T12:00:01.0Z","session":"s","hook":"h","event":"config_change","source":"journal_append","fields":{"path":"/b"}}' \
  > "$CHOME/.claude/governance-events.jsonl"
if HOME="$CHOME" python3 "$GS" >/dev/null 2>"$FIXTURE/cerr.txt" && grep -q "corrupt JSONL line 2" "$FIXTURE/cerr.txt"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s corrupt JSONL line → warned (lineno), not crashed\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s corrupt-line fail-loud broken\n' "governance-summary"
fi

# (H) empty-existing vs all-corrupt journal are distinguished (not both "0 events")
EHOME="$FIXTURE/ehome"; mkdir -p "$EHOME/.claude"
printf 'garbage\nmoregarbage\n' > "$EHOME/.claude/governance-events.jsonl"
allc=$(HOME="$EHOME" python3 "$GS" 2>/dev/null | grep -c "ALL 2 line.*corrupt")
: > "$EHOME/.claude/governance-events.jsonl"
emp=$(HOME="$EHOME" python3 "$GS" 2>/dev/null | grep -c "0 events (empty)")
if [ "$allc" -ge 1 ] && [ "$emp" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s all-corrupt vs empty journal distinguished\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s empty/all-corrupt: allc=%s emp=%s\n' "governance-summary" "$allc" "$emp"
fi

# (I) an event not in KNOWN_EVENTS is warned (schema-drift signal), not silently counted
UHOME="$FIXTURE/uhome"; mkdir -p "$UHOME/.claude"
printf '%s\n' '{"id":"1-h-a","ts":"2026-06-08T12:00:00.0Z","session":"s","hook":"h","event":"totally_new_event","source":"journal_append","fields":{"category":"x"}}' > "$UHOME/.claude/governance-events.jsonl"
if HOME="$UHOME" python3 "$GS" 2>/dev/null | grep -qi "unknown event.*totally_new_event"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s unknown event → warned (schema drift)\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s unknown-event warning missing\n' "governance-summary"
fi

# (J) --since survives a legacy naive-ts line (regression guard: naive-vs-aware
# compare used to crash the whole digest before the load_lines/_within fix)
NHOME="$FIXTURE/nhome"; mkdir -p "$NHOME/.claude"
printf '2026-06-08T10:00:00\ts\t/a.py\tSQL_INJECTION: x\n' > "$NHOME/.claude/security-diff-review.log"
if HOME="$NHOME" python3 "$GS" --since 7 >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s --since survives legacy naive-ts (no crash)\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s --since crashed on naive-ts\n' "governance-summary"
fi

# (K) harness-audit check #29 rejects a hook that calls BOTH journal_append and
# hook_decision (gate↔evidence separation) — minimal fixture repo + run audit.
AUDIT="$HOOKS/../skills/harness-audit/scripts/audit.sh"
KREPO="$FIXTURE/krepo"; mkdir -p "$KREPO/claude/hooks" "$KREPO/claude/agents" "$KREPO/claude/skills" "$KREPO/claude/commands"
cp "$JLIB" "$KREPO/claude/hooks/_lib.sh"
printf '#!/bin/bash\nsource "$(dirname "$0")/_lib.sh"\njournal_append a b c\nhook_decision deny x\n' > "$KREPO/claude/hooks/both-hook.sh"
# Capture first: audit exits non-zero (finding count), which under `set -o
# pipefail` would poison `audit | grep` and read as "no match" even when grep hit.
kaudit_out=$([ -f "$AUDIT" ] && bash "$AUDIT" "$KREPO" 2>&1 || true)
if printf '%s\n' "$kaudit_out" | grep -q "calls BOTH journal_append and hook_decision"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s audit #29 rejects gate+journal in one hook\n' "harness-audit"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s audit #29 negative test did not fire\n' "harness-audit"
fi

# (L) decision-provenance-nudge.sh is ADVISORY-ONLY — it journals decision_rationale
# + nudges via additionalContext, and NEVER emits a permissionDecision. This is the
# LLM-judge-circularity guard (CLAUDE.md §): a computational path-match nudge that
# never decides can never become a model-driven mutation gate (autonomy invariant,
# the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model). Also pins the #31.1-avoidance: the threshold is the one-way-door class
# only, so a benign edit is SILENT (no blanket firing that manufactures boilerplate).
echo
echo "--- C1 evidence journal: decision-provenance-nudge advisory invariant ---"
DPN="$HOOKS/advisory/decision-provenance-nudge.sh"
DPNJ="$FIXTURE/dpn.jsonl"; : > "$DPNJ"

# L1: a caged path (hooks/_lib.sh, under hooks/**) -> NO permissionDecision in
# output, additionalContext nudge present, and a decision_rationale event journaled
# with the machine-provenance fields. jq -e '... // empty' yields nothing when the
# key is absent, so an empty $PD means the advisory invariant holds.
PDOUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/_lib.sh"},"session_id":"dpnL"}' "$HOOKS" | CLAUDE_JOURNAL_PATH="$DPNJ" bash "$DPN" 2>/dev/null)
pd_dec=$(printf '%s' "$PDOUT" | jq -r '.hookSpecificOutput.permissionDecision // "<none>"' 2>/dev/null)
pd_ctx=$(printf '%s' "$PDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null | /usr/bin/grep -c "decision-sizing triad")
pd_dr=$(jq -r 'select(.event=="decision_rationale") | .fields.surface_touched' "$DPNJ" 2>/dev/null | head -1)
pd_owd=$(jq -r 'select(.event=="decision_rationale") | .fields.one_way_door' "$DPNJ" 2>/dev/null | head -1)
if [ "$pd_dec" = "<none>" ] && [ "$pd_ctx" = "1" ] && [ "$pd_dr" = "hooks/_lib.sh" ] && [ "$pd_owd" = "true" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s caged edit: no permissionDecision + nudge + decision_rationale\n' "decision-nudge"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s caged: dec=%s ctx=%s dr=%s owd=%s\n' "decision-nudge" "$pd_dec" "$pd_ctx" "$pd_dr" "$pd_owd"
fi

# L2: a benign path -> SILENT (no output, no new journal line). Pins the narrow
# threshold: routine edits do not trip the nudge (the #31.1 blanket-trap avoided).
L2_BEFORE=$(wc -l < "$DPNJ" 2>/dev/null || echo 0)
L2OUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/dpn-benign.txt"},"session_id":"dpnL"}' | CLAUDE_JOURNAL_PATH="$DPNJ" bash "$DPN" 2>/dev/null)
L2_AFTER=$(wc -l < "$DPNJ" 2>/dev/null || echo 0)
if [ -z "$L2OUT" ] && [ "$L2_BEFORE" = "$L2_AFTER" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s benign edit silent (no blanket fire)\n' "decision-nudge"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s benign: out=[%s] lines %s->%s\n' "decision-nudge" "$L2OUT" "$L2_BEFORE" "$L2_AFTER"
fi

