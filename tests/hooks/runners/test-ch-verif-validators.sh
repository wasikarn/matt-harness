# shellcheck disable=SC1090,SC1091,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-verif-validators.sh — standalone suite run by test-critical-hooks.sh
# Covers: verification-gate (11 tests), verification-tier-audit (2 tests),
#         review-pr-journal-pre-emit-validator (4 tests CC/DD/EE/FF),
#         recursive-improve-observe.py (7 tests).

# --- verification-gate: trails-only SessionEnd sensor (advisory, non-blocking) ---
# Phase-3 verification-doctrine gate: reads .scratch/*/verification-trail.md under
# CLAUDE_PROJECT_DIR, reports the verification_tier mix, flags a no-trail declared
# without a reason, journals a verification_summary event, and NEVER emits a
# permissionDecision (pure sensor — honors gate↔evidence separation, audit #29).
echo
echo "--- verification-gate: trails-only SessionEnd sensor ---"
VGROOT="$FIXTURE/vgroot"
mkdir -p "$VGROOT/.scratch/feat-a" "$VGROOT/.scratch/feat-b"
printf '# Verification trail: feat-a\n- verification_tier: tdd-provenance\n- red_green: aaa111 → bbb222\n- pr_test_analyzer: pass\n- optout_reason: n/a\n' > "$VGROOT/.scratch/feat-a/verification-trail.md"
printf '# Verification trail: feat-b\n- verification_tier: no-trail\n- red_green: n/a\n- pr_test_analyzer: not-run\n- optout_reason:\n' > "$VGROOT/.scratch/feat-b/verification-trail.md"
VGJOURNAL="$FIXTURE/vg-journal.jsonl"; : > "$VGJOURNAL"
VGEVENT='{"session_id":"vg-test","hook_event_name":"SessionEnd"}'
VGOUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VGROOT" CLAUDE_JOURNAL_PATH="$VGJOURNAL" bash "$HOOKS/session/verification-gate.sh" 2>/dev/null); VGRC=$?

# (1) exits 0 (never blocks session end) AND emits NO permissionDecision (pure sensor)
if [ "$VGRC" = 0 ] && ! printf '%s' "$VGOUT" | grep -q 'permissionDecision'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s exit 0, no permissionDecision (non-blocking sensor)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q\n' "verification-gate.sh" "$VGRC" "$VGOUT"
fi

# (2) advisory names the tier mix (tdd-provenance + no-trail both present this session)
if printf '%s' "$VGOUT" | grep -q 'tdd-provenance' && printf '%s' "$VGOUT" | grep -q 'no-trail'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s advisory reports the session tier mix\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s tier mix missing from output: %q\n' "verification-gate.sh" "$VGOUT"
fi

# (3) flags the gap: feat-b is no-trail with an empty optout_reason
if printf '%s' "$VGOUT" | grep -q 'feat-b'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s flags no-trail without a reason (feat-b)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s did not flag the no-trail gap: %q\n' "verification-gate.sh" "$VGOUT"
fi

# (4) journals a verification_summary event with the real session id + counts
if jq -se 'any(.[]; .event=="verification_summary" and .session=="vg-test" and .fields.features==2 and .fields.no_trail==1 and .fields.tdd_provenance==1 and .fields.gaps==1)' "$VGJOURNAL" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s journals verification_summary {features:2,no_trail:1,gaps:1}\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s verification_summary event wrong/absent: %s\n' "verification-gate.sh" "$(cat "$VGJOURNAL")"
fi

# (5) trail-less project: exit 0, no crash, no verification_summary journaled (no noise)
VGROOT2="$FIXTURE/vgroot-empty"; mkdir -p "$VGROOT2/.scratch/nothing"
VGJOURNAL2="$FIXTURE/vg-journal2.jsonl"; : > "$VGJOURNAL2"
VGOUT2=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VGROOT2" CLAUDE_JOURNAL_PATH="$VGJOURNAL2" bash "$HOOKS/session/verification-gate.sh" 2>/dev/null); VGRC2=$?
if [ "$VGRC2" = 0 ] && ! grep -q 'verification_summary' "$VGJOURNAL2" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ %-26s trail-less session: exit 0, no event journaled (no noise)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s journal=%s\n' "verification-gate.sh" "$VGRC2" "$(cat "$VGJOURNAL2")"
fi

# (6) richer mix — proves analyzer-pass IS counted, multi-gap accumulation works,
#     and an empty/typo/missing/"none" verification_tier is surfaced as a GAP (not
#     silently misclassified — refutes the review's swallowed-error claim), while a
#     real optout_reason is NOT a gap. 7 feats → f=7, tdd=1, analyzer=1, no_trail=3, gaps=4.
VG3="$FIXTURE/vgroot3"
mkdir -p "$VG3"/.scratch/a-tdd "$VG3"/.scratch/b-analyzer "$VG3"/.scratch/c-reason \
         "$VG3"/.scratch/d-empty "$VG3"/.scratch/e-typo "$VG3"/.scratch/f-notier "$VG3"/.scratch/g-none
printf '# t\n- verification_tier: tdd-provenance\n'  > "$VG3/.scratch/a-tdd/verification-trail.md"
printf '# t\n- verification_tier: analyzer-pass\n'   > "$VG3/.scratch/b-analyzer/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason: docs-only, no behavior to assert\n' > "$VG3/.scratch/c-reason/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason:\n'      > "$VG3/.scratch/d-empty/verification-trail.md"
printf '# t\n- verification_tier: bogus-typo\n'      > "$VG3/.scratch/e-typo/verification-trail.md"
printf '# t\n- red_green: n/a\n'                     > "$VG3/.scratch/f-notier/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason: none\n' > "$VG3/.scratch/g-none/verification-trail.md"
VGJ3="$FIXTURE/vg-journal3.jsonl"; : > "$VGJ3"
VG3_OUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG3" CLAUDE_JOURNAL_PATH="$VGJ3" bash "$HOOKS/session/verification-gate.sh" 2>/dev/null); VG3_RC=$?
if [ "$VG3_RC" = 0 ] && jq -se 'any(.[]; .event=="verification_summary" and .fields.features==7 and .fields.tdd_provenance==1 and .fields.analyzer_pass==1 and .fields.no_trail==3 and .fields.gaps==4)' "$VGJ3" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s counts analyzer-pass; typo/missing/none/empty are gaps, reasoned no-trail is not (f=7,gaps=4)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s counts wrong: %s\n' "verification-gate.sh" "$VG3_RC" "$(cat "$VGJ3")"
fi

# (7) gap advisory names EVERY gap slug (accumulation) and omits the reasoned no-trail
if printf '%s' "$VG3_OUT" | grep -q 'd-empty' && printf '%s' "$VG3_OUT" | grep -q 'e-typo' \
   && printf '%s' "$VG3_OUT" | grep -q 'f-notier' && printf '%s' "$VG3_OUT" | grep -q 'g-none' \
   && ! printf '%s' "$VG3_OUT" | grep -q 'c-reason'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s gap advisory lists all 4 gaps, omits the reasoned no-trail\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s gap slug list wrong: %q\n' "verification-gate.sh" "$VG3_OUT"
fi

# (8) journal_append failure (jq GUARANTEED absent) must NOT break the non-blocking
#     contract: gate still exits 0 AND still prints the advisory. (Same jq-absent
#     PATH technique as the journal_append fail-loud case above.)
VGBIN="$FIXTURE/vgbin"; mkdir -p "$VGBIN"
for b in bash sed find basename dirname tr head cat python3 mkdir grep; do ln -sf "$(command -v "$b")" "$VGBIN/$b" 2>/dev/null; done
VGJF="$FIXTURE/vg-journalfail.jsonl"; : > "$VGJF"
VGJF_OUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG3" CLAUDE_JOURNAL_PATH="$VGJF" PATH="$VGBIN" bash "$HOOKS/session/verification-gate.sh" 2>/dev/null); VGJF_RC=$?
if [ "$VGJF_RC" = 0 ] && printf '%s' "$VGJF_OUT" | grep -q 'session verification'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s journal fail (no jq) → still exit 0 + advisory (non-blocking)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q\n' "verification-gate.sh" "$VGJF_RC" "$VGJF_OUT"
fi

# (9) no .scratch dir at all → exit 0 silently, nothing journaled (the -d guard)
VG4="$FIXTURE/vgroot4-noscratch"; mkdir -p "$VG4"
VGJ4="$FIXTURE/vg-journal4.jsonl"; : > "$VGJ4"
VG4_OUT=$(printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG4" CLAUDE_JOURNAL_PATH="$VGJ4" bash "$HOOKS/session/verification-gate.sh" 2>/dev/null); VG4_RC=$?
if [ "$VG4_RC" = 0 ] && [ -z "$VG4_OUT" ] && ! grep -q 'verification_summary' "$VGJ4" 2>/dev/null; then
  PASS=$((PASS+1)); printf '  ✅ %-26s no .scratch dir → exit 0 silent, nothing journaled\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q journal=%s\n' "verification-gate.sh" "$VG4_RC" "$VG4_OUT" "$(cat "$VGJ4")"
fi

# (10) F4: gaps>0 → exit_reason="degrading" in the journaled verification_summary.
#     Reuses the VGROOT fixture (feat-a tdd-provenance, feat-b no-trail w/ blank reason → 1 gap).
if jq -se 'any(.[]; .event=="verification_summary" and .session=="vg-test" and .fields.exit_reason=="degrading" and .fields.gaps==1)' "$VGJOURNAL" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s exit_reason="degrading" when gaps>0 (F4)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit_reason wrong on gap session: %s\n' "verification-gate.sh" "$(cat "$VGJOURNAL")"
fi

# (11) F4: clean session (no gaps) → exit_reason="complete". Builds a fresh fixture:
#     one feature with a real trail, one with a no-trail+reasoned optout → 0 gaps.
VG5="$FIXTURE/vgroot5-clean"
mkdir -p "$VG5/.scratch/feat-good" "$VG5/.scratch/feat-reasoned"
printf '# t\n- verification_tier: tdd-provenance\n' > "$VG5/.scratch/feat-good/verification-trail.md"
printf '# t\n- verification_tier: no-trail\n- optout_reason: docs-only, no behavior to assert\n' > "$VG5/.scratch/feat-reasoned/verification-trail.md"
VGJ5="$FIXTURE/vg-journal5.jsonl"; : > "$VGJ5"
( cd "$VG5" >/dev/null; printf '%s' "$VGEVENT" | CLAUDE_PROJECT_DIR="$VG5" CLAUDE_JOURNAL_PATH="$VGJ5" bash "$HOOKS/session/verification-gate.sh" >/dev/null 2>&1 ) || true
if jq -se 'any(.[]; .event=="verification_summary" and .session=="vg-test" and .fields.exit_reason=="complete" and .fields.gaps==0 and .fields.features==2)' "$VGJ5" >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s exit_reason="complete" on clean session (F4)\n' "verification-gate.sh"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit_reason wrong on clean session: %s\n' "verification-gate.sh" "$(cat "$VGJ5")"
fi

# --- verification-tier-audit.py: retro-grader (declared trail authoritative; fallback no-trail) ---
echo
echo "--- verification-tier-audit: retro-grader ---"
VTA="$FIXTURE/vta"
mkdir -p "$VTA/.scratch/synthfeat" "$VTA/.scratch/baretask"
printf '# Verification trail: synthfeat\n- verification_tier: tdd-provenance\n- red_green: c0ffee → f00df00d\n- pr_test_analyzer: pass\n' > "$VTA/.scratch/synthfeat/verification-trail.md"
printf '# Acceptance: baretask\n' > "$VTA/.scratch/baretask/ACCEPTANCE.md"
VTA_OUT=$(python3 "$HOOKS/../scripts/governance/verification-tier-audit.py" --root "$VTA" synthfeat baretask 2>/dev/null); VTA_RC=$?

# (1) a declared verification-trail.md tier is authoritative
if [ "$VTA_RC" = 0 ] && printf '%s' "$VTA_OUT" | grep -E 'synthfeat' | grep -q 'tdd-provenance'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s reads declared verification_tier from trail\n' "verification-tier-audit.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s rc=%s out=%q\n' "verification-tier-audit.py" "$VTA_RC" "$VTA_OUT"
fi

# (2) no trail + no tests/evals → graded no-trail (fallback branch)
if printf '%s' "$VTA_OUT" | grep -E 'baretask' | grep -q 'no-trail'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s grades trail-less feature as no-trail\n' "verification-tier-audit.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s baretask not graded no-trail: %q\n' "verification-tier-audit.py" "$VTA_OUT"
fi

# --- review-pr-journal-pre-emit-validator.py: Layer 2 (ask-gate, additive) ---
# Companion to review-pr-journal.py (Layer 1, best-effort, see tests M/N/N2/P).
# The validator is a pre-emit CLI that /review-pr SKILL.md step 4 calls BEFORE
# the journaler. It re-uses the journaler's enum regexes (lockstep via Python
# import — do NOT redeclare the enums) and exits 2 on miss so the human can
# AskUserQuestion before the journal gets polluted. Q3=a is preserved (the
# journaler still WARNINGs but emits; the validator is the ask-gate, not a
# deny-gate). These tests prove the four surface contracts the SKILL.md
# depends on: (CC) all-clean exit 0; (DD) miss → exit 2 + named stderr;
# (EE) manifest dedup short-circuits (already-journaled findings don't
# re-block); (FF) the validator is read-only (it never writes the journal
# or the .journaled manifest, even on a miss).

# (CC) all-clean findings → exit 0, stderr names the count.
VDIR1="$FIXTURE/rj-vdir1"; rm -rf "$VDIR1"; mkdir -p "$VDIR1"
cat > "$VDIR1/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"CC1","tier":"Critical","disposition":"survived","decision":"fix-now","pair_id":"P1"}
{"local_id":"CC2","tier":"Important","disposition":"rejected","decision":"proceed","pair_id":"P2"}
{"local_id":"CC3","tier":"Minor","disposition":"survived","decision":"fix-later","pair_id":"P3"}
FIXTURE_EOF
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/pr/review-pr-journal-pre-emit-validator.py" "$VDIR1" 2>&1 >/dev/null) || EXIT_CODE=$?
N_PASS=$(printf '%s\n' "$STDERR" | grep -c "OK: 3 finding(s) passed" || true)
# The validator must NOT have created a .journaled manifest — that is the
# journaler's job (Layer 1). A Layer-2 write here would double-track state.
HAS_MANIFEST=$([ -e "$VDIR1/.journaled" ] && echo yes || echo no)
if [ "$EXIT_CODE" = 0 ] && [ "$N_PASS" = 1 ] && [ "$HAS_MANIFEST" = no ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s all-clean: exit 0, stderr OK-count, no manifest write (Layer 2 read-only)\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 0) n_pass=%s (want 1) has_manifest=%s (want no)\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$N_PASS" "$HAS_MANIFEST"
fi

# (DD) enum-miss → exit 2, stderr names EVERY offending finding + field, NO
# manifest write. This is the core ask-gate contract: the human must see
# which findings are bad and which field on each, before deciding to
# proceed. A test that only checks exit-2 (without naming) would miss a
# regression where the validator printed "validation failed" without
# per-finding detail.
VDIR2="$FIXTURE/rj-vdir2"; rm -rf "$VDIR2"; mkdir -p "$VDIR2"
cat > "$VDIR2/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"DD1","tier":"whoops","disposition":"survived","decision":"proceed","pair_id":"P1"}
{"local_id":"DD2","tier":"Minor","disposition":"unknown","decision":"proceed","pair_id":"P2"}
{"local_id":"DD3","tier":"Minor","disposition":"rejected","decision":"eventually","pair_id":"P3"}
{"local_id":"DD4","tier":"Critical","disposition":"survived","decision":"fix-now","pair_id":"P4"}
FIXTURE_EOF
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/pr/review-pr-journal-pre-emit-validator.py" "$VDIR2" 2>&1 >/dev/null) || EXIT_CODE=$?
# Expect 3 named findings (DD1 bad tier, DD2 bad disp, DD3 bad dec) and
# DD4 silently passing. The exit-2 message must say ASK-GATE + count, and
# every offending finding's local_id + bad field must appear on stderr.
N_BLOCK=$(printf '%s\n' "$STDERR" | grep -c "ASK-GATE: 3 finding(s) failed" || true)
HAS_DD1=$(printf '%s' "$STDERR" | grep -c "local_id=DD1: tier='whoops'" || true)
HAS_DD2=$(printf '%s' "$STDERR" | grep -c "local_id=DD2: disposition='unknown'" || true)
HAS_DD3=$(printf '%s' "$STDERR" | grep -c "local_id=DD3: decision='eventually'" || true)
NO_DD4=$(printf '%s' "$STDERR" | grep -c "local_id=DD4" || true)
HAS_MANIFEST=$([ -e "$VDIR2/.journaled" ] && echo yes || echo no)
if [ "$EXIT_CODE" = 2 ] && [ "$N_BLOCK" = 1 ] \
   && [ "$HAS_DD1" = 1 ] && [ "$HAS_DD2" = 1 ] && [ "$HAS_DD3" = 1 ] \
   && [ "$NO_DD4" = 0 ] && [ "$HAS_MANIFEST" = no ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s enum-miss: exit 2, all 3 bad findings named on stderr, clean finding silent, no manifest write\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s n_block=%s dd1=%s dd2=%s dd3=%s no_dd4=%s has_manifest=%s\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$N_BLOCK" "$HAS_DD1" "$HAS_DD2" "$HAS_DD3" "$NO_DD4" "$HAS_MANIFEST"
fi

# (EE) manifest dedup short-circuits the validator: a finding with a bad
# enum that is ALREADY in the manifest must NOT block (the manifest
# proves it passed the gate previously, so re-validation is a no-op).
VDIR3="$FIXTURE/rj-vdir3"; rm -rf "$VDIR3"; mkdir -p "$VDIR3"
cat > "$VDIR3/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"EE1","tier":"CRITICAL_TYPO","disposition":"survived","decision":"fix-now","pair_id":"P1"}
{"local_id":"EE2","tier":"BAD_TIER","disposition":"survived","decision":"proceed","pair_id":"P2"}
FIXTURE_EOF
# Pre-seed manifest as if EE1 was journaled in a prior run.
printf '%s\n' '{"local_id":"EE1","finding_id":"fake-fid","verdict_id":"fake-vid"}' > "$VDIR3/.journaled"
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/pr/review-pr-journal-pre-emit-validator.py" "$VDIR3" 2>&1 >/dev/null) || EXIT_CODE=$?
N_ALREADY=$(printf '%s\n' "$STDERR" | grep -c "1 already in manifest" || true)
N_BLOCK=$(printf '%s\n' "$STDERR" | grep -c "1 finding(s) failed" || true)
HAS_EE1_AS_BLOCKER=$(printf '%s' "$STDERR" | grep -c "local_id=EE1:" || true)
HAS_EE2_AS_BLOCKER=$(printf '%s' "$STDERR" | grep -c "local_id=EE2: tier='BAD_TIER'" || true)
if [ "$EXIT_CODE" = 2 ] && [ "$N_ALREADY" = 1 ] && [ "$N_BLOCK" = 1 ] \
   && [ "$HAS_EE1_AS_BLOCKER" = 0 ] && [ "$HAS_EE2_AS_BLOCKER" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s manifest dedup: already-journaled finding skipped, only the new bad one blocks\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s n_already=%s n_block=%s ee1_blocker=%s (want 0) ee2_blocker=%s\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$N_ALREADY" "$N_BLOCK" "$HAS_EE1_AS_BLOCKER" "$HAS_EE2_AS_BLOCKER"
fi

# (FF) the validator is fail-loud on a malformed .journaled manifest
# (analog to journaler test R). Exit 2, stderr names the file, no
# event/journal write.
VDIR4="$FIXTURE/rj-vdir4"; rm -rf "$VDIR4"; mkdir -p "$VDIR4"
cat > "$VDIR4/findings.jsonl" << 'FIXTURE_EOF'
{"local_id":"FF1","tier":"Critical","disposition":"survived","decision":"fix-now","pair_id":"P1"}
FIXTURE_EOF
printf 'not-json-at-all\ngarbage line 2\n' > "$VDIR4/.journaled"
EXIT_CODE=0
STDERR=$(python3 "$SCRIPTS/pr/review-pr-journal-pre-emit-validator.py" "$VDIR4" 2>&1 >/dev/null) || EXIT_CODE=$?
HAS_REFUSING=$(printf '%s' "$STDERR" | grep -c "refusing to validate" || true)
HAS_PATH=$(printf '%s' "$STDERR" | grep -c "\.journaled" || true)
if [ "$EXIT_CODE" = 2 ] && [ "$HAS_REFUSING" = 1 ] && [ "$HAS_PATH" = 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s malformed manifest: exit 2, stderr refuses + names file (lockstep with journaler R)\n' "review-pr-journal-pre-emit-validator"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s exit=%s (want 2) refusing=%s path=%s\n' "review-pr-journal-pre-emit-validator" "$EXIT_CODE" "$HAS_REFUSING" "$HAS_PATH"
fi

# --- recursive-improve-observe.py: reads verification_summary, surfaces gaps as triggers ---
# Phase-4 observe reader: groups verification_summary events by session, keeps the
# LATEST per session, flags sessions with gaps>0 as improvement triggers. Read-only,
# exit 0 always (a report for the human-gated ritual, not a gate). Reuses
# governance-summary.load_jsonl (no second JSONL parser, same contract as the audit).
echo
echo "--- recursive-improve-observe: verification_summary reader ---"
RIO="$HOOKS/../scripts/pr/recursive-improve-observe.py"
RIJ="$FIXTURE/rio-journal.jsonl"
# one session with a recorded verification gap (gaps=4) + one clean session (gaps=0)
{
  printf '{"id":"1-verification-gate-a","ts":"2026-06-10T01:00:00.000Z","session":"sess-gappy","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":7,"tdd_provenance":1,"analyzer_pass":1,"no_trail":3,"gaps":4}}\n'
  printf '{"id":"2-verification-gate-b","ts":"2026-06-10T02:00:00.000Z","session":"sess-clean","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":2,"tdd_provenance":1,"analyzer_pass":0,"no_trail":1,"gaps":0}}\n'
} > "$RIJ"
RIO_OUT=$(python3 "$RIO" --journal "$RIJ" 2>/dev/null); RIO_RC=$?

# (1) surfaces the gappy session as an improvement trigger
if [ "$RIO_RC" = 0 ] && printf '%s' "$RIO_OUT" | grep -q 'sess-gappy' && printf '%s' "$RIO_OUT" | grep -qi 'gap'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s surfaces a session with gaps>0 as an improvement trigger\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s gappy session not surfaced: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO_RC" "$RIO_OUT"
fi

# (2) LATEST event per session wins
RIJ2="$FIXTURE/rio-journal2.jsonl"
{
  printf '{"id":"1-vg-a","ts":"2026-06-10T01:00:00.000Z","session":"sess-fixed","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":3,"tdd_provenance":1,"analyzer_pass":0,"no_trail":2,"gaps":2}}\n'
  printf '{"id":"2-vg-b","ts":"2026-06-10T05:00:00.000Z","session":"sess-fixed","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":3,"tdd_provenance":3,"analyzer_pass":0,"no_trail":0,"gaps":0}}\n'
} > "$RIJ2"
RIO2_OUT=$(python3 "$RIO" --journal "$RIJ2" 2>/dev/null); RIO2_RC=$?
if [ "$RIO2_RC" = 0 ] && ! printf '%s' "$RIO2_OUT" | grep -q -- '- sess-fixed'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s latest event per session wins (a fixed session is not a trigger)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s stale gap event flagged a fixed session: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO2_RC" "$RIO2_OUT"
fi

# (3) all-clean journal (gaps=0) → reports clean, emits NO trigger bullet
RIJ3="$FIXTURE/rio-journal3.jsonl"
printf '{"id":"1-vg","ts":"2026-06-10T01:00:00.000Z","session":"sess-ok","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":2,"tdd_provenance":2,"analyzer_pass":0,"no_trail":0,"gaps":0}}\n' > "$RIJ3"
RIO3_OUT=$(python3 "$RIO" --journal "$RIJ3" 2>/dev/null); RIO3_RC=$?
if [ "$RIO3_RC" = 0 ] && printf '%s' "$RIO3_OUT" | grep -qi 'clean' && ! printf '%s' "$RIO3_OUT" | grep -q -- '- sess-ok'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s clean posture → no trigger (false-positive guard)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s clean posture mishandled: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO3_RC" "$RIO3_OUT"
fi

# (4) journal exists but has NO verification_summary events → graceful empty, exit 0
RIJ4="$FIXTURE/rio-journal4.jsonl"
printf '{"id":"1-x","ts":"2026-06-10T01:00:00.000Z","session":"s","hook":"review-pr-journaler","event":"review_finding","source":"journal_append","fields":{"file":"a.py","line":1,"tier":"Minor","agent":"code-reviewer","summary":"x"}}\n' > "$RIJ4"
RIO4_OUT=$(python3 "$RIO" --journal "$RIJ4" 2>/dev/null); RIO4_RC=$?
if [ "$RIO4_RC" = 0 ] && printf '%s' "$RIO4_OUT" | grep -qi 'no verification_summary'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s journal w/o summary events → graceful empty, exit 0\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s did not handle summary-less journal: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO4_RC" "$RIO4_OUT"
fi

# (5) a verification_summary missing the `gaps` field → treated as 0 (no KeyError)
RIJ5="$FIXTURE/rio-journal5.jsonl"
printf '{"id":"1-vg","ts":"2026-06-10T01:00:00.000Z","session":"sess-partial","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":1,"tdd_provenance":1}}\n' > "$RIJ5"
RIO5_OUT=$(python3 "$RIO" --journal "$RIJ5" 2>/dev/null); RIO5_RC=$?
if [ "$RIO5_RC" = 0 ] && printf '%s' "$RIO5_OUT" | grep -q 'sess-partial' && ! printf '%s' "$RIO5_OUT" | grep -q -- '- sess-partial'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s missing gaps field → 0, no crash (not a trigger)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s missing-field handling wrong: rc=%s out=%q\n' "recursive-improve-observe.py" "$RIO5_RC" "$RIO5_OUT"
fi

# (6) read-only: a run does NOT mutate the journal
RIO_SUM_BEFORE=$(cksum "$RIJ" | awk '{print $1, $2}')
python3 "$RIO" --journal "$RIJ" >/dev/null 2>&1; RIO6_RC=$?
RIO_SUM_AFTER=$(cksum "$RIJ" | awk '{print $1, $2}')
if [ "$RIO6_RC" = 0 ] && [ "$RIO_SUM_BEFORE" = "$RIO_SUM_AFTER" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s read-only: run leaves the journal byte-identical\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s mutated the journal or rc!=0: rc=%s before=%q after=%q\n' "recursive-improve-observe.py" "$RIO6_RC" "$RIO_SUM_BEFORE" "$RIO_SUM_AFTER"
fi

# (7) a verification_summary with a PRESENT-but-garbage field (gaps:"corrupted") must
#     surface the degradation to stderr — silently coercing it to 0 would mask a real gap.
RIJ7="$FIXTURE/rio-journal7.jsonl"
printf '{"id":"1-vg","ts":"2026-06-10T01:00:00.000Z","session":"sess-garbage","hook":"verification-gate","event":"verification_summary","source":"journal_append","fields":{"features":1,"gaps":"corrupted"}}\n' > "$RIJ7"
RIO7_ERR="$FIXTURE/rio7-err.txt"
RIO7_OUT=$(python3 "$RIO" --journal "$RIJ7" 2>"$RIO7_ERR"); RIO7_RC=$?
if [ "$RIO7_RC" = 0 ] && grep -qi 'unparseable' "$RIO7_ERR" && grep -q 'corrupted' "$RIO7_ERR"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s present-but-garbage field → stderr warning, not silent (exit 0)\n' "recursive-improve-observe.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s garbage field not surfaced: rc=%s err=%q\n' "recursive-improve-observe.py" "$RIO7_RC" "$(cat "$RIO7_ERR")"
fi

# (8) run-acceptance.py exit-3 (malformed ACCEPTANCE.md). A "## Criteria" section
#     the author wrote but that has ZERO parseable `- [ ]` checkboxes is a parse
#     error (exit 3), NOT exit 0 — before the malformed guard such a file parsed
#     to an empty criteria list and was silently scored as PASS (exit 0). Reads
#     the committed repro at eval/fixtures/acceptance-malformed-criteria/ into a
#     temp .scratch slug (run-acceptance resolves slugs under REPO_ROOT/.scratch).
RA="$HOOKS/../scripts/evals/run-acceptance.py"
RA_REPO="$(cd "$HOOKS/.." && pwd)"
RA_FIX="$RA_REPO/eval/fixtures/acceptance-malformed-criteria/ACCEPTANCE.md"
RA_SLUG_BAD="ch-acc-malformed-$$"
mkdir -p "$RA_REPO/.scratch/$RA_SLUG_BAD"
cp "$RA_FIX" "$RA_REPO/.scratch/$RA_SLUG_BAD/ACCEPTANCE.md"
RA_BAD_ERR="$FIXTURE/ra-bad-err.txt"
set +e
python3 "$RA" "$RA_SLUG_BAD" >/dev/null 2>"$RA_BAD_ERR"; RA_BAD_RC=$?
set -e
rm -rf "$RA_REPO/.scratch/$RA_SLUG_BAD"
if [ "$RA_BAD_RC" = 3 ] && grep -qi 'malformed' "$RA_BAD_ERR"; then
  PASS=$((PASS+1)); printf '  ✅ %-26s malformed ## Criteria (no checkboxes) → exit 3 (was unreachable/silent exit 0)\n' "run-acceptance.py"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s malformed → want rc=3+"malformed", got rc=%s err=%q\n' "run-acceptance.py" "$RA_BAD_RC" "$(cat "$RA_BAD_ERR")"
fi

# (9) positive control — a well-formed `## Criteria` with one safe checkbox must
#     NOT hit exit 3 (the guard is specific to the zero-checkbox case, not all
#     `## Criteria` sections).
RA_SLUG_OK="ch-acc-ok-$$"
mkdir -p "$RA_REPO/.scratch/$RA_SLUG_OK"
printf '# ok\n\n## Criteria\n\n- [ ] true\n' > "$RA_REPO/.scratch/$RA_SLUG_OK/ACCEPTANCE.md"
set +e
python3 "$RA" "$RA_SLUG_OK" >/dev/null 2>&1; RA_OK_RC=$?
set -e
rm -rf "$RA_REPO/.scratch/$RA_SLUG_OK"
if [ "$RA_OK_RC" != 3 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s well-formed ## Criteria (1 checkbox) does NOT exit 3 (rc=%s)\n' "run-acceptance.py" "$RA_OK_RC"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s well-formed wrongly hit exit 3 (false positive)\n' "run-acceptance.py"
fi
