# shellcheck disable=SC1090,SC1091,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-journal-phaseii.sh — standalone suite run by test-critical-hooks.sh
# Covers: C1 Phase II (L1, L2, M, N, N2, P, O, R, S, T, U, V, W, X, Y, Z, AA, BB).

# --- C1 Phase II: id-echo additive + non-hook emitter + journaler + registry ---
# The journaler is the /review-pr producer bridge. (L)/(M)/(N)/(O) prove each
# piece of the Phase II contract in isolation; (K) above already proved the
# gate↔evidence separation is intact (the new scripts live in claude/scripts/,
# which audit #29 does NOT scan — verified at audit.sh:666 `for f in hooks/*.sh`).
SCRIPTS="$HOOKS/../scripts"

# (L1) _lib.py:journal_append emits a valid nested-envelope event AND prints
# the minted id on stdout. The id in stdout == the id in the journal file.
# Replaces the journal-emit.sh test that pre-dated the python port (2026-06-09).
: > "$JPATH"
# Set the SID to the journaler hook id (the bash version's self-fallback at
# journal-emit.sh:16 — `SID="${CLAUDE_SESSION_ID:-review-pr-journaler}"` —
# produced the same effect: when the parent shell doesn't propagate a
# session, the journaler attributes the events to itself).
JE=$(CLAUDE_SESSION_ID="review-pr-journaler" CLAUDE_JOURNAL_PATH="$JPATH" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _lib; _lib.journal_append("review-pr-journaler", "review_finding", sys.argv[2])' \
     "$HOOKS" \
     '{"local_id":"L1","file":"a.py","line":1,"tier":"Minor","agent":"code-reviewer","summary":"x"}' 2>/dev/null)
if [ -n "$JE" ] && [ "$JE" = "$(jq -r .id "$JPATH")" ] \
   && [ "$(jq -r '.event' "$JPATH")" = "review_finding" ] \
   && [ "$(jq -r '.fields.tier' "$JPATH")" = "Minor" ] \
   && [ "$(jq -r '.fields.local_id' "$JPATH")" = "L1" ] \
   && [ "$(jq -r '.session' "$JPATH")" = "review-pr-journaler" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s emits review_finding, prints id == file id, session fallback correct\n' "_lib.py:journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s emit/id/session mismatch: stdout=%s file=%s\n' "_lib.py:journal_append" "$JE" "$(cat "$JPATH")"
fi

# (L2) _lib.py:journal_append SID-fallback: when CLAUDE_SESSION_ID is unset
# AND the caller does not set os.environ.setdefault, the envelope stamps
# `session: "no-sid"` (per _lib.py:109 `os.environ.get("CLAUDE_SESSION_ID",
# "no-sid")`).
: > "$JPATH"
JE2=$(unset CLAUDE_SESSION_ID; CLAUDE_JOURNAL_PATH="$JPATH" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import _lib; _lib.journal_append("test-hook", "review_finding", sys.argv[2])' \
      "$HOOKS" \
      '{"local_id":"L2","file":"a.py","line":1,"tier":"Minor","agent":"code-reviewer","summary":"x"}' 2>/dev/null)
if [ -n "$JE2" ] && [ "$(jq -r '.session' "$JPATH")" = "no-sid" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s session==no-sid when CLAUDE_SESSION_ID unset (no caller setdefault)\n' "_lib.py:journal_append:no-sid"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s session-fallback unset branch: stdout=%s file=%s\n' "_lib.py:journal_append:no-sid" "$JE2" "$(cat "$JPATH")"
fi

# (M) review-pr-journal.py: findings.jsonl → 1 review_finding + 1 verification_verdict
# per finding; verdict.subject_id == finding.id; finding.fields.local_id ==
# findings.jsonl's local_id (human-readability invariant). The linkage the
# SCRUTINIZE disposition depends on (without it, the journaler would emit
# orphan verdicts).
SDIR="$FIXTURE/rj-sdir"; rm -rf "$SDIR"; mkdir -p "$SDIR"
printf '%s\n' \
  '{"local_id":"F1","file":"a.py","line":10,"tier":"Critical","disposition":"survived","decision":"fix-now","agent":"code-reviewer","rejected_reason":"","summary":"unwrap None"}' \
  '{"local_id":"F2","file":"b.py","line":20,"tier":"Minor","disposition":"rejected","decision":"proceed","agent":"security-reviewer","rejected_reason":"Q3 happy path only","summary":"old kex"}' \
  > "$SDIR/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR" 2>/dev/null
N_EVT=$(wc -l < "$JPATH" | tr -d ' ')
N_FIND=$(grep -c '"event":"review_finding"' "$JPATH" || true)
N_VERD=$(grep -c '"event":"verification_verdict"' "$JPATH" || true)
# Linkage: for each review_finding, find its verdict and assert subject_id match.
LINK_OK=1
while IFS= read -r fid; do
  sid=$(jq -r --arg fid "$fid" 'select(.fields.subject_id==$fid) | .id' "$JPATH")
  [ -n "$sid" ] || { LINK_OK=0; break; }
done < <(jq -r 'select(.event=="review_finding") | .id' "$JPATH")
# local_id is preserved in finding.fields (human-readability, not linkage).
LID_F1=$(jq -r 'select(.event=="review_finding" and .fields.local_id=="F1") | .id' "$JPATH")
LID_F2=$(jq -r 'select(.event=="review_finding" and .fields.local_id=="F2") | .id' "$JPATH")
# Manifest: per-pair JSONL line, 2 entries, both local_ids present.
N_MANIFEST=$(wc -l < "$SDIR/.journaled" | tr -d ' ')
MANIFEST_F1=$(grep -c '"local_id":"F1"' "$SDIR/.journaled" || true)
MANIFEST_F2=$(grep -c '"local_id":"F2"' "$SDIR/.journaled" || true)
if [ "$N_EVT" = 4 ] && [ "$N_FIND" = 2 ] && [ "$N_VERD" = 2 ] && [ "$LINK_OK" = 1 ] \
   && [ -n "$LID_F1" ] && [ -n "$LID_F2" ] \
   && [ "$N_MANIFEST" = 2 ] && [ "$MANIFEST_F1" = 1 ] && [ "$MANIFEST_F2" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s 2 finding+verdict pairs, verdict.subject_id == finding.id, local_id preserved, manifest=2\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s n_find=%s n_verd=%s link_ok=%s lid_f1=%s lid_f2=%s manifest=%s mf1=%s mf2=%s\n' "review-pr-journal.py" "$N_EVT" "$N_FIND" "$N_VERD" "$LINK_OK" "$LID_F1" "$LID_F2" "$N_MANIFEST" "$MANIFEST_F1" "$MANIFEST_F2"
fi

# (N) review-pr-journal.py idempotency: a second run on the same scratch dir
# no-ops (every local_id in findings.jsonl is already in the manifest) and
# does NOT double-write the journal.
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR" 2>/dev/null
N_EVT2=$(wc -l < "$JPATH" | tr -d ' ')
N_MANIFEST2=$(wc -l < "$SDIR/.journaled" | tr -d ' ')
if [ "$N_EVT2" = 4 ] && [ -e "$SDIR/.journaled" ] && [ "$N_MANIFEST2" = 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s re-run no-ops (manifest skip, no double-write)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt_after_rerun=%s marker=%s n_manifest=%s\n' "review-pr-journal.py" "$N_EVT2" "$([ -e "$SDIR/.journaled" ] && echo yes || echo no)" "$N_MANIFEST2"
fi

# (N2) review-pr-journal.py partial-run recovery: simulate "first run got
# K of N findings journaled, then SIGTERM" by pre-writing a partial
# manifest with K entries, then re-run and assert the second run skips
# the K already-emitted findings and emits only the remaining N-K.
SDIR2="$FIXTURE/rj-sdir2"; rm -rf "$SDIR2"; mkdir -p "$SDIR2"
printf '%s\n' \
  '{"local_id":"P1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"p1"}' \
  '{"local_id":"P2","file":"b.py","line":2,"tier":"Minor","disposition":"rejected","decision":"fix-now","agent":"y","rejected_reason":"q","summary":"p2"}' \
  '{"local_id":"P3","file":"c.py","line":3,"tier":"Critical","disposition":"survived","decision":"fix-now","agent":"z","rejected_reason":"","summary":"p3"}' \
  > "$SDIR2/findings.jsonl"
# Pre-seed manifest as if P1 and P2 were journaled in a prior partial run.
printf '%s\n' \
  '{"local_id":"P1","finding_id":"fake-id-1","verdict_id":"fake-id-2"}' \
  '{"local_id":"P2","finding_id":"fake-id-3","verdict_id":"fake-id-4"}' \
  > "$SDIR2/.journaled"
# Pre-seed the journal file with the 4 events from the prior partial run.
printf '%s\n' \
  '{"id":"fake-id-1","ts":"2026-06-08T12:00:00.000Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"local_id":"P1","file":"a.py","line":1,"tier":"Minor","agent":"x","summary":"p1"}}' \
  '{"id":"fake-id-2","ts":"2026-06-08T12:00:00.001Z","session":"s","hook":"review-pr-journaler","event":"verification_verdict","source":"journal_append","fields":{"subject_id":"fake-id-1","disposition":"survived","tier":"Minor","decision":"proceed","rejected_reason":""}}' \
  '{"id":"fake-id-3","ts":"2026-06-08T12:00:00.002Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"local_id":"P2","file":"b.py","line":2,"tier":"Minor","agent":"y","summary":"p2"}}' \
  '{"id":"fake-id-4","ts":"2026-06-08T12:00:00.003Z","session":"s","hook":"review-pr-journaler","event":"verification_verdict","source":"journal_append","fields":{"subject_id":"fake-id-3","disposition":"rejected","tier":"Minor","decision":"fix-now","rejected_reason":"q"}}' \
  > "$JPATH"
# Re-run the journaler; it should skip P1+P2 and emit only P3.
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR2" 2>/dev/null
N_EVT3=$(wc -l < "$JPATH" | tr -d ' ')
N_FIND3=$(grep -c '"event":"review_finding"' "$JPATH" || true)
N_VERD3=$(grep -c '"event":"verification_verdict"' "$JPATH" || true)
N_MANIFEST3=$(wc -l < "$SDIR2/.journaled" | tr -d ' ')
# After retry: journal = 4 (pre-seed) + 2 (P3 pair) = 6, manifest = 2 (pre-seed) + 1 (P3) = 3.
if [ "$N_EVT3" = 6 ] && [ "$N_FIND3" = 3 ] && [ "$N_VERD3" = 3 ] && [ "$N_MANIFEST3" = 3 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s partial-run: skip already-journaled, resume cleanly (P3 only)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 6) n_find=%s (want 3) n_verd=%s (want 3) n_manifest=%s (want 3)\n' "review-pr-journal.py" "$N_EVT3" "$N_FIND3" "$N_VERD3" "$N_MANIFEST3"
fi

# (P) review-pr-journal.py enum validation: a finding with a bad tier /
# disposition / decision emits a WARNING on stderr AND still emits the
# event (Q3=a "silent FYI, never unwinds" — journaler is best-effort, not
# a submit gate; the user sees the warning, the journal has the data).
SDIR3="$FIXTURE/rj-sdir3"; rm -rf "$SDIR3"; mkdir -p "$SDIR3"
printf '%s\n' \
  '{"local_id":"Q1","file":"a.py","line":1,"tier":"whoops","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"bad tier"}' \
  '{"local_id":"Q2","file":"b.py","line":2,"tier":"Minor","disposition":"maybe","decision":"proceed","agent":"y","rejected_reason":"","summary":"bad disp"}' \
  '{"local_id":"Q3","file":"c.py","line":3,"tier":"Minor","disposition":"rejected","decision":"eventually","agent":"z","rejected_reason":"","summary":"bad dec"}' \
  > "$SDIR3/findings.jsonl"
: > "$JPATH"
STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR3" 2>&1 >/dev/null || true)
N_EVT_P=$(wc -l < "$JPATH" | tr -d ' ')
# All 3 findings should have been journaled (best-effort, not blocked).
# All 3 should have produced a WARNING on stderr naming the local_id and
# the bad value.
WARN_TIER=$(printf '%s' "$STDERR" | grep -c "tier='whoops'" || true)
WARN_DISP=$(printf '%s' "$STDERR" | grep -c "disposition='maybe'" || true)
WARN_DEC=$(printf '%s' "$STDERR" | grep -c "decision='eventually'" || true)
if [ "$N_EVT_P" = 6 ] && [ "$WARN_TIER" = 1 ] && [ "$WARN_DISP" = 1 ] && [ "$WARN_DEC" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s bad enum: WARNING to stderr, journal still emits (best-effort)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 6) warn_tier=%s warn_disp=%s warn_dec=%s\n' "review-pr-journal.py" "$N_EVT_P" "$WARN_TIER" "$WARN_DISP" "$WARN_DEC"
fi

# (Q) REMOVED 2026-06-09: bash review-pr-journaler ported to _lib.py

# (O) governance-summary digests review_finding (and verification_verdict) without
# the "unknown event" warn that would fire if KNOWN_EVENTS hadn't been updated.
OHOME="$FIXTURE/ohome"; mkdir -p "$OHOME/.claude"
printf '%s\n' \
  '{"id":"1-rf-a","ts":"2026-06-08T12:00:00.000Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"file":"a.py","line":1,"tier":"Minor","agent":"x","summary":"y"}}' \
  '{"id":"2-vv-a","ts":"2026-06-08T12:00:00.001Z","session":"s","hook":"review-pr-journaler","event":"verification_verdict","source":"journal_append","fields":{"subject_id":"1-rf-a","disposition":"survived","tier":"Minor","decision":"proceed","rejected_reason":""}}' \
  > "$OHOME/.claude/governance-events.jsonl"
OUT=$(HOME="$OHOME" python3 "$GS" 2>/dev/null)
if printf '%s\n' "$OUT" | grep -q "review_finding" && ! printf '%s\n' "$OUT" | grep -qi "unknown event.*review_finding"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s review_finding digested, no unknown-event warn\n' "governance-summary"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s digest failed or registry lag\n' "governance-summary"
fi

# (R) review-pr-journal.py bails loud on a malformed .journaled manifest
SDIR5="$FIXTURE/rj-sdir5"; rm -rf "$SDIR5"; mkdir -p "$SDIR5"
printf '%s\n' \
  '{"local_id":"R1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"ok"}' \
  > "$SDIR5/findings.jsonl"
printf 'not-json-at-all\ngarbage line 2\n' > "$SDIR5/.journaled"
: > "$JPATH"
EXIT_CODE=0
STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR5" 2>&1 >/dev/null) || EXIT_CODE=$?
N_EVT_R=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$EXIT_CODE" = 2 ] \
   && printf '%s' "$STDERR" | grep -q "\.journaled" \
   && printf '%s' "$STDERR" | grep -q "refusing to retry" \
   && [ "$N_EVT_R" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s malformed manifest: exit 2, stderr names file, no events written\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 2) n_evt=%s (want 0) stderr=%s\n' "review-pr-journal.py" "$EXIT_CODE" "$N_EVT_R" "$STDERR"
fi

# (S) review-pr-journal.py fails loud on missing findings.jsonl
SDIR6="$FIXTURE/rj-sdir6"; rm -rf "$SDIR6"; mkdir -p "$SDIR6"
# Intentionally do NOT create findings.jsonl.
: > "$JPATH"
EXIT_CODE=0
STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR6" 2>&1 >/dev/null) || EXIT_CODE=$?
N_EVT_S=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$EXIT_CODE" = 2 ] \
   && printf '%s' "$STDERR" | grep -q "missing" \
   && printf '%s' "$STDERR" | grep -q "findings.jsonl" \
   && [ "$N_EVT_S" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s missing findings.jsonl: exit 2, stderr names path, no events written\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 2) n_evt=%s (want 0) stderr=%s\n' "review-pr-journal.py" "$EXIT_CODE" "$N_EVT_S" "$STDERR"
fi

# (T) review-pr-journal.py preserves `line: null` for review-body findings
SDIR7="$FIXTURE/rj-sdir7"; rm -rf "$SDIR7"; mkdir -p "$SDIR7"
printf '%s\n' \
  '{"local_id":"T1","file":"","line":null,"tier":"","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"review-body finding"}' \
  > "$SDIR7/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR7" 2>/dev/null
LINE_FIELD=$(grep '"event":"review_finding"' "$JPATH" | head -1 | jq -r '.fields.line')
N_EVT_T=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$N_EVT_T" = 2 ] && [ "$LINE_FIELD" = "null" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s review-body finding: line=null (JSON null, not string)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 2) fields.line=%q (want JSON null)\n' "review-pr-journal.py" "$N_EVT_T" "$LINE_FIELD"
fi

# (U) review-pr-journal.py JSON-escapes model-controlled ids on the manifest write
SDIR8="$FIXTURE/rj-sdir8"; rm -rf "$SDIR8"; mkdir -p "$SDIR8"
printf '%s\n' \
  '{"local_id":"U1\"with\nquote","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"escape probe"}' \
  > "$SDIR8/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR8" 2>/dev/null
ROUND_TRIP=$(jq -r '.local_id // empty' < "$SDIR8/.journaled" 2>/dev/null)
N_MANI=$(wc -l < "$SDIR8/.journaled" | tr -d ' ')
if [ "$N_MANI" = 1 ] && [ "$ROUND_TRIP" = 'U1"with
quote' ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest escapes adversarial local_id (parseable + round-trip)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_mani=%s (want 1) round_trip=%q (want the adversarial local_id)\n' "review-pr-journal.py" "$N_MANI" "$ROUND_TRIP"
fi

# (V) review-pr-journal.py writes a manifest line whose finding_id/verdict_id
# match the just-emitted journal event ids
SDIR9="$FIXTURE/rj-sdir9"; rm -rf "$SDIR9"; mkdir -p "$SDIR9"
printf '%s\n' \
  '{"local_id":"V1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"manifest-link probe"}' \
  > "$SDIR9/findings.jsonl"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR9" 2>/dev/null
J_FID=$(grep '"event":"review_finding"' "$JPATH" | head -1 | jq -r '.id // empty')
J_VID=$(grep '"event":"verification_verdict"' "$JPATH" | head -1 | jq -r '.id // empty')
M_FID=$(jq -r '.finding_id // empty' < "$SDIR9/.journaled")
M_VID=$(jq -r '.verdict_id // empty' < "$SDIR9/.journaled")
N_EVT_V=$(wc -l < "$JPATH" | tr -d ' ')
N_MANI_V=$(wc -l < "$SDIR9/.journaled" | tr -d ' ')
if [ "$N_EVT_V" = 2 ] && [ "$N_MANI_V" = 1 ] \
   && [ -n "$J_FID" ] && [ "$J_FID" = "$M_FID" ] \
   && [ -n "$J_VID" ] && [ "$J_VID" = "$M_VID" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest finding_id/verdict_id match journal event ids\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s n_mani=%s j_fid=%s m_fid=%s j_vid=%s m_vid=%s\n' "review-pr-journal.py" "$N_EVT_V" "$N_MANI_V" "$J_FID" "$M_FID" "$J_VID" "$M_VID"
fi

# (W) review-pr-journal.py dedup is keyed on .local_id, NOT on .file/.tier/etc.
SDIR10="$FIXTURE/rj-sdir10"; rm -rf "$SDIR10"; mkdir -p "$SDIR10"
cat > "$SDIR10/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"W1\"with\nquote","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"dedup probe A"}
{"local_id":"W2\"with\nquote","file":"a.py","line":2,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"dedup probe B"}
FIXTURE_EOF
: > "$JPATH"
# First run: 2 fresh local_ids → 2 pairs emitted (n_evt=4 events).
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR10" 2>/dev/null
# Second run: both local_ids already in manifest → 0 pairs emitted.
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR10" 2>/dev/null
N_EVT_W=$(wc -l < "$JPATH" | tr -d ' ')
N_MANI_W=$(wc -l < "$SDIR10/.journaled" | tr -d ' ')
MANI_LIDS=$(jq -r '.local_id // empty' < "$SDIR10/.journaled" 2>/dev/null | sort | tr '\n' '|')
EXPECT_LID_A=$(printf '%b' 'W1"with\nquote')
EXPECT_LID_B=$(printf '%b' 'W2"with\nquote')
EXPECT_LIDS=$(printf '%s\n%s\n' "$EXPECT_LID_A" "$EXPECT_LID_B" | sort | tr '\n' '|')
if [ "$N_EVT_W" = 4 ] && [ "$N_MANI_W" = 2 ] && [ "$MANI_LIDS" = "$EXPECT_LIDS" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s dedup keyed on local_id (n_evt=4, n_mani=2, both A and B present)\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1))
  if [ "$N_EVT_W" != 4 ] || [ "$N_MANI_W" != 2 ]; then
    printf '  ❌ %-26s n_evt=%s (want 4) n_mani=%s (want 2) — dedup collapsed distinct local_ids (wrong-field IX)\n' "review-pr-journal.py" "$N_EVT_W" "$N_MANI_W" >&2
  else
    printf '  ❌ %-26s n_evt=4 n_mani=2 but MANI_LIDS≠EXPECT — manifest lost a local_id\n' "review-pr-journal.py" >&2
  fi
fi

# (X) review-pr-journal.py handles findings with a null or missing .local_id
SDIR11="$FIXTURE/rj-sdir11"; rm -rf "$SDIR11"; mkdir -p "$SDIR11"
cat > "$SDIR11/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":null,"file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"null local_id probe"}
{"file":"b.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"missing local_id probe"}
{"local_id":"","file":"c.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"empty local_id probe"}
FIXTURE_EOF
: > "$JPATH"
STDERR_X=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR11" 2>&1 >/dev/null || true)
N_EVT_X=$(wc -l < "$JPATH" | tr -d ' ')
N_MANI_X=0
if [ -e "$SDIR11/.journaled" ]; then
  N_MANI_X=$(wc -l < "$SDIR11/.journaled" | tr -d ' ')
fi
N_ERR_X=$(printf '%s\n' "$STDERR_X" | grep -c "review-pr-journal: ERROR: finding at offset" || true)
if [ "$N_EVT_X" = 0 ] && [ "$N_MANI_X" = 0 ] && [ "$N_ERR_X" = 3 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s null/missing/empty local_id → 3 errors, 0 events, 0 manifest lines\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 0) n_mani=%s (want 0) n_err=%s (want 3)\n' "review-pr-journal.py" "$N_EVT_X" "$N_MANI_X" "$N_ERR_X" >&2
fi

# (Y) review-pr-journal.py dedup INDEX last-wins on duplicate manifest entries
SDIR12="$FIXTURE/rj-sdir12"; rm -rf "$SDIR12"; mkdir -p "$SDIR12"
cat > "$SDIR12/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"Y1","file":"a.py","line":1,"tier":"Minor","disposition":"survived","decision":"proceed","agent":"x","rejected_reason":"","summary":"dup-manifest probe A"}
FIXTURE_EOF
jq -nc '{local_id:"Y1",finding_id:"fake-fid-1",verdict_id:"fake-vid-1"}' > "$SDIR12/.journaled"
jq -nc '{local_id:"Y1",finding_id:"fake-fid-2",verdict_id:"fake-vid-2"}' >> "$SDIR12/.journaled"
: > "$JPATH"
CLAUDE_JOURNAL_PATH="$JPATH" python3 "$SCRIPTS/pr/review-pr-journal.py" "$SDIR12" 2>/dev/null
N_EVT_Y=$(wc -l < "$JPATH" | tr -d ' ')
N_MANI_Y=$(wc -l < "$SDIR12/.journaled" | tr -d ' ')
if [ "$N_EVT_Y" = 0 ] && [ "$N_MANI_Y" = 2 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s dup-manifest entries: dedup last-wins, no emit, manifest unchanged\n' "review-pr-journal.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 0) n_mani=%s (want 2)\n' "review-pr-journal.py" "$N_EVT_Y" "$N_MANI_Y" >&2
fi

# (Z) _lib.py:journal_append fail-loud on non-serializable dict values
: > "$JPATH"
JE_Z=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import _lib
import os; os.environ["CLAUDE_JOURNAL_PATH"] = sys.argv[2]
_lib.journal_append("test-hook", "config_change", {"file": set([1,2])})
' "$HOOKS" "$JPATH" 2>&1)
RC_Z=$?
N_EVT_Z=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$RC_Z" = 2 ] && [ "$N_EVT_Z" = 0 ] && printf '%s' "$JE_Z" | grep -q "TypeError"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s non-serializable dict → exit 2 (TypeError caught, no partial write)\n' "_lib.py:journal_append"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s (want 2) n_evt=%s (want 0) stderr=%s\n' "_lib.py:journal_append" "$RC_Z" "$N_EVT_Z" "$JE_Z" >&2
fi

# (AA) _lib.py:_redact byte-for-byte equivalent to bash `val_dl` for the keyword substring
: > "$JPATH"
AA_OUT=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import _lib
import os; os.environ["CLAUDE_JOURNAL_PATH"] = sys.argv[2]
_lib.journal_append("test-hook", "config_change",
                    {"description": "the user password is leaked"})
' "$HOOKS" "$JPATH" 2>/dev/null)
REDACTED=$(grep '"event":"config_change"' "$JPATH" | head -1 | jq -r '.fields.description')
if [ "$REDACTED" = "[redacted]" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s value-keyword redact matches bash (password|secret|token|credential)\n' "_lib.py:_redact"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s fields.description=%q (want "[redacted]")\n' "_lib.py:_redact" "$REDACTED" >&2
fi

# (BB) _lib.py:_redact emits a stderr WARNING when the depth cap fires
: > "$JPATH"
BB_STDERR=$(CLAUDE_JOURNAL_PATH="$JPATH" python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import _lib
import os; os.environ["CLAUDE_JOURNAL_PATH"] = sys.argv[2]
deep = {"leaf": "value"}; d = deep
for _ in range(100): d["n"] = {"a": 1}; d = d["n"]
_lib.journal_append("test-hook", "config_change", deep)
' "$HOOKS" "$JPATH" 2>&1 >/dev/null)
N_EVT_BB=$(wc -l < "$JPATH" | tr -d ' ')
if [ "$N_EVT_BB" = 1 ] && printf '%s' "$BB_STDERR" | grep -q "WARNING.*depth-capped"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s depth-capped at 64 → stderr WARNING + 1 journal line (no crash)\n' "_lib.py:_redact"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s n_evt=%s (want 1) stderr=%s\n' "_lib.py:_redact" "$N_EVT_BB" "$BB_STDERR" >&2
fi
