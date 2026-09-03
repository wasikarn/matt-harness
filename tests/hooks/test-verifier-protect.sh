#!/usr/bin/env bash
# Behavioral tests for verifier-protect.sh (always-on gate — no opt-in condition,
# unlike worktree-guard.py — fires on every Bash/Write/Edit call in every repo running
# this plugin). Had zero automated coverage before 2026-08-04: this file was added the
# same day as the round-3 port of worktree-guard.py's heredoc/ANSI-C/newline/$VAR/~
# fixes into this gate's own embedded generator, specifically to close that gap.
# Run standalone: bash tests/hooks/test-verifier-protect.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$ROOT/hooks/gates/verifier-protect.sh"

pass=0
fail=0

payload_bash() { # payload_bash <command>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

payload_write() { # payload_write <file_path> [content]
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2] if len(sys.argv)>2 else ""}}))' "$@"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== verifier-protect gate ==="

cd "$ROOT" || exit 1

# Baseline sanity (pre-existing behavior, not touched this round)
out=$(payload_bash "cp evil.sh hooks/gates/evil.sh" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "direct Bash write to hooks/gates/* -> ask" "$ok"

out=$(payload_write "hooks/gates/foo.py" "print(1)" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write tool targeting hooks/gates/* -> ask" "$ok"

out=$(payload_bash "cp a.sh /tmp/somewhere/b.sh" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "unrelated benign write -> exit 0, no output" "$ok"

# T12/#91's own new files (hooks/pretooluse-table.json, dispatch-pretooluse.py/.sh)
# inherited none of the verifier-protect coverage that hooks/hooks.json itself
# has, since gate routing MOVED into them -- a model could repoint a gate's
# script, delete a table row, or rewrite the merge logic with zero prompt.
# Found by an independent adversarial audit, 2026-08-25; fixed the same day
# in both is_gate_path() and this gate's own Bash fast-path allowlist.
out=$(payload_write "hooks/pretooluse-table.json" "[]" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write tool targeting hooks/pretooluse-table.json -> ask" "$ok"

out=$(payload_write "hooks/dispatch-pretooluse.py" "print(1)" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write tool targeting hooks/dispatch-pretooluse.py -> ask" "$ok"

out=$(payload_write "hooks/dispatch-pretooluse.sh" "echo x" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Write tool targeting hooks/dispatch-pretooluse.sh -> ask" "$ok"

out=$(payload_bash "sed -i '' 's/deny/allow/' hooks/pretooluse-table.json" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Bash-mediated sed -i on hooks/pretooluse-table.json -> ask (not the fast-path skip)" "$ok"

# Round-3 port regressions/gaps (found by a subagent_type:kbg:silent-failure-hunter
# re-verification dispatch against worktree-guard.py the same day, then confirmed to
# also be exploitable here by direct reproduction against the unmodified file before
# porting the fix). Each pairs a must-ask positive case with the closest negative case,
# same discipline as test-worktree-guard.sh's battery: a fix that only stops the bypass
# but starts false-denying benign commands is not actually fixed.
BATTERY=(
  "newline-joined write on 2nd line|$(printf 'echo hello\nsed -i "" "s/x/y/" hooks/gates/irrecoverable.sh')|ask"
  "heredoc body w/ unbalanced quote, write after|$(printf "cat <<EOF > /tmp/x.txt\nit%ss here\nEOF\ncp evil.sh hooks/gates/evil2.sh" "'")|ask"
  "ANSI-C quoted target|echo x > \$'hooks/gates/evil5.sh'|ask"
  "hyphenated heredoc delimiter, write after|$(printf 'cat <<MY-EOF\nbody\nMY-EOF\ncp evil.sh hooks/gates/evil6.sh')|ask"
  "unquoted \$TARGETDIR target|cp evil.sh \$TARGETDIR/evil3.sh|ask"
  "unquoted ~ target|cp evil.sh ~/evil4.sh|ask"
  "comment mentions a protected-looking path, no real write|cp a.sh b.sh # update hooks/gates/x.sh|noask"
  "comment contains a fake redirect symbol|ls -la # see > hooks/gates/notes.txt for details|noask"
  "write on same line before a trailing comment, target NOT protected|cp a.sh /tmp/b.sh # note|noask"
  # GH #124 (2026-09-03): _newlines_to_seps() used to preserve a real backslash-newline
  # continuation as a literal "\<newline>" pair, on the theory that shlex handles it
  # harmlessly on its own. It does not: shlex's posix-mode escape handling drops only the
  # backslash, leaving the newline glued onto whatever token follows -- e.g.
  # "sed \<newline>-i" tokenizes to "\n-i", not "-i". That silently broke this generator's
  # own exact-match/startswith idiom guards (sed/perl -i detection, and even argv0 itself
  # when a continuation splits it), the same shape as GH #122/#123's top-level flag
  # checks. Confirmed against real bash first: both commands below execute identically to
  # their continuation-free form. Confirmed live against the unfixed gate: bash_write_
  # targets() yielded zero targets for either, a silent allow on a write that really does
  # land on a verifier surface. Fixed by removing the backslash-newline pair entirely.
  "sed -i split by continuation onto the -i flag (GH #124)|$(printf 'sed \\\n-i -e s/x/y/ hooks/gates/irrecoverable.sh')|ask"
  "argv0 itself (tee) split by continuation (GH #124)|$(printf 'true && \\\ntee hooks/gates/irrecoverable.sh')|ask"
  # Reviewer-found regression in the GH #124 fix (2026-09-03): _newlines_to_seps() is a
  # context-blind regex substitution -- it has no idea whether a backslash-newline sits
  # inside a real bash "#" comment. In real bash a comment always ends at the very next
  # literal newline no matter what precedes it (comments get zero escape processing), so
  # a backslash right before that newline has NO continuation effect there. The
  # post-#124-fix code did not know this and fully erased the pair anyway, deleting the
  # only newline that would have terminated the comment for the downstream
  # shlex.shlex(..., commenters=#) reader -- swallowing the write statement that followed
  # into the same comment window. Confirmed against real bash first (bash -x): the write
  # executes for real, right after the comment line. Confirmed live against the unfixed
  # gate: rc=0, no output -- a silent allow, WORSE than pre-#124, which at least denied.
  "backslash before a comment-terminating newline (post-#124 regression)|$(printf 'echo hello #comment \\\ncp evil.sh hooks/gates/irrecoverable.sh')|ask"
  # Same class, PRE-EXISTING (older than GH #124): TWO backslashes before a
  # comment-terminating newline. Backslash count is irrelevant inside a comment (no
  # escape processing happens there at all), but the regex only matches the LAST
  # backslash + newline as one pair and erases it anyway, again eating the separator.
  "two backslashes before a comment-terminating newline (pre-existing windowing gap)|$(printf 'echo hello #comment \\\\\ncp evil.sh hooks/gates/irrecoverable.sh')|ask"
  # ANSI-C escaped-internal-quote regression (fresh-context re-verification, 2026-09-03):
  # _normalize_ansi_c_quotes() used to copy the raw $'...' escape sequence verbatim and
  # slap plain quotes around it, producing an unbalanced 'a\'b' for $'a\'b' -- which threw
  # _newlines_to_seps' own quote-tracking scanner into a permanent in_squote state, eating
  # the write statement below with zero separator inserted. Confirmed against real bash
  # first (bash -x and a real cp): $'a\'b' evaluates to the 3-char string a'b, IDENTICAL to
  # the bash splice idiom 'a'\''b' (single quotes have no escape mechanism, so a literal
  # quote can only be spliced in this way). Confirmed live against the unfixed gate: rc=0,
  # no output -- a silent allow. Fixed by decoding the escaped quote into that splice idiom.
  "ANSI-C escaped internal quote, write after (fresh-context re-verification)|$(printf 'echo $%sa\\%sb%s\ncp evil.sh hooks/gates/irrecoverable.sh' "'" "'" "'")|ask"
  # Companion: a plain $'...' with NO escaped quote, write on the next line, must keep
  # behaving exactly as before the fix (guards against overcorrection breaking the common,
  # already-working case).
  "plain ANSI-C quote with no escaped quote, write after|$(printf 'echo $%splain text%s\ncp evil.sh hooks/gates/irrecoverable.sh' "'" "'")|ask"
  # Primary use case: the escaped quote sits INSIDE the write TARGET itself, resolving into
  # a verifier path -- $'hooks/gates/we\'ird.sh' decodes to the literal filename
  # hooks/gates/we'ird.sh, same as real bash.
  "ANSI-C escaped quote inside the write target itself|$(printf 'cp evil.sh $%shooks/gates/we\\%sird.sh%s' "'" "'" "'")|ask"
  # GH #125 (2026-09-03): the BASH-LEVEL fast-path pre-filter (lines ~85-108,
  # NOT the python _newlines_to_seps above) has its own cruder normalization:
  # the sed backslash-nt substitution matches only the LAST backslash immediately before a
  # JSON-encoded "\n", so a real 1-backslash continuation survives as a
  # residual space (e.g. "hoo\<nl>ks/gates/x.sh" -> "hoo ks/gates/x.sh"),
  # which no longer contains the contiguous substring "hooks/gates" -- the
  # fast path then concludes _run=0 (allow) and exits 0 BEFORE python ever
  # runs, even though real bash fully removes a 1-backslash continuation and
  # actually writes hooks/gates/irrecoverable.sh. Ground-truthed against real
  # bash first (bash -x): the write executes for real. Fixed by deferring
  # ANY raw-input backslash to python unconditionally, rather than
  # reimplementing bash own parity-sensitive continuation rule inside this
  # already twice-self-locked-out fast path.
  "1-backslash continuation splits hooks/gates (GH #125 bypass)|$(printf 'echo x > hoo\\\nks/gates/irrecoverable.sh')|ask"
  # Parity companion: 2 backslashes before the newline means the FIRST
  # backslash escapes the SECOND (one literal backslash char), and the
  # newline that follows is then a real, unescaped statement-ending newline
  # -- NOT a continuation. Ground-truthed against real bash in an isolated
  # scratch dir: this writes "x" into a harmless file literally named
  # "hoo\", then tries (and fails) to run "ks/gates/irrecoverable.sh" as a
  # command -- hooks/gates/irrecoverable.sh is never touched. Must stay
  # noask so the fix does not overcorrect into asking on every backslash
  # occurrence regardless of what real bash would do with it.
  "2-backslash non-continuation before newline (parity companion)|$(printf 'echo x > hoo\\\\\nks/gates/irrecoverable.sh')|noask"
  # Same bypass shape against a different protected substring (hooks/advisory).
  "1-backslash continuation splits hooks/advisory|$(printf 'echo x > hoo\\\nks/advisory/evil10.py')|ask"
  # Same bypass shape against hooks/hooks.json.
  "1-backslash continuation splits hooks/hooks.json (via hoo/ks split)|$(printf 'echo x > hoo\\\nks/hooks.json')|ask"
  # Continuation at the very start of the command, unrelated to the write
  # target itself -- confirms ANY raw backslash defers to python, not just
  # one that happens to sit inside the protected substring.
  "continuation at the very start of the command|$(printf '\\\necho x > hooks/gates/evil11.sh')|ask"
  # Continuation immediately before the redirect operator -- real bash joins
  # "echo x" and "> hooks/gates/evil12.sh" with nothing between them (">" is
  # a metacharacter token boundary regardless of adjacent whitespace).
  "continuation immediately before the redirect operator|$(printf 'echo x\\\n> hooks/gates/evil12.sh')|ask"
)

for row in "${BATTERY[@]}"; do
  desc="${row%%|*}"
  rest="${row#*|}"
  cmd="${rest%|*}"
  expect="${rest##*|}"
  out=$(payload_bash "$cmd" | TARGETDIR="$ROOT/hooks/gates" HOME="$ROOT/hooks/gates" bash "$GUARD" 2>/dev/null)
  got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
  ok=1
  if [ "$expect" = "ask" ] && [ "$got_ask" -eq 0 ]; then ok=0; fi
  if [ "$expect" = "noask" ] && [ "$got_ask" -eq 1 ]; then ok=0; fi
  check "battery: $desc" "$ok"
done

# Round-4 regression tests (found 2026-08-04 by a subagent_type:kbg:silent-failure-hunter
# dispatch covering both worktree-guard.py and verifier-protect.sh together -- a different
# idiom family than the same-day preprocessing fixes above: git apply/am and patch never
# scanned diff CONTENT for the real +++ b/<path> target, and bare tar extraction (no -C)
# yielded no candidate at all. All 3 were already disclosed as deferred follow-ups in this
# repo's own v0.68.171 CHANGELOG entry; closed here as their own scoped piece of work.
DIFF_FILE="${TMPDIR:-/tmp}/kbg-vp-round4-evil.diff"
printf -- '--- a/hooks/gates/irrecoverable.sh\n+++ b/hooks/gates/irrecoverable.sh\n@@ -1,1 +1,1 @@\n-x\n+evil\n' > "$DIFF_FILE"
BENIGN_DIFF="${TMPDIR:-/tmp}/kbg-vp-round4-benign.diff"
printf -- '--- a/README.md\n+++ b/README.md\n@@ -1,1 +1,1 @@\n-x\n+y\n' > "$BENIGN_DIFF"

out=$(payload_bash "git apply $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "git apply: real target lives in diff content, not argv -> ask" "$ok"

out=$(payload_bash "git apply $BENIGN_DIFF" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "git apply against a diff touching nothing protected -> exit 0, no false ask" "$ok"

# -C relocates where a relative in-diff target resolves. The first version of this fix
# dispatched into apply/am correctly for -C but still resolved the diff's relative target
# against the hook's own cwd -- confirmed the hard way while building this round's fix.
out=$(payload_bash "git -C $ROOT apply $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "git -C <dir> apply: -C resolves the diff target, not the hook's own cwd -> ask" "$ok"

out=$(payload_bash "patch -p1 < $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "patch, stdin-piped: real target lives in diff content, not argv -> ask" "$ok"

out=$(payload_bash "patch --directory=$ROOT -p1 < $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "patch --directory=: real target resolves against it, not bare cwd -> ask" "$ok"

out=$( (cd "$ROOT/hooks/gates" && payload_bash "tar xf archive.tar" | bash "$GUARD") 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "tar xf, no -C, cwd itself is inside hooks/gates -> ask" "$ok"

out=$(payload_bash "tar xf archive.tar" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "tar xf, no -C, cwd is repo root (documented residual gap, not a regression) -> exit 0" "$ok"

# Round-5 (2026-08-06): the heredoc-stripping fix ported into irrecoverable.sh
# for a false-positive it caused there uncovered the same unconditional strip
# already present in this gate -- with it disabled entirely, a write hidden
# inside a heredoc fed to an interpreter (bash <<EOF, python3 <<EOF) reached
# bash_write_targets and was correctly caught, proving the strip itself is
# what hides the write, not a gap in bash_write_targets. Reproduced live
# against the unmodified gate before writing the fix (a real Bash write to a
# protected path silently resolved to a clean allow). Fixed by skipping the
# strip when the heredoc feeds a known interpreter -- same predicate as
# irrecoverable.sh, paired here with a negative case so an interpreter
# heredoc with no write inside does not start over-asking.
out=$(payload_bash $'bash <<EOF\necho x > hooks/gates/evil7.sh\nEOF' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "write hidden inside a heredoc fed to bash is no longer a silent bypass" "$ok"

out=$(payload_bash $'python3 <<EOF\nprint(1)\nEOF' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "interpreter heredoc with no write inside does not over-ask" "$ok"

# path-hardcode block still wins over ask (folded gate, pre-existing, sanity only).
# Built via concatenation, not a literal contiguous string, so this test file itself
# does not trip the very gate it is testing when this test file is written/edited.
hardcoded_snippet="path=/Us""ers/someone/x"
out=$(payload_write "hooks/gates/newfile.sh" "$hardcoded_snippet" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 2 ] && ok=0
check "hardcoded /Users/ path in .sh content -> block exit 2 (wins over ask)" "$ok"

# GH #125 fast-path sanity: a plainly-benign command with no backslash and no
# write idiom/verifier substring at all must still be caught by the fast path
# itself (exit 0, no output) -- the fix must not force every command through
# python3, only ones containing a raw backslash.
out=$(payload_bash "ls -la" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "plain benign command, no backslash, no write idiom -> exit 0, no output (fast path still works)" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
