#!/usr/bin/env bash
# Behavioral tests for the worktree-guard gate (opt-in, generic PreToolUse redirect).
# Uses the KBG_GUARDED_WORKSPACE / KBG_WORKTREE_ROOT env seams to run against throwaway
# repos — never touches any real workspace or ~/.worktrees.
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
  # KBG_ALLOW_MAIN_EDIT= resets the escape hatch so an ambient export (e.g. a
  # dev's own shell profile) can't silently no-op every deny/redirect assertion
  # below; env's last-wins semantics let "$@" still opt back in when a test wants it.
  echo "$p" | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= "$@" python3 "$GUARD"
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
out=$(run_guard "$(payload "$WS/repo1/f.txt" sess1234)" KBG_ALLOW_MAIN_EDIT=1 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "KBG_ALLOW_MAIN_EDIT=1: exit 0, no output" "$ok"

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

# KBG_WORKTREE_BASE=main → worktree based on origin/main, not the develop checkout
out=$(run_guard "$(payload "$WS/repo2/f.txt" sessbase)" KBG_WORKTREE_BASE=main 2>/dev/null); rc=$?
got=$(git -C "$WT/repo2-wip-sessbase" rev-parse HEAD 2>/dev/null)
ok=1
[ "$rc" -eq 0 ] && [ "$got" = "$MAIN_SHA" ] && echo "$out" | /usr/bin/grep -q 'base origin/main' && ok=0
check "KBG_WORKTREE_BASE=main: worktree HEAD == origin/main tip, message names base" "$ok"

# Bogus KBG_WORKTREE_BASE → fetch fails → fail-open to HEAD (still redirects)
out=$(run_guard "$(payload "$WS/repo1/g.txt" sessbogus)" KBG_WORKTREE_BASE=no-such-branch 2>/dev/null); rc=$?
ok=1
[ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"updatedInput"' \
  && echo "$out" | /usr/bin/grep -q 'base current HEAD' && ok=0
check "bogus KBG_WORKTREE_BASE: fail-open to current HEAD, still redirects" "$ok"

# Kill-switch discriminator: CWD == the fake workspace root itself, but
# KBG_GUARDED_WORKSPACE is unset. Without the "if not WORKSPACE or not isabs(...): return
# None" guard in classify(), under(fp, "") resolves against CWD and would wrongly protect
# repo1 (on develop, a protected branch) even though nothing is configured. With the
# guard: total no-op regardless of CWD. This is the real regression witness for that
# line — a python-side _selftest() assertion can't discriminate it (traced: a nonexistent
# path returns None earlier via the "not a git repo" branch, and a path at the repo root
# hits the pre-existing workspace-root exemption either way).
out=$(cd "$WS" && echo "$(payload "$WS/repo1/f.txt" sesskill)" \
  | env -u KBG_GUARDED_WORKSPACE -u KBG_WORKTREE_ROOT -u KBG_WORKTREE_BASE -u KBG_ALLOW_MAIN_EDIT \
  python3 "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "KBG_GUARDED_WORKSPACE unset, cwd==fake workspace root: still exit 0 (kill-switch, not cwd-guard)" "$ok"

# Unset in the ordinary case (no adversarial cwd either) -> total no-op.
out=$(echo "$(payload "$TMP/elsewhere2.txt" sessnorm)" \
  | env -u KBG_GUARDED_WORKSPACE python3 "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "KBG_GUARDED_WORKSPACE unset (default case): exit 0, no output" "$ok"

# Wrapper-string test: this is the only exercise the actual hooks.json bash -c string
# ever gets (shellcheck never lints an embedded JSON string value). Extract it exactly
# as shipped and run it in isolated subshells so env changes don't leak into the rest of
# this script.
WRAPPER_CMD=$(python3 -c "
import json
d = json.load(open('$ROOT/hooks/hooks.json'))
for blk in d['hooks']['PreToolUse']:
    if blk.get('id') == 'gate:bash:worktree-guard':
        print(blk['hooks'][0]['command'])
        break
")
ok=1; [ -n "$WRAPPER_CMD" ] && ok=0
check "wrapper command string extracted from hooks.json" "$ok"

out=$( (unset KBG_GUARDED_WORKSPACE CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT
  echo '{}' | eval "$WRAPPER_CMD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "wrapper string: var unset -> exit 0, no output (python never spawned)" "$ok"

bashpayload=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "echo x >> $WS/repo1/f.txt")
out=$( (export KBG_GUARDED_WORKSPACE="$WS" CLAUDE_PROJECT_DIR="$WS/repo1" CLAUDE_PLUGIN_ROOT="$ROOT"
  echo "$bashpayload" | eval "$WRAPPER_CMD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "wrapper string: var set + Bash write to protected checkout -> deny exit 2" "$ok"

# Regression test (found + fixed 2026-08-04): a heredoc whose BODY contains an
# unbalanced quote (an ordinary English contraction is enough) used to trip
# shlex's global quote-balance check, falling back to a quote-blind cmd.split()
# that mangled a quoted, space-containing write target into a fragment with a
# stray leading quote and no ".txt" -- and critically, run from $WS (the
# guarded workspace root) targeting the sub-repo via a relative "repo1/..."
# path, that mangled fragment's nearest EXISTING directory ancestor climbs
# all the way back up to $WS itself, which trips the workspace-root exemption
# ("the file this comment is protecting" is exempt by design) -- letting the
# write through the gate silently (exit 0, no denial) instead of being denied
# as a sub-repo main-checkout write. Must run from $WS, not from inside
# repo1 -- cd'ing into repo1 first makes ANY mangled fragment resolve under
# repo1 regardless of tokenization correctness, which doesn't exercise the
# actual bug (confirmed: an earlier draft of this test passed against the
# unfixed code for exactly this reason).
HEREDOC_CMD=$(printf 'cat <<%s > "repo1/notes file.txt"\nit%ss here\nEOF' "'EOF'" "'")
bashpayload_heredoc=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$HEREDOC_CMD")
out=$( (cd "$WS" && echo "$bashpayload_heredoc" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "heredoc body w/ unbalanced quote + quoted spaced target -> deny exit 2 (not a silent bypass)" "$ok"

# Same class, ANSI-C quoting: shlex doesn't raise on \$'...', it just splits on
# the bare \$ and yields the wrong token ('\$' itself) instead of the real
# name -- which, run from \$WS the same way, also climbs to the exempt
# workspace root.
ANSIC_CMD="echo x > \$'repo1/notes file.txt'"
bashpayload_ansic=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$ANSIC_CMD")
out=$( (cd "$WS" && echo "$bashpayload_ansic" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "ANSI-C \$'...' quoted target -> deny exit 2 (not a silent bypass)" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
