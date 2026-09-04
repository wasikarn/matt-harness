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

# GH #128/#130 proof helper: forcing a marker-spliced command through to
# python3 does NOT, by itself, make python3 correctly resolve the splice and
# ask -- confirmed by direct testing: python3's own shlex tokenizer
# (bash_write_targets, punctuation_chars=True) fragments a spliced
# argv0/redirect-target exactly like the bash fast path did, so is_gate_path()
# never sees a reconstructed "hooks/gates" substring and the final
# classification still concludes a silent allow even after this fix. That
# deeper "python3's own tokenizer resolution of command substitution" gap is
# GH #129 -- confirmed here to also affect verifier-protect.sh, not just
# irrecoverable.sh where it was first found -- and stays explicitly out of
# scope for #128/#130 (same scope line already drawn in irrecoverable.sh's own
# sibling fix, commit 9749a43b same day). What #128/#130 DO close is the fast
# path's own premature short-circuit: before the fix, a marker-spliced command
# never reached even the python3-availability guard; after the fix, it does. A
# bare rc=0 cannot tell these two apart (both print nothing with python3
# present), so this proves it the same way tests/hooks/test-gates.sh's
# test_nopython_allow already does for irrecoverable.sh's identical sibling
# case: strip python3 off PATH (keep only bash/cat/sed/tr, which is all this
# gate's own fast path shells out to) and assert the announced "python3 not
# found" fail-open note fires -- which can only happen if the fast path
# deferred past its own allow and reached that guard. /bin/cat resolved
# directly (not via `command -v`) because this shell has `alias cat=bat`,
# which `command -v` reports as the alias text, not a path.
NOPY_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-vp-nopy.XXXXXX")
ln -s /bin/cat "$NOPY_BIN/cat"
ln -s /bin/bash "$NOPY_BIN/bash"
ln -s /usr/bin/sed "$NOPY_BIN/sed"
ln -s /usr/bin/tr "$NOPY_BIN/tr"

check_reaches_pyguard() { # check_reaches_pyguard <desc> <command> <expect:reach|noreach>
  local desc="$1" cmd="$2" expect="$3" rc errf
  errf=$(mktemp "${TMPDIR:-/tmp}/kbg-vp-nopy-err.XXXXXX")
  rc=$(payload_bash "$cmd" | PATH="$NOPY_BIN" bash "$GUARD" 2>"$errf"; echo $?)
  local reached=1
  [ "$rc" = "0" ] && /usr/bin/grep -q 'python3 not found' "$errf" && reached=0
  local ok=1
  if [ "$expect" = "reach" ] && [ "$reached" -eq 0 ]; then ok=0; fi
  if [ "$expect" = "noreach" ] && [ "$reached" -eq 1 ]; then ok=0; fi
  check "$desc" "$ok"
  rm -f "$errf"
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
  # GH #127 (2026-09-03): the protected-path case-statement match never
  # lowercased $_norm before matching, unlike this file's own header comment
  # (macOS/APFS is case-insensitive but case-preserving) and the python-side
  # is_gate_path()'s case-insensitive comparison. hooks/GATES/ resolves to the
  # IDENTICAL real directory as hooks/gates/ on this filesystem (confirmed via
  # `ls -ld` first), but the case-sensitive glob *hooks/gates* never matched
  # the differently-cased spelling -- falling through to a silent fast-allow.
  # Ground-truthed against real bash first: the write lands in the real
  # protected directory either way.
  "differently-cased protected path (GH #127 bypass)|echo x > hooks/GATES/probe127.sh|ask"
  # Parity companion: an unrelated differently-cased word, targeting a
  # NON-protected path, must not start over-asking just because lowercasing
  # was added -- lowering only widens the match against the tracked protected
  # substrings, it must not turn every uppercase letter into a false ask.
  "differently-cased word, non-protected target (parity companion)|echo x > /tmp/GATES/probe127b.sh|noask"
  # Missing-operator gap (2026-09-03): this generator own SEPS window-split
  # set never included ( ) { } grouping/brace-group operators -- unlike its
  # two already-fixed siblings irrecoverable.sh (line ~276) and
  # merge-door.sh (line ~129), which both carry
  # OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}. shlex with
  # punctuation_chars=True already tokenizes a bare ( ) { } as its own
  # token (confirmed by direct testing), but without them in SEPS the
  # window is never split there -- so "(cp evil.sh hooks/gates/x.sh)"
  # yields ONE window ["(", "cp", "evil.sh", "hooks/gates/x.sh", ")"] whose
  # argv0 is the literal "(", never "cp" -- the write-command dispatch for
  # cp/mv/install never fires and the write silently allows. Confirmed live
  # against the unfixed gate before writing this test. Same shape for a
  # brace group ("{ ...; }").
  "grouped command (parens) hides argv0 from cp dispatch|(cp evil.sh hooks/gates/x.sh)|ask"
  "brace-group command hides argv0 from cp dispatch|{ cp evil.sh hooks/gates/x.sh; }|ask"
  # Negative control: a literal ( inside a QUOTED argument (this repo's own
  # commit-message convention, e.g. fix(gates): ...) is not a grouping
  # operator at all -- shlex keeps the whole quoted span as ONE token
  # (confirmed by direct testing), so adding ( ) { } to SEPS must not start
  # misreading this as a subshell boundary.
  "quoted literal paren in a commit message, not a grouping op|git commit -m \"fix(gates): update x\"|noask"
  # Discriminating companion to the row above: on its own, a quoted-paren
  # command yields zero write targets regardless of whether the quoted (
  # fragments correctly, so it would stay noask even against a broken
  # SEPS/tokenizer that mis-split the quoted span (a vacuous check). Chaining
  # a real protected write after it makes this row actually earn the
  # "not misread as a grouping boundary" claim: if the quoted ( ever DID
  # spuriously start a new window, it would orphan the following cp window
  # and this would go noask instead.
  "quoted literal paren, then a real protected write chained after|git commit -m \"fix(gates): update x\" && cp evil.sh hooks/gates/y.sh|ask"
  # Independent-reviewer finding (2026-09-03): a command substitution that
  # resolves EMPTY at runtime (e.g. $(true)) glues onto the very next flag in
  # real bash ("cp $(true)-t DIR file" IS "cp -t DIR file"), but
  # _blank_substitutions above replaces it with a non-empty PH byte instead of
  # nothing, so the resulting token (PH + "-t"/"-i") never matches a raw
  # startswith("-") flag test below. Confirmed live before this fix: all
  # three rows silently allowed (rc=0, no output) -- the cp/mv/install -t
  # detection fell through to nonflag[-1] (wrong target), and the sed/perl -i
  # detection never entered its yield loop at all (zero targets).
  "PH-prefixed -t flag on cp, GH review 2026-09-03|cp \$(true)-t hooks/gates/ evil.sh|ask"
  "PH-prefixed -i flag on sed, GH review 2026-09-03|sed \$(true)-i s/a/b/ hooks/gates/x.sh|ask"
  "PH-prefixed -i flag on perl, GH review 2026-09-03|perl \$(true)-i -pe s/a/b/ hooks/gates/x.sh|ask"
  # Parity companion: an ORDINARY (non-spliced) -t flag pointing at a
  # non-protected directory must stay allowed -- the fix must only change
  # behavior for a PH-prefixed token, never widen an already-correct ordinary
  # flag parse.
  "ordinary -t flag, non-protected target, parity companion|cp evil.sh -t /tmp/harmless_dir|noask"
  # Adversarial-review follow-up (2026-09-03): the leading-PH fix above
  # covered cp/mv/install/sed/perl but not dd or tar, both of which read
  # their flags with the identical unstripped startswith/exact-match shape.
  "PH-prefixed of= flag on dd targets a verifier path, was silently allowed|dd if=/dev/zero \$(true)of=hooks/gates/probevp1.sh bs=1 count=1|ask"
  "baseline: plain dd of= to a verifier path, no splice (must still ask)|dd if=/dev/zero of=hooks/gates/probevp1.sh bs=1 count=1|ask"
  "PH-prefixed -C flag on tar falls through to the . fallback, losing the real target, was silently allowed|tar -xf evil.tar \$(true)-C hooks/gates/|ask"
  "baseline: plain tar -C to a verifier path, no splice (must still ask)|tar -xf evil.tar -C hooks/gates/|ask"
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

# Adversarial-review follow-up (2026-09-03): rest[0] == "-C" and
# rest[sub_idx] in ("apply","am") above were both an exact/unstripped
# check, unlike the already-fixed cp/mv/install -t detection. A PH-glued -C
# falls through to sub_idx=0, and rest[0] no longer equals "apply"/"am"
# either -- the whole branch is skipped, not just the wrong directory.
out=$(payload_bash "git \$(true)-C $ROOT apply $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "PH-glued -C on git apply, was silently allowed (Layer 2) -> ask" "$ok"

# Layer 3: a standalone (not glued) vanish token between "git" and "-C"
# shifts rest[0] out of the "-C" position the exact same way real bash
# word-splitting would shift it, but the PH-only token stays in place here
# instead of vanishing -- so rest[0] is the PH token, never "-C", and the
# whole apply/am branch never fires. Confirmed exploitable before this fix:
# rc=0, no output at all.
out=$(payload_bash "git \$(true) -C $ROOT apply $DIFF_FILE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Layer 3: standalone vanish shifts -C out of position on git apply, was silently allowed -> ask" "$ok"

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

# GH #128 (2026-09-03): a backtick command substitution vanishes in real bash
# with zero width ("echo x > hoo`true`ks/gates/probe128.sh" evaluates to a
# target of hooks/gates/probe128.sh, ground-truthed via `bash -x` first) but
# survives here as literal characters, splicing the protected-path substring
# apart so the case-statement match at the (fixed) inner check never sees a
# contiguous "hooks/gates". See check_reaches_pyguard's own comment above for
# why this asserts "reached the python3-availability guard" rather than "ask"
# -- python3's own tokenizer has the identical splicing blindness (confirmed
# by direct testing of bash_write_targets), so forcing through to python3
# closes only the fast path's own premature short-circuit, not the full
# bypass end-to-end (that deeper piece is GH #129, explicitly out of scope).
check_reaches_pyguard "backtick splicing defeats protected-path check (GH #128 bypass) -> no longer fast-path-exited" \
  "$(printf 'echo x > hoo`true`ks/gates/probe128.sh')" "reach"

# GH #130 (2026-09-03): the SEPARATE outer write-command-NAME dispatch
# (*tee*|*sed*|*cp*|...) has the identical splicing weakness, via a different
# marker: "c$(true)p evil.sh hooks/gates/x.sh" evaluates in real bash to
# "cp evil.sh hooks/gates/x.sh" (ground-truthed via `bash -x` first), but the
# literal string never contains a contiguous "cp" for the outer dispatch to
# match. Same residual-gap caveat as GH #128 above.
check_reaches_pyguard "\$(...) splicing defeats write-command-name dispatch (GH #130 bypass) -> no longer fast-path-exited" \
  "$(printf 'c$(true)p evil130.sh hooks/gates/x.sh')" "reach"

# Controls: a plainly benign command, and a benign write to a non-protected
# target, must both keep being caught by the fast path itself (never reach
# the python3-availability guard) -- the new _has_subst guard must not force
# EVERY command through python3, only ones actually carrying a splicing
# marker.
check_reaches_pyguard "plain benign command, no splicing marker -> still fast-path-exited" \
  "ls -la" "noreach"
check_reaches_pyguard "benign write to a non-protected target, no splicing marker -> still fast-path-exited" \
  "cp a.sh /tmp/somewhere/b.sh" "noreach"

# Fresh-context review finding (2026-09-03): $@ and $* are a 5th zero-width
# splicer the 4-marker enumeration above (backtick, $(, ${, $') never covered
# -- with zero positional parameters (real in a hook-script invocation
# context), both expand to nothing, so "c$@p evil.sh hooks/gates/xgap.sh"
# vanishes in real bash into "cp evil.sh hooks/gates/xgap.sh" (ground-truthed
# via `bash -x` first: `+ cp evil.sh hooks/gates/xgap.sh`) but survives here
# as literal characters, splicing the write-command-NAME dispatch apart --
# same GH #130 shape, one marker spelling short. Confirmed live before this
# fix: fast-path-exited (rc=0, no note), never reaching the python3-
# availability guard. This motivated replacing the whole enumeration with a
# single "any bare $ or backtick" guard rather than adding a 5th/6th marker.
check_reaches_pyguard "\$@ splicing defeats write-command-name dispatch (zero-positional-params bypass) -> no longer fast-path-exited" \
  "$(printf 'c$@p evil.sh hooks/gates/xgap.sh')" "reach"
check_reaches_pyguard "\$* splicing defeats write-command-name dispatch (zero-positional-params bypass) -> no longer fast-path-exited" \
  "$(printf 'c$*p evil.sh hooks/gates/xgap2.sh')" "reach"

# Step 7 benign-marker battery: each of the 4 splicing marker spellings, used
# in a totally ordinary way with NO write idiom and NO protected-path target
# anywhere in the command, must still resolve to a clean allow once routed
# through python3 (not merely "reach the guard" -- these carry no write op at
# all, so python3's own tokenizer quirks never come into play; this is a
# false-positive check on the new _has_subst guard itself, not on GH #129).
out=$(payload_bash "$(printf 'echo `date`')" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "benign backtick substitution, no write target -> exit 0, no output" "$ok"

out=$(payload_bash "$(printf 'echo $(date)')" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "benign \$(...) substitution, no write target -> exit 0, no output" "$ok"

out=$(payload_bash "$(printf 'echo ${HOME}')" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "benign \${...} expansion, no write target -> exit 0, no output" "$ok"

out=$(payload_bash "$(printf "echo \$'hello'")" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "benign \$'...' ANSI-C quoting, no write target -> exit 0, no output" "$ok"

# Deep ANSI-C decode gap (2026-09-03, same session as the irrecoverable.sh
# fix for the identical root cause): this generator's own
# _normalize_ansi_c_quotes only fixed token BOUNDARIES ($'...' -> '...',
# escapes left raw) -- enough for the redirect/target scanning this file
# does elsewhere, but NOT for the exact-string argv0 dispatch above (argv0
# == "tee", argv0 in ("rm","trash"), ("sed","perl"), ("cp","mv","install"),
# argv0 == "rsync"/"tar"/"patch"/"git"/"dd"). "c$'\x70' evil.sh
# hooks/gates/x.sh" re-quotes (boundary-only) to "c'\x70' evil.sh ...",
# which shlex glues into the literal argv0 "c\x70" (raw backslash-x-7-0),
# never equal to "cp". Confirmed live before this fix: bash_write_targets()
# yields zero candidates -- a silent allow on a real cp write to a verifier
# path. Fixed by porting the escape-RESOLVING _normalize_ansi_c_quotes from
# irrecoverable.sh (same root cause, fixed there first the same session)
# rather than re-deriving the decode logic here.
out=$(payload_bash "c\$'\\x70' evil.sh hooks/gates/x.sh" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "ANSI-C hex-escape-glued argv0 (c\$'\\x70' resolves to cp) writes to hooks/gates -> ask" "$ok"

# Negative control: an ordinary single-quoted argument with no \$'...' form
# at all never enters the ANSI-C regex -- must stay correctly classified
# (no write target here at all -- git commit alone), not misclassified as
# some ANSI-C construct by the deeper decode logic.
out=$(payload_bash "git commit -m 'a normal message'" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "ordinary single-quoted commit message unaffected by ANSI-C normalization (negative control)" "$ok"

# Real decode-path exercise (port of test-gates.sh's equivalent control for
# irrecoverable.sh's own sibling fix): a genuine \$'...' payload with an
# embedded \n escape that DOES enter the new decode path. The decoded
# newline must stay INSIDE the returned quoted span (SQ...SQ), or
# _newlines_to_seps below would read it as a real statement separator and
# corrupt quote-balance tracking for the write on the next line, either
# hiding it (silent allow) or misparsing everything after.
out=$(payload_bash "$(printf 'echo $%sline1\\nline2%s\ncp evil.sh hooks/gates/x2.sh' "'" "'")" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "ANSI-C embedded \\n decode stays inside quoted span, real write on next line still ask (decode-path exercise)" "$ok"

# GH #129 (2026-09-03): ported from irrecoverable.sh -- python3's own shlex
# tokenizer does not resolve a command-substitution splice either (the
# check_reaches_pyguard rows above only proved the fast path stops
# short-circuiting; they never asserted python3 then classifies correctly).
# A blanked-to-placeholder splice at argv0 must be duplicate-checked against
# every write-verb this generator dispatches on, and a target token that
# still carries the placeholder must be treated as a possible protected path.
out=$(payload_bash "$(printf 'c$(true)p evil.sh hooks/gates/x.sh')" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "GH #129: argv0 splice (c\$(true)p -> cp) targeting a protected path -> ask" "$ok"

out=$(payload_bash 'cp evil.sh hooks/g${x}ates/x.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "GH #129: target-path splice via \${x} (unknown var) -> ask (placeholder-bearing target treated as possibly protected)" "$ok"

out=$(payload_bash "$(printf '$(which cp) evil.sh /tmp/harmless.txt')" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "GH #129 negative control: argv0 splice resolving to a benign non-protected op -> allow (no over-deny from duplication)" "$ok"

out=$(payload_bash "$(printf 'echo "it%ss" ; c$(true)p evil.sh hooks/gates/x.sh' "'")" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "GH #129: English contraction adjacent to a real splice does not mask it -> ask" "$ok"

# GH #139 (2026-09-04): the $(...)/${...} closer-search used to scan forward
# for the FIRST "(" or ")" byte and treat that as the terminator -- not
# depth-aware, so a paren nested INSIDE the span (a function definition)
# aborted the match early, leaving the true end of the span un-blanked.
# "c$(f() { :; }; f)p evil.sh hooks/gates/x.sh" really runs as
# "cp evil.sh hooks/gates/x.sh" (the function body is a no-op, so the
# substitution resolves to empty), but pre-fix the un-blanked "(", ")",
# "{", "}" bytes fragment the shlex tokenization so no window's argv0 ever
# reads "cp" -- confirmed live: allow (no ask) before this fix. Fixed by
# depth-counting same-type brackets in the closer-search (same technique
# irrecoverable.sh sibling GH #139 fix and main-exec-guard.sh own
# _inner_cmds already use).
out=$(payload_bash "$(printf 'c$(f() { :; }; f)p evil.sh hooks/gates/x.sh')" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "GH #139: nested function-construct inside \$(...) defeats the old first-byte closer-search, real bash resolves to cp targeting a protected path -> ask" "$ok"

# Companion DoS check: depth-counting a closer-search that never balances
# (an adversarial flood of unclosed "$(" starts) must stay bounded by a
# work budget instead of costing O(remaining length) PER start -- O(n^2)
# total (same fix/rationale as irrecoverable.sh, GH #139). Budget exhaustion
# alone is NOT safe to read as "no protected-path target found, allow": that
# fallback path leaves the span un-blanked, the exact bypass shape GH #139
# closed, so an adversary could pad a real dangerous command with just
# enough flood to burn the budget and hide the payload again. Fixed by a
# _DEPTH_BUDGET_BLOWN flag that raises, routing to this file's existing
# top-level except Exception: emit_ask -- so this must complete fast AND ask.
depth_flood_cmd=$(python3 -c 'print("$(" * 50000)')
depth_flood_start=$(date +%s)
depth_flood_out=$(payload_bash "$depth_flood_cmd" | timeout 10 bash "$GUARD" 2>/dev/null); depth_flood_rc=$?
depth_flood_elapsed=$(( $(date +%s) - depth_flood_start ))
ok=1
if [ "$depth_flood_rc" -eq 0 ] && echo "$depth_flood_out" | /usr/bin/grep -q '"permissionDecision": "ask"' && [ "$depth_flood_elapsed" -le 10 ]; then ok=0; fi
check "GH #139: 50,000x unclosed \"\$(\" flood completes within a generous ceiling and asks (fail-closed budget-exhaustion fix)" "$ok"

# 5-finding fix round (2026-09-04): comment-truncation join, quote-boundary
# shlex ValueError containment, comment-state tracking in the substitution
# scanner, tar mode_str/has_extract PH parity, patch -d/--directory parity.

# Finding 1 (comment-truncation silent bypass): the old
# `cmd + " ; " + " ; ".join(bodies)` join let a hash earlier in the string
# (including one inside an EARLIER recovered body) start a shlex comment
# that silently swallowed everything appended after it. Fixed by leading
# each appended body with a real newline instead of a plain " ; ".
out=$(payload_bash 'echo $(cp evil.sh hooks/gates/x2f1.sh)  # copy' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding 1: a trailing comment after a recovered body no longer swallows it -> ask" "$ok"

out=$(payload_bash 'echo $(: #x) $(cp evil.sh hooks/gates/y1.sh)' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding 1: a hash embedded INSIDE an earlier recovered body does not swallow a later one -> ask" "$ok"

# Finding 4 (quote-boundary-crossing span match): the ${...}/$(...)/backtick
# closer-search in _blank_substitutions scans forward without tracking quote
# state for characters it skips over. A span crossing a real quote (common
# in an interpreter heredoc embedding a JSON/Python literal with a stray
# ${, which _strip_heredocs deliberately never strips) can desync quote
# tracking and leave the blanked string unbalanced even though the ORIGINAL
# command was valid -- shlex.shlex(...) then raised ValueError, turning a
# benign command into a hard ask. Fixed by falling back to a separator-aware
# split of the ORIGINAL (pre-blanking) command when it alone parses cleanly.
F4CMD=$(printf 'python3 - <<PY\nd = {"10k unmatched ${ (20KB)": "${ "*10000,\n}\nprint(d)\nPY')
out=$(payload_bash "$F4CMD" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 4: \${ span crossing a real quote in a benign heredoc no longer hard-fails -> exit 0, no output" "$ok"

# A genuinely malformed command (unbalanced before blanking too) must still
# get this file's existing fail-safe ask -- the fix must distinguish
# self-inflicted corruption from real malformation, not blanket-suppress it.
out=$(payload_bash 'echo "genuinely unbalanced' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding 4: a genuinely malformed command (unbalanced before blanking too) still gets the fail-safe ask" "$ok"

# Reviewer follow-up (2026-09-04): a naive whitespace .split() fallback is
# itself exploitable -- it glues a compound command into one token stream
# with no separator awareness, so a real write placed AFTER a ; (or
# &&/||/&), glued tight against it with no surrounding whitespace, never
# surfaces as its own window and its argv0 never gets checked at all.
# Confirmed live against the naive-split version of this fix before
# correcting it: rc=0, no output -- a silent allow, worse than the ask this
# whole branch exists to give instead. Fixed by splitting on the same
# separators the window-builder recognizes (finding ";" etc. regardless of
# adjacent whitespace, unlike .split()) before naive-word-splitting each
# plain segment in between.
out=$(payload_bash 'echo ${y:-"a}b"};cp evil.sh hooks/gates/probe4c.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding 4: a real write glued tight after a separator, following a quote-corrupting span, is not lost by the fallback -> ask" "$ok"

# Reviewer follow-up #2 (2026-09-04): the Finding-4 fallback tokenizes the
# ORIGINAL, never-blanked command string, so a spliced dispatch token
# reaching that path still carries its literal substitution syntax (e.g.
# "c$(true)p") -- it never contains the PH placeholder byte. The GH #129
# splice-duplication trigger is gated purely on "PH in argv0", so it never
# fired on this path and a spliced argv0 sailed through unrecognized.
# Confirmed live before the _has_raw_subst fix: rc=0, no output -- a silent
# allow. Fixed by widening the duplication trigger to also catch a token
# still carrying raw backtick/$(/${syntax (a narrow, ONE-TOKEN check, not a
# bare "$" scan -- that would misfire on an ordinary $VAR-shaped token).
# This combined "quote-crossing span forces the fallback + a splice in the
# fallback's own output" cell was never in this suite before, which is
# exactly why it shipped.
out=$(payload_bash 'echo ${y:-"a}b"} ; c$(true)p evil.sh hooks/gates/x.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding 4: a spliced argv0 (c\$(true)p) surviving into the fallback path is still duplicate-checked -> ask" "$ok"

# Same shape, dangerous command BEFORE the quote-crossing span instead of
# after -- the fix must not be positionally lucky.
out=$(payload_bash 'c$(true)p evil.sh hooks/gates/x2.sh ; echo ${y:-"a}b"}' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding 4: a spliced argv0 BEFORE the quote-crossing span is still duplicate-checked -> ask" "$ok"

# Negative controls: the widened trigger must not start over-asking on
# ordinary command substitutions that resolve to a harmless op or target.
out=$(payload_bash '$(which git) status' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 4 negative control: \$(which git) status -> exit 0, no output" "$ok"

out=$(payload_bash '$(command -v ls) -la' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 4 negative control: \$(command -v ls) -la -> exit 0, no output" "$ok"

out=$(payload_bash 'c$(true)p /tmp/a /tmp/b' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 4 negative control: spliced cp to a non-guarded path -> exit 0, no output" "$ok"

out=$(payload_bash 'ls $(pwd)' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 4 negative control: ls \$(pwd) -> exit 0, no output" "$ok"

out=$(payload_bash 'echo "$HOME/x"' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 4 negative control: bare \$VAR (no raw substitution syntax) does not trigger the widened check -> exit 0, no output" "$ok"

# Finding 5 (comment-state not tracked in the substitution scanner): the
# inner scanner tracked quote state but not comment state, so a
# substitution-shaped string sitting inside a real hash comment still got
# matched and its body collected as a live command, raising a false ask on
# an innocent command.
out=$(payload_bash "$(printf 'cp a.sh b.sh # see also: $(cp evil.sh hooks/gates/z1.sh)\necho done')" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 5: a substitution-shaped string inside a real comment is not matched as a live command -> exit 0, no output" "$ok"

# Finding 9 (tar mode_str/has_extract missing .lstrip(PH)): not exploitable
# as a silent allow today (a PH byte does not remove the "x" the loose
# containment check looks for), but a PH-disguised LONG flag whose name
# happens to contain "x" for reasons unrelated to extraction (e.g.
# --exclude) was incorrectly treated as an extract-mode indicator by the
# unstripped rest[0]/mode_str read, producing a false ask on an ordinary
# tar CREATE run from inside a protected directory.
out=$( (cd "$ROOT/hooks/gates" && payload_bash 'tar $(true)--exclude=foo -cf archive.tar somedir' | bash "$GUARD") 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 9: PH-disguised --exclude long flag no longer misread as extract mode -> exit 0, no output" "$ok"

# Finding 10 (patch branch missing -d/--directory): the patch branch had
# -o/--output but no -d/--directory relocation, unlike worktree-guard.py's
# structurally identical branch. A diff whose own +++ b/<path> target
# carries no protected-path substring at all was silently allowed even when
# --directory= relocates it into one.
DIFF10="${TMPDIR:-/tmp}/kbg-vp-finding10.diff"
printf -- '--- a/newfile10.sh\n+++ b/newfile10.sh\n@@ -1,1 +1,1 @@\n-x\n+evil\n' > "$DIFF10"
out=$(payload_bash "patch --directory=hooks/gates -p1 < $DIFF10" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding 10: patch --directory= relocates an otherwise-unrecognizable diff target -> ask" "$ok"

out=$(payload_bash "patch --directory=/tmp/harmless_dir -p1 < $DIFF10" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Finding 10 negative control: --directory= pointing away from a protected surface -> exit 0, no output" "$ok"

# Finding A (2026-09-04 sweep): the final target-path check for cp/mv/
# install/etc ("PH in expanded or is_gate_path(expanded)") had the same
# PH-blindness as the argv0-duplication trigger -- a target token that
# reached here via the Finding-4 fallback with raw substitution syntax
# straddling the protected-path text (e.g. "hoo$(true)ks/gates/x.sh")
# carries no PH and no contiguous "hooks/gates" substring either, so
# neither disjunct fired. Confirmed live before the fix: rc=0, no output --
# a silent allow. Fixed by widening to "PH in expanded or
# _has_raw_subst(expanded) or is_gate_path(expanded)".
out=$(payload_bash 'echo ${y:-"a}b"} ; cp evil.sh hoo$(true)ks/gates/x.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Finding A: a raw-subst target path straddling the protected substring is still caught -> ask" "$ok"

# Systematic sweep (2026-09-04): a single safety-net loop over every token
# in each fallback-reached window now yields any token still carrying raw
# substitution syntax as its own candidate, closing 5 confirmed-live
# flag-detection gaps in one place (sed/perl -i, cp/mv/install -t, tar -C,
# git -C + apply/am, dd of=) instead of patching each site's PH-stripping
# logic individually. Each payload below was confirmed live (rc=0, no
# output) before the safety net; each must now ask.

out=$(payload_bash 'echo ${y:-"a}b"} ; sed $(true)-i -e s/x/y/ hooks/gates/z.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Safety net (a): sed with a raw-subst-disguised -i flag -> ask" "$ok"

out=$(payload_bash 'echo ${y:-"a}b"} ; cp $(true)-t hooks/gates/ evil.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Safety net (b): cp with a raw-subst-disguised -t flag -> ask" "$ok"

out=$(payload_bash 'echo ${y:-"a}b"} ; tar -xf archive.tar $(true)-C hooks/gates/' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Safety net (c): tar with a raw-subst-disguised -C flag -> ask" "$ok"

DIFFSAFE="${TMPDIR:-/tmp}/kbg-vp-safetynet-git.diff"
printf -- '--- a/irrecoverable.sh\n+++ b/irrecoverable.sh\n@@ -1,1 +1,1 @@\n-x\n+evil\n' > "$DIFFSAFE"
out=$(payload_bash "echo \${y:-\"a}b\"} ; git \$(true)-C /tmp apply $DIFFSAFE" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Safety net (d): git with a raw-subst-disguised -C flag ahead of apply -> ask" "$ok"

out=$(payload_bash 'echo ${y:-"a}b"} ; dd if=/dev/zero $(true)of=hooks/gates/probeX.sh bs=1' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Safety net (e): dd with a raw-subst-disguised of= flag -> ask" "$ok"

# Mid-flag PH splice (2026-09-04, cross-file review): a splice landing MID-
# flag (-$(true)i, -$(true)t), not just leading, survives primary-path
# blanking as a PH byte INSIDE the token (-PHi / -PHt). The prior fix only
# used t.lstrip(PH), which strips the left edge only, so a mid-flag splice
# left every flag-match check False -- for sed/perl this also failed the
# OUTER if-gate above the whole yield block, so the branch yielded NOTHING,
# a total silent bypass, not just one missed check. Confirmed live before
# this fix: both rc=0, no output.
out=$(payload_bash 'sed -$(true)i -e s/x/y/ hooks/gates/z.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Mid-flag splice: sed -\$(true)i (splice after the dash, before the letter) -> ask" "$ok"

out=$(payload_bash 'cp -$(true)t hooks/gates/ evil.sh' | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Mid-flag splice: cp -\$(true)t (real destination hooks/gates/ recovered, not nonflag[-1]) -> ask" "$ok"

out=$(payload_bash "git -\$(true)C hooks/gates apply ${TMPDIR:-/tmp}/kbg-vp-safetynet-git.diff" | bash "$GUARD" 2>/dev/null)
ok=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ok=0
check "Mid-flag splice: git -\$(true)C (outer gate above apply/am dispatch no longer fails closed) -> ask" "$ok"

# Negative controls: an ordinary, non-spliced flag must not start over-
# asking now that flag checks use .replace(PH, "") instead of .lstrip(PH).
out=$(payload_bash 'sed -i -e s/x/y/ /tmp/harmless.txt' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Mid-flag splice negative control: plain sed -i on a harmless path -> exit 0, no output" "$ok"

out=$(payload_bash 'cp -t /tmp/dest/ /tmp/src.txt' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Mid-flag splice negative control: plain cp -t to a harmless dir -> exit 0, no output" "$ok"

out=$(payload_bash 'dd if=/dev/zero of=/tmp/harmless.bin bs=1' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Mid-flag splice negative control: plain dd of= to a harmless path -> exit 0, no output" "$ok"

# Regression guard (2026-09-04): re-confirm the benign-heredoc case from the
# Finding 4 test above still allows after this round's widening -- this is
# the exact shape that broke once already this session (KNOWN_WRITE_VERBS
# gating, previous round) when a check got too broad.
out=$(payload_bash "$F4CMD" | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "Mid-flag splice regression guard: benign 10k-\${ python heredoc still allows -> exit 0, no output" "$ok"

# --- GH #140: unbounded shlex tokenize cost on an oversized raw command
# string inside bash_write_targets()'s shlex.shlex(..., punctuation_chars=True)
# call (and its shlex.split() ValueError fallback) -- no length cap anywhere
# upstream, cost superlinear in the length of a single long token. Measured
# live against this exact file (single token appended to a real redirect
# into hooks/gates/, python3 cold-start included): 100,000 chars ~0.23s,
# 150,000 ~0.37s, 200,000 ~0.55s, 250,000 ~0.71s, 300,000 ~0.92s -- a
# 700,000-char payload blows straight past a 2s timeout pre-fix (confirmed
# live: rc=124). timeout pattern copied from test-merge-door.sh's own DoS
# regression battery (commit 7b37691e).
LEN_PAD=$(python3 -c "print('A' * 700000)")

start=$(date +%s)
out=$(payload_bash "echo $LEN_PAD > hooks/gates/x.sh" | timeout 2 bash "$GUARD" 2>/dev/null)
rc=$?
elapsed=$(( $(date +%s) - start ))
ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ask=0
ok=1
if [ "$rc" -eq 0 ] && [ "$elapsed" -le 2 ] && [ "$ask" -eq 0 ]; then ok=0; fi
check "oversized single-token write to hooks/gates/ still asks within a strict 2s bound (GH #140 length cap)" "$ok"

# Direction-pinning: the same oversized padding forced through to python3
# (a stray backslash defers the fast-path exactly like GH #125's own
# continuation-parity guard, unrelated to this fix) but targeting a
# NON-protected path (/tmp/output.txt) must ALSO ask, fast -- proving the
# LENGTH CAP fired on size alone, not a real is_gate_path() match that just
# happened to still finish inside the timeout. A cap that fell through to
# "no candidate yielded, allow" on this path would wrongly resolve this one
# to a silent allow instead.
start=$(date +%s)
out=$(payload_bash "echo hi \\ $LEN_PAD > /tmp/output.txt" | timeout 2 bash "$GUARD" 2>/dev/null)
rc=$?
elapsed=$(( $(date +%s) - start ))
ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && ask=0
ok=1
if [ "$rc" -eq 0 ] && [ "$elapsed" -le 2 ] && [ "$ask" -eq 0 ]; then ok=0; fi
check "oversized padding, NON-protected target -> still asks fast (pins the cap, not a real path match, GH #140)" "$ok"

# Negative control: a realistic, modestly-sized legitimate command -- well
# under the cap -- must still resolve to a clean allow (exit 0, no output).
# Proves the cap does not false-positive on ordinary usage merely for being
# longer than trivial.
out=$(payload_bash 'echo "some normal medium length text describing output" > /tmp/output.txt' | bash "$GUARD" 2>/dev/null); rc=$?
ok=1; [ "$rc" -eq 0 ] && [ -z "$out" ] && ok=0
check "realistic modestly-sized command, well under the GH #140 length cap -> still allows" "$ok"

echo ""
echo "=== missing sibling .py (corrupted/partial plugin install; follow-up to #146) ==="
# GH #146 extracted this gate's embedded python3 -c block into a sibling
# verifier-protect.py, resolved via "$(dirname "$0")/verifier-protect.py". If
# that sibling is missing or unreadable, this gate's own documented contract
# (header comment: "exit 0 + ask JSON on internal error too -- fail-safe: an
# unparseable payload must never resolve to a silent allow on a
# tamper-resistance gate") must still hold: emit an ask JSON (exit 0), not a
# bare nonzero exit carrying a raw "python3: can't open file ..." message.
# Simulate by copying ONLY the .sh into an isolated scratch dir (never touch
# the real repo file) so $(dirname "$0") resolves to a directory with no
# verifier-protect.py sibling.
MISSPY_VP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kbg-misspy-vp.XXXXXX")
cp "$GUARD" "$MISSPY_VP_DIR/verifier-protect.sh"
_errf=$(mktemp "${TMPDIR:-/tmp}/kbg-misspy-vp-err.XXXXXX")
_out=$(payload_bash "cp evil.sh hooks/gates/evil.sh" | bash "$MISSPY_VP_DIR/verifier-protect.sh" 2>"$_errf")
_rc=$?
_ok=1
# Real JSON parse, not a substring grep -- a grep on the literal
# '"permissionDecision": "ask"' text would also pass on a typo'd sibling key
# (hookEventName, permissionDecisionReason) that Claude Code's hook-output
# parser would then fail to recognize, silently falling through to allow on
# a tamper-resistance gate -- exactly the fail-open this fix exists to avoid.
if [ "$_rc" -eq 0 ] \
   && echo "$_out" | python3 -c 'import json,sys
d=json.load(sys.stdin)["hookSpecificOutput"]
sys.exit(0 if d["hookEventName"] == "PreToolUse" and d["permissionDecision"] == "ask" and d["permissionDecisionReason"] else 1)' 2>/dev/null \
   && ! /usr/bin/grep -qi "can't open file\|Traceback" "$_errf"; then
  _ok=0
fi
check "missing sibling verifier-protect.py -> ask JSON (exit 0), no raw traceback" "$_ok"
rm -f "$_errf"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[ "$fail" -eq 0 ] && exit 0 || exit 1
