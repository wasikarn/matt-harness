#!/usr/bin/env bash
# Behavioral tests for the worktree-guard gate (opt-in, generic PreToolUse redirect).
# Uses the MH_GUARDED_WORKSPACE / MH_WORKTREE_ROOT env seams to run against throwaway
# repos — never touches any real workspace or ~/.worktrees.
# Run standalone: bash tests/hooks/test-worktree-guard.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$ROOT/hooks/gates/worktree-guard.py"

pass=0
fail=0

TMP=$(mktemp -d "${TMPDIR:-/tmp}/wtguard.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

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

payload_bash() { # payload_bash <command>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

run_guard() { # run_guard <payload> [extra env as K=V ...]
  local p="$1"; shift
  # MH_ALLOW_MAIN_EDIT= resets the escape hatch so an ambient export (e.g. a
  # dev's own shell profile) can't silently no-op every deny/redirect assertion
  # below; env's last-wins semantics let "$@" still opt back in when a test wants it.
  echo "$p" | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= "$@" python3 "$GUARD"
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
out=$(run_guard "$(payload "$WS/repo1/f.txt" sess1234)" MH_ALLOW_MAIN_EDIT=1 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "MH_ALLOW_MAIN_EDIT=1: exit 0, no output" "$ok"

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

# MH_WORKTREE_BASE=main → worktree based on origin/main, not the develop checkout
out=$(run_guard "$(payload "$WS/repo2/f.txt" sessbase)" MH_WORKTREE_BASE=main 2>/dev/null); rc=$?
got=$(git -C "$WT/repo2-wip-sessbase" rev-parse HEAD 2>/dev/null)
ok=1
[ "$rc" -eq 0 ] && [ "$got" = "$MAIN_SHA" ] && echo "$out" | /usr/bin/grep -q 'base origin/main' && ok=0
check "MH_WORKTREE_BASE=main: worktree HEAD == origin/main tip, message names base" "$ok"

# Bogus MH_WORKTREE_BASE → fetch fails → fail-open to HEAD (still redirects)
out=$(run_guard "$(payload "$WS/repo1/g.txt" sessbogus)" MH_WORKTREE_BASE=no-such-branch 2>/dev/null); rc=$?
ok=1
[ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"updatedInput"' \
  && echo "$out" | /usr/bin/grep -q 'base current HEAD' && ok=0
check "bogus MH_WORKTREE_BASE: fail-open to current HEAD, still redirects" "$ok"

# Kill-switch discriminator: CWD == the fake workspace root itself, but
# MH_GUARDED_WORKSPACE is unset. Without the "if not WORKSPACE or not isabs(...): return
# None" guard in classify(), under(fp, "") resolves against CWD and would wrongly protect
# repo1 (on develop, a protected branch) even though nothing is configured. With the
# guard: total no-op regardless of CWD. This is the real regression witness for that
# line — a python-side _selftest() assertion can't discriminate it (traced: a nonexistent
# path returns None earlier via the "not a git repo" branch, and a path at the repo root
# hits the pre-existing workspace-root exemption either way).
out=$(cd "$WS" && echo "$(payload "$WS/repo1/f.txt" sesskill)" \
  | env -u MH_GUARDED_WORKSPACE -u MH_WORKTREE_ROOT -u MH_WORKTREE_BASE -u MH_ALLOW_MAIN_EDIT \
  python3 "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "MH_GUARDED_WORKSPACE unset, cwd==fake workspace root: still exit 0 (kill-switch, not cwd-guard)" "$ok"

# Unset in the ordinary case (no adversarial cwd either) -> total no-op.
out=$(echo "$(payload "$TMP/elsewhere2.txt" sessnorm)" \
  | env -u MH_GUARDED_WORKSPACE python3 "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "MH_GUARDED_WORKSPACE unset (default case): exit 0, no output" "$ok"

# Wrapper-script test: gate:bash:worktree-guard's registration points
# `command`/`args` at a real file (hooks/gates/worktree-guard-dispatch.sh,
# extracted 2026-08-19 to dedupe the byte-identical prelude that used to be
# inlined separately in both worktree-guard hooks.json entries) instead of an
# embedded bash -c string. Shellcheck now lints that file directly as a
# tracked .sh in the normal lint layer, so this test no longer needs to
# extract-and-eval a JSON string in isolation -- it resolves the declared
# script path and runs that file, which is what actually happens at runtime.
# T12 (#91): the individual gate:* PreToolUse entries moved out of hooks.json
# into hooks/pretooluse-table.json (hooks.json now names one dispatcher for
# the whole event) -- extraction points there instead. The table's "script"
# field is repo-relative with no ${CLAUDE_PLUGIN_ROOT} placeholder (unlike
# the old hooks.json args), so resolution is a plain join, not a substitution.
WRAPPER_SCRIPT=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for entry in d:
    if entry.get("id") == "gate:bash:worktree-guard":
        print(entry["script"])
        break
' "$ROOT/hooks/pretooluse-table.json")
ok=1; [ -n "$WRAPPER_SCRIPT" ] && ok=0
check "wrapper script path extracted from pretooluse-table.json" "$ok"

out=$( (unset MH_GUARDED_WORKSPACE CLAUDE_PROJECT_DIR
  export CLAUDE_PLUGIN_ROOT="$ROOT"
  echo '{}' | bash "$ROOT/$WRAPPER_SCRIPT") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "wrapper script: var unset -> exit 0, no output (python never spawned)" "$ok"

bashpayload=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "echo x >> $WS/repo1/f.txt")
out=$( (export MH_GUARDED_WORKSPACE="$WS" CLAUDE_PROJECT_DIR="$WS/repo1" CLAUDE_PLUGIN_ROOT="$ROOT"
  echo "$bashpayload" | bash "$ROOT/$WRAPPER_SCRIPT") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "wrapper script: var set + Bash write to protected checkout -> deny exit 2" "$ok"

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
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "heredoc body w/ unbalanced quote + quoted spaced target -> deny exit 2 (not a silent bypass)" "$ok"

# Same class, ANSI-C quoting: shlex doesn't raise on \$'...', it just splits on
# the bare \$ and yields the wrong token ('\$' itself) instead of the real
# name -- which, run from \$WS the same way, also climbs to the exempt
# workspace root.
ANSIC_CMD="echo x > \$'repo1/notes file.txt'"
bashpayload_ansic=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$ANSIC_CMD")
out=$( (cd "$WS" && echo "$bashpayload_ansic" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "ANSI-C \$'...' quoted target -> deny exit 2 (not a silent bypass)" "$ok"

# Fresh-context re-verification found (2026-09-03) a regression in _normalize_ansi_c_quotes()
# itself, introduced by the GH #124 quote-tracking rewrite of _newlines_to_seps() above: for an
# ANSI-C string containing an escaped internal quote, e.g. $'a\'b', the old naive rewrap (wrap
# the raw captured text in plain quotes) produced 'a\'b' -- an UNBALANCED string with 3 raw quote
# bytes and no legitimate close. _newlines_to_seps' own quote-tracking scanner then opens
# in_squote at the first quote, never finds a real closing quote, and stays in_squote for the
# rest of the command -- silently swallowing every following newline/write with NO separator
# inserted at all. Confirmed against real bash first (bash -x and a real cp): $'a\'b' evaluates
# to the 3-char string a'b, IDENTICAL to the bash splice idiom 'a'\''b' (single quotes have no
# escape mechanism, so a literal quote can only be spliced in this way). Fixed by decoding the
# captured \' unit into that splice idiom instead of copying it raw -- confirmed live against the
# unfixed gate: bash_write_targets() yielded zero targets for the command below (silent bypass).
ANSIC_ESCQUOTE_CMD=$(printf 'echo $%sa\\%sb%s\ncp evil.sh repo1/f.txt' "'" "'" "'")
bashpayload_ansiescquote=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$ANSIC_ESCQUOTE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_ansiescquote" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "ANSI-C \$'a\\'b' (escaped internal quote) + write after it -> deny exit 2 (not silently allowed)" "$ok"

# Adversarial re-verification (2026-09-03, final review before ship): TWO separate ANSI-C
# strings on the same line, each with its own escaped internal quote. This targets the decode's
# own regex boundary -- does _ANSI_C_QUOTE_RE's per-match capture correctly stop at each string's
# own closing quote, or does the first escaped-quote's greedy consumption bleed across into the
# second string's opening $'? Confirmed against real bash first (bash -x): both strings decode
# independently (a'b and c'd), and the trailing write still executes as a separate statement.
ANSIC_TWOSEG_CMD=$(printf "echo \$%sa\\\\%sb%s \$%sc\\\\%sd%s\ncp evil.sh repo1/f.txt" "'" "'" "'" "'" "'" "'")
bashpayload_ansitwoseg=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$ANSIC_TWOSEG_CMD")
out=$( (cd "$WS" && echo "$bashpayload_ansitwoseg" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "two ANSI-C strings on one line, each with an escaped quote, + write after -> deny exit 2" "$ok"

# GH #129 companion fix (this file, 2026-09-03): argv0-splice via command substitution.
# _blank_substitutions() (ported mechanism-only from irrecoverable.sh) plus the
# KNOWN_WRITE_CMDS candidate-duplication loop close the identical bypass shape
# irrecoverable.sh already fixed for its own exact-match argv0 dispatch -- a spliced argv0
# like "c$(true)p" (bash-equivalent to "cp") never equals "cp"/"mv"/"install"/... by exact
# string match. Confirmed by hand-trace before this fix: shlex tokenized the unfixed command
# into an argv0 token no dispatch branch matches (the raw "c$(true)p" text, backticks/parens
# intact -- shlex has no notion that a $(...) span vanishes once bash evaluates it), so
# bash_write_targets() yielded ZERO targets -- a silent bypass of a write that really lands
# on the protected checkout.
SPLICE_ARGV0_CMD='c$(true)p evil.sh repo1/f.txt'
bashpayload_spliceargv0=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$SPLICE_ARGV0_CMD")
out=$( (cd "$WS" && echo "$bashpayload_spliceargv0" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "argv0 splice via \$(...) resolving to cp, writing inside the guarded workspace -> deny exit 2 (was a silent bypass)" "$ok"

# Same bug family, the splice sits in the write TARGET instead of argv0: an unknown \${x}
# parameter expansion blanks to the PH placeholder rather than resolving to empty (real bash
# expands an unset \$x to ""), but the nearest EXISTING directory ancestor of the resulting
# fictitious path still climbs to the real, protected repo1 checkout either way -- so the
# placeholder mismatch doesn't change the verdict here, only the exact candidate string.
TARGET_SPLICE_CMD='cp evil.sh repo1/sub${x}dir/notes.txt'
bashpayload_targetsplice=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$TARGET_SPLICE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_targetsplice" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "target-path splice via \${x} (unknown var) -> deny exit 2" "$ok"

# Negative control: the SAME splice shape, run from a directory genuinely OUTSIDE the guarded
# workspace (not the workspace root itself, which is exempt via an unrelated path -- see the
# "workspace-root repo file: exempt" case above) -- must allow. Guards against an
# overcorrection that denies any splice regardless of where it actually resolves.
OUTSIDE_SPLICE_CMD='$(which cp) evil.sh /tmp/harmless.txt'
bashpayload_outsidesplice=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$OUTSIDE_SPLICE_CMD")
out=$( (cd "$TMP" && echo "$bashpayload_outsidesplice" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "argv0 splice resolving OUTSIDE the guarded workspace -> allow exit 0 (not over-blocked)" "$ok"

# English contraction inside real double quotes must not mask a genuine splice sitting later
# in the same command -- the exact false-negative shape a naive apostrophe-pairing regex hits
# (irrecoverable.sh's own confirmed bug: a shorthand mark used inside real double quotes pairs
# across a genuine $(...) splice and hides it entirely). Fixed the same way here via real
# shell quote-state tracking in _blank_substitutions instead of regex pairing of quote bytes.
CONTRACTION_SPLICE_CMD=$(printf 'echo "it%ss" ; c$(true)p evil.sh repo1/f.txt' "'")
bashpayload_contractionsplice=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$CONTRACTION_SPLICE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_contractionsplice" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "English contraction inside double quotes must not mask a splice later in the command -> deny exit 2" "$ok"

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
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
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
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "hyphenated heredoc delimiter + write statement after it -> deny exit 2 (not silently eaten)" "$ok"

# GH #124 (2026-09-03): _newlines_to_seps() used to preserve a real backslash-newline
# continuation as a literal two-char "\<newline>" pair, on the theory that shlex's own
# posix-mode escape handling deals with it harmlessly. It doesn't: shlex drops only the
# backslash, leaving the newline glued onto whatever token follows -- e.g.
# "sed \<newline>-i" tokenizes to ['sed', '\n-i'], not ['sed', '-i']. That broke every
# exact-match/startswith idiom guard in bash_write_targets() whose target token can sit
# right after a continuation: sed/perl's -i detection, and even argv0 itself when a
# continuation splits it. Confirmed against real bash first (bash -x): both commands
# below execute identically to their continuation-free form, with the write actually
# landing. Confirmed live against the unfixed gate: bash_write_targets() yielded zero
# targets for either, so main() never called classify() at all (silent exit 0). Fixed by
# removing the backslash-newline pair ENTIRELY instead of restoring it, matching bash's
# own line-continuation semantics (same fix pattern as GH #122/#123's char-by-char
# parsers in irrecoverable.sh/main-exec-guard.sh, applied here to this file's
# placeholder-substitution version instead).
SEDI_GLUE_CMD=$(printf 'sed \\\n-i -e s/x/y/ repo1/f.txt')
bashpayload_sedi=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$SEDI_GLUE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_sedi" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "GH #124: sed -i split by backslash-newline continuation onto the -i flag -> deny exit 2 (was a silent bypass)" "$ok"

TEE_GLUE_CMD=$(printf 'true && \\\ntee repo1/f.txt')
bashpayload_teeglue=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$TEE_GLUE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_teeglue" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "GH #124: argv0 itself (tee) split by backslash-newline continuation -> deny exit 2 (was a silent bypass)" "$ok"

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
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "write on a line after a '#' comment -> deny exit 2 (not swallowed as one giant comment)" "$ok"

# Companion: a comment plus a benign command that writes nowhere near the workspace must NOT
# false-deny -- guards against an overcorrection (e.g. disabling commenters entirely, which the
# round-3 dispatch explicitly tested and rejected: it leaks comment text into unrelated targets).
BENIGN_COMMENT_CMD="ls -la # see repo1/notes.txt for details"
bashpayload_benign=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$BENIGN_COMMENT_CMD")
out=$( (cd "$WS" && echo "$bashpayload_benign" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "comment mentioning a workspace-looking path, no real write -> exit 0 (not a false deny)" "$ok"

# Reviewer-found regression in the GH #124 fix above (2026-09-03): _newlines_to_seps() is a
# context-blind regex substitution -- it has no idea whether a backslash-newline sits inside a
# real bash "#" comment. In real bash a comment always ends at the very next literal newline no
# matter what precedes it (comments get zero escape processing), so a backslash right before
# that newline has NO continuation effect there. The post-#124-fix code did not know this and
# fully erased the pair anyway (cmd.replace(placeholder, "")), deleting the only newline that
# would have terminated the comment for the downstream shlex.shlex(..., commenters='#') reader --
# swallowing the write statement that followed into the same comment window. Confirmed against
# real bash first (bash -x): the write executes for real, right after the comment line. Confirmed
# live against the unfixed gate: bash_write_targets() yielded zero targets (silent bypass) --
# WORSE than pre-#124, which at least left the newline in place and denied.
COMMENT_CONT_CMD=$(printf 'echo hello #comment \\\ncp evil.sh repo1/f.txt')
bashpayload_commentcont=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$COMMENT_CONT_CMD")
out=$( (cd "$WS" && echo "$bashpayload_commentcont" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "backslash right before a comment-terminating newline -> deny exit 2 (not swallowed into the comment)" "$ok"

# Side-effect probe: a separate, PRE-EXISTING windowing gap the same reviewer flagged, older
# than GH #124 -- TWO backslashes right before a comment-terminating newline. No continuation is
# even possible inside a comment (POSIX comments get zero escape processing, so the backslash
# COUNT is irrelevant there), but the same context-blind regex only matches the LAST backslash +
# newline as one "continuation" pair and erases it anyway, again eating the separator. Real bash
# still executes the write on the next line regardless of backslash count before the
# comment-ending newline.
COMMENT_2BS_CMD=$(printf 'echo hello #comment \\\\\ncp evil.sh repo1/f.txt')
bashpayload_comment2bs=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$COMMENT_2BS_CMD")
out=$( (cd "$WS" && echo "$bashpayload_comment2bs" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "two backslashes before a comment-terminating newline -> deny exit 2 (pre-existing windowing gap)" "$ok"

# Finding 2: an unquoted \$VAR or ~ redirect target was never expanded before os.path.abspath() --
# '\$' isn't in shlex's default wordchars (splits '\$HOME/x' into '\$' + 'HOME/x') and even a
# whole-token target never ran through expandvars/expanduser, so a write that really lands
# inside the guarded workspace via an env var or ~ silently bypassed the gate. MYVAR is used
# instead of overriding HOME broadly, to keep this test isolated from the rest of the suite.
VARWRITE_CMD='echo x >> $MYVAR/repo1/f.txt'
bashpayload_var=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$VARWRITE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_var" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= MYVAR="$WS" python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "unquoted \$VAR redirect target resolving into the workspace -> deny exit 2" "$ok"

TILDEWRITE_CMD='echo x >> ~/repo1/f.txt'
bashpayload_tilde=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$TILDEWRITE_CMD")
out=$( (cd "$WS" && echo "$bashpayload_tilde" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= HOME="$WS" python3 "$GUARD") 2>/dev/null); rc=$?
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
    # GH #124: a real backslash-newline continuation used to survive into shlex as a
    # literal 2-char pair, which shlex partially un-escapes (drops the backslash, keeps
    # the newline glued onto the next token) -- breaking any exact-match/startswith check
    # whose token sits right after the continuation.
    ("sed -i split by continuation onto the -i flag (GH #124)",
     "sed \\\n-i -e s/x/y/ repo1/target.txt", {"repo1/target.txt"}, None),
    ("argv0 itself (tee) split by continuation (GH #124)",
     "true && \\\ntee repo1/target.txt", {"repo1/target.txt"}, None),
    ("dd of= prefix split by continuation (GH #124)",
     "dd if=/dev/zero \\\nof=repo1/target.txt", {"repo1/target.txt"}, None),
    # Reviewer-found regression in the GH #124 fix: a backslash right before a
    # comment-terminating newline has no continuation effect in real bash (comments end
    # at the very next literal newline no matter what), but the post-#124 regex erased
    # the pair anyway, eating the only newline that would have closed the comment.
    ("backslash before a comment-terminating newline (post-#124 regression)",
     "echo hello #comment \\\ncp evil.sh repo1/target.txt", {"repo1/target.txt"}, None),
    # Same class, pre-existing (older than GH #124): TWO backslashes before a
    # comment-terminating newline. Backslash count is irrelevant inside a comment, but
    # the regex still matched the last backslash+newline as one pair and erased it.
    ("two backslashes before a comment-terminating newline (pre-existing windowing gap)",
     "echo hello #comment \\\\\ncp evil.sh repo1/target.txt", {"repo1/target.txt"}, None),
    # ANSI-C escaped-internal-quote regression (fresh-context re-verification, 2026-09-03):
    # _normalize_ansi_c_quotes() used to copy the raw $'...' escape sequence verbatim and
    # slap plain quotes around it, producing an unbalanced 'a\'b' for $'a\'b' -- which threw
    # _newlines_to_seps' own quote-tracking scanner into a permanent in_squote state, eating
    # the write statement below with zero separator. Fixed by decoding the escaped quote into
    # the bash 'a'\''b' splice idiom (ground-truthed identical to $'a\'b' in real bash).
    ("ANSI-C escaped internal quote spliced into a balanced quote idiom",
     "echo $'a\\'b'\ncp secret.txt repo1/target.txt", {"repo1/target.txt"}, None),
    # Companion: a plain $'...' with NO escaped quote must keep behaving exactly as before
    # the fix (guards against overcorrection breaking the common, already-working case).
    ("plain ANSI-C quote with no escaped quote still works",
     "echo $'plain text'\ncp secret.txt repo1/target.txt", {"repo1/target.txt"}, None),
    # Primary use case: the escaped quote sits INSIDE the write TARGET itself (not just
    # incidental text before it) -- $'repo1/we\'ird.txt' decodes to the literal filename
    # repo1/we'ird.txt, same as real bash.
    ("ANSI-C escaped quote inside the write target itself",
     "cp secret.txt $'repo1/we\\'ird.txt'", {"repo1/we'ird.txt"}, None),
    # Grouping-operator gap (2026-09-03, same root cause as verifier-protect.sh's identical
    # fix that same day): SEPS was {";", "&&", "||", "|", "&"} -- missing "(", ")", "{", "}".
    # A parenthesized/braced command never gets its window split at the grouping boundary, so
    # "(" or "{" becomes argv0 instead of the real command, and no argv0-dispatch branch
    # matches it -- silent bypass (empty target set) instead of the real "cp" target.
    ("parenthesized subshell command (grouping-operator gap)",
     "(cp evil.sh repo1/target.txt)", {"repo1/target.txt"}, None),
    ("braced group command (grouping-operator gap)",
     "{ cp evil.sh repo1/target.txt; }", {"repo1/target.txt"}, None),
    # Negative control: a literal "(" / "{" inside a QUOTED argument is not a real grouping
    # construct -- shlex keeps the quoted token intact as one string, so it must never equal
    # the bare "(" / "{" separator token and must not be misclassified as a window boundary.
    ("quoted literal parenthesis is not a grouping operator",
     'echo "value(1)" > repo1/target.txt', {"repo1/target.txt"}, None),
    ("quoted literal brace is not a grouping operator",
     'echo "{not a group}" > repo1/target.txt', {"repo1/target.txt"}, None),
    # 2026-09-03: _normalize_ansi_c_quotes only fixed token BOUNDARIES ($'...' -> '...'),
    # never RESOLVED the escape itself. This file's dispatch below compares argv0 by EXACT
    # STRING (argv0 in ("cp", "mv", "install"), ...), so a boundary-only rewrite leaves argv0
    # as the literal token "c\x70" (backslash-x-7-0 raw), which can never equal "cp". Same
    # root cause fixed the same day in a sibling gate for its own exact-match argv0 dispatch;
    # ported the corrected decode logic here. Confirmed exploitable live before this fix:
    # bash_write_targets() yielded [] for the command below (silent bypass) -- bash itself
    # evaluates it identically to a plain cp of evil.sh onto repo1/target.txt.
    ("ANSI-C hex escape resolves argv0 back to a real command (was a silent bypass)",
     "c$'\\x70' evil.sh repo1/target.txt", {"repo1/target.txt"}, None),
    # Negative control: an ordinary single-quoted argument (no $'...' form at all, never
    # enters the ANSI-C regex) must stay correctly classified after the fix -- guards against
    # the decode-resolving rewrite breaking the common, already-working case.
    ("ordinary single-quoted argument unaffected by ANSI-C normalization",
     "cp secret.txt 'repo1/target.txt'", {"repo1/target.txt"}, None),
    # Decode-path-without-mis-split control: the write TARGET itself carries a \n escape
    # that must actually RESOLVE to a real newline byte (not stay literal backslash-n, which
    # is what the old boundary-only rewrite produced), and that real newline byte must stay
    # INSIDE the quoted span rather than leaking out and being read by _newlines_to_seps as a
    # statement separator -- which would either mis-split this one write into two windows or
    # throw off its quote-tracking scanner and swallow the write statement that follows with
    # no separator inserted. The second write confirms the window after it is still detected
    # independently.
    ("ANSI-C newline escape resolves to a real newline inside the target, without mis-splitting the window after it",
     "cp secret.txt $'repo1/embed\\nded.txt'\ncp evil.sh repo1/target.txt",
     {"repo1/embed\nded.txt", "repo1/target.txt"}, None),
    # Negative control for the tar false-positive fix (item 7, 2026-09-03): once argv0
    # splices to a PH-bearing token, the tar branch runs against WHATEVER the real first
    # argument is, even when the real command was never tar at all. A bare "x in mode_str"
    # containment check false-denied on any first argument that merely CONTAINS the letter x
    # -- "extract.sh" looks like an old-style "-xvf" flag cluster to a naive containment
    # check, but is really just a filename. Fixed by requiring every character of mode_str to
    # be a real tar single-letter flag before "x" counts as extract mode -- "extract.sh" fails
    # immediately on its own "." byte, which is never a real tar flag character, so the tar
    # branch now correctly yields nothing. must_equal (not must_include) confirms "." (the
    # false implicit-cwd-extraction target) is ABSENT -- the only candidate left is the one
    # every other duplicated branch (tee/cp/mv/install/rsync/patch) independently agrees on.
    ("PH-spliced argv0 with a tar-look-alike first arg does not false-flag tar extract (item 7 fix)",
     "$(true)x extract.sh", None, {"extract.sh"}),
    # Reviewer-found bug in a SIBLING gate (irrecoverable.sh/verifier-protect.sh, confirmed
    # 2026-09-03), independently re-verified here against this file's own flag-detection sites:
    # a command substitution resolving to empty sitting IMMEDIATELY BEFORE a flag's leading
    # dash vanishes in real bash ("sed $(true)-i ..." really runs as "sed -i ..."), but
    # _blank_substitutions() inserts a literal, non-empty PH byte instead of modeling "resolves
    # to empty" -- so the token becomes e.g. "\x01-i", which does NOT start with a literal "-".
    # Every startswith("-")/exact-equality flag check below silently MISSED it before this fix,
    # not just the argv0-dispatch that _blank_substitutions itself already covers via the
    # KNOWN_WRITE_CMDS duplication loop -- this is a second, independent gap one level deeper,
    # inside the per-command flag parsing. Fixed by stripping a leading PH before every such
    # test (t.lstrip(PH)), same fix shape as the sibling gates.
    ("sed -i via PH-before-dash splice (was a silent bypass)",
     "sed $(true)-i s/a/b/ repo1/target.txt", {"repo1/target.txt"}, None),
    ("perl -i via PH-before-dash splice (was a silent bypass)",
     "perl $(true)-i -e s/a/b/ repo1/target.txt", {"repo1/target.txt"}, None),
    ("cp -t via PH-before-dash splice (was: fell through to nonflag[-1], a source arg not the real dest)",
     "cp $(true)-t repo1 evil.sh", {"repo1"}, None),
    ("mv -t via PH-before-dash splice (was: fell through to nonflag[-1], a source arg not the real dest)",
     "mv $(true)-t repo1 evil.sh", {"repo1"}, None),
    ("install -t via PH-before-dash splice (was: fell through to nonflag[-1], a source arg not the real dest)",
     "install $(true)-t repo1 evil.sh", {"repo1"}, None),
    ("tar short -xvf via PH-before-dash splice (was a silent bypass)",
     "tar $(true)-xvf archive.tar -C repo1", {"repo1"}, None),
    # Legacy tar mode strings are bare words with no dash at all, so the leading PH can sit
    # directly in front of the flag letters too, not just before a dash -- a distinct splice
    # shape from every other site above, needing the same fix (mode_str.lstrip(PH) before the
    # "--" check and before dash-stripping).
    ("tar old-style xvf via PH-before-bareword splice, no dash at all (was a silent bypass)",
     "tar $(true)xvf evil.tar -C repo1", {"repo1"}, None),
    ("tar -C via PH-before-dash splice (was: fell through to the implicit-cwd '.' fallback)",
     "tar -xf archive.tar $(true)-C repo1", {"repo1"}, None),
    ("dd of= via PH-before-prefix splice, not a dash flag but the same root cause (was a silent bypass)",
     "dd if=/dev/zero $(true)of=repo1/target.txt", {"repo1/target.txt"}, None),
    # 2026-09-03 finding 6a: a $(...) body re-appended after " ; " landed inside a
    # trailing "# comment" that was still open (shlex's comment handling stops only at
    # a literal newline) -- the whole recovered write vanished into that comment.
    ("comment-truncation: $(...) body then trailing # comment (was a silent bypass)",
     "echo $(cp evil.sh repo1/f.txt)  # copy", {"repo1/f.txt"}, None),
    # 2026-09-03 finding 6b: the ${...} closer-search doesn't track quote state over
    # skipped characters, so a genuinely balanced default-value expansion containing a
    # quoted "}" matched its closer at the wrong "}" and raised ValueError (a false
    # deny on ordinary bash, not a real problem with the command).
    ('param-expansion default with a quoted "}" no longer false-denies (was ValueError)',
     'echo ${x:-"a}b"}', None, set()),
    # Composite regression witness: an EARLIER version of the finding-6b fallback used a
    # plain raw_cmd.split(), which fuses "repo1/f.txt;" into one word and collapses this
    # into a single window -- the nonflag[-1] fallback then grabbed the trailing
    # ${x:-"a}b"} token instead of the real cp target, a fail-open on a deny-gate (a
    # write that should deny would have silently allowed). The separator-aware fallback
    # keeps ";" as its own token so the real target still surfaces.
    #
    # Recorded red for THIS case specifically (not reproducible through this battery):
    # the unfixed code raises ValueError on the PRECEDING case (the bare ${x:-"a}b"}
    # probe two entries up) before this one ever runs, and this loop has no per-case
    # try/except, so a battery run against unfixed code shows this case as a missing
    # line, not a clean FAIL -- see the harness-limitation note below the CASES list.
    # Verified instead by direct probe against the intermediate raw_cmd.split()
    # fallback (2026-09-03, before the separator-aware split replaced it): got
    # {'${x:-"a}b"}'} -- the real cp target was silently dropped. This case's PASS
    # here is against the shipped separator-aware fallback, confirming it recovers
    # {'repo1/f.txt'} where the intermediate version did not.
    ("cp target still recovered when followed by a ${...} false-positive trigger (was fail-open)",
     'cp evil.sh repo1/f.txt; echo ${x:-"a}b"}', {"repo1/f.txt"}, None),
    # Finding 5 (2026-09-03, dispatch gap flagged separately from 6a/6b/8): _scan_once
    # had no in_comment state, so a $(...) span appearing only inside a "# ..." comment
    # still got matched and blanked, then re-appended by the finding-6a body-reappend as
    # if it were a real statement -- a merely-commented-out command treated as live.
    # Verified pre-fix (source reconstructed minus this hunk): this exact command
    # returned {'b.sh', 'guarded/z.sh'} -- the commented-out target leaked in.
    ("commented-out $(...) is inert, not treated as a live statement (was a false positive)",
     'cp a.sh b.sh # note $(cp evil.sh guarded/z.sh)\necho hi', None, {"b.sh"}),
    # Companion control: a GENUINE (non-commented) substitution on the same physical
    # structure -- next line, not after a "#" -- must still be caught. Same before and
    # after finding 5 (this is the case the fix must not break), so this is a control,
    # not a regression witness on its own; it matters paired with the case above.
    ("genuine (non-commented) $(...) on the same structure still caught (control)",
     'cp a.sh b.sh\n$(cp evil.sh guarded/z.sh)', {"b.sh", "guarded/z.sh"}, None),
    # 2026-09-03, cross-file reviewer finding: the finding-6b ValueError fallback
    # tokenizes raw_cmd directly (never runs through _blank_substitutions), so a
    # spliced argv0 in that path keeps its literal substitution syntax and never
    # contains PH -- the PH-only GH #129 duplication trigger above can never fire
    # on it by construction. Verified pre-fix (source reconstructed minus the
    # _has_raw_subst widening): this exact command returned [] -- silent allow of
    # a real write. _has_raw_subst(argv0) closes it by also triggering on raw
    # backtick/$(/${ syntax, not just PH.
    ("quote-crossing fallback + spliced argv0 still caught (was a silent allow)",
     'echo ${y:-"a}b"} ; c$(true)p evil.sh target.txt', {"target.txt"}, None),
    # 2026-09-04, third cross-file review: a mid-flag splice (PH landing INSIDE an
    # already-dash-prefixed flag, not glued to the front of it) was invisible to the
    # old leading-only t.lstrip(PH) -- "-\x01i" doesn't start with PH (it starts with
    # "-"), so lstrip(PH) is a no-op and every startswith("-i")/exact-equality test
    # missed it. Confirmed live pre-fix (source reconstructed minus the
    # replace(PH, "")/_has_raw_subst widening): this exact command returned [] --
    # sed's -i detection is the single outer gate for the whole branch, so the miss
    # was a full silent bypass, not a degraded one.
    ("sed -i via mid-flag PH splice (was a silent bypass, distinct from the leading-PH case above)",
     "sed -$(true)i -e s/x/y/ repo1/target.txt", {"repo1/target.txt"}, None),
    # Same mid-flag shape, via the ValueError-fallback path -- raw_cmd is tokenized
    # directly there and never runs through _blank_substitutions, so "-$(true)i"
    # keeps its literal, unblanked text (no PH byte at all for replace(PH, "") to
    # strip). _has_raw_subst() closes it the same way it already does for argv0 and
    # the Bash write-target fail-safe in main().
    ("sed -i via mid-flag splice on the ValueError-fallback path (was a silent allow)",
     'echo ${y:-"a}b"} ; sed -$(true)i -e s/x/y/ repo1/target.txt', {"repo1/target.txt"}, None),
    # Negative control (noask): an ordinary sed with NO -i at all (a stream-editor
    # read, not an in-place write) must not be false-flagged just because argv0 is
    # "sed" -- guards against an overcorrection that treats every sed invocation as
    # a write regardless of whether -i is actually present.
    ("sed with no -i flag at all is not a write (noask negative control)",
     "sed -e s/x/y/ repo1/target.txt", None, set()),
]

# Known harness limitation, not fixed here (out of scope for this round -- flagged for
# whoever next adds a case that legitimately raises): the loop below calls
# wtg.bash_write_targets(cmd) with no per-case try/except, so a case that raises
# ValueError kills the whole heredoc script mid-iteration instead of reporting a clean
# FAIL for that one case -- every case after it in CASES silently never runs, with no
# "crashed here" signal, just a shorter tally. Confirmed 2026-09-03 while red-testing
# the finding-6b cases above: the unfixed code raised on the ${x:-"a}b"} case and the
# composite case right after it never printed a line at all.
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

# Round-4 regression tests (found 2026-08-04 by a subagent_type:kbg:silent-failure-hunter
# dispatch covering both worktree-guard.py and verifier-protect.sh together -- a different
# idiom family than rounds 1-3: git apply/am and patch never scanned diff CONTENT for the
# real +++ b/<path> target, and bare tar extraction (no -C) yielded no candidate at all.
# All 3 were already disclosed as deferred follow-ups in this repo's own v0.68.171
# CHANGELOG entry; closed here as their own scoped piece of work per explicit user choice.
DIFF_FILE="$TMP/evil.diff"
printf -- '--- a/f.txt\n+++ b/f.txt\n@@ -1,1 +1,1 @@\n-x\n+evil\n' > "$DIFF_FILE"

out=$( (cd "$WS/repo1" && echo "$(payload_bash "git apply $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "git apply: real target lives in diff content (+++ b/f.txt), not argv -> deny exit 2" "$ok"

# The first version of this fix dispatched into git apply/am correctly for -C but still
# resolved the diff's relative target against the hook's own cwd instead of the -C value --
# confirmed the hard way while building this round's fix, not assumed clean. Run from $WS
# itself (the exempt workspace root) so a naive cwd-relative resolution would silently pass.
out=$( (cd "$WS" && echo "$(payload_bash "git -C $WS/repo1 apply $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "git -C <dir> apply: -C resolves the diff target, not the hook's own cwd -> deny exit 2" "$ok"

# Reviewer-found bug (confirmed in a sibling gate 2026-09-03, re-verified here): git -C's
# exact-equality check (rest[0] == "-C") never accounted for a leading PH placeholder from an
# empty command substitution ($(true)-C -> \x01-C in real bash resolves to plain -C). Unlike
# patch's -d below, there is no redundant nonflag fallback here -- the ENTIRE apply/am dispatch
# is gated behind this one check, so a bypass yielded nothing at all (full pipeline, was exit
# 0). Run from $WS (the exempt workspace root) so a naive cwd-relative resolution would
# silently pass, same discipline as the non-spliced case above.
out=$( (cd "$WS" && echo "$(payload_bash "git \$(true)-C $WS/repo1 apply $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "git \$(true)-C <dir> apply (PH-before-dash splice): still deny exit 2 (was a silent bypass)" "$ok"

# Adversarial-review find (2026-09-03): the apply/am dispatch check itself
# (rest[sub_idx] in ("apply", "am")) never accounted for a leading PH
# placeholder either -- one token over from the git -C bug above, a splice
# glued directly onto the subcommand token bypassed the ENTIRE apply/am
# dispatch. Run from $WS/repo1 (protected main checkout) so only a correct
# apply/am dispatch, not an accidental fallback, can deny.
out=$( (cd "$WS/repo1" && echo "$(payload_bash "git \$(true)apply $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "git \$(true)apply <diff> (PH-glued-to-subcommand splice): still deny exit 2 (was a silent bypass)" "$ok"

out=$( (cd "$WS/repo1" && echo "$(payload_bash "git \$(true)am $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "git \$(true)am <diff> (PH-glued-to-subcommand splice): still deny exit 2 (was a silent bypass)" "$ok"

# patch's -d/--directory relocates where a relative in-diff target resolves, same class of
# bug as git -C above. Run from $TMP (neutral, outside any repo) so a naive cwd-relative
# resolution would silently pass.
out=$( (cd "$TMP" && echo "$(payload_bash "patch --directory=$WS/repo1 -p1 < $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "patch --directory=: real target resolves against it, not bare cwd -> deny exit 2" "$ok"

# Same reviewer-found bug, patch's bundled --directory=X form: unlike -d/--directory (a
# separate token whose VALUE independently lands in `nonflag` and gets yielded regardless of
# whether the flag itself is recognized -- see the code comment at this branch), --directory=X
# packs flag and value into ONE token, so a PH-disguised prefix hides the whole value with no
# redundant fallback. Run from $TMP (neutral) so a naive cwd-relative resolution would silently
# pass, same discipline as the non-spliced case above.
out=$( (cd "$TMP" && echo "$(payload_bash "patch \$(true)--directory=$WS/repo1 -p1 < $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "patch \$(true)--directory= (PH-before-dashdash splice): still deny exit 2 (was a silent bypass)" "$ok"

# tar xf with no -C writes into cwd; the branch used to yield nothing at all for this form.
out=$( (cd "$WS/repo1" && echo "$(payload_bash "tar xf archive.tar")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "tar xf, no -C: cwd itself is the implicit target -> deny exit 2" "$ok"

# Layer 3 bug (found by an independent adversarial reviewer, 2026-09-03): a
# STANDALONE, unquoted word that resolves to empty at runtime vanishes
# entirely in real bash via word-splitting, shifting every later token left
# by one position. The two fixed-index reads below (git apply/am's -C check
# at rest[0], and tar's mode-string check also at rest[0]) instead see a
# PH-only token sitting in that position and read the wrong token, missing
# the real -C directory / extract mode entirely. Fixed by also running each
# check against a second, COMPACTED token list with every bare-PH-only token
# removed -- the verdict denies if either pass denies.
out=$( (cd "$WS" && echo "$(payload_bash "git \$(true) -C $WS/repo1 apply $DIFF_FILE")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "git \$(true) -C <dir> apply (bare vanish before -C): still deny exit 2 (was a silent bypass)" "$ok"

# cwd is $WS (outside repo1) so only the -C reading — not an accidental cwd
# fallback — can make this deny; that isolates the fixed-index bug from the
# already-working "tar xf, no -C" implicit-cwd case above.
out=$( (cd "$WS" && echo "$(payload_bash "tar \$(true) -xf archive.tar -C $WS/repo1")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "tar \$(true) -xf archive.tar -C <dir> (bare vanish before -xf): still deny exit 2 (was a silent bypass)" "$ok"

# Adjacent shape checked while closing the above (2026-09-03): a bare-vanish
# token AT argv0 itself ("$(true) tar -xf archive.tar -C repo1") was also
# probed. Not added as its own regression case here -- differential testing
# (this fix present vs. reverted to rest-only scope) showed the full suite
# passes either way for that shape, so a test for it would not distinguish
# buggy from fixed behavior (test-honesty "distinguishes-or-it-doesn't"
# rule). Root cause: argv0 containing PH already routes through the GH #129
# KNOWN_WRITE_CMDS duplication loop, and its tee/patch candidates
# unconditionally yield every non-flag token in `rest` regardless of
# position, so the real target still surfaces through one of them even
# while the tar/git branches' own fixed-index read is misaligned -- see the
# code comment at rest_compacted's definition in worktree-guard.py.

# Negative: git apply against a diff that does not touch a protected path must not false-deny.
BENIGN_DIFF="$TMP/benign.diff"
printf -- '--- a/README.md\n+++ b/README.md\n@@ -1,1 +1,1 @@\n-old\n+new\n' > "$BENIGN_DIFF"
out=$( (cd "$TMP" && echo "$(payload_bash "git apply $BENIGN_DIFF")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "git apply against a diff outside the workspace: exit 0, no false deny" "$ok"

# 2026-08-23 mutation-testing probe (docs/research/mutation-probe-results-2026-08-23.md):
# bash_write_targets() detects each in-place-edit idiom below TODAY, but no test held it,
# so a mutation to the sed/cp/tar/dd extraction survived the suite (fail-open, undetected).
# Each writes to repo1 (a protected develop main-checkout) run from $WS -> must deny exit 2.
for idiom_case in \
  "sed --in-place 's/x/y/' repo1/f.txt|sed --in-place (GNU long form)" \
  "sed -i -e 's/x/y/' repo1/f.txt|sed -i -e (routine -e script form)" \
  "cp -t repo1 secret.txt|cp -t <protected-dir> (target via -t, not source)" \
  "cp -at repo1 secret.txt|cp -at <protected-dir> (combined flags, space -t value)" \
  "dd if=/dev/zero of=repo1/f.txt|dd of=<protected-file>" \
  "tar -x -C repo1 -f /tmp/a.tar|tar -x -C <protected-dir>"; do
  cmd=${idiom_case%%|*}; desc=${idiom_case##*|}
  out=$( (cd "$WS" && echo "$(payload_bash "$cmd")" \
    | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
  ok=1; [ "$rc" -eq 2 ] && ok=0
  check "in-place idiom writes to protected checkout -> deny exit 2: $desc" "$ok"
done

# 2026-08-23 probe, highest-severity cluster: classify()'s worktree/branch decision. The gate
# treats a repo's MAIN checkout as shared-tree (redirect) REGARDLESS of branch, and a real
# worktree as safe ONLY on a non-protected branch. Mutations inverting either condition
# fail-open (a shared checkout on a feature branch, or a protected-branch worktree, slips
# through) with no test noticing. Build the three distinguishing fixtures and lock each verdict.
CLS="$TMP/cls"; mkdir -p "$CLS"
# (a) sub-repo whose MAIN checkout is on a NON-protected branch, inside the workspace.
mkrepo "$WS/repofeat" develop; git -C "$WS/repofeat" switch -q -c feature
out=$(run_guard "$(payload "$WS/repofeat/f.txt" sesscla)" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"updatedInput"' && ok=0
check "(a) main checkout on a non-protected branch is still shared-tree -> redirect (not silent-allow)" "$ok"
# (b) a REAL worktree checked out on a PROTECTED branch (develop), inside the workspace. The
# main checkout must be off develop so git will let the worktree take it.
mkrepo "$WS/repowt" develop; git -C "$WS/repowt" switch -q -c feature
git -C "$WS/repowt" worktree add -q "$WS/wt-dev" develop 2>/dev/null
out=$(run_guard "$(payload "$WS/wt-dev/f.txt" sessclb)" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && echo "$out" | /usr/bin/grep -q '"updatedInput"' && ok=0
check "(b) worktree on a protected branch inside the workspace -> redirect (not silent-allow)" "$ok"
# (c) a real worktree on a NON-protected branch inside the workspace -> genuinely safe, must
# NOT be redirected or denied (guards against over-blocking legit feature worktrees).
git -C "$WS/repowt" worktree add -q -b feat-c "$WS/wt-featc" 2>/dev/null
out=$(run_guard "$(payload "$WS/wt-featc/f.txt" sessclc)" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "(c) worktree on a non-protected branch inside the workspace -> allow, no redirect (not over-blocked)" "$ok"

# Grouping-operator gap, full pipeline (2026-09-03): confirm the same bug through main() /
# classify(), not just the bash_write_targets() battery above -- a parenthesized or braced
# command run against a protected checkout must deny exit 2, not silently pass.
GROUP_PAREN_CMD='(cp evil.sh repo1/f.txt)'
out=$( (cd "$WS" && echo "$(payload_bash "$GROUP_PAREN_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "grouping-operator gap: (cp evil.sh repo1/f.txt) -> deny exit 2 (was a silent bypass)" "$ok"

GROUP_BRACE_CMD='{ cp evil.sh repo1/f.txt; }'
out=$( (cd "$WS" && echo "$(payload_bash "$GROUP_BRACE_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "grouping-operator gap: { cp evil.sh repo1/f.txt; } -> deny exit 2 (was a silent bypass)" "$ok"

# Negative control, full pipeline: a legitimate command with a literal "(" in a quoted
# argument (not a real grouping construct) must not be misclassified -- must still resolve
# and deny on its real write target, not silently pass due to a broken window split.
QUOTED_PAREN_CMD='echo "value(1)" > repo1/f.txt'
out=$( (cd "$WS" && echo "$(payload_bash "$QUOTED_PAREN_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "negative control: quoted literal '(' in an argument is not a grouping operator -> still deny exit 2 on the real target" "$ok"

# Finding 6b, full pipeline (2026-09-03): a genuinely balanced default-value expansion
# containing a quoted "}" used to raise ValueError inside bash_write_targets() (the
# ${...} closer-search doesn't track quote state), which main()'s catch turns into a
# fail-closed deny -- a false deny on ordinary bash with no write target at all. This
# distinguishes cleanly: exit 2 before this session's fix, exit 0 after.
PARAM_EXPANSION_CMD='echo ${x:-"a}b"}'
out=$( (cd "$WS" && echo "$(payload_bash "$PARAM_EXPANSION_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "finding 6b: \${x:-\"a}b\"} default-value expansion no longer false-denies -> exit 0 (was exit 2)" "$ok"

# Control, not a regression witness (test-honesty rule 6): a genuinely unterminated
# quote is real ambiguity, not this scanner's own artifact -- it must still deny both
# before and after the finding-6b fix (the fallback's own validity probe re-raises on
# it). Exit code is identical pre- and post-fix; this only confirms the fail-closed
# contract wasn't loosened by the fix, it is not evidence the fix does anything.
MALFORMED_CMD='echo "unterminated'
out=$( (cd "$WS" && echo "$(payload_bash "$MALFORMED_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "control (unchanged both sides): genuinely unterminated quote still denies exit 2" "$ok"

# 2026-09-03/04, second adversarial reviewer round: main()'s Bash-branch loop had no
# PH/raw-subst fail-safe at all before resolving a yielded target through
# os.path.abspath()/classify() -- unlike verifier-protect.sh's equivalent check. A splice
# landing INSIDE the target itself (not just at argv0) survives all the way to that call.
# Both cases below use the REAL absolute path to the guarded repo1 checkout -- the exploit
# is specifically that a PH/raw-subst byte glued to the FRONT of an otherwise-absolute path
# makes os.path.abspath() treat it as relative and reparent it under the hook's own cwd, so
# it can never match under(fp, WORKSPACE).
#
# Bug 2 (more severe -- no fallback trigger needed, live on the ordinary primary path):
# $(true) blanks to a leading PH byte fused onto the absolute path with no space between
# them. Verified pre-fix (source reconstructed minus this hunk): exit 0, silent allow of a
# real write into the guarded checkout.
ABS_SPLICE_CMD='cp evil.sh $(true)'"$WS"'/repo1/target.txt'
out=$( (cd "$WS" && echo "$(payload_bash "$ABS_SPLICE_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "PH glued to an absolute guarded target still denies exit 2 (was a silent allow, no fallback needed)" "$ok"

# Bug 1 (fallback-path variant, same shape as the finding-6b/argv0 fix): the leading
# quote-crossing span forces the ValueError fallback, whose tokens come from raw_cmd and
# never get PH-blanked at all -- the literal, unblanked "$(true)" is still glued to the
# front of the absolute path, defeating abspath() the same way PH does.
FALLBACK_ABS_SPLICE_CMD='echo ${y:-"a}b"} ; cp evil.sh $(true)'"$WS"'/repo1/target.txt'
out=$( (cd "$WS" && echo "$(payload_bash "$FALLBACK_ABS_SPLICE_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "raw \$(...) glued to an absolute guarded target via the fallback path still denies exit 2 (was a silent allow)" "$ok"

# Round-5 regression, full pipeline (2026-09-04, third cross-file review): the confirmed
# mid-flag splice payload run through main()/classify(), not just the bash_write_targets()
# battery above. Real bash: "$(true)" evaluates to empty and vanishes, so this really runs
# as "sed -i -e s/x/y/ repo1/f.txt" -- an in-place edit landing on the protected checkout.
# Verified pre-fix (source reconstructed minus the replace(PH, "")/_has_raw_subst widening):
# exit 0, silent allow.
SED_MIDFLAG_CMD='sed -$(true)i -e s/x/y/ repo1/f.txt'
out=$( (cd "$WS" && echo "$(payload_bash "$SED_MIDFLAG_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "sed -i via mid-flag \$(true) splice denies exit 2 (was a silent allow, full pipeline)" "$ok"

# Negative control (noask), full pipeline: the same benign no -i sed command as the battery
# control above, run through main()/classify() -- must allow with no output at all, guarding
# against an overcorrection that denies any sed invocation regardless of -i.
SED_NOFLAG_CMD='sed -e s/x/y/ repo1/f.txt'
out=$( (cd "$WS" && echo "$(payload_bash "$SED_NOFLAG_CMD")" \
  | env MH_GUARDED_WORKSPACE="$WS" MH_WORKTREE_ROOT="$WT" MH_ALLOW_MAIN_EDIT= python3 "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "sed with no -i is not a write, exit 0 no output (noask negative control, full pipeline)" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
