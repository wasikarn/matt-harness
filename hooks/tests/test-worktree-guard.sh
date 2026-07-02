#!/usr/bin/env bash
# Behavioral tests for the worktree-guard gate (tathep-scoped PreToolUse redirect).
# Uses the TATHEP_WORKSPACE / TATHEP_WT_ROOT env seams to run against throwaway repos —
# never touches the real ~/Codes/Works/tathep or ~/.worktrees.
# Run standalone: bash hooks/tests/test-worktree-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$ROOT/hooks/gates/worktree-guard.py"

pass=0
fail=0

TMP=$(mktemp -d "${TMPDIR:-/tmp}/wtguard.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

WS="$TMP/ws"
WT="$TMP/wt"
mkdir -p "$WS" "$WT"

mkrepo() { # mkrepo <dir> <branch>
  git init -q -b "$2" "$1"
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  echo x > "$1/f.txt"
  git -C "$1" add f.txt
  git -C "$1" -c user.email=t@t -c user.name=t commit -q -m add-f
}

payload() { # payload <file_path> [session_id]
  python3 -c 'import json,sys; d={"tool_name":"Edit","tool_input":{"file_path":sys.argv[1]}};
d.update({"session_id":sys.argv[2]} if len(sys.argv)>2 else {}); print(json.dumps(d))' "$@"
}

run_guard() { # run_guard <payload> [extra env as K=V ...]
  local p="$1"; shift
  echo "$p" | env TATHEP_WORKSPACE="$WS" TATHEP_WT_ROOT="$WT" "$@" python3 "$GUARD"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

# Fixtures: workspace-root repo, one sub-repo, one cloned sub-repo with origin.
mkrepo "$WS" develop
mkrepo "$WS/repo1" develop

SRC="$TMP/src"
mkrepo "$SRC" main
MAIN_SHA=$(git -C "$SRC" rev-parse HEAD)
git -C "$SRC" switch -q -c develop
echo dev >> "$SRC/f.txt"
git -C "$SRC" -c user.email=t@t -c user.name=t commit -qam dev-ahead
git clone -q "$SRC" "$WS/repo2"   # clone lands on develop (src HEAD)

echo "=== worktree-guard gate ==="

# --selftest
ok=1; python3 "$GUARD" --selftest >/dev/null 2>&1 && ok=0
check "--selftest passes" "$ok"

# Outside workspace → silent no-op
out=$(run_guard "$(payload "$TMP/elsewhere.txt" sess1234)" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "outside workspace: exit 0, no output" "$ok"

# Escape hatch
out=$(run_guard "$(payload "$WS/repo1/f.txt" sess1234)" TATHEP_ALLOW_MAIN_EDIT=1 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "TATHEP_ALLOW_MAIN_EDIT=1: exit 0, no output" "$ok"

# Workspace-root repo exempt
out=$(run_guard "$(payload "$WS/notes.md" sess1234)" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "workspace-root repo file: exempt" "$ok"

# No session id → deny (exit 2)
run_guard "$(payload "$WS/repo1/f.txt")" >/dev/null 2>&1; rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "sub-repo edit without session_id: deny exit 2" "$ok"

# Main-checkout edit → redirect JSON + worktree created
out=$(run_guard "$(payload "$WS/repo1/f.txt" sessabcd)" 2>/dev/null); rc=$?
ok=1
echo "$out" | /usr/bin/grep -q "\"file_path\": \"$WT/repo1-wip-sessabcd/f.txt\"" \
  && [ "$rc" -eq 0 ] && [ -d "$WT/repo1-wip-sessabcd" ] && ok=0
check "main-checkout edit: redirected into \$WT/repo1-wip-<slug>" "$ok"

wtbranch=$(git -C "$WT/repo1-wip-sessabcd" rev-parse --abbrev-ref HEAD 2>/dev/null)
ok=1; [ "$wtbranch" = "wip/sessabcd" ] && ok=0
check "auto-worktree is on branch wip/<slug>" "$ok"

# Redirected path itself (under WT_ROOT, outside workspace) passes through untouched
out=$(run_guard "$(payload "$WT/repo1-wip-sessabcd/f.txt" sessabcd)" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "edit inside the auto-worktree: no re-redirect" "$ok"

# TATHEP_BASE=main → worktree based on origin/main, not the develop checkout
out=$(run_guard "$(payload "$WS/repo2/f.txt" sessbase)" TATHEP_BASE=main 2>/dev/null); rc=$?
got=$(git -C "$WT/repo2-wip-sessbase" rev-parse HEAD 2>/dev/null)
ok=1
[ "$rc" -eq 0 ] && [ "$got" = "$MAIN_SHA" ] && echo "$out" | /usr/bin/grep -q 'base origin/main' && ok=0
check "TATHEP_BASE=main: worktree HEAD == origin/main tip, message names base" "$ok"

# Bogus TATHEP_BASE → fetch fails → fail-open to HEAD (still redirects)
out=$(run_guard "$(payload "$WS/repo1/g.txt" sessbogus)" TATHEP_BASE=no-such-branch 2>/dev/null); rc=$?
ok=1
[ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"updatedInput"' \
  && echo "$out" | /usr/bin/grep -q 'base current HEAD' && ok=0
check "bogus TATHEP_BASE: fail-open to current HEAD, still redirects" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
