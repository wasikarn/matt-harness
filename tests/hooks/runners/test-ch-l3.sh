#!/usr/bin/env bash
# test-ch-l3.sh — L3 bounded-autonomy machinery (ADR 0003):
#   - l3-push-gate.sh  (Gate 2: deny push/merge/hooksPath while unreviewed)
#   - _lib.sh L3 immunity (profile-off / disabled-hooks can't disarm gates under L3)
#   - l3-loop-guard.py (caps + cage, fail-closed, flag-immutable)
#   - audit check-numbering stability (#32/#34/#41/#43/#44 must not drift)
# shellcheck disable=SC1090,SC2034,SC2086
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"

REPO="$(cd "$HOOKS/.." && pwd)"
GUARD="$REPO/scripts/l3-loop-guard.py"
AUDIT="$REPO/skills/harness-audit/scripts/audit.sh"

# pcheck <env-string> <want-decision> <label> <command>
# Runs l3-push-gate.sh with the given env (e.g. "KBG_AUTONOMY_L3=1") on a Bash command.
pcheck() {
  local env="$1" want="$2" label="$3" cmd="$4" out got
  out=$(printf '%s' "$(bash_event "$cmd")" | env $env bash "$HOOKS/gates/l3-push-gate.sh" 2>/dev/null)
  if [ -z "$out" ]; then got="none"; else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"); fi
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l3-push-gate" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "l3-push-gate" "$label" "$want" "$got"; fi
}

# --- l3-push-gate: flag-scoped, Gate-2 enforcement ---
pcheck ""                                            none "inert when L3 unset (normal session)"          "git push origin develop"
pcheck "KBG_AUTONOMY_L3=1"                            deny "L3 active + unreviewed: deny git push"          "git push origin develop"
pcheck "KBG_AUTONOMY_L3=1"                            deny "L3 active + unreviewed: deny gh pr merge"        "gh pr merge 12"
pcheck "KBG_AUTONOMY_L3=1 KBG_L3_REVIEW_DONE=1"       none "L3 active + reviewed: allow git push"           "git push origin develop"
pcheck "KBG_AUTONOMY_L3=1 KBG_L3_REVIEW_DONE=1"       deny "reviewed but inline-forged flag: deny"          "KBG_L3_REVIEW_DONE=1 git push"
pcheck "KBG_AUTONOMY_L3=1 KBG_L3_REVIEW_DONE=1"       deny "reviewed: still deny hooksPath redirect"        "git config core.hooksPath /tmp/x"
pcheck "KBG_AUTONOMY_L3=1 KBG_L3_REVIEW_DONE=1"       deny "reviewed: deny ephemeral -c hooksPath"          "git -c core.hooksPath=/tmp/x config foo"
pcheck "KBG_AUTONOMY_L3=1"                            none "L3 active: allow local commit (no push)"        "git commit -m wip"
# Immunity: profile=off must NOT disarm the push-gate during an L3 run.
pcheck "KBG_AUTONOMY_L3=1 CLAUDE_HOOK_PROFILE=off"    deny "immunity: profile=off can't bypass under L3"    "git push origin develop"
pcheck "KBG_AUTONOMY_L3=1 CLAUDE_DISABLED_HOOKS=l3-push-gate" deny "immunity: disabled-hooks can't bypass under L3" "git push origin develop"

# --- l3-loop-guard.py: caps + cage, fail-closed, flag-immutable ---
# Run the guard inline so the exit code is captured in gcheck's own scope (a
# $(...) wrapper would lose $? to its subshell). out=$(...) captures stdout; the
# very next $? is the guard's exit.
gcheck() {
  local want="$1" wexit="$2" label="$3" env="$4"; shift 4
  local out gx got
  out=$(env $env python3 "$GUARD" "$@" 2>/dev/null); gx=$?
  got=$(printf '%s' "$out" | jq -r '.decision // "none"' 2>/dev/null || echo "none")
  if [ "$got" = "$want" ] && [ "$gx" = "$wexit" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l3-loop-guard" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s/%s, got %s/%s)\n' "l3-loop-guard" "$label" "$want" "$wexit" "$got" "$gx"; fi
}

if command -v python3 >/dev/null 2>&1; then
  # selftest must pass (matcher + fail-closed posture).
  if python3 "$GUARD" selftest >/dev/null 2>&1; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l3-loop-guard" "selftest passes"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "l3-loop-guard" "selftest FAILED"; fi

  # check-act: flag off → STOP (refuses to run); caged path → REVERT; editable → CONTINUE; tamper → REVERT.
  gcheck STOP     10 "check-act refuses when flag off"      ""                     check-act "$REPO/hooks/x.sh"
  gcheck REVERT   20 "check-act REVERTs on caged hooks/ path" "KBG_AUTONOMY_L3=1"   check-act "$REPO/hooks/_lib.sh"
  gcheck REVERT   20 "check-act REVERTs on caged audit.sh"  "KBG_AUTONOMY_L3=1"     check-act "$AUDIT"
  gcheck CONTINUE  0 "check-act allows an editable skill"   "KBG_AUTONOMY_L3=1"     check-act "$REPO/skills/recursive-improve/SKILL.md"
  gcheck REVERT   20 "check-act REVERTs on tamper var"      "KBG_AUTONOMY_L3=1"     check-act "$REPO/README.md" --candidate-cmd "export KBG_AUTONOMY_L3=1"
  gcheck REVERT   20 "check-act REVERTs path outside repo"  "KBG_AUTONOMY_L3=1"     check-act "/etc/hosts"

  # precheck: flag off → STOP; max-runs cap → STOP after the budget.
  gcheck STOP     10 "precheck refuses when flag off"       ""                     precheck --state "$FIXTURE/st1.json" --max-runs 1 --no-dirty-abort
  gcheck CONTINUE  0 "precheck CONTINUE on first cycle"     "KBG_AUTONOMY_L3=1"    precheck --state "$FIXTURE/st2.json" --max-runs 1 --no-dirty-abort
  gcheck STOP     10 "precheck STOP when max-runs reached"  "KBG_AUTONOMY_L3=1"    precheck --state "$FIXTURE/st2.json" --max-runs 1 --no-dirty-abort
else
  printf '  ⚠️  python3 absent — skipped l3-loop-guard checks\n'
fi

# --- audit check-numbering stability: the autonomy-load-bearing IDs must not drift ---
ncheck() {
  local id="$1"
  if /usr/bin/grep -qE "^# ${id}\. " "$AUDIT"; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit-numbering" "#${id} present"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit-numbering" "#${id} MISSING (load-bearing ID drifted)"; fi
}
for id in 32 34 41 43 44; do ncheck "$id"; done

# --- audit #43b: cage-completeness must CRIT when a required anchor is removed ---
# (test-honesty Rule 9 "distinguishes-or-it-doesn't": a green-only check is decoration.
# Runs the REAL audit.sh against a fixture that gates #43 on (fake ADR 0003 + real guard
# so 43a/43c stay clean) with a cage that is the real cage MINUS one required anchor.)
CF="$FIXTURE/cage43"; mkdir -p "$CF/docs/adr" "$CF/scripts" "$CF/agents"
printf -- '---\nname: x\ntools: Read\n---\nx\n' > "$CF/agents/x.md"  # satisfy audit's fleet guard
printf '# adr0003 — gate #43 on\n' > "$CF/docs/adr/0003-l3-bounded-autonomy.md"
cp "$REPO/scripts/l3-loop-guard.py" "$CF/scripts/l3-loop-guard.py"
/usr/bin/grep -vxF 'CONTEXT.md' "$REPO/scripts/l3-cage.txt" > "$CF/scripts/l3-cage.txt"  # holed
HOLED=$(bash "$AUDIT" "$CF" 2>&1)
if printf '%s\n' "$HOLED" | /usr/bin/grep -q 'cage incomplete' && printf '%s\n' "$HOLED" | /usr/bin/grep -qF 'CONTEXT.md'; then
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#43b" "CRITs on holed cage (names missing anchor)"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#43b" "did NOT CRIT on holed cage"
fi
cp "$REPO/scripts/l3-cage.txt" "$CF/scripts/l3-cage.txt"  # full cage = control
if bash "$AUDIT" "$CF" 2>&1 | /usr/bin/grep -q 'cage incomplete'; then
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#43b" "false-positive on complete cage"
else
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#43b" "silent on complete cage"
fi

report
