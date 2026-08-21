#!/usr/bin/env bash
# Behavioral tests for gate:skill:review-pr-loop (hooks/gates/review-pr-loop-gate.sh).
# The gate asks ONLY at genuine exhaustion on the exact reviewed HEAD; every
# other shape allows. Fixture git repo + REVIEW_PR_STATE_DIR seam — never
# touches ~/.claude/state. Run standalone: bash tests/hooks/test-review-pr-loop-gate.sh
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/review-pr-loop-gate.sh"

pass=0
fail=0
check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/looploop.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

REPO="$TMP/repo"
STATE="$TMP/state"
mkdir -p "$REPO" "$STATE"
git init -q -b develop "$REPO"
git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

skill_payload() { # skill_payload <skill-name>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Skill","tool_input":{"skill":sys.argv[1]},"session_id":"loopgate-test"}))' "$1"
}

state_json() { # state_json <loop_decision> <loop_reason> <force_human> <last_sha> <branch>
  python3 -c 'import json,sys
d={"loop_decision":sys.argv[1],"loop_reason":sys.argv[2],
   "force_human":sys.argv[3]=="true","last_sha":sys.argv[4],"branch":sys.argv[5],
   "round":5,"clean":False,"review_mode":"own-branch"}
print(json.dumps(d))' "$@" > "$STATE/review-last.json"
}

run_gate() { # run_gate <payload> [extra env K=V ...]
  local p="$1"; shift
  # KBG_SKIP_LOOP_GATE= neutralizes an ambient export; HOME redirected so the
  # journal writes into the fixture, not the real ~/.local/share/kbg/metrics.
  (cd "$REPO" && printf '%s' "$p" \
    | env KBG_SKIP_LOOP_GATE= HOME="$TMP" REVIEW_PR_STATE_DIR="$STATE" "$@" bash "$GATE")
}

asks() { grep -q '"permissionDecision": "ask"'; }

# 1. Non-review-pr skill → allow silently
rm -f "$STATE/review-last.json"
state_json stop ceiling true "$HEAD_SHA" develop
out=$(run_gate "$(skill_payload kbg:review-pr-finish)"); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "review-pr-finish never matches (anchored regex)" $?

# 2. No state file → allow
rm -f "$STATE/review-last.json"
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "missing state → allow (first-ever review)" $?

# 3. Malformed state → allow
echo '{broken' > "$STATE/review-last.json"
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "malformed state → allow (fail-open)" $?

# 4. Converged stop → allow: the loop ended WELL, never ask on the success path
state_json stop converged false "$HEAD_SHA" develop
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "converged stop → allow (success path never asks)" $?

# 5. Continue verdict → allow (the normal auto-loop re-invocation)
state_json continue "" false "$HEAD_SHA" develop
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "loop_decision=continue → allow (auto-loop unharmed)" $?

# 6. Ceiling stop, same HEAD, same branch → ASK
state_json stop ceiling true "$HEAD_SHA" develop
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && asks <<<"$out"
check "ceiling stop on current HEAD → ask" $?

# 6b. Unqualified skill name also matches
out=$(run_gate "$(skill_payload review-pr)"); rc=$?
[ "$rc" -eq 0 ] && asks <<<"$out"
check "unqualified 'review-pr' also gated" $?

# 7. Same exhaustion but HEAD moved since → allow (human did work)
state_json stop ceiling true "0000000000000000000000000000000000000000" develop
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "exhausted but HEAD moved → allow (freshness guard)" $?

# 8. Same exhaustion but different branch → allow
state_json stop ceiling true "$HEAD_SHA" other-branch
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "exhausted on another branch → allow" $?

# 9. force_human=true with NO loop_decision (Phase-7-skip shape) → ask
python3 -c 'import json,sys
print(json.dumps({"force_human":True,"last_sha":sys.argv[1],"branch":"develop","round":5}))' "$HEAD_SHA" > "$STATE/review-last.json"
out=$(run_gate "$(skill_payload kbg:review-pr)"); rc=$?
[ "$rc" -eq 0 ] && asks <<<"$out"
check "force_human without persisted verdict → ask (partial Phase-7-skip cover)" $?

# 10. KBG_SKIP_LOOP_GATE=1 on the asking shape → allow (headless valve)
state_json stop ceiling true "$HEAD_SHA" develop
out=$(run_gate "$(skill_payload kbg:review-pr)" KBG_SKIP_LOOP_GATE=1); rc=$?
[ "$rc" -eq 0 ] && ! asks <<<"$out"
check "KBG_SKIP_LOOP_GATE=1 → allow (headless valve)" $?

# 11. Journal recorded both an ask and an allow decision
j="$TMP/.local/share/kbg/metrics/review-pr-loop-gate.jsonl"
[ -f "$j" ] && grep -q '"decision": "ask"' "$j" && grep -q '"decision": "allow"' "$j"
check "journal captured matched decisions (observability)" $?

# 12. Sync-seam pin (compliance-audit advisory 2026-08-22): the gate's
# EXHAUSTED tuple duplicates should-continue-loop.sh's reason tokens with no
# shared source — a token rename there would silently dis-arm the gate
# ("stalled" has no force_human backstop). Machine-pin both sides.
seam=0
LOOP_SCRIPT="$ROOT/skills/review-pr/scripts/should-continue-loop.sh"
for tok in ceiling regressed churning stalled; do
  grep -q "$tok" "$LOOP_SCRIPT" || { echo "    token '$tok' missing from should-continue-loop.sh" >&2; seam=1; }
done
grep -q 'EXHAUSTED = ("ceiling", "regressed", "churning", "stalled")' "$GATE" \
  || { echo "    gate EXHAUSTED tuple changed — re-pin against loop script tokens" >&2; seam=1; }
check "EXHAUSTED tokens machine-pinned to loop script (sync-seam)" $seam

echo
echo "review-pr-loop-gate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
