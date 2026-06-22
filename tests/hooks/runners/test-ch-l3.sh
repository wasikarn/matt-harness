#!/usr/bin/env bash
# test-ch-l3.sh — L3 bounded-autonomy machinery (ADR 0003):
#   - l3-push-gate.sh  (Gate 2: deny push/merge/hooksPath while unreviewed)
#   - _lib.sh L3 immunity (profile-off / disabled-hooks can't disarm gates under L3)
#   - block-dangerous-git.sh (L3 rollback carve-out: allow `reset --hard <l3-precycle>` under flag)
#   - l3-loop-guard.py (caps + cage, fail-closed, flag-immutable)
#   - audit check-numbering stability (#32/#34/#41/#43/#44 must not drift)
# shellcheck disable=SC1090,SC2034,SC2086
# shellcheck shell=bash
source "$(dirname "$0")/test-critical-hooks-lib.sh"

REPO="$(cd "$HOOKS/.." && pwd)"
GUARD="$REPO/scripts/l3-loop-guard.py"
AUDIT="$REPO/skills/harness-audit/scripts/audit.sh"

# pcheck <env-string> <want-decision> <label> <command>
# Runs l3-push-gate.sh with the given env on a Bash command. The armed cases pass
# KBG_AUTONOMY=1 + CLAUDE_PROJECT_DIR pointing at a per-repo arming fixture (the
# only surface autonomy_on() honors — guard 3); a user-global flag arms nothing.
pcheck() {
  local env="$1" want="$2" label="$3" cmd="$4" out got
  out=$(printf '%s' "$(bash_event "$cmd")" | env $env bash "$HOOKS/gates/l3-push-gate.sh" 2>/dev/null)
  if [ -z "$out" ]; then got="none"; else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"); fi
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l3-push-gate" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "l3-push-gate" "$label" "$want" "$got"; fi
}

# --- per-repo arming fixtures (guard 3, design §5 F1) ---
# autonomy_on() arms ONLY from a per-repo .claude/settings.local.json env block;
# a user-global KBG_AUTONOMY=1 (env set but the per-repo file does not carry it)
# arms NOTHING. ARMED_PROJ carries the arming key; BARE_PROJ does not (simulates a
# user-global flag reaching a repo that did not arm locally).
ARMED_PROJ="$FIXTURE/armproj"; mkdir -p "$ARMED_PROJ/.claude"
printf '{"env":{"KBG_AUTONOMY":"1"}}' > "$ARMED_PROJ/.claude/settings.local.json"
BARE_PROJ="$FIXTURE/bareproj"; mkdir -p "$BARE_PROJ/.claude"
printf '{"permissions":{}}' > "$BARE_PROJ/.claude/settings.local.json"
# Armed env = KBG_AUTONOMY=1 + CLAUDE_PROJECT_DIR → arming fixture (mirrors Claude
# Code injecting the per-repo env block into the hook process). GLOBAL = env set
# but CLAUDE_PROJECT_DIR → a repo whose local settings do NOT carry the key.
ARMED_ENV="KBG_AUTONOMY=1 CLAUDE_PROJECT_DIR=$ARMED_PROJ"
GLOBAL_ENV="KBG_AUTONOMY=1 CLAUDE_PROJECT_DIR=$BARE_PROJ"

# --- l3-push-gate: flag-scoped, Gate-2 enforcement (single-key autonomy_on) ---
pcheck ""                                            none "inert when flag unset (normal session)"          "git push origin develop"
pcheck "$ARMED_ENV"                                  deny "armed (per-repo) + unreviewed: deny git push"    "git push origin develop"
pcheck "$ARMED_ENV"                                  deny "armed (per-repo) + unreviewed: deny gh pr merge" "gh pr merge 12"
pcheck "$ARMED_ENV KBG_REVIEW_DONE=1"                none "armed + reviewed: allow git push"               "git push origin develop"
pcheck "$ARMED_ENV KBG_REVIEW_DONE=1"                deny "reviewed but inline-forged flag: deny"          "KBG_REVIEW_DONE=1 git push"
pcheck "$ARMED_ENV KBG_REVIEW_DONE=1"                deny "reviewed: still deny hooksPath redirect"        "git config core.hooksPath /tmp/x"
pcheck "$ARMED_ENV KBG_REVIEW_DONE=1"                deny "reviewed: deny ephemeral -c hooksPath"          "git -c core.hooksPath=/tmp/x config foo"
pcheck "$ARMED_ENV"                                  none "armed: allow local commit (no push)"            "git commit -m wip"
# Guard 3: a user-global flag (env=1 but the per-repo file does not carry it) arms
# NOTHING — the push gate no-ops, exactly like a flag-unset session.
pcheck "$GLOBAL_ENV"                                 none "user-global flag (no per-repo arming): arms nothing" "git push origin develop"
# Immunity: profile=off / disabled-hooks must NOT disarm the push-gate while armed.
pcheck "$ARMED_ENV CLAUDE_HOOK_PROFILE=off"          deny "immunity: profile=off can't bypass when armed"  "git push origin develop"
pcheck "$ARMED_ENV CLAUDE_DISABLED_HOOKS=l3-push-gate" deny "immunity: disabled-hooks can't bypass when armed" "git push origin develop"

# --- block-dangerous-git: L3 rollback carve-out (ADR 0003) ---
# The loop rolls back a failed cycle with `git reset --hard <l3-precycle-* tag>`.
# block-dangerous-git blanket-denies `git reset --hard`; the carve-out allows ONLY
# that exact command, full-anchored, and ONLY under KBG_AUTONOMY_L3=1.
# dgcheck <env> <want> <label> <command>
dgcheck() {
  local env="$1" want="$2" label="$3" cmd="$4" out got
  out=$(printf '%s' "$(bash_event "$cmd")" | env $env bash "$HOOKS/gates/block-dangerous-git.sh" 2>/dev/null)
  if [ -z "$out" ]; then got="none"; else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"); fi
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "block-dangerous-git" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "block-dangerous-git" "$label" "$want" "$got"; fi
}
dgcheck "KBG_AUTONOMY_L3=1"      none "L3 rollback: allow reset --hard <l3-precycle tag>"   "git reset --hard l3-precycle-run1-1"
dgcheck "KBG_AUTONOMY_L3=1"      deny "L3 on: deny reset --hard to a non-precycle ref"      "git reset --hard HEAD~3"
dgcheck "-u KBG_AUTONOMY_L3"     deny "flag off: deny reset --hard even to l3-precycle tag" "git reset --hard l3-precycle-run1-1"
dgcheck "KBG_AUTONOMY_L3=1"      deny "carve-out can't ride a compound (force-push appended)" "git reset --hard l3-precycle-run1-1 && git push --force origin main"

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

  # no-progress cap (--max-flat): 2 consecutive GREEN-but-flat cycles → STOP, even
  # though nothing failed. Distinct from fail-streak (which counts reds).
  gcheck CONTINUE  0 "precheck c1 (no-progress)"           "KBG_AUTONOMY_L3=1"    precheck --state "$FIXTURE/st3.json" --max-runs 9 --max-flat 2 --no-dirty-abort
  gcheck CONTINUE  0 "record green-flat #1"                "KBG_AUTONOMY_L3=1"    record-result --state "$FIXTURE/st3.json" --green --flat
  gcheck CONTINUE  0 "precheck c2 (1 flat < cap)"          "KBG_AUTONOMY_L3=1"    precheck --state "$FIXTURE/st3.json" --max-runs 9 --max-flat 2 --no-dirty-abort
  gcheck CONTINUE  0 "record green-flat #2"                "KBG_AUTONOMY_L3=1"    record-result --state "$FIXTURE/st3.json" --green --flat
  gcheck STOP     10 "precheck STOP at no-progress cap"    "KBG_AUTONOMY_L3=1"    precheck --state "$FIXTURE/st3.json" --max-runs 9 --max-flat 2 --no-dirty-abort
  # an IMPROVED green resets the no-progress streak (so a productive cycle clears it).
  gcheck CONTINUE  0 "precheck c1 (reset path)"            "KBG_AUTONOMY_L3=1"    precheck --state "$FIXTURE/st4.json" --max-runs 9 --max-flat 1 --no-dirty-abort
  gcheck CONTINUE  0 "record green-flat (streak=1)"        "KBG_AUTONOMY_L3=1"    record-result --state "$FIXTURE/st4.json" --green --flat
  gcheck CONTINUE  0 "record green-improved (resets)"      "KBG_AUTONOMY_L3=1"    record-result --state "$FIXTURE/st4.json" --green
  gcheck CONTINUE  0 "precheck continues after reset"      "KBG_AUTONOMY_L3=1"    precheck --state "$FIXTURE/st4.json" --max-runs 9 --max-flat 1 --no-dirty-abort
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
