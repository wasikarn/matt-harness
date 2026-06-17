# shellcheck disable=SC1090,SC1091,SC2034
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-harness-audit32.sh — standalone suite run by test-critical-hooks.sh
# Covers: harness-audit check #32 (PP/QQ/RR), inferential-structural-judge
#         (HOO15 T1-T5 + bash-n + shellcheck), notify-sensor-staleness (HOO1 T1-T5).

# --- harness-audit check #32 — autonomy invariant guardrail ---
# Round-2 drill-down (2026-06-12) found that the load-bearing autonomy
# invariant (CONTEXT.md §Invariants) had no deterministic check. This
# trio (PP/QQ/RR) is the regression guard for that check. The invariant
# is enforced via the `disable-model-invocation: true` frontmatter on
# skills/recursive-improve/SKILL.md. If the field regresses to `: false`,
# `: True` (Python truthy), or is removed, the harness loses its
# self-binding and the model can self-start the recursive-improve skill
# — a one-model-version-away self-rewriter. The check emits CRIT, not
# WARN, because the invariant is irreversible (per ADR 0002).
#
# Mirrors the (MM)/(NN)/(OO) trio pattern: hermetic temp-dir fixture
# for the violation paths, real-repo path for the positive control.
# The (PP) test runs against the real kbg-harness repo to verify the
# check is silent when the field is present (the contract is that the
# audit green bar is preserved for the actual harness state).
AUDIT="$HOOKS/../skills/harness-audit/scripts/audit.sh"

# (PP) positive control — real repo, recursive-improve has the field.
# The audit should produce zero INVARIANT_FAIL findings.
set +e
PP_OUT=$(bash "$AUDIT" . 2>&1)
PP_RC=$?
set -e
PP_HAS_INVARIANT=$(printf '%s' "$PP_OUT" | grep -c "INVARIANT\|autonomy invariant regressed" || true)
if [ "$PP_HAS_INVARIANT" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s real repo: 0 INVARIANT_FAIL (recursive-improve has disable-model-invocation: true)\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s real repo emitted %s INVARIANT_FAIL findings (want 0), rc=%s:\n%s\n' "harness-audit #32" "$PP_HAS_INVARIANT" "$PP_RC" "$PP_OUT"
fi

# (QQ) violation fixture — temp recursive-improve skill with the field
# set to `false` (the would-be regression).
QQ_F="$FIXTURE/qq-ri-bad"; rm -rf "$QQ_F"; mkdir -p "$QQ_F/claude/skills/recursive-improve" "$QQ_F/claude/agents" "$QQ_F/claude/commands" "$QQ_F/claude/hooks" "$QQ_F/claude/docs" "$QQ_F/.claude-plugin"
cat > "$QQ_F/claude/skills/recursive-improve/SKILL.md" <<'SK'
---
name: recursive-improve
description: "fixture — field flipped to false"
disable-model-invocation: false
---
# fixture
SK
cat > "$QQ_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "qq-fixture", "version": "0.0.1" }
PJ
set +e
QQ_OUT=$(bash "$AUDIT" "$QQ_F" 2>&1)
QQ_RC=$?
set -e
QQ_HAS_CRIT=$(printf '%s' "$QQ_OUT" | grep -c "missing 'disable-model-invocation: true'" || true)
if [ "$QQ_HAS_CRIT" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s violation fixture: 1+ CRIT fires (disable-model-invocation flipped to false)\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s violation fixture: 0 CRIT (want 1+), rc=%s:\n%s\n' "harness-audit #32" "$QQ_RC" "$QQ_OUT"
fi

# (RR) regression guard — field value-typo must NOT pass silently.
# A regression to "True" / "yes" / "1" / "on" would silently disable the gate.
# The check is grep -qF (fixed string) which is exact-match — verified
# here by feeding it `: True` (Python truthy) and asserting 1+ CRIT.
RR_F="$FIXTURE/rr-ri-truthy"; rm -rf "$RR_F"; mkdir -p "$RR_F/claude/skills/recursive-improve" "$RR_F/claude/agents" "$RR_F/claude/commands" "$RR_F/claude/hooks" "$RR_F/claude/docs" "$RR_F/.claude-plugin"
cat > "$RR_F/claude/skills/recursive-improve/SKILL.md" <<'SK'
---
name: recursive-improve
description: "fixture — field is Python truthy `True` (capital T)"
disable-model-invocation: True
---
# fixture
SK
cat > "$RR_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "rr-fixture", "version": "0.0.1" }
PJ
set +e
RR_OUT=$(bash "$AUDIT" "$RR_F" 2>&1)
RR_RC=$?
set -e
RR_HAS_CRIT=$(printf '%s' "$RR_OUT" | grep -c "missing 'disable-model-invocation: true'" || true)
if [ "$RR_HAS_CRIT" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s truthy-typo regression: CRIT fires (check is exact-match on `: true`, not truthy)\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s truthy-typo regression: 0 CRIT (want 1+) — check would silently pass `: True` — rc=%s:\n%s\n' "harness-audit #32" "$RR_RC" "$RR_OUT"
fi

# (SS) deleted-skill hole — the surface-closure (2026-06-16) case. ADR 0002 is
# present (the repo DECLARES the invariant) but the self-binding skill was
# deleted. Pre-closure the check silently passed ("no file = no guard"); now
# the deletion itself is the regression and must CRIT.
SS_F="$FIXTURE/ss-ri-deleted"; rm -rf "$SS_F"; mkdir -p "$SS_F/claude/docs/adr" "$SS_F/claude/agents" "$SS_F/claude/commands" "$SS_F/claude/hooks" "$SS_F/.claude-plugin"
cat > "$SS_F/claude/docs/adr/0002-autonomy-invariant.md" <<'ADR'
# ADR 0002: Autonomy invariant — fixture (declares the invariant, no skill present)
ADR
cat > "$SS_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "ss-fixture", "version": "0.0.1" }
PJ
set +e
SS_OUT=$(bash "$AUDIT" "$SS_F" 2>&1)
SS_RC=$?
set -e
SS_HAS_CRIT=$(printf '%s' "$SS_OUT" | grep -c "recursive-improve/SKILL.md is MISSING" || true)
if [ "$SS_HAS_CRIT" -ge 1 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s deleted-skill hole: ADR present + skill gone fires CRIT (was silent pass)\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s deleted-skill hole: 0 CRIT (want 1+), rc=%s:\n%s\n' "harness-audit #32" "$SS_RC" "$SS_OUT"
fi

# (TT) doc-surface phrase drop — surfaces 1/2/4 closure. ADR present, skill
# present AND good (no surface-3 CRIT), but a doc surface (CONTEXT.md) lost its
# load-bearing phrase. Must CRIT on the phrase drop, and must NOT CRIT surface 3.
TT_F="$FIXTURE/tt-surface-drop"; rm -rf "$TT_F"; mkdir -p "$TT_F/claude/skills/recursive-improve" "$TT_F/claude/docs/adr" "$TT_F/claude/agents" "$TT_F/claude/commands" "$TT_F/claude/hooks" "$TT_F/.claude-plugin"
cat > "$TT_F/claude/skills/recursive-improve/SKILL.md" <<'SK'
---
name: recursive-improve
description: "fixture — good flag, so surface 3 is silent"
disable-model-invocation: true
---
# fixture
SK
cat > "$TT_F/claude/docs/adr/0002-autonomy-invariant.md" <<'ADR'
# ADR 0002: Autonomy invariant — fixture
ADR
# CONTEXT.md present but reworded (the load-bearing phrase is gone).
cat > "$TT_F/claude/CONTEXT.md" <<'CTX'
## Invariants
- Autonomy is human-gated. No self-driving repair cycle lives here.
CTX
cat > "$TT_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "tt-fixture", "version": "0.0.1" }
PJ
set +e
TT_OUT=$(bash "$AUDIT" "$TT_F" 2>&1)
TT_RC=$?
set -e
TT_HAS_PHRASE_CRIT=$(printf '%s' "$TT_OUT" | grep -c "dropped its load-bearing phrase" || true)
TT_HAS_S3=$(printf '%s' "$TT_OUT" | grep -c "missing 'disable-model-invocation: true'" || true)
if [ "$TT_HAS_PHRASE_CRIT" -ge 1 ] && [ "$TT_HAS_S3" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s surface phrase drop: reworded CONTEXT.md fires CRIT; good skill stays silent\n' "harness-audit #32"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s surface phrase drop: want phrase-CRIT + no-S3, got phrase=%s s3=%s rc=%s:\n%s\n' "harness-audit #32" "$TT_HAS_PHRASE_CRIT" "$TT_HAS_S3" "$TT_RC" "$TT_OUT"
fi

# --- harness-audit check #34 — autonomy invariant surface 5 (advisory-only) ---
# Inferential-FB sensors (sensors.json fallback_role=="inferential-FB") must
# NEVER emit a permissionDecision. #29 catches decide-AND-journal; #34 catches
# decide-WITHOUT-journal, which would otherwise slip the net (covert L4 gate).

# (UU) positive control — real repo: every inferential-FB sensor is advisory,
# so zero "emits a permissionDecision" CRITs.
set +e
UU_OUT=$(bash "$AUDIT" . 2>&1)
set -e
UU_HAS_CRIT=$(printf '%s' "$UU_OUT" | grep -c "inferential-FB sensor.*emits a permissionDecision" || true)
if [ "$UU_HAS_CRIT" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s real repo: 0 surface-5 CRIT (all inferential-FB sensors advisory)\n' "harness-audit #34"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s real repo emitted %s surface-5 CRIT (want 0):\n%s\n' "harness-audit #34" "$UU_HAS_CRIT" "$UU_OUT"
fi

# (VV) violation fixture — an inferential-FB sensor whose hook calls hook_decision
# (the _lib emitter) must CRIT. Comment-only mentions must NOT (comment-stripping).
VV_F="$FIXTURE/vv-inf-fb-gates"; rm -rf "$VV_F"; mkdir -p "$VV_F/claude/hooks/advisory" "$VV_F/claude/agents" "$VV_F/claude/commands" "$VV_F/.claude-plugin"
cat > "$VV_F/claude/hooks/sensors.json" <<'JSON'
{"version":1,"sensors":[
  {"name":"foo-advisory-log","should_fire_when":"Stop:*","max_silent_days":30,"fallback_role":"inferential-FB","must_fire_in_session":false,"enabled":true},
  {"name":"bar-clean-log","should_fire_when":"Stop:*","max_silent_days":30,"fallback_role":"inferential-FB","must_fire_in_session":false,"enabled":true}
]}
JSON
cat > "$VV_F/claude/hooks/advisory/foo-advisory-log.sh" <<'SH'
#!/usr/bin/env bash
# advisory sensor that WRONGLY gates the tool call
hook_decision deny "should not gate"
SH
cat > "$VV_F/claude/hooks/advisory/bar-clean-log.sh" <<'SH'
#!/usr/bin/env bash
# clean advisory sensor — only a comment mentions permissionDecision, never emits it
echo '{"ok":true}'
SH
cat > "$VV_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "vv-fixture", "version": "0.0.1" }
PJ
set +e
VV_OUT=$(bash "$AUDIT" "$VV_F" 2>&1)
set -e
VV_HAS_FOO=$(printf '%s' "$VV_OUT" | grep -c "inferential-FB sensor 'foo-advisory-log'" || true)
VV_HAS_BAR=$(printf '%s' "$VV_OUT" | grep -c "inferential-FB sensor 'bar-clean-log'" || true)
if [ "$VV_HAS_FOO" -ge 1 ] && [ "$VV_HAS_BAR" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s violation fixture: gating sensor CRITs; comment-only sensor stays silent\n' "harness-audit #34"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s violation fixture: want foo-CRIT + no-bar, got foo=%s bar=%s:\n%s\n' "harness-audit #34" "$VV_HAS_FOO" "$VV_HAS_BAR" "$VV_OUT"
fi

# --- harness-audit check #35 — disable-model-invocation requires a reason (WARN) ---
# Deterministic presence check (replaces the toothless reporter-shape heuristic
# that matched zero real flagged surfaces — a Rule-9 test that could not fail).
# Every disable-model-invocation:true surface must carry a non-empty
# disable-model-invocation-reason:. HAS teeth: an unreasoned flag WARNs.

# (WW) positive control — real repo: all 26 flagged surfaces carry a reason, so
# zero #35 reason-WARNs.
set +e
WW_OUT=$(bash "$AUDIT" . 2>&1)
set -e
WW_HAS=$(printf '%s' "$WW_OUT" | grep -c "without a 'disable-model-invocation-reason:'" || true)
if [ "$WW_HAS" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s real repo: every flagged surface carries a reason (0 WARN)\n' "harness-audit #35"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s real repo emitted %s unreasoned-flag WARN (want 0):\n%s\n' "harness-audit #35" "$WW_HAS" "$WW_OUT"
fi

# (XX) violation fixture — a flagged surface WITHOUT a reason must WARN; a flagged
# surface WITH a reason must NOT. This is the can-fail property the old check lacked.
XX_F="$FIXTURE/xx-reason-required"; rm -rf "$XX_F"; mkdir -p "$XX_F/commands" "$XX_F/skills" "$XX_F/agents" "$XX_F/.claude-plugin"
cat > "$XX_F/commands/foo-noreason.md" <<'MD'
---
name: foo-noreason
description: "Ship the release: merge the PR, tag, push, verify. Use when the user says ship it."
disable-model-invocation: true
---
MD
cat > "$XX_F/commands/foo-reasoned.md" <<'MD'
---
name: foo-reasoned
description: "Ship the release: merge the PR, tag, push, verify. Use when the user says ship it."
disable-model-invocation: true
disable-model-invocation-reason: "irreversible external — cuts a release"
---
MD
cat > "$XX_F/.claude-plugin/plugin.json" <<'PJ'
{ "name": "xx-fixture", "version": "0.0.1" }
PJ
set +e
XX_OUT=$(bash "$AUDIT" "$XX_F" 2>&1)
set -e
XX_HAS_NOREASON=$(printf '%s' "$XX_OUT" | grep -c "'foo-noreason': disable-model-invocation: true without a" || true)
XX_HAS_REASONED=$(printf '%s' "$XX_OUT" | grep -c "'foo-reasoned'.*without a" || true)
if [ "$XX_HAS_NOREASON" -ge 1 ] && [ "$XX_HAS_REASONED" = 0 ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s reason fixture: WARN on unreasoned flag; silent on reasoned flag\n' "harness-audit #35"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s reason fixture: want noreason-WARN + reasoned-silent, got nr=%s r=%s:\n%s\n' "harness-audit #35" "$XX_HAS_NOREASON" "$XX_HAS_REASONED" "$XX_OUT"
fi

# ── HOOK-1.5: inferential-structural-judge-on-session-end.sh (matcher-less SessionEnd) ──
# Inferential-FB sensor that journals a verdict to ~/.claude/governance-events.jsonl.
# It is journal-only and never emits a permissionDecision (autonomy invariant,
# ADR 0002 §L112). Tests cover the deterministic shell logic; the agent
# invocation (`claude -p --agent ...`) is exercised separately via the
# EVAL-1 fixture runner (the agent runtime is not always present in the
# shell-only test env, and exercising it here would couple the test to
# the agent's verdict quality, which is the fixture's job).
#
# Test setup convention (matches HOO1 below): hermetic $TEMP tree, journal
# redirected via CLAUDE_JOURNAL_PATH, HOME redirected so the dismissal file
# lives at $HOME/.claude/state/... The agent itself is not invoked (we test
# paths that short-circuit BEFORE the `claude -p` call — empty diff,
# missing transcript, missing claude binary).

HOOK1_5_HOOK_SRC="$HOOKS/session/inferential-structural-judge-on-session-end.sh"
[ -f "$HOOK1_5_HOOK_SRC" ] || { echo "FATAL: $HOOK1_5_HOOK_SRC missing" >&2; exit 1; }

# Helper: run the SessionEnd hook with a controlled envelope + journal path.
# Args:
#   $1 = JSON envelope (transcript_path, session_id)
#   $2 = CLAUDE_JOURNAL_PATH to redirect journal writes
#   $3 = HOME override (for dismissal file at $HOME/.claude/state/...)
#   $4 = PATH override (to test the "claude absent" path)
# Echoes the hook's stdout; returns the hook's exit code via $?.
hoo15_run() {
  local env_json="$1" journal_path="$2" home_override="$3" path_override="$4"
  local T="$FIXTURE/hook15-$$-$RANDOM"
  mkdir -p "$T"
  # Copy BOTH the hook AND _lib.sh — the hook's L28 `source $(dirname $0)/_lib.sh`
  # is a path-relative source that requires _lib.sh to sit alongside it.
  cp "$HOOK1_5_HOOK_SRC" "$T/inferential-structural-judge-on-session-end.sh"
  cp "$HOOKS/_lib.sh" "$(dirname "$T")/_lib.sh"
  CLAUDE_JOURNAL_PATH="$journal_path" \
    HOME="$home_override" \
    PATH="$path_override" \
    CLAUDE_SESSION_ID="test-session-$$" \
    bash "$T/inferential-structural-judge-on-session-end.sh" <<< "$env_json" 2>/dev/null
}

# Build a hermetic PATH that has coreutils + jq + python3 (so the hook
# can do its work) but NOT claude (so the `command -v claude` check at
# hook L35-41 falls into failure-mode 1: agent_absent → journal a
# skipped event and exit 0).
# shellcheck disable=SC2155  # the two-step find/skip is intentional
CLAUDE_BIN=$(command -v claude 2>/dev/null || true)
CLAUDE_DIR=""
if [ -n "$CLAUDE_BIN" ]; then CLAUDE_DIR=$(dirname "$CLAUDE_BIN"); fi
SYSTEM_PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
EMPTY_PATH=""
IFS=':' read -r -a path_parts <<< "$SYSTEM_PATH"
for p in "${path_parts[@]}"; do
  if [ -n "$p" ] && [ "$p" != "$CLAUDE_DIR" ]; then EMPTY_PATH="${EMPTY_PATH:+${EMPTY_PATH}:}$p"; fi
done
[ -n "$EMPTY_PATH" ] || EMPTY_PATH="/usr/bin:/bin"

# Test 1: agent_absent path (no claude in PATH) → journal skipped:agent_absent
# and exit 0 with no stdout. This is failure-mode 1 from the design doc §6.
HOO15_T1_JOURNAL="$FIXTURE/hook15-t1-journal.jsonl"
HOO15_T1_HOME="$FIXTURE/hook15-t1-home"; mkdir -p "$HOO15_T1_HOME"
HOO15_T1_ENVELOPE='{"transcript_path":"/nonexistent/transcript.jsonl","session_id":"test-sess-1"}'
HOO15_T1_OUT=$(hoo15_run "$HOO15_T1_ENVELOPE" "$HOO15_T1_JOURNAL" "$HOO15_T1_HOME" "$EMPTY_PATH")
HOO15_T1_RC=$?
HOO15_T1_LAST=$(tail -1 "$HOO15_T1_JOURNAL" 2>/dev/null)
if [ "$HOO15_T1_RC" = "0" ] \
   && [ -z "$HOO15_T1_OUT" ] \
   && [ -n "$HOO15_T1_LAST" ] \
   && printf '%s' "$HOO15_T1_LAST" | jq -e '.event == "inferential_structural_verdict_skipped" and .fields.reason == "agent_absent"' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s agent_absent: skipped event with reason=agent_absent, exit 0, no stdout\n' "infer-structural-judge"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s agent_absent: rc=%s out=%s last_event=%s\n' "infer-structural-judge" "$HOO15_T1_RC" "$HOO15_T1_OUT" "$HOO15_T1_LAST"
fi

# Test 2: empty/missing transcript + claude absent → still agent_absent path
HOO15_T2_JOURNAL="$FIXTURE/hook15-t2-journal.jsonl"
HOO15_T2_HOME="$FIXTURE/hook15-t2-home"; mkdir -p "$HOO15_T2_HOME"
HOO15_T2_OUT=$(hoo15_run '{}' "$HOO15_T2_JOURNAL" "$HOO15_T2_HOME" "$EMPTY_PATH")
HOO15_T2_RC=$?
HOO15_T2_LAST=$(tail -1 "$HOO15_T2_JOURNAL" 2>/dev/null)
if [ "$HOO15_T2_RC" = "0" ] \
   && [ -z "$HOO15_T2_OUT" ] \
   && [ -n "$HOO15_T2_LAST" ] \
   && printf '%s' "$HOO15_T2_LAST" | jq -e '.fields.reason == "agent_absent"' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s empty envelope: degrades silently to agent_absent, no crash\n' "infer-structural-judge"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s empty envelope: rc=%s out=%s last_event=%s\n' "infer-structural-judge" "$HOO15_T2_RC" "$HOO15_T2_OUT" "$HOO15_T2_LAST"
fi

# Test 3: autonomy-invariant scan (negative test). The hook source must NOT
# contain the string "permissionDecision" in any CODE line (not a comment).
# Comments mentioning the invariant are fine; what we forbid is a literal
# `permissionDecision: "deny"` (or similar) being EMITTED by the hook.
HOOK1_5_STRIPPED=$(grep -vE '^[[:space:]]*#' "$HOOK1_5_HOOK_SRC")
AGENT_STRIPPED=$(grep -vE '^[[:space:]]*#' "$HOOKS/../agents/inferential-structural-judge.md")
if ! printf '%s\n' "$HOOK1_5_STRIPPED" | grep -qF 'permissionDecision' \
   && ! printf '%s\n' "$AGENT_STRIPPED" | grep -qF 'permissionDecision'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s autonomy invariant: no permissionDecision in hook or agent code (comments OK)\n' "infer-structural-judge"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s autonomy invariant: permissionDecision found in hook or agent code\n' "infer-structural-judge"
fi

# Test 4: bash syntax + shellcheck-clean
HOO15_T4_BASHN=$(bash -n "$HOOK1_5_HOOK_SRC" 2>&1)
if [ -z "$HOO15_T4_BASHN" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s bash -n clean\n' "infer-structural-judge"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s bash -n failed: %s\n' "infer-structural-judge" "$HOO15_T4_BASHN"
fi
if command -v shellcheck >/dev/null 2>&1; then
  HOO15_T4_SC=$(shellcheck -S error "$HOOK1_5_HOOK_SRC" 2>&1 || true)
  if [ -z "$HOO15_T4_SC" ]; then
    PASS=$((PASS+1)); printf '  ✅ %-26s shellcheck -S error clean\n' "infer-structural-judge"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-26s shellcheck -S error: %s\n' "infer-structural-judge" "$HOO15_T4_SC"
  fi
fi

# Test 5: prior-verdict lookup handles the "old journal entries (no paths
# field)" case gracefully. Pre-fix-shape entries should be treated as
# "no prior" (the lookup filters them out via `select((.fields.paths // [])
# | length > 0)`).
HOO15_T5_JOURNAL="$FIXTURE/hook15-t5-journal.jsonl"
cat > "$HOO15_T5_JOURNAL" <<'EOF'
{"id":"1","ts":"2026-06-15T10:00:00.000Z","session":"old","hook":"inferential-structural-judge","event":"inferential_structural_verdict","source":"journal_append","fields":{"score":5,"dimensions":{"over_engineering":3,"arch_drift":2,"test_pattern":2,"doctrine_conformance":2},"top_finding":"old","recommendation":"flag"}}
{"id":"2","ts":"2026-06-15T11:00:00.000Z","session":"new","hook":"inferential-structural-judge","event":"inferential_structural_verdict","source":"journal_append","fields":{"score":3,"dimensions":{"over_engineering":2,"arch_drift":1,"test_pattern":1,"doctrine_conformance":1},"top_finding":"new","recommendation":"accept","paths":["agents/foo.md"]}}
EOF
HOO15_T5_RESULT=$(jq -s --argjson cur '["agents/foo.md"]' --arg sid "current" '
  [ .[]?
      | select(.event=="inferential_structural_verdict")
      | select(.session != $sid)
      | select((.fields.paths // []) | length > 0)
      | { session: .session, ts: .ts, paths: .fields.paths, score: .fields.score } ]
  | map(select(.paths | .[] as $p | $cur | index($p) != null))
  | group_by(.paths | tostring) | map(last)
  | .[0:50]
' "$HOO15_T5_JOURNAL" 2>/dev/null)
HOO15_T5_RC=$?
if [ "$HOO15_T5_RC" = "0" ] \
   && [ "$(printf '%s' "$HOO15_T5_RESULT" | jq 'length')" = "1" ] \
   && printf '%s' "$HOO15_T5_RESULT" | jq -e '.[0].paths | index("agents/foo.md") != null' >/dev/null 2>&1; then
  PASS=$((PASS+1)); printf '  ✅ %-26s prior-verdict lookup: filters old-shape entries, returns new-shape overlap\n' "infer-structural-judge"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s prior-verdict lookup: rc=%s result=%s\n' "infer-structural-judge" "$HOO15_T5_RC" "$HOO15_T5_RESULT"
fi

# ── HOOK-1: notify-sensor-staleness.sh (matcher-less SessionStart) ──
# Five tests, each builds a hermetic temp tree (copy of the hook + fixture
# sensors.json + stub audit.sh), runs the hook with HOME=$TEMP (dismissal
# file redirection) and CLAUDE_JOURNAL_PATH=$TEMP/journal.jsonl (journal
# redirection), and asserts on the emitted additionalContext. The stub
# audit.sh reads STUB_AUDIT_OUTPUT_FILE (env var) and emits its contents
# — this is a one-line, test-only artifact, NOT a real audit re-implementation.
HOOK1_HOOK_SRC="$HOOKS/maintenance/notify-sensor-staleness.sh"
[ -f "$HOOK1_HOOK_SRC" ] || { echo "FATAL: $HOOK1_HOOK_SRC missing" >&2; exit 1; }

# Test helper: build a fresh temp tree and run the hook once. Args:
#   $1 = sensors.json content (will be written to $T/sensors.json)
#   $2 = STUB_AUDIT_OUTPUT_FILE content (will be written to $FIXTURE/.claude/audit-stub-output.json)
#   $3 = HOME override (dismissal file lives at $HOME/.claude/state/...)
#   $4 = sensors.json filename (default: "sensors.json"; for the missing-file test)
# Outputs the hook's stdout to FD 1. Returns the hook's exit code via $?.
#
# Layout note: the hook resolves AUDIT_SH via "$(dirname "$BASH_SOURCE")/../skills/...".
# For the hook at $T/notify-sensor-staleness.sh, that's $T/../skills/... which
# resolves to the PARENT of $T (which is $FIXTURE). So the stub audit.sh must
# live at $FIXTURE/skills/harness-audit/scripts/audit.sh — shared across tests.
HOO1_STUB_DIR="$FIXTURE/skills/harness-audit/scripts"
HOO1_STUB_SH="$HOO1_STUB_DIR/audit.sh"
HOO1_STUB_OUT="$FIXTURE/.claude/audit-stub-output.json"
mkdir -p "$HOO1_STUB_DIR" "$FIXTURE/.claude"
# Write the stub once (idempotent — same content each call)
cat > "$HOO1_STUB_SH" <<'STUB'
#!/usr/bin/env bash
# Test stub for audit.sh --staleness-only. Emits the JSON in
# $STUB_AUDIT_OUTPUT_FILE (env var). Empty file → `[]`.
out="${STUB_AUDIT_OUTPUT_FILE:-}"
if [ -f "$out" ]; then
  cat "$out"
else
  echo "[]"
fi
STUB
chmod +x "$HOO1_STUB_SH"

hoo1_run() {
  local sensors_content="$1" stub_output_content="$2" home_override="$3"
  local sensors_filename="${4:-sensors.json}"
  # Mirror the real layout: hook lives at hooks/maintenance/, so:
  #   HOOK_DIR = $FIXTURE/hooks/maintenance
  #   SENSORS_JSON = $FIXTURE/hooks/maintenance/../sensors.json = $FIXTURE/hooks/sensors.json
  #   AUDIT_SH    = $FIXTURE/hooks/maintenance/../../skills/...  = $FIXTURE/skills/... ✓
  local HOO1_HOOK_DIR="$FIXTURE/hooks/maintenance"
  mkdir -p "$HOO1_HOOK_DIR"
  # Copy the hook script (not symlink — the trap deletes the dir)
  cp "$HOOK1_HOOK_SRC" "$HOO1_HOOK_DIR/notify-sensor-staleness.sh"
  # Fixture registry (or skip for the missing-file test)
  # sensors.json must be at $FIXTURE/hooks/<sensors_filename> so that
  # $HOO1_HOOK_DIR/../sensors.json resolves to it.
  # When sensors_content is empty (missing-file test), remove any leftover
  # sensors.json from prior tests so the hook truly sees a missing file.
  if [ -n "$sensors_content" ]; then
    printf '%s' "$sensors_content" > "$FIXTURE/hooks/$sensors_filename"
  else
    rm -f "$FIXTURE/hooks/sensors.json"
  fi
  # Write the stub's output file (the JSON list the real audit would emit)
  printf '%s' "$stub_output_content" > "$HOO1_STUB_OUT"
  # Run the hook. HOME redirects the dismissal file; CLAUDE_JOURNAL_PATH
  # redirects the journal. Both are required for hermetic isolation.
  ( HOME="$home_override" \
      CLAUDE_JOURNAL_PATH="$FIXTURE/.claude/journal.jsonl" \
      STUB_AUDIT_OUTPUT_FILE="$HOO1_STUB_OUT" \
      bash "$HOO1_HOOK_DIR/notify-sensor-staleness.sh" < /dev/null )
}

# Fixture: a single enforcement sensor (computational-FF) with last_fired=null
# (i.e. never fired → days_silent=null → Q3 treats as stale).
HOO1_SENSORS_1ENF='{"version":1,"sensors":[
  {"name":"block-dangerous-git","should_fire_when":"PreToolUse:Bash","max_silent_days":1,"fallback_role":"computational-FF","must_fire_in_session":false,"enabled":true}
]}'
# Audit-flag output: 1 entry, days_silent=null
HOO1_AUDIT_1ENF='[{"name":"block-dangerous-git","last_fired":null,"days_silent":null,"fallback_role":"computational-FF","max_silent_days":1,"must_fire_in_session":false,"enabled":true,"should_fire_when":"PreToolUse:Bash"}]'

# Test 1: Q3 enforcement trigger fires (1 stale enforcement, no dismissal file).
# Expect: stdout contains `additionalContext` with the sensor name + [enforcement].
HOO1_T1_HOME="$FIXTURE/hook1-t1-home"; mkdir -p "$HOO1_T1_HOME"
HOO1_T1_OUT=$(hoo1_run "$HOO1_SENSORS_1ENF" "$HOO1_AUDIT_1ENF" "$HOO1_T1_HOME" 2>/dev/null)
HOO1_T1_RC=$?
if [ "$HOO1_T1_RC" = "0" ] \
   && [ -n "$HOO1_T1_OUT" ] \
   && printf '%s' "$HOO1_T1_OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
   && printf '%s' "$HOO1_T1_OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF 'block-dangerous-git' \
   && printf '%s' "$HOO1_T1_OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF '[enforcement]'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s Q3 enforcement: 1 stale fires additionalContext with [enforcement] tag\n' "notify-sensor-staleness"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s Q3 enforcement: hook did not fire correctly (rc=%s, out=%s)\n' "notify-sensor-staleness" "$HOO1_T1_RC" "$HOO1_T1_OUT"
fi

# Test 2: Q3 advisory threshold (3+ fires). 3 stale advisory sensors (inferrential-FF).
HOO1_SENSORS_3ADV='{"version":1,"sensors":[
  {"name":"auto-review-nudge","should_fire_when":"UserPromptSubmit:*","max_silent_days":7,"fallback_role":"inferential-FF","must_fire_in_session":false,"enabled":true},
  {"name":"iron-rule-reminder","should_fire_when":"UserPromptSubmit:*","max_silent_days":7,"fallback_role":"inferential-FF","must_fire_in_session":false,"enabled":true},
  {"name":"skill-nudge","should_fire_when":"UserPromptSubmit:*","max_silent_days":7,"fallback_role":"inferential-FF","must_fire_in_session":false,"enabled":true}
]}'
HOO1_AUDIT_3ADV='[{"name":"auto-review-nudge","last_fired":null,"days_silent":null,"fallback_role":"inferential-FF","max_silent_days":7,"must_fire_in_session":false,"enabled":true,"should_fire_when":"UserPromptSubmit:*"},{"name":"iron-rule-reminder","last_fired":null,"days_silent":null,"fallback_role":"inferential-FF","max_silent_days":7,"must_fire_in_session":false,"enabled":true,"should_fire_when":"UserPromptSubmit:*"},{"name":"skill-nudge","last_fired":null,"days_silent":null,"fallback_role":"inferential-FF","max_silent_days":7,"must_fire_in_session":false,"enabled":true,"should_fire_when":"UserPromptSubmit:*"}]'
HOO1_T2_HOME="$FIXTURE/hook1-t2-home"; mkdir -p "$HOO1_T2_HOME"
HOO1_T2_OUT=$(hoo1_run "$HOO1_SENSORS_3ADV" "$HOO1_AUDIT_3ADV" "$HOO1_T2_HOME" 2>/dev/null)
HOO1_T2_RC=$?
if [ "$HOO1_T2_RC" = "0" ] \
   && [ -n "$HOO1_T2_OUT" ] \
   && printf '%s' "$HOO1_T2_OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1 \
   && printf '%s' "$HOO1_T2_OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF '[advisory]' \
   && printf '%s' "$HOO1_T2_OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF 'iron-rule-reminder' \
   && printf '%s' "$HOO1_T2_OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF 'auto-review-nudge' \
   && printf '%s' "$HOO1_T2_OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -qF 'skill-nudge'; then
  PASS=$((PASS+1)); printf '  ✅ %-26s Q3 advisory: 3 stale fires additionalContext with [advisory] tag\n' "notify-sensor-staleness"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s Q3 advisory: hook did not fire correctly (rc=%s, out=%s)\n' "notify-sensor-staleness" "$HOO1_T2_RC" "$HOO1_T2_OUT"
fi

# Test 3: Q3 advisory below threshold (silent). 2 stale advisory + 0 enforcement
# → trigger does NOT fire → no additionalContext on stdout.
HOO1_SENSORS_2ADV='{"version":1,"sensors":[
  {"name":"auto-review-nudge","should_fire_when":"UserPromptSubmit:*","max_silent_days":7,"fallback_role":"inferential-FF","must_fire_in_session":false,"enabled":true},
  {"name":"iron-rule-reminder","should_fire_when":"UserPromptSubmit:*","max_silent_days":7,"fallback_role":"inferential-FF","must_fire_in_session":false,"enabled":true}
]}'
HOO1_AUDIT_2ADV='[{"name":"auto-review-nudge","last_fired":null,"days_silent":null,"fallback_role":"inferential-FF","max_silent_days":7,"must_fire_in_session":false,"enabled":true,"should_fire_when":"UserPromptSubmit:*"},{"name":"iron-rule-reminder","last_fired":null,"days_silent":null,"fallback_role":"inferential-FF","max_silent_days":7,"must_fire_in_session":false,"enabled":true,"should_fire_when":"UserPromptSubmit:*"}]'
HOO1_T3_HOME="$FIXTURE/hook1-t3-home"; mkdir -p "$HOO1_T3_HOME"
HOO1_T3_OUT=$(hoo1_run "$HOO1_SENSORS_2ADV" "$HOO1_AUDIT_2ADV" "$HOO1_T3_HOME" 2>/dev/null)
HOO1_T3_RC=$?
if [ "$HOO1_T3_RC" = "0" ] && [ -z "$HOO1_T3_OUT" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s Q3 advisory below threshold: 2 stale is silent (no additionalContext)\n' "notify-sensor-staleness"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s Q3 advisory below threshold: expected silent, got rc=%s out=%s\n' "notify-sensor-staleness" "$HOO1_T3_RC" "$HOO1_T3_OUT"
fi

# Test 4: Q4 hash match (silent). 1 stale enforcement + a dismissal file whose
# `dismissed_set_hash` matches the current stale-set hash AND `dismissed_until`
# is in the future. Expect: no additionalContext.
HOO1_T4_HOME="$FIXTURE/hook1-t4-home"; mkdir -p "$HOO1_T4_HOME/.claude/state"
HOO1_T4_HASH=$(printf 'block-dangerous-git' | shasum -a 256 | awk '{print $1}')
# dismissed_until = 2099-01-01 (way in the future, deterministic across runs)
cat > "$HOO1_T4_HOME/.claude/state/kbg-staleness-dismissed.json" <<EOF
{"dismissed_until":"2099-01-01T00:00:00Z","dismissed_set_hash":"sha256:${HOO1_T4_HASH}"}
EOF
HOO1_T4_OUT=$(hoo1_run "$HOO1_SENSORS_1ENF" "$HOO1_AUDIT_1ENF" "$HOO1_T4_HOME" 2>/dev/null)
HOO1_T4_RC=$?
if [ "$HOO1_T4_RC" = "0" ] && [ -z "$HOO1_T4_OUT" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s Q4 hash match: matching dismissal + future TTL is silent\n' "notify-sensor-staleness"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s Q4 hash match: expected silent, got rc=%s out=%s\n' "notify-sensor-staleness" "$HOO1_T4_RC" "$HOO1_T4_OUT"
fi

# Test 5: graceful degradation (silent). Missing sensors.json. Expect: no
# additionalContext, exit 0, no stderr.
HOO1_T5_HOME="$FIXTURE/hook1-t5-home"; mkdir -p "$HOO1_T5_HOME"
# 4th arg "" tells hoo1_run to skip writing sensors.json entirely.
HOO1_T5_OUT=$(hoo1_run "" "[]" "$HOO1_T5_HOME" "" 2>&1)
HOO1_T5_RC=$?
if [ "$HOO1_T5_RC" = "0" ] && [ -z "$HOO1_T5_OUT" ]; then
  PASS=$((PASS+1)); printf '  ✅ %-26s graceful degradation: missing sensors.json → silent, rc=0, no stderr\n' "notify-sensor-staleness"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-26s graceful degradation: expected silent/rc=0, got rc=%s out=%s\n' "notify-sensor-staleness" "$HOO1_T5_RC" "$HOO1_T5_OUT"
fi
