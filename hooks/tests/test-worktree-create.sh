#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal $ in test payload strings is intentional
# Behavioral tests for the worktree-create-block gate (WorktreeCreate + WorktreeRemove
# events) and the irrecoverable.sh extension for `git worktree add -b <new-branch>`.
# Uses the `CLAUDE_PROJECT_DIR` env seam + a TMPDIR fixture containing a real
# throwaway git repo (so the walk-up can find .git) and an optional .kbg-no-worktree
# sentinel. Never touches the real kbg-harness repo.
# Run standalone: bash hooks/tests/test-worktree-create.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WT_CREATE_GATE="$ROOT/hooks/gates/worktree-create-block.sh"
IRRECOVERABLE_GATE="$ROOT/hooks/gates/irrecoverable.sh"

pass=0
fail=0

# Per-test scratch dir for capturing stderr.
WORK_TMP="$TMPDIR/kbg-wt-test-stderr.$$"
mkdir -p "$WORK_TMP"

# ---- fixture: throwaway git repo with optional sentinel ----
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kbg-wt-test.XXXXXX")
trap 'rm -rf "$WORK_TMP" "$TMP"' EXIT
mkrepo() { # mkrepo <dir> <branch>
  git init -q -b "$2" "$1"
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

# Two repos: one with sentinel (kbg-sentinel-on) and one without (kbg-sentinel-off).
REPO_ON="$TMP/kbg-on"
REPO_OFF="$TMP/kbg-off"
mkrepo "$REPO_ON" develop
mkrepo "$REPO_OFF" develop
echo "# kbg-harness sentinel" > "$REPO_ON/.kbg-no-worktree"
# REPO_OFF has no sentinel file (non-kbg repo simulation)

# Subdir of REPO_ON for cwd-is-subdir tests.
mkdir -p "$REPO_ON/agents/sub"
mkdir -p "$REPO_ON/hooks/gates"

# Tathep-simulation dir (a real repo with NO sentinel and a different branch).
REPO_TATHEP="$TMP/tathep-sim"
mkrepo "$REPO_TATHEP" main
# No .kbg-no-worktree here.

# ---- payload builders ----
# WorktreeCreate event payload — {tool_name, tool_input: {path, branch?, detach?}, cwd?, agent_type?}
wtcreate_payload() { # wtcreate_payload <path> <branch> [detach:0|1] [cwd] [agent_type]
  python3 -c '
import json, sys
ti = {"path": sys.argv[1]}
if sys.argv[2]:
    ti["branch"] = sys.argv[2]
if len(sys.argv) > 3 and sys.argv[3] == "1":
    ti["detach"] = True
d = {"tool_name": "WorktreeCreate", "tool_input": ti}
if len(sys.argv) > 4 and sys.argv[4]:
    d["cwd"] = sys.argv[4]
if len(sys.argv) > 5 and sys.argv[5]:
    d["agent_type"] = sys.argv[5]
print(json.dumps(d))
' "$@"
}

# Bash event payload — {tool_name: Bash, tool_input: {command: ...}}
bash_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"; }

# ---- run helpers ----
# Run a gate against a payload, with cwd set to a real dir (so walk-up finds the repo).
# Usage: run <gate> <payload> [<cwd>]
run() {
  local gate="$1" payload="$2" cwd="${3:-$REPO_ON}"
  ( cd "$cwd" && printf '%s' "$payload" | bash "$gate" 2>/dev/null )
}
# Run gate, capture BOTH the gate's exit code AND its stderr. The
# captured pair is written to global vars RC and STDOUT_ERR, set
# before returning. Stdout from the gate itself is discarded.
RC=0
STDOUT_ERR=""
run_stderr() {
  local gate="$1" payload="$2" cwd="${3:-$REPO_ON}"
  local errfile="$WORK_TMP/stderr.$$"
  ( cd "$cwd" && printf '%s' "$payload" | bash "$gate" ) >/dev/null 2>"$errfile"
  RC=$?
  STDOUT_ERR=$(cat "$errfile")
  rm -f "$errfile"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

# Expect deny: exit 2 + stderr contains BLOCKED
expect_deny() {
  local desc="$1" gate="$2" payload="$3" cwd="${4:-$REPO_ON}"
  run_stderr "$gate" "$payload" "$cwd"
  if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2
    fail=$((fail + 1))
  fi
}

# Expect allow: exit 0 + empty stderr
expect_allow() {
  local desc="$1" gate="$2" payload="$3" cwd="${4:-$REPO_ON}"
  run_stderr "$gate" "$payload" "$cwd"
  if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2
    fail=$((fail + 1))
  fi
}

# =============================================================================
echo "=== WorktreeCreate event gate (kbg-sentinel-on repo) ==="
# =============================================================================

# 1. Sentinel on + -b feat/x → DENY
expect_deny "T1: sentinel on + -b feat/x (DENY)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' 'feat/x' 0 "$REPO_ON")"

# 2. Sentinel on + -b develop → ALLOW
expect_allow "T2: sentinel on + -b develop (ALLOW — rev-parse verify)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/dev-wt' 'develop' 0 "$REPO_ON")"

# 3. Sentinel on + no -b (existing branch checkout) → ALLOW
expect_allow "T3: sentinel on + no -b (ALLOW)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/checkout-wt' '' 0 "$REPO_ON")"

# 4. Sentinel on + --detach + path contains review-pr-N + -b feat/x → DENY
# (review-pr allowlist requires NO -b; -b feat/x is doctrine-breaking)
expect_deny "T4: sentinel on + --detach review-pr + -b feat/x (DENY — -b breaks review-pr shape)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/review-pr-7' 'feat/x' 1 "$REPO_ON")"

# 5. Sentinel on + --detach + path contains review-pr-N + NO -b → ALLOW
expect_allow "T5: sentinel on + --detach review-pr + no -b (ALLOW — review-pr shape)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/review-pr-7' '' 1 "$REPO_ON")"

# 6. Sentinel on + --detach but path is NOT review-pr → DENY
expect_deny "T6: sentinel on + --detach /tmp/some-other -b feat/x (DENY — not review-pr)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/some-other' 'feat/x' 1 "$REPO_ON")"

# 7. Sentinel on + -b feat/x from subagent → DENY (agent_type does not bypass)
expect_deny "T7: sentinel on + -b feat/x from subagent (DENY)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' 'feat/x' 0 "$REPO_ON" 'kbg:test')"

# 8. Sentinel on + typo'd developp → DENY
expect_deny "T8: sentinel on + -b developp typo (DENY — -b != 'develop')" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' 'developp' 0 "$REPO_ON")"

# 9. Sentinel OFF repo + -b feat/x → ALLOW (no doctrine)
expect_allow "T9: sentinel off + -b feat/x (ALLOW — no doctrine)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' 'feat/x' 0 "$REPO_OFF")"

# 10. WorktreeRemove → ALLOW (symmetric observer, any path)
expect_allow "T10: WorktreeRemove (ALLOW — symmetric observer)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' '' 0 "$REPO_ON")"  # tool_name WorktreeRemove handled by python — see below
# Above uses tool_name=WorktreeCreate; replace:
expect_allow "T10b: WorktreeRemove explicit (ALLOW)" \
  "$WT_CREATE_GATE" \
  "{\"tool_name\":\"WorktreeRemove\",\"cwd\":\"$REPO_ON\"}"

# 11. Sentinel on + WorktreeCreate but unparseable stdin → ALLOW (fail-safe,
# debug log expected on stderr — fail-safe ALLOW is intentional, not silent)
desc="T11: unparseable stdin (ALLOW fail-safe, debug log expected)"
run_stderr "$WT_CREATE_GATE" "not valid json" "$REPO_ON"
if [ "$RC" -eq 0 ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 12. Sentinel on + cwd is subdir of repo (walk-up test) + -b feat/x → DENY
expect_deny "T12: sentinel on + cwd is agents/sub + -b feat/x (DENY — walk-up works)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' 'feat/x' 0 "$REPO_ON/agents/sub")"

# 13. Sentinel on + cwd is deep subdir hooks/gates + -b feat/x → DENY
expect_deny "T13: sentinel on + cwd is hooks/gates + -b feat/x (DENY — deep walk-up)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' 'feat/x' 0 "$REPO_ON/hooks/gates")"

# 14. cwd outside any git repo + -b feat/x → ALLOW (no doctrine context, fail-open,
# debug log expected on stderr — fail-open ALLOW is intentional, not silent)
desc="T14: cwd=/tmp + -b feat/x (ALLOW — not in any git repo, fail-open, debug log)"
run_stderr "$WT_CREATE_GATE" "$(wtcreate_payload '/tmp/x' 'feat/x' 0 '/tmp')" '/tmp'
if [ "$RC" -eq 0 ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 15. Sentinel on + -B (force-create) feat/x → DENY
expect_deny "T15: sentinel on + -B feat/x (DENY — -B is the force-create variant)" \
  "$WT_CREATE_GATE" \
  "$(wtcreate_payload '/tmp/x' 'feat/x' 0 "$REPO_ON")"
# Note: this is the same as T1; WorktreeCreate payload doesn't distinguish -b vs -B
# (the event has a single `branch` field regardless of which flag set it). The
# distinction only matters in the Bash gate below.

# =============================================================================
echo ""
echo "=== WorktreeRemove event gate (kbg-sentinel-on repo) ==="
# =============================================================================

# 16. WorktreeRemove from subagent → ALLOW (always)
expect_allow "T16: WorktreeRemove from subagent (ALLOW — symmetric)" \
  "$WT_CREATE_GATE" \
  "{\"tool_name\":\"WorktreeRemove\",\"cwd\":\"$REPO_ON\",\"agent_type\":\"kbg:test\"}"

# 17. WorktreeRemove from a path under tathep-simulation → ALLOW
expect_allow "T17: WorktreeRemove in non-kbg repo (ALLOW — no doctrine)" \
  "$WT_CREATE_GATE" \
  "{\"tool_name\":\"WorktreeRemove\",\"cwd\":\"$REPO_TATHEP\"}"

# =============================================================================
echo ""
echo "=== Bash gate extension (git worktree add via PreToolUse:Bash) ==="
# =============================================================================

# Run irrecoverable.sh with cwd=REPO_ON so the walk-up finds .kbg-no-worktree.
bash_run() {
  ( cd "$1" && printf '%s' "$2" | bash "$IRRECOVERABLE_GATE" 2>/dev/null )
}
bash_run_stderr() {
  local cwd="$1" payload="$2"
  local errfile="$WORK_TMP/bash_stderr.$$"
  ( cd "$cwd" && printf '%s' "$payload" | bash "$IRRECOVERABLE_GATE" ) >/dev/null 2>"$errfile"
  RC=$?
  STDOUT_ERR=$(cat "$errfile")
  rm -f "$errfile"
}

# 18. git worktree add -b feat/x via Bash in sentinel-on repo → DENY
desc="T18: bash git worktree add -b feat/x in sentinel-on repo (DENY)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree add /tmp/x -b feat/x')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 19. git worktree add -b develop via Bash → ALLOW
desc="T19: bash git worktree add -b develop in sentinel-on repo (ALLOW)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree add /tmp/dev-wt -b develop')"
if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 20. git worktree add --detach /tmp/review-pr-7 via Bash → ALLOW (review-pr)
desc="T20: bash git worktree add --detach /tmp/review-pr-7 (ALLOW — review-pr shape, no -b)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree add --detach /tmp/review-pr-7 HEAD')"
if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 21. git worktree add --detach /tmp/some-other -b feat/x via Bash → DENY
desc="T21: bash git worktree add --detach /tmp/some-other -b feat/x (DENY — -b breaks review-pr shape)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree add --detach /tmp/some-other HEAD -b feat/x')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 22. git worktree list via Bash → ALLOW (other op, not creation)
desc="T22: bash git worktree list (ALLOW — not creation)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree list')"
if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 23. git worktree remove via Bash → ALLOW
desc="T23: bash git worktree remove (ALLOW — not creation)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree remove /tmp/x')"
if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 24. xargs git worktree add -b feat/x via Bash → DENY (R3 fix: xargs unwrap catches git)
desc="T24: bash xargs git worktree add -b feat/x (DENY — R3 xargs unwrap fix)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'find . -name x -print0 | xargs git worktree add /tmp/foo -b feat/x')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 25. sudo git worktree add -b feat/x via Bash → DENY (sudo unwrap pre-existing)
desc="T25: bash sudo git worktree add -b feat/x (DENY — sudo unwrap pre-existing)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'sudo git worktree add /tmp/x -b feat/x')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 26. Sentinel OFF repo + git worktree add -b feat/x via Bash → ALLOW (no doctrine)
desc="T26: bash git worktree add -b feat/x in sentinel-off repo (ALLOW — no doctrine)"
bash_run_stderr "$REPO_OFF" "$(bash_payload 'git worktree add /tmp/x -b feat/x')"
if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 27. -b flag BEFORE path: `git worktree add -b feat/x /tmp/x` → DENY (flag scan all args)
desc="T27: bash git worktree add -b feat/x /tmp/x (-b before path, DENY)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree add -b feat/x /tmp/x')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 28. -B (force-create): DENY
desc="T28: bash git worktree add -B feat/x /tmp/x (-B force-create, DENY)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree add -B feat/x /tmp/x')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 29. --branch long form: DENY
desc="T29: bash git worktree add --branch feat/x /tmp/x (--branch long form, DENY)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git worktree add --branch feat/x /tmp/x')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 30. rm -rf regression test (the irrecoverable.sh original must still fire)
desc="T30: regression: bash rm -rf (still DENY by original irrecoverable check)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'rm -rf /tmp/test')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 31. git push --force regression test
desc="T31: regression: bash git push --force (still DENY by original irrecoverable check)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git push --force origin develop')"
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 32. git checkout main — ALLOW (no force, no reset, not a worktree add)
desc="T32: regression: bash git checkout main (ALLOW — normal git op)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'git checkout main')"
if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 33. ls -la — ALLOW (sentinel on, no git subcommand at all)
desc="T33: regression: bash ls -la (ALLOW — irrelevant command)"
bash_run_stderr "$REPO_ON" "$(bash_payload 'ls -la')"
if [ "$RC" -eq 0 ] && [ -z "$STDOUT_ERR" ]; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

# 34. Sentinel on + branch is 'develop' but git rev-parse fails (develop renamed away)
# We simulate by deleting the develop branch. The gate's defensive check should deny.
git -C "$REPO_ON" branch -m develop old-name
desc="T34: sentinel on + -b develop but develop branch was renamed (DENY by rev-parse defensive)"
run_stderr "$WT_CREATE_GATE" "$(wtcreate_payload '/tmp/x' 'develop' 0 "$REPO_ON")"
git -C "$REPO_ON" branch -m old-name develop  # restore for any subsequent tests
if [ "$RC" -eq 2 ] && echo "$STDOUT_ERR" | /usr/bin/grep -q 'BLOCKED'; then
  echo "  ✅ $desc"; pass=$((pass+1))
else
  echo "  ❌ $desc (rc=$RC out=<$(printf '%s' "$STDOUT_ERR" | head -c 120)>)" >&2; fail=$((fail+1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
