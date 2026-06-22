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
# Gate-2 maker≠checker (#30): a fixture journal with a review_finding event (a
# kbg:review-pr pass) + an empty one, so the push-gate's review-pr requirement can
# be exercised hermetically (CLAUDE_JOURNAL_PATH overrides the real journal).
REVJ="$FIXTURE/revjournal.jsonl"
printf '%s\n' '{"id":"x","ts":"2026-06-22T00:00:00Z","session":"s","hook":"review-pr","event":"review_finding","source":"journal_append","fields":{}}' > "$REVJ"
EMPTYJ="$FIXTURE/emptyjournal.jsonl"; : > "$EMPTYJ"

# --- l3-push-gate: flag-scoped, Gate-2 enforcement (single-key autonomy_on) ---
pcheck ""                                            none "inert when flag unset (normal session)"          "git push origin develop"
pcheck "$ARMED_ENV"                                  deny "armed (per-repo) + unreviewed: deny git push"    "git push origin develop"
pcheck "$ARMED_ENV"                                  deny "armed (per-repo) + unreviewed: deny gh pr merge" "gh pr merge 12"
pcheck "$ARMED_ENV KBG_REVIEW_DONE=1 CLAUDE_JOURNAL_PATH=$REVJ"    none "armed + reviewed (review-pr pass journalled): allow git push" "git push origin develop"
pcheck "$ARMED_ENV KBG_REVIEW_DONE=1 CLAUDE_JOURNAL_PATH=$EMPTYJ"  deny "armed + KBG_REVIEW_DONE but no review-pr pass → deny (maker≠checker)" "git push origin develop"
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

# --- l4-act-gate: Act-layer self-launch guard (design §5 Act-layer gate + §8) ---
# The launchd plist + kill-file live outside the repo; this PreToolUse gate DENIES
# any write/launchctl mutation to them while armed. Real-DENY matrix (the Slice-3
# hard precondition). write_event + actcheck/actwcheck mirror pcheck.
write_event() { printf '{"tool_name":"Write","tool_input":{"file_path":%s}}' "$(printf '%s' "$1" | jq -R .)"; }
actcheck() {
  local env="$1" want="$2" label="$3" cmd="$4" out got
  out=$(printf '%s' "$(bash_event "$cmd")" | env $env bash "$HOOKS/gates/l4-act-gate.sh" 2>/dev/null)
  if [ -z "$out" ]; then got="none"; else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"); fi
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l4-act-gate" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "l4-act-gate" "$label" "$want" "$got"; fi
}
actwcheck() {
  local env="$1" want="$2" label="$3" fp="$4" out got
  out=$(printf '%s' "$(write_event "$fp")" | env $env bash "$HOOKS/gates/l4-act-gate.sh" 2>/dev/null)
  if [ -z "$out" ]; then got="none"; else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"); fi
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l4-act-gate" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "l4-act-gate" "$label" "$want" "$got"; fi
}
actcheck ""            none "inert when flag unset (normal session)"             "launchctl unload ~/Library/LaunchAgents/com.kbg.l4-launcher.plist"
actcheck "$ARMED_ENV"  deny "armed: deny launchctl unload of the plist"         "launchctl unload ~/Library/LaunchAgents/com.kbg.l4-launcher.plist"
actcheck "$ARMED_ENV"  deny "armed: deny launchctl bootstrap of the plist"      "launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.kbg.l4-launcher.plist"
actcheck "$ARMED_ENV"  none "armed: launchctl list (read) allowed"              "launchctl list"
actcheck "$ARMED_ENV"  deny "armed: deny write redirection to the plist"        "echo x > ~/Library/LaunchAgents/com.kbg.l4-launcher.plist"
actcheck "$ARMED_ENV"  deny "armed: deny rm of the kill-file"                   "rm ~/.claude/kbg-l4-kill"
actcheck "$ARMED_ENV"  none "armed: cat the plist (read) allowed"               "cat ~/Library/LaunchAgents/com.kbg.l4-launcher.plist"
actcheck "$ARMED_ENV"  none "armed: normal git commit (not an act-gate concern)" "git commit -m wip"
actwcheck "$ARMED_ENV" deny "armed: Write the plist → deny"                     "$HOME/Library/LaunchAgents/com.kbg.l4-launcher.plist"
actwcheck "$ARMED_ENV" deny "armed: Write the kill-file → deny"                 "$HOME/.claude/kbg-l4-kill"
actwcheck "$ARMED_ENV" none "armed: Write a normal path → none"                 "/tmp/some-file"

# --- block-dangerous-git: L3/L4 rollback carve-out (ADR 0003/0004) ---
# The loop rolls back a failed cycle with `git reset --hard <l3-precycle-* tag>`.
# block-dangerous-git blanket-denies `git reset --hard`; the carve-out allows ONLY
# that exact command, full-anchored, and ONLY when armed (autonomy_on).
# dgcheck <env> <want> <label> <command>
dgcheck() {
  local env="$1" want="$2" label="$3" cmd="$4" out got
  out=$(printf '%s' "$(bash_event "$cmd")" | env $env bash "$HOOKS/gates/block-dangerous-git.sh" 2>/dev/null)
  if [ -z "$out" ]; then got="none"; else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"); fi
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "block-dangerous-git" "$label"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "block-dangerous-git" "$label" "$want" "$got"; fi
}
dgcheck "$ARMED_ENV"  none "rollback: allow reset --hard <l3-precycle tag> when armed"   "git reset --hard l3-precycle-run1-1"
dgcheck "$ARMED_ENV"  deny "armed: deny reset --hard to a non-precycle ref"              "git reset --hard HEAD~3"
dgcheck ""            deny "flag off: deny reset --hard even to l3-precycle tag"         "git reset --hard l3-precycle-run1-1"
dgcheck "$ARMED_ENV"  deny "carve-out can't ride a compound (force-push appended)"       "git reset --hard l3-precycle-run1-1 && git push --force origin main"

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
  gcheck REVERT   20 "check-act REVERTs on caged hooks/ path" "$ARMED_ENV"   check-act "$REPO/hooks/_lib.sh"
  gcheck REVERT   20 "check-act REVERTs on caged audit.sh"  "$ARMED_ENV"     check-act "$AUDIT"
  gcheck CONTINUE  0 "check-act allows an editable skill"   "$ARMED_ENV"     check-act "$REPO/skills/recursive-improve/SKILL.md"
  gcheck REVERT   20 "check-act REVERTs on tamper var"      "$ARMED_ENV"     check-act "$REPO/README.md" --candidate-cmd "export KBG_AUTONOMY=1"
  gcheck REVERT   20 "check-act REVERTs path outside repo"  "$ARMED_ENV"     check-act "/etc/hosts"

  # precheck: flag off → STOP; max-runs cap → STOP after the budget.
  gcheck STOP     10 "precheck refuses when flag off"       ""                     precheck --state "$FIXTURE/st1.json" --max-runs 1 --no-dirty-abort
  gcheck CONTINUE  0 "precheck CONTINUE on first cycle"     "$ARMED_ENV"    precheck --state "$FIXTURE/st2.json" --max-runs 1 --no-dirty-abort
  gcheck STOP     10 "precheck STOP when max-runs reached"  "$ARMED_ENV"    precheck --state "$FIXTURE/st2.json" --max-runs 1 --no-dirty-abort

  # no-progress cap (--max-flat): 2 consecutive GREEN-but-flat cycles → STOP, even
  # though nothing failed. Distinct from fail-streak (which counts reds).
  gcheck CONTINUE  0 "precheck c1 (no-progress)"           "$ARMED_ENV"    precheck --state "$FIXTURE/st3.json" --max-runs 9 --max-flat 2 --no-dirty-abort
  gcheck CONTINUE  0 "record green-flat #1"                "$ARMED_ENV"    record-result --state "$FIXTURE/st3.json" --green --flat
  gcheck CONTINUE  0 "precheck c2 (1 flat < cap)"          "$ARMED_ENV"    precheck --state "$FIXTURE/st3.json" --max-runs 9 --max-flat 2 --no-dirty-abort
  gcheck CONTINUE  0 "record green-flat #2"                "$ARMED_ENV"    record-result --state "$FIXTURE/st3.json" --green --flat
  gcheck STOP     10 "precheck STOP at no-progress cap"    "$ARMED_ENV"    precheck --state "$FIXTURE/st3.json" --max-runs 9 --max-flat 2 --no-dirty-abort
  # an IMPROVED green resets the no-progress streak (so a productive cycle clears it).
  gcheck CONTINUE  0 "precheck c1 (reset path)"            "$ARMED_ENV"    precheck --state "$FIXTURE/st4.json" --max-runs 9 --max-flat 1 --no-dirty-abort
  gcheck CONTINUE  0 "record green-flat (streak=1)"        "$ARMED_ENV"    record-result --state "$FIXTURE/st4.json" --green --flat
  gcheck CONTINUE  0 "record green-improved (resets)"      "$ARMED_ENV"    record-result --state "$FIXTURE/st4.json" --green
  gcheck CONTINUE  0 "precheck continues after reset"      "$ARMED_ENV"    precheck --state "$FIXTURE/st4.json" --max-runs 9 --max-flat 1 --no-dirty-abort

  # R4 cumulative ceiling (design §5 R4): cross-run caps over a sliding window,
  # persisted in a SEPARATE caged file the loop cannot reset. Per-run caps stay;
  # these bound a repeatedly-restarting self-launcher. max-runs-per-window allows N
  # launches then STOPs; max-wall-per-window is fed by record-result --wall-seconds.
  gcheck STOP     10 "R4 cap without --window-seconds → STOP" "$ARMED_ENV" precheck --state "$FIXTURE/r4c.json" --max-runs 9 --no-dirty-abort --max-runs-per-window 2 --window-seconds 0 --window-state "$FIXTURE/winC.json"
  gcheck CONTINUE  0 "R4 c1 (under runs-per-window)"          "$ARMED_ENV" precheck --state "$FIXTURE/r4a.json" --max-runs 9 --no-dirty-abort --max-runs-per-window 2 --window-seconds 3600 --window-state "$FIXTURE/winA.json"
  gcheck CONTINUE  0 "R4 c2 (1 launch < cap 2)"               "$ARMED_ENV" precheck --state "$FIXTURE/r4a.json" --max-runs 9 --no-dirty-abort --max-runs-per-window 2 --window-seconds 3600 --window-state "$FIXTURE/winA.json"
  gcheck STOP     10 "R4 c3 STOP at runs-per-window (2)"      "$ARMED_ENV" precheck --state "$FIXTURE/r4a.json" --max-runs 9 --no-dirty-abort --max-runs-per-window 2 --window-seconds 3600 --window-state "$FIXTURE/winA.json"
  gcheck CONTINUE  0 "R4 record wall 6s (#1)"                 "$ARMED_ENV" record-result --state "$FIXTURE/r4b.json" --green --wall-seconds 6 --window-seconds 3600 --window-state "$FIXTURE/winB.json"
  gcheck CONTINUE  0 "R4 precheck (wall 6s < 10)"             "$ARMED_ENV" precheck --state "$FIXTURE/r4b.json" --max-runs 9 --no-dirty-abort --max-wall-per-window 10 --window-seconds 3600 --window-state "$FIXTURE/winB.json"
  gcheck CONTINUE  0 "R4 record wall 6s (#2 → 12s)"           "$ARMED_ENV" record-result --state "$FIXTURE/r4b.json" --green --wall-seconds 6 --window-seconds 3600 --window-state "$FIXTURE/winB.json"
  gcheck STOP     10 "R4 precheck STOP at wall cap (10s)"     "$ARMED_ENV" precheck --state "$FIXTURE/r4b.json" --max-runs 9 --no-dirty-abort --max-wall-per-window 10 --window-seconds 3600 --window-state "$FIXTURE/winB.json"

  # F4 installer fail-safe (design §5 F4 + §12 guards 1+2): the guard anchors
  # REPO_ROOT to CWD's git toplevel + affirmatively asserts it is a kbg-harness
  # checkout, so an unattended loop never mutates the wrong tree. Arming (per-repo
  # .claude/settings.local.json via ARMED_ENV) is deliberately DECOUPLED from the
  # mutated tree (CWD) — f4check runs the guard with CWD set to <dir>. An armed run
  # in a non-kbg tree must STOP at the F4 gate, not proceed to mutate it.
  # f4check <cwd> <want> <wexit> <label> <guard-args...>
  f4check() {
    local dir="$1" want="$2" wexit="$3" label="$4"; shift 4
    local out gx got
    out=$(cd "$dir" && env $ARMED_ENV python3 "$GUARD" "$@" 2>/dev/null); gx=$?
    got=$(printf '%s' "$out" | jq -r '.decision // "none"' 2>/dev/null || echo "none")
    if [ "$got" = "$want" ] && [ "$gx" = "$wexit" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l3-loop-guard" "$label"
    else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s/%s, got %s/%s)\n' "l3-loop-guard" "$label" "$want" "$wexit" "$got" "$gx"; fi
  }
  # F4 negative: a non-git CWD → STOP (not a git working tree).
  f4check "$BARE_PROJ"  STOP 10 "F4: non-git CWD → STOP"                precheck --state "$FIXTURE/f4a.json" --max-runs 1 --no-dirty-abort
  # F4 negative: a git CWD with no kbg manifest → STOP (not a kbg-harness checkout).
  F4GIT="$FIXTURE/f4git"; mkdir -p "$F4GIT"; git -C "$F4GIT" init -q
  f4check "$F4GIT"      STOP 10 "F4: git CWD but not kbg → STOP"        precheck --state "$FIXTURE/f4b.json" --max-runs 1 --no-dirty-abort
  # F4 positive: the real kbg checkout → anchored, precheck proceeds.
  f4check "$REPO"       CONTINUE 0 "F4: kbg CWD → anchored, precheck proceeds" precheck --state "$FIXTURE/f4c.json" --max-runs 1 --no-dirty-abort

  # R3 per-cycle cage re-assert (design §5 R3): the loop-guard's --assert-cage-intact
  # shells `audit.sh --only 43` every cycle; a holed cage → STOP even when a later
  # model verdict (Slice 2) is green. First exercise the per-check runner directly,
  # then the guard integration (positive + fail-closed).
  R3CF="$FIXTURE/r3cage"; mkdir -p "$R3CF/docs/adr" "$R3CF/scripts" "$R3CF/scripts/l4"
  printf '# adr0003 — gate #43 on\n' > "$R3CF/docs/adr/0003-l3-bounded-autonomy.md"
  /usr/bin/grep -vxF 'CONTEXT.md' "$REPO/scripts/l3-cage.txt" > "$R3CF/scripts/l3-cage.txt"  # holed
  cp "$REPO/scripts/l4/cage-intact.sh" "$R3CF/scripts/l4/cage-intact.sh"  # the per-check runner the relay/`--only` shells
  bash "$AUDIT" --only 43 "$R3CF" >/dev/null 2>&1; _r=$?
  if [ "$_r" -ne 0 ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit --only 43" "holed cage → non-zero CRIT"; else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit --only 43" "holed cage did NOT CRIT"; fi
  bash "$AUDIT" --only 43 "$REPO" >/dev/null 2>&1; _r=$?
  if [ "$_r" -eq 0 ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit --only 43" "real repo → 0 (clean)"; else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (rc=%s)\n' "audit --only 43" "real repo did NOT exit 0" "$_r"; fi
  bash "$AUDIT" --only 99 "$REPO" >/dev/null 2>&1; _r=$?
  if [ "$_r" -eq 2 ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit --only 99" "unsupported id → exit 2"; else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (rc=%s)\n' "audit --only 99" "unsupported id did NOT exit 2" "$_r"; fi
  # Guard integration: clean cage (CWD=$REPO) → CONTINUE; fail-closed (kbg fixture
  # with no audit.sh) → STOP.
  gcheck CONTINUE 0 "R3 --assert-cage-intact: clean cage → CONTINUE" "$ARMED_ENV" precheck --state "$FIXTURE/r3p.json" --max-runs 9 --no-dirty-abort --assert-cage-intact
  R3FC="$FIXTURE/r3fail"; mkdir -p "$R3FC/.claude-plugin" "$R3FC/scripts" "$R3FC/docs/adr"
  printf '{"name":"kbg","version":"0.0.0"}' > "$R3FC/.claude-plugin/plugin.json"
  printf '# adr0003\n' > "$R3FC/docs/adr/0003-l3-bounded-autonomy.md"
  (cd "$R3FC" && git init -q)   # a kbg-sentinel git tree with NO audit.sh
  f4check "$R3FC" STOP 10 "R3 --assert-cage-intact: audit.sh missing → STOP (fail-closed)" precheck --state "$FIXTURE/r3f.json" --max-runs 9 --no-dirty-abort --assert-cage-intact

  # --- Slice 1: l4-auto-keep writer (design §6, #27) + check-act memory exemption ---
  # check-act exempts the sanctioned out-of-repo memory dir (design §6: memory/ is
  # uncaged). _memory_dir() derives from CLAUDE_PROJECT_DIR (=$ARMED_PROJ), so the
  # test path must match that slug. Armed check-act on a memory-dir path → CONTINUE
  # (not "outside repo"); a non-memory outside path → REVERT.
  _memtest="$HOME/.claude/projects/$(printf '%s' "$ARMED_PROJ" | sed 's|/|-|g')/memory"
  gcheck CONTINUE 0 "check-act exempts the memory dir" "$ARMED_ENV" check-act "$_memtest/some-learning.md"
  gcheck REVERT   20 "check-act still denies a non-memory outside path" "$ARMED_ENV" check-act "/etc/hosts"

  # Writer e2e: armed + a fixture queue → writes memory/<slug>.md + promotes; unarmed → no write.
  WQ="$FIXTURE/keep"; mkdir -p "$WQ/memory/_candidates"
  _qrow='{"ts":"2026-06-22T00:00:00Z","session_id":"s","project_slug":"x","kind":"preference","trigger":"always use trash not rm rf","evidence":"user said use trash not rm","seen_count":3,"first_seen":"2026-06-01","last_seen":"2026-06-22","scope":"repo","source":"learn-capture","status":"open"}'
  printf '%s\n' "$_qrow" > "$WQ/memory/_candidates/queue.jsonl"
  printf '[]\n' > "$WQ/transcript.jsonl"
  env $ARMED_ENV python3 "$REPO/scripts/l4/l4-auto-keep.py" --transcript "$WQ/transcript.jsonl" >/dev/null 2>&1
  if [ -f "$WQ/memory/always-use-trash-not-rm-rf.md" ] && [ "$(jq -r '.status' "$WQ/memory/_candidates/queue.jsonl" 2>/dev/null)" = "promoted" ]; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l4-auto-keep" "armed: writes memory + promotes the candidate"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "l4-auto-keep" "armed: did NOT write+promote"
  fi
  # Unarmed: reset the queue to open, remove the memory file, re-run unarmed → no write.
  printf '%s\n' "$_qrow" > "$WQ/memory/_candidates/queue.jsonl"
  rm -f "$WQ/memory/always-use-trash-not-rm-rf.md" "$WQ/memory/MEMORY.md"
  env KBG_AUTONOMY=0 CLAUDE_PROJECT_DIR="$BARE_PROJ" python3 "$REPO/scripts/l4/l4-auto-keep.py" --transcript "$WQ/transcript.jsonl" >/dev/null 2>&1
  if [ ! -f "$WQ/memory/always-use-trash-not-rm-rf.md" ] && [ "$(jq -r '.status' "$WQ/memory/_candidates/queue.jsonl" 2>/dev/null)" = "open" ]; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l4-auto-keep" "unarmed: no write, queue stays open (byte-identical)"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "l4-auto-keep" "unarmed: wrote anyway (autonomy gate regressed)"
  fi

  # --- audit #47b: the writer must have NO confidence comparison + NO git push/gh
  # (design §6, #28 blocker-A/C). Inject each into a fixture copy + assert the audit
  # CRITs (tests the assertion's own failure mode). Control: the clean writer is silent. ---
  KCF="$FIXTURE/keep47b"; mkdir -p "$KCF/scripts/l4" "$KCF/agents"
  printf -- '---\nname: x\ntools: Read\n---\nx\n' > "$KCF/agents/x.md"  # satisfy the audit's fleet guard
  cp "$REPO/scripts/l4/l4-auto-keep.py" "$KCF/scripts/l4/l4-auto-keep.py"
  printf '\nif confidence >= 0.7: pass  # ponytail: injected for the #47b blocker-A test\n' >> "$KCF/scripts/l4/l4-auto-keep.py"
  _dbgA=$(bash "$AUDIT" "$KCF" 2>&1)
  if printf '%s\n' "$_dbgA" | /usr/bin/grep -q 'l4-auto-keep.py compares confidence'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#47b" "CRITs on a confidence comparison in the writer (blocker-A)"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#47b" "did NOT CRIT on confidence comparison (blocker-A)"
  fi
  cp "$REPO/scripts/l4/l4-auto-keep.py" "$KCF/scripts/l4/l4-auto-keep.py"
  printf '\nsubprocess.run(["git","push","origin","develop"])  # ponytail: injected for the #47b blocker-C test\n' >> "$KCF/scripts/l4/l4-auto-keep.py"
  _dbgC=$(bash "$AUDIT" "$KCF" 2>&1)
  if printf '%s\n' "$_dbgC" | /usr/bin/grep -q 'l4-auto-keep.py shells a git push'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#47b" "CRITs on a git push in the writer (blocker-C)"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#47b" "did NOT CRIT on git push (blocker-C)"
  fi
  cp "$REPO/scripts/l4/l4-auto-keep.py" "$KCF/scripts/l4/l4-auto-keep.py"
  _dbgK=$(bash "$AUDIT" "$KCF" 2>&1)
  if printf '%s\n' "$_dbgK" | /usr/bin/grep -qE 'l4-auto-keep.py (compares confidence|shells a git push)'; then
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#47b" "false-positive on the clean writer"
  else
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#47b" "silent on the clean writer"
  fi

  # --- Slice 2: l4-quality-gate (model-as-gate, design §7, #29) + audit #49 ---
  # qcheck <result> <skill> <judge-cmd> <want-stdout> <want-exit> <label>
  qcheck() {
    local result="$1" skill="$2" jcmd="$3" want="$4" wexit="$5" label="$6" out got gx
    out=$(env KBG_QUALITY_JUDGE_CMD="$jcmd" CLAUDE_JOURNAL_PATH="$EMPTYJ" bash "$REPO/scripts/l4/l4-quality-gate.sh" "$result" "$skill" 2>/dev/null); gx=$?
    got=$(printf '%s' "$out" | tr -d '\n')
    if [ "$got" = "$want" ] && [ "$gx" = "$wexit" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l4-quality-gate" "$label"
    else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s/%s, got %s/%s)\n' "l4-quality-gate" "$label" "$want" "$wexit" "$got" "$gx"; fi
  }
  qcheck red    tech-humanize  "echo SHOULD_NOT_RUN" red      21 "red → red (never bless; judge not invoked)"
  qcheck green  tech-humanize  "echo NOT_GOOD"       rollback 20 "green + NOT_GOOD → rollback (veto-green)"
  qcheck green  tech-humanize  "echo GOOD"           green     0 "green + GOOD → green"
  qcheck green  tech-humanize  "echo garbage"        rollback 20 "green + unparseable → rollback (fail-closed)"
  qcheck green  tech-humanize  "false"               rollback 20 "green + judge errors → rollback (fail-closed)"
  qcheck green  tech-humanize  "true"                rollback 20 "green + empty verdict → rollback (fail-closed)"
  qcheck green  some-code-skill "echo GOOD"          rollback 20 "green + non-allowlisted skill → rollback (fail-closed)"
  qcheck purple tech-humanize  "echo GOOD"           rollback 20 "unknown gauntlet result → rollback (fail-closed)"

  # §10 non-circularity proof: a holed cage forces STOP (audit --only 43 CRITs) EVEN
  # WHEN the model verdict is green — the cage check is computational + gates the model.
  R3HOLE="$FIXTURE/r3hole"; mkdir -p "$R3HOLE/docs/adr" "$R3HOLE/scripts" "$R3HOLE/scripts/l4"
  printf '# adr0003\n' > "$R3HOLE/docs/adr/0003-l3-bounded-autonomy.md"
  /usr/bin/grep -vxF 'CONTEXT.md' "$REPO/scripts/l3-cage.txt" > "$R3HOLE/scripts/l3-cage.txt"
  cp "$REPO/scripts/l4/cage-intact.sh" "$R3HOLE/scripts/l4/cage-intact.sh"
  _holecrit=$(bash "$AUDIT" --only 43 "$R3HOLE" 2>&1); _holerc=$?
  if [ "$_holerc" -ne 0 ] && printf '%s\n' "$_holecrit" | /usr/bin/grep -q 'cage incomplete'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l4-quality-gate" "§10: holed cage CRITs even when the model verdict is green"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "l4-quality-gate" "§10: holed cage did NOT CRIT (non-circularity regressed)"
  fi

  # --- audit #49: the quality-gate must be fail-closed + read-only (design §7, #30).
  # Inject a regression into a fixture copy + assert the CRIT (tests the assertion's
  # own failure mode). Control: the clean gate is silent. ---
  QCF="$FIXTURE/qgate49"; mkdir -p "$QCF/scripts/l4" "$QCF/agents" "$QCF/docs/adr"
  printf -- '---\nname: x\ntools: Read\n---\nx\n' > "$QCF/agents/x.md"
  printf '# adr0004\n' > "$QCF/docs/adr/0004-l4-autonomy.md"  # gate #49 on ADR 0004
  cp "$REPO/scripts/l4/l4-quality-trial.txt" "$QCF/scripts/l4/l4-quality-trial.txt"
  cp "$REPO/scripts/l4/l4-quality-gate.sh" "$QCF/scripts/l4/l4-quality-gate.sh"
  sed -i '' 's/--allowedTools Read/--allowedTools Read,Write/' "$QCF/scripts/l4/l4-quality-gate.sh" 2>/dev/null || sed -i 's/--allowedTools Read/--allowedTools Read,Write/' "$QCF/scripts/l4/l4-quality-gate.sh"
  _q49a=$(bash "$AUDIT" "$QCF" 2>&1)
  if printf '%s\n' "$_q49a" | /usr/bin/grep -q 'judge-grants-mutation'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#49" "CRITs when the judge grants Write (read-only regressed)"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#49" "did NOT CRIT on judge-grants-Write"
  fi
  cp "$REPO/scripts/l4/l4-quality-gate.sh" "$QCF/scripts/l4/l4-quality-gate.sh"
  sed -i '' '/RESULT" = "red"/d' "$QCF/scripts/l4/l4-quality-gate.sh" 2>/dev/null || sed -i '/RESULT" = "red"/d' "$QCF/scripts/l4/l4-quality-gate.sh"
  _q49b=$(bash "$AUDIT" "$QCF" 2>&1)
  if printf '%s\n' "$_q49b" | /usr/bin/grep -q 'red-shortcircuit'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#49" "CRITs when the red short-circuit is removed (veto-only regressed)"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#49" "did NOT CRIT on missing red short-circuit"
  fi
  cp "$REPO/scripts/l4/l4-quality-gate.sh" "$QCF/scripts/l4/l4-quality-gate.sh"
  _q49k=$(bash "$AUDIT" "$QCF" 2>&1)
  if printf '%s\n' "$_q49k" | /usr/bin/grep -qE 'judge-grants-mutation|red-shortcircuit|veto-green|read-only-judge|fail-closed-default'; then
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#49" "false-positive on the clean quality-gate"
  else
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#49" "silent on the clean quality-gate"
  fi

  # --- Slice 3: l4-launch.sh (self-launch, design §8, #31) + exit-tripwire (#32) ---
  # Launcher: no scheduler.conf → abort (kill-switch); kill-file → abort; normal →
  # arms the flag + surfaces R4 caps + invokes the cycle. lcheck <conf> <killfile>
  # <want-cycle-ran: yes|no> <label>.
  LFX="$FIXTURE/launch"; mkdir -p "$LFX"
  LCONF="$LFX/scheduler.conf"; printf '{"interval_seconds":3600,"max_runs_per_window":6,"window_seconds":21600}' > "$LCONF"
  LKILL="$LFX/kill"
  lcheck() {
    local conf="$1" kill="$2" want="$3" label="$4" out
    out=$(env KBG_L4_CONF="$conf" KBG_L4_KILLFILE="$kill" KBG_LAUNCH_CMD="echo CYCLE_RAN" bash "$REPO/scripts/l4/launch.sh" 2>/dev/null)
    local got="no"; printf '%s' "$out" | grep -q CYCLE_RAN && got="yes"
    if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l4-launch" "$label"
    else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want cycle=%s, got=%s)\n' "l4-launch" "$label" "$want" "$got"; fi
  }
  lcheck "$LFX/nope.json" "$LKILL" no  "no scheduler.conf → abort (kill-switch active)"
  : > "$LKILL"
  lcheck "$LCONF" "$LKILL" no  "kill-file present → abort"
  /bin/rm -f "$LKILL"
  lcheck "$LCONF" "$LKILL" yes "normal → arms + drives ONE --auto cycle"

  # exit-tripwire (#32): an L4-authored commit touching a security gate → CRIT;
  # a non-security file → clean. Built in a temp git repo (no hooks fire here).
  TG="$FIXTURE/tripwire"; git init -q "$TG"; git -C "$TG" config user.email t@t; git -C "$TG" config user.name t
  mkdir -p "$TG/hooks/gates"; printf 'x' > "$TG/hooks/gates/x.sh"; git -C "$TG" add -A; git -C "$TG" commit -qm 'normal'
  printf 'y' > "$TG/hooks/gates/x.sh"; git -C "$TG" add -A; git -C "$TG" commit -qm 'l4 sec-gate change'$'\n\n''L4-authored: yes'
  _tw1=$( ( cd "$TG" && bash "$REPO/scripts/l4/exit-tripwire.sh" HEAD~1..HEAD ) 2>&1 ); _tw1rc=$?
  if [ "$_tw1rc" -ne 0 ] && printf '%s\n' "$_tw1" | /usr/bin/grep -q 'CRIT'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "exit-tripwire" "L4-authored commit touching a security gate → CRIT"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "exit-tripwire" "did NOT CRIT on L4-authored sec-gate change"
  fi
  printf 'z' > "$TG/README.md"; git -C "$TG" add -A; git -C "$TG" commit -qm 'l4 doc change'$'\n\n''L4-authored: yes'
  _tw2=$( ( cd "$TG" && bash "$REPO/scripts/l4/exit-tripwire.sh" HEAD~1..HEAD ) 2>&1 ); _tw2rc=$?
  if [ "$_tw2rc" -eq 0 ] && printf '%s\n' "$_tw2" | /usr/bin/grep -q 'clean'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "exit-tripwire" "L4-authored commit touching a non-security file → clean"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "exit-tripwire" "false-positive on a non-security L4 commit"
  fi

  # --- audit #32b: the caged launcher is the sole sanctioned self-start (design §8,
  # #32). Inject a regression (remove the kill-file check) into a fixture copy + assert
  # the CRIT. Control: the clean launcher is silent. ---
  LCF="$FIXTURE/launch32b"; mkdir -p "$LCF/scripts/l4" "$LCF/agents" "$LCF/docs/adr"
  printf -- '---\nname: x\ntools: Read\n---\nx\n' > "$LCF/agents/x.md"
  printf '# adr0004\n' > "$LCF/docs/adr/0004-l4-autonomy.md"
  cp "$REPO/scripts/l4/launch.sh" "$LCF/scripts/l4/launch.sh"
  sed -i '' '/KILLFILE/d' "$LCF/scripts/l4/launch.sh" 2>/dev/null || sed -i '/KILLFILE/d' "$LCF/scripts/l4/launch.sh"
  _l32=$(bash "$AUDIT" "$LCF" 2>&1)
  if printf '%s\n' "$_l32" | /usr/bin/grep -q '#32b.*kill-file'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#32b" "CRITs when launch.sh drops the kill-file check"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#32b" "did NOT CRIT on missing kill-file check"
  fi
  cp "$REPO/scripts/l4/launch.sh" "$LCF/scripts/l4/launch.sh"
  _l32k=$(bash "$AUDIT" "$LCF" 2>&1)
  if printf '%s\n' "$_l32k" | /usr/bin/grep -qE '#32b.*kill-file|#32b.*scheduler'; then
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#32b" "false-positive on the clean launcher"
  else
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#32b" "silent on the clean launcher"
  fi

  # --- Slice 4 / L5: auto-push ship-gate (ADR 0005, design §8.5, #35) ---
  # Folded into l3-push-gate.sh as the L5 leg. A green-gauntlet batch may auto-push
  # ONLY to an allowlisted host+org (default EMPTY → un-configured pushes nowhere),
  # AND only after a green gauntlet. Deny on divergence / un-configured / unverified.
  # pcheck5 <cwd> <env> <want> <label> <cmd> — runs the gate with CWD=<cwd> (a fixture
  # git repo with controlled remotes) so `git remote get-url` resolves hermetically.
  L5FX="$FIXTURE/l5repo"; git init -q "$L5FX"
  git -C "$L5FX" remote add origin git@github.com:wasikarn/kbg-harness.git
  git -C "$L5FX" remote add divergent git@gitlab.com:otherorg/repo.git
  GREENJ="$FIXTURE/greenjournal.jsonl"
  printf '%s\n' '{"id":"g","ts":"2026-06-22T00:00:00Z","session":"s","hook":"recursive-improve","event":"l3_cycle","source":"journal_append","fields":{"outcome":"green","run_id":"r","iteration":1}}' > "$GREENJ"
  pcheck5() {
    local cwd="$1" env="$2" want="$3" label="$4" cmd="$5" out got
    out=$(printf '%s' "$(bash_event "$cmd")" | ( cd "$cwd" && env $env bash "$HOOKS/gates/l3-push-gate.sh" ) 2>/dev/null)
    if [ -z "$out" ]; then got="none"; else got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse-error"); fi
    if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "l5-ship-gate" "$label"
    else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s (want %s, got %s)\n' "l5-ship-gate" "$label" "$want" "$got"; fi
  }
  pcheck5 "$L5FX" "$ARMED_ENV CLAUDE_JOURNAL_PATH=$GREENJ"                      deny  "empty allowlist → deny (un-configured pushes nowhere)" "git push origin develop"
  pcheck5 "$L5FX" "$ARMED_ENV KBG_L5_SHIP_ALLOWLIST=github.com:wasikarn CLAUDE_JOURNAL_PATH=$GREENJ"  none  "allowlisted origin + green gauntlet → allow" "git push origin develop"
  pcheck5 "$L5FX" "$ARMED_ENV KBG_L5_SHIP_ALLOWLIST=github.com:wasikarn CLAUDE_JOURNAL_PATH=$GREENJ"  deny  "divergent remote → deny (cross-remote divergence)" "git push divergent develop"
  pcheck5 "$L5FX" "$ARMED_ENV KBG_L5_SHIP_ALLOWLIST=github.com:wasikarn CLAUDE_JOURNAL_PATH=$EMPTYJ"   deny  "no green gauntlet on record → deny (unverified)" "git push origin develop"

  # --- audit #50: the L5 ship-gate leg must keep the empty-allowlist default + the
  # divergence DENY + the green-gauntlet requirement (design §8.5, #35). Inject a
  # regression (drop the empty-default) into a fixture copy + assert the CRIT. ---
  PCF="$FIXTURE/push50"; mkdir -p "$PCF/hooks/gates" "$PCF/agents" "$PCF/docs/adr"
  printf -- '---\nname: x\ntools: Read\n---\nx\n' > "$PCF/agents/x.md"
  printf '# adr0005\n' > "$PCF/docs/adr/0005-l5-auto-push.md"  # gate #50 on ADR 0005
  cp "$REPO/hooks/gates/l3-push-gate.sh" "$PCF/hooks/gates/l3-push-gate.sh"
  sed -i '' 's/KBG_L5_SHIP_ALLOWLIST:-/KBG_L5_SHIP_ALLOWLIST:-github.com:default/' "$PCF/hooks/gates/l3-push-gate.sh" 2>/dev/null || sed -i 's/KBG_L5_SHIP_ALLOWLIST:-/KBG_L5_SHIP_ALLOWLIST:-github.com:default/' "$PCF/hooks/gates/l3-push-gate.sh"
  _p50=$(bash "$AUDIT" "$PCF" 2>&1)
  if printf '%s\n' "$_p50" | /usr/bin/grep -q 'empty-default'; then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#50" "CRITs when the empty-allowlist default is removed"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#50" "did NOT CRIT on missing empty-default"
  fi
  cp "$REPO/hooks/gates/l3-push-gate.sh" "$PCF/hooks/gates/l3-push-gate.sh"
  _p50k=$(bash "$AUDIT" "$PCF" 2>&1)
  if printf '%s\n' "$_p50k" | /usr/bin/grep -qE 'audit #50:.*l3-push-gate|empty-default|allowlist-var|dest-resolution|green-gauntlet|allowlist-membership'; then
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#50" "false-positive on the clean ship-gate leg"
  else
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#50" "silent on the clean ship-gate leg"
  fi
else
  printf '  ⚠️  python3 absent — skipped l3-loop-guard checks\n'
fi

# --- audit check-numbering stability: the autonomy-load-bearing IDs must not drift ---
ncheck() {
  local id="$1"
  if /usr/bin/grep -qE "^# ${id}\. " "$AUDIT"; then PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit-numbering" "#${id} present"
  else FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit-numbering" "#${id} MISSING (load-bearing ID drifted)"; fi
}
for id in 32 34 41 43 44 48 49 50; do ncheck "$id"; done

# --- audit #43b: cage-completeness must CRIT when a required anchor is removed ---
# (test-honesty Rule 9 "distinguishes-or-it-doesn't": a green-only check is decoration.
# Runs the REAL audit.sh against a fixture that gates #43 on (fake ADR 0003 + real guard
# so 43a/43c stay clean) with a cage that is the real cage MINUS one required anchor.)
CF="$FIXTURE/cage43"; mkdir -p "$CF/docs/adr" "$CF/scripts" "$CF/scripts/l4" "$CF/agents"
printf -- '---\nname: x\ntools: Read\n---\nx\n' > "$CF/agents/x.md"  # satisfy audit's fleet guard
printf '# adr0003 — gate #43 on\n' > "$CF/docs/adr/0003-l3-bounded-autonomy.md"
cp "$REPO/scripts/l3-loop-guard.py" "$CF/scripts/l3-loop-guard.py"
cp "$REPO/scripts/l4/cage-intact.sh" "$CF/scripts/l4/cage-intact.sh"  # #43 relays through this standalone
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

# --- audit #43d: L4 cage↔anchor lockstep (design §5 F2/F3 blocker). #43b is
# directional (anchors⊆cage), so a cage-only L4 add would pass silently; #43d
# checks the curated L4 anchors are in BOTH surfaces and emits a DISTINCT drift
# message. Hole one L4 anchor (scripts/l4/**) from the cage → CRIT names it.
CFD="$FIXTURE/cage43d"; mkdir -p "$CFD/docs/adr" "$CFD/scripts" "$CFD/scripts/l4" "$CFD/agents"
printf -- '---\nname: x\ntools: Read\n---\nx\n' > "$CFD/agents/x.md"
printf '# adr0003 — gate #43 on\n' > "$CFD/docs/adr/0003-l3-bounded-autonomy.md"
cp "$REPO/scripts/l3-loop-guard.py" "$CFD/scripts/l3-loop-guard.py"
cp "$REPO/scripts/l4/cage-intact.sh" "$CFD/scripts/l4/cage-intact.sh"  # #43d relays through this standalone
/usr/bin/grep -vxF 'scripts/l4/**' "$REPO/scripts/l3-cage.txt" > "$CFD/scripts/l3-cage.txt"  # L4 anchor holed from cage
DRIFTED=$(bash "$AUDIT" "$CFD" 2>&1)
if printf '%s\n' "$DRIFTED" | /usr/bin/grep -q 'cage↔anchor drift' && printf '%s\n' "$DRIFTED" | /usr/bin/grep -qF 'scripts/l4/**'; then
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#43d" "CRITs on L4 anchor missing from cage (drift message)"
else
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#43d" "did NOT CRIT with drift message on holed L4 anchor"
fi
cp "$REPO/scripts/l3-cage.txt" "$CFD/scripts/l3-cage.txt"  # full cage = control
if bash "$AUDIT" "$CFD" 2>&1 | /usr/bin/grep -q 'cage↔anchor drift'; then
  FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit#43d" "false-positive drift on complete cage"
else
  PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit#43d" "silent on complete cage (no drift)"
fi

report
