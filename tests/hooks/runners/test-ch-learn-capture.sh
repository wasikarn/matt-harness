#!/usr/bin/env bash
# test-ch-learn-capture.sh — the passive learning-capture pair (ADR 0002 addendum).
# learn-capture.sh (SessionEnd, default-OFF) harvests operator corrections/prefs from
# the transcript and APPENDS JSONL candidate rows to an out-of-repo queue; it must
# NEVER write when OFF, NEVER emit a permissionDecision, NEVER gate, and stay precise
# (a bare "no" / assistant text / quoted code must not be harvested). learn-drain-nudge.sh
# (SessionStart) reminds only when the queue has AGED rows, and never re-nags the same set.
# shellcheck disable=SC1090,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"

CAP="$HOOKS/session/learn-capture.sh"
NUDGE="$HOOKS/session/learn-drain-nudge.sh"

lcheck() {  # lcheck <rc> <label>
  if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); printf '  ✅ %-20s %s\n' "learn-capture" "$2"
  else FAIL=$((FAIL+1)); printf '  ❌ %-20s %s\n' "learn-capture" "$2"; fi
}

# helper: run the capture hook for a transcript, echo the resulting queue path
run_capture() {  # run_capture <proj-dir> <transcript-rel> <flag-on:1|0>
  local proj="$1" tname="$2" on="$3"
  local t="$proj/$tname"
  local env_flag=()
  [ "$on" = "1" ] && env_flag=(KBG_LEARN_CAPTURE=1)
  printf '%s' "{\"transcript_path\":\"$t\",\"session_id\":\"sess\"}" \
    | env "${env_flag[@]}" bash "$CAP" >/dev/null 2>&1
}

queue_of() { echo "$1/memory/_candidates/queue.jsonl"; }
count_rows() { [ -f "$1" ] && /usr/bin/grep -c . "$1" 2>/dev/null || echo 0; }

# ── 1. OFF (default) → exit 0, no queue written ──────────────────────
P1="$FIXTURE/p1"; mkdir -p "$P1"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"no, use ripgrep not grep"}}' > "$P1/t.jsonl"
RC=0
printf '%s' "{\"transcript_path\":\"$P1/t.jsonl\",\"session_id\":\"s\"}" | bash "$CAP" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ];                       lcheck $? "OFF: exit 0"
[ ! -f "$(queue_of "$P1")" ];         lcheck $? "OFF: no queue file written"

# ── 2. ON + a real correction → exactly 1 row, kind=correction ───────
P2="$FIXTURE/p2"; mkdir -p "$P2"
cat > "$P2/t.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"no, use ripgrep not grep for this"}}
{"type":"assistant","message":{"role":"assistant","content":"ok, I'll use ripgrep"}}
JSONL
run_capture "$P2" t.jsonl 1
Q2="$(queue_of "$P2")"
[ "$(count_rows "$Q2")" -eq 1 ];      lcheck $? "ON: one correction → 1 row"
KIND=$(jq -r '.kind' "$Q2" 2>/dev/null | head -1)
[ "$KIND" = "correction" ];           lcheck $? "ON: row kind=correction"
NOCONF=$(jq -e 'has("confidence")|not' "$Q2" >/dev/null 2>&1 && echo ok)
[ "$NOCONF" = "ok" ];                 lcheck $? "ON: NO confidence field at capture"

# ── 3. precision: adversarial near-misses → 0 rows ───────────────────
P3="$FIXTURE/p3"; mkdir -p "$P3"
cat > "$P3/t.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"no"}}
{"type":"user","message":{"role":"user","content":"yes please continue"}}
{"type":"assistant","message":{"role":"assistant","content":"no, use X not Y"}}
{"type":"user","message":{"role":"user","content":"run `# no, use X not Y` in the file"}}
{"type":"user","message":{"role":"user","content":"No, I agree with your approach"}}
{"type":"user","message":{"role":"user","content":"never mind, I was confused"}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"no, use X not Y"}]}}
JSONL
run_capture "$P3" t.jsonl 1
Q3="$(queue_of "$P3")"
[ "$(count_rows "$Q3")" -eq 0 ];      lcheck $? "precision: bare-no / affirm / assistant / quoted / 'No,I agree' / 'never mind' / tool_result → 0 rows"

# ── 4. dedupe: same correction twice in one session → 1 row ──────────
P4="$FIXTURE/p4"; mkdir -p "$P4"
cat > "$P4/t.jsonl" <<'JSONL'
{"type":"user","message":{"role":"user","content":"no, use ripgrep not grep"}}
{"type":"user","message":{"role":"user","content":"no, use ripgrep not grep"}}
JSONL
run_capture "$P4" t.jsonl 1
[ "$(count_rows "$(queue_of "$P4")")" -eq 1 ]; lcheck $? "dedupe: identical correction → 1 row"

# ── 5. secret-scrub: a credential in the trigger → row dropped ───────
P5="$FIXTURE/p5"; mkdir -p "$P5"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"no, use the api_key sk-abcdefghijklmnopqrstuvwxyz12 not the old one"}}' > "$P5/t.jsonl"
run_capture "$P5" t.jsonl 1
[ "$(count_rows "$(queue_of "$P5")")" -eq 0 ]; lcheck $? "secret-scrub: secret in evidence → whole row dropped"

# ── 6. never a permissionDecision; always exit 0 ─────────────────────
OUT=$(printf '%s' "{\"transcript_path\":\"$P2/t.jsonl\",\"session_id\":\"s\"}" | env KBG_LEARN_CAPTURE=1 bash "$CAP" 2>/dev/null)
printf '%s' "$OUT" | /usr/bin/grep -q "permissionDecision"; [ $? -ne 0 ]; lcheck $? "never emits a permissionDecision"

# ── 7. drain-nudge: aged backlog fires; fresh queue stays silent ─────
NH="$FIXTURE/nudge-home"; PROJ="/tmp/learn-proj-x"
SLUG=$(printf '%s' "$PROJ" | sed 's|/|-|g')
QDIR="$NH/.claude/projects/$SLUG/memory/_candidates"; mkdir -p "$QDIR"
OLD=$(python3 -c "import datetime as d;print((d.date.today()-d.timedelta(days=20)).isoformat())")
: > "$QDIR/queue.jsonl"
for i in 1 2 3 4 5 6; do
  printf '{"kind":"correction","trigger":"t%s","evidence":"e%s","status":"open","first_seen":"%s","last_seen":"%s","seen_count":1}\n' "$i" "$i" "$OLD" "$OLD" >> "$QDIR/queue.jsonl"
done
NOUT=$(printf '%s' '{"source":"startup"}' | env HOME="$NH" CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>/dev/null)
printf '%s' "$NOUT" | /usr/bin/grep -q "await review"; lcheck $? "drain-nudge: aged backlog → fires"
# second run, same set → hash-gated silence
NOUT2=$(printf '%s' '{"source":"startup"}' | env HOME="$NH" CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>/dev/null)
[ -z "$NOUT2" ];                      lcheck $? "drain-nudge: same set → no re-nag (hash-gated)"
# fresh rows (today) → below age threshold → silent
NH2="$FIXTURE/nudge-home2"; QDIR2="$NH2/.claude/projects/$SLUG/memory/_candidates"; mkdir -p "$QDIR2"
NOW=$(python3 -c "import datetime as d;print(d.date.today().isoformat())")
for i in 1 2 3 4 5 6; do
  printf '{"kind":"correction","trigger":"t%s","evidence":"e%s","status":"open","first_seen":"%s","last_seen":"%s","seen_count":1}\n' "$i" "$i" "$NOW" "$NOW" >> "$QDIR2/queue.jsonl"
done
NOUT3=$(printf '%s' '{"source":"startup"}' | env HOME="$NH2" CLAUDE_PROJECT_DIR="$PROJ" bash "$NUDGE" 2>/dev/null)
[ -z "$NOUT3" ];                      lcheck $? "drain-nudge: fresh rows (<7d) → silent"

report
