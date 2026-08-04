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

# Regression test (found + fixed 2026-08-04, round 2 -- caught by a genuine
# subagent_type:kbg:silent-failure-hunter re-verification dispatch after the
# round-1 fix landed): shlex treats a bare newline as ordinary whitespace, and
# SEPS never included '\n' -- so a write-only statement on any line but the
# first of a multi-statement Bash command was invisible to every argv0-dispatch
# branch. Two statements joined only by a newline (no ';'/'&&'), write on the
# second line.
NEWLINE_CMD=$(printf 'echo hello\nsed -i "" "s/x/y/" repo1/f.txt')
bashpayload_newline=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$NEWLINE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_newline" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "write on 2nd line of a newline-joined command -> deny exit 2 (not a silent bypass)" "$ok"

# Same round-2 dispatch, a regression in round-1's OWN fix: the heredoc
# delimiter regex only matched \w+ (word characters), so a delimiter with a
# hyphen (a real, common bash pattern -- <<MY-EOF) never matched the closing
# line, and _strip_heredocs silently consumed every remaining line as "body",
# including a real write statement that followed -- worse than round-1's bug,
# since it ate content instead of just mis-tokenizing it.
HYPHEN_HEREDOC_CMD=$(printf 'cat <<MY-EOF\nsome content\nMY-EOF\nsed -i "" "s/x/y/" repo1/f.txt')
bashpayload_hyphenhd=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$HYPHEN_HEREDOC_CMD")
out=$( (cd "$WS" && echo "$bashpayload_hyphenhd" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "hyphenated heredoc delimiter + write statement after it -> deny exit 2 (not silently eaten)" "$ok"

# Round-3 regression tests (found 2026-08-04 by a genuine subagent_type:kbg:silent-failure-hunter
# re-verification dispatch after the round-2 fix landed -- one of the two is a regression in
# round-2's OWN fix, the same failure shape as round-2 finding a regression in round-1's fix).

# Finding 1: round-2's _newlines_to_seps replaced EVERY '\n' with ' ; ', which left no real
# newline anywhere in the command -- shlex's default commenters='#' handling calls readline()
# to skip a comment, which stops at the next '\n' in the stream, so with no '\n' left a '#'
# anywhere in the command swallowed everything after it as one giant comment, hiding any write
# statement that came after. A comment on an earlier line followed by a real write on a later
# line is the minimal repro.
COMMENT_CMD=$(printf 'echo hi # just a note\nsed -i "" "s/x/y/" repo1/f.txt')
bashpayload_comment=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$COMMENT_CMD")
out=$( (cd "$WS" && echo "$bashpayload_comment" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "write on a line after a '#' comment -> deny exit 2 (not swallowed as one giant comment)" "$ok"

# Companion: a comment plus a benign command that writes nowhere near the workspace must NOT
# false-deny -- guards against an overcorrection (e.g. disabling commenters entirely, which the
# round-3 dispatch explicitly tested and rejected: it leaks comment text into unrelated targets).
BENIGN_COMMENT_CMD="ls -la # see repo1/notes.txt for details"
bashpayload_benign=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$BENIGN_COMMENT_CMD")
out=$( (cd "$WS" && echo "$bashpayload_benign" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "comment mentioning a workspace-looking path, no real write -> exit 0 (not a false deny)" "$ok"

# Finding 2: an unquoted \$VAR or ~ redirect target was never expanded before os.path.abspath() --
# '\$' isn't in shlex's default wordchars (splits '\$HOME/x' into '\$' + 'HOME/x') and even a
# whole-token target never ran through expandvars/expanduser, so a write that really lands
# inside the guarded workspace via an env var or ~ silently bypassed the gate. MYVAR is used
# instead of overriding HOME broadly, to keep this test isolated from the rest of the suite.
VARWRITE_CMD='echo x >> $MYVAR/repo1/f.txt'
bashpayload_var=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$VARWRITE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_var" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= MYVAR="$WS" python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "unquoted \$VAR redirect target resolving into the workspace -> deny exit 2" "$ok"

TILDEWRITE_CMD='echo x >> ~/repo1/f.txt'
bashpayload_tilde=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$TILDEWRITE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_tilde" \
  | env KBG_GUARDED_WORKSPACE="$WS" KBG_WORKTREE_ROOT="$WT" KBG_ALLOW_MAIN_EDIT= HOME="$WS" python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "unquoted ~ redirect target resolving into the workspace -> deny exit 2" "$ok"

# Table-driven battery against bash_write_targets() directly (unit level, not through the full
# main()/classify() pipeline) -- this is the shape that actually caught round 3's findings: the
# re-verification dispatch found them by running ~25 probe commands directly against the
# extracted function, not by walking the deny/allow surface one case at a time. Promoted here
# (instead of thrown away as a one-off probe script, which is what happened after rounds 1 and 2)
# so it persists as the regression net for round 4 and beyond. Positive cases assert the real
# target is present (extra pre-existing quirky yields, e.g. sed's own expression argument, are
# out of scope for this battery); negative cases assert exact equality -- any unexpected token at
# all is itself the failure mode being guarded against (comment content or a fake redirect symbol
# leaking into a "target").
BATTERY_OUT=$(WTG_PATH="$GUARD" python3 <<'PYEOF'
import importlib.util, os, sys

spec = importlib.util.spec_from_file_location("wtg", os.environ["WTG_PATH"])
wtg = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(wtg)
except SystemExit:
    pass

CASES = [
    ("baseline write", "cp secret.txt repo1/target.txt", {"repo1/target.txt"}, None),
    ("comment-then-write", "echo hi # comment\ncp secret.txt repo1/target.txt", {"repo1/target.txt"}, None),
    ("write-then-trailing-comment", "cp secret.txt repo1/target.txt # note", {"repo1/target.txt"}, None),
    ("comment-first-line", "# leading note\ncp secret.txt repo1/target.txt", {"repo1/target.txt"}, None),
    ("unquoted $VAR target tokenized whole", "cp secret.txt $HOME/repo1/target.txt", {"$HOME/repo1/target.txt"}, None),
    ("unquoted ~ target tokenized whole", "cp secret.txt ~/repo1/target.txt", {"~/repo1/target.txt"}, None),
    ("comment mentions unrelated sensitive path", "cp a.sh b.sh # update hooks/gates/x.sh", None, {"b.sh"}),
    ("comment contains fake redirect symbol", "ls -la # see > repo1/notes.txt for details", None, set()),
    ("# inside quotes is not a comment", 'echo "value#tag" > repo1/out.txt', {"repo1/out.txt"}, None),
    ("benign no-write command", "git status && ls repo1/", None, set()),
]

fails = 0
for desc, cmd, must_include, must_equal in CASES:
    got = set(wtg.bash_write_targets(cmd))
    ok = (must_include is None or must_include.issubset(got)) and (must_equal is None or got == must_equal)
    print(f"{'PASS' if ok else 'FAIL'}\t{desc}\tgot={sorted(got)}")
    fails += 0 if ok else 1
sys.exit(1 if fails else 0)
PYEOF
)
while IFS=$'\t' read -r status desc detail; do
  [ -z "$status" ] && continue
  ok=1; [ "$status" = "PASS" ] && ok=0
  check "battery: $desc ($detail)" "$ok"
done <<< "$BATTERY_OUT"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
