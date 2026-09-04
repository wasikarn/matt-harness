#!/usr/bin/env bash
# Behavioral tests for hooks/gates/merge-door.sh. Covers the ask-on-match
# case, the operator-window/prefix-wrapper/whitespace shapes the argv-based
# classifier is supposed to catch, and the false-positive/negative shapes
# named by the adversarial plan review that sank the original word-boundary-
# regex design: a HEREDOC/commit-message mention of "gh pr merge" as prose
# must NOT ask, and the `gh api .../merge` REST equivalent is a documented,
# deliberate non-goal (also must not ask). Also covers the sudo -u/-g
# value-taking-flag bypass (issue #115, fixed 2026-08-28): before the fix,
# `sudo -u alice gh pr merge` was misread as argv0="alice", not "gh".
# Run standalone: bash tests/hooks/test-merge-door.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$ROOT/hooks/gates/merge-door.sh"

pass=0
fail=0

payload_bash() { # payload_bash <command>
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

check() { # check <desc> <ok:0|1>
  if [ "$2" -eq 0 ]; then echo "  ✅ $1"; pass=$((pass + 1))
  else echo "  ❌ $1" >&2; fail=$((fail + 1)); fi
}

echo "=== merge-door gate ==="
cd "$ROOT" || exit 1

BATTERY=(
  "plain gh pr merge -> ask|gh pr merge 123|ask"
  "gh pr merge, no PR number -> ask|gh pr merge|ask"
  "extra internal whitespace -> ask (argv-tokenized, not regex)|gh  pr   merge 123|ask"
  "sudo-wrapped -> ask (prefix-wrapper unwrap)|sudo gh pr merge 123|ask"
  "sudo -u <user>-wrapped -> ask (issue #115 fix)|sudo -u alice gh pr merge 123|ask"
  "sudo --user=<user>-wrapped -> ask (issue #115 fix, = form)|sudo --user=alice gh pr merge 123|ask"
  "sudo -g <group>-wrapped -> ask (issue #115 fix)|sudo -g admins gh pr merge 123|ask"
  "second command in an operator chain -> ask|echo hi && gh pr merge 123|ask"
  "gh pr view -> noask (not a merge)|gh pr view 123|noask"
  "git merge -> noask (argv0 is git, not gh)|git merge feature-branch|noask"
  "gh api REST merge endpoint -> noask (documented non-goal)|gh api -X PUT repos/o/r/pulls/123/merge|noask"
  "glued semicolon, no space -> ask (deep-audit 2026-08-28)|git push;gh pr merge 123|ask"
  "glued &&, no space -> ask (deep-audit 2026-08-28)|git push&&gh pr merge 123|ask"
  "glued pipe, no space -> ask (deep-audit 2026-08-28)|echo x|gh pr merge 123|ask"
  "subshell wrap, no space -> ask (deep-audit 2026-08-28)|(gh pr merge 123)|ask"
  "brace group -> ask (deep-audit 2026-08-28)|{ gh pr merge 123; }|ask"
  "sudo -nu <user> bundled short flags -> ask (deep-audit 2026-08-28)|sudo -nu alice gh pr merge 123|ask"
  "sudo -Sku <user> bundled short flags -> ask (deep-audit 2026-08-28)|sudo -Sku alice gh pr merge 123|ask"
  "sudo -un <user>: u's value is the attached 'n', alice is the real wrapped cmd -> noask (must not over-fire)|sudo -un alice gh pr merge 123|noask"
)

for row in "${BATTERY[@]}"; do
  desc="${row%%|*}"
  rest="${row#*|}"
  cmd="${rest%|*}"
  expect="${rest##*|}"
  out=$(payload_bash "$cmd" | bash "$GATE" 2>/dev/null)
  got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
  ok=1
  if [ "$expect" = "ask" ] && [ "$got_ask" -eq 0 ]; then ok=0; fi
  if [ "$expect" = "noask" ] && [ "$got_ask" -eq 1 ]; then ok=0; fi
  check "battery: $desc" "$ok"
done

# HEREDOC/commit-message prose mention must NOT ask — the exact false-positive
# class a naive regex design would have hit, and the reason irrecoverable.sh's
# own _strip_heredocs exists.
heredoc_cmd=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nRun gh pr merge after this lands\nEOF\n)"')
out=$(payload_bash "$heredoc_cmd" | bash "$GATE" 2>/dev/null)
got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
ok=1; [ "$got_ask" -eq 1 ] && ok=0
check "HEREDOC commit message mentioning 'gh pr merge' as prose -> noask" "$ok"

# Real backslash-newline continuation, no surrounding whitespace, splitting a
# dispatch token apart -- GH #126. Bash removes both the backslash AND the
# newline entirely (ground-truthed via `bash -x`), joining the two halves
# with nothing between them, so each of these is a genuine, valid
# `gh pr merge`-shaped command that must still ask. The old _newlines_to_seps
# put the literal "\<newline>" back unchanged instead of removing it, which
# left a stray embedded newline glued onto whichever token followed --
# defeating the exact-match argv0/token dispatch the same way GH #122/#123
# were defeated, and the old bash-level fast-path prefilter had the same
# "GH #122 adjacent finding" gap irrecoverable.sh already fixed: a
# continuation splitting "gh" or "merge" itself turned the escape into a
# space, so neither candidate substring survived and python3 was never even
# spawned. Built with `printf` (real backslash + real newline chars, not the
# BATTERY array above) since an embedded raw newline inside a
# "desc|cmd|expect" row is fragile to parse -- same standalone-block
# precedent as the HEREDOC case just above.
assert_ask() { # assert_ask <desc> <command>
  local out got_ask
  out=$(payload_bash "$2" | bash "$GATE" 2>/dev/null)
  got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
  check "$1" "$got_ask"
}
assert_ask "backslash-newline continuation, split inside gh -> ask (GH #126)" "$(printf 'g\\\nh pr merge 123')"
assert_ask "backslash-newline continuation, split inside pr -> ask (GH #126)" "$(printf 'gh p\\\nr merge 123')"
assert_ask "backslash-newline continuation, split inside merge -> ask (GH #126)" "$(printf 'gh pr me\\\nrge 123')"
assert_ask "backslash-newline continuation, split inside sudo wrapper -> ask (GH #126)" "$(printf 's\\\nudo gh pr merge 123')"

assert_noask() { # assert_noask <desc> <command>
  local out got_ask
  out=$(payload_bash "$2" | bash "$GATE" 2>/dev/null)
  got_ask=1; echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"' && got_ask=0
  local ok=1; [ "$got_ask" -eq 1 ] && ok=0
  check "$1" "$ok"
}

# GH #131 comment-swallow / GH #133 backslash-parity / GH #132 command-sub
# fast-path splice, all found+fixed together 2026-09-03: the naive
# _newlines_to_seps regex (`re.sub(r"\\\n", "", s)`) was neither
# comment-aware nor backslash-parity-aware, and the bash-level fast path had
# no guard against a vanishing $()/backtick construct splicing "gh"/"merge"
# apart. Fixed by porting irrecoverable.sh's char-by-char state-machine
# _newlines_to_seps verbatim (comment/quote/parity-aware) plus a `_defer`
# flag on the bash fast path for any raw $/backtick/backslash.

# #131: a trailing backslash immediately before a real newline has NO
# continuation effect while inside a "#" comment -- a bash comment already
# ends at the literal newline regardless of what precedes it. The naive
# regex did not know it was inside a comment and joined the next physical
# line onto the same window as the comment, swallowing "gh pr merge 123"
# into the comment text entirely (silent allow, confirmed pre-fix above).
comment_swallow_cmd=$(printf 'git status # comment \\\ngh pr merge 123')
assert_ask "comment-swallow: backslash before a real newline inside a # comment is not a continuation -> ask (#131)" "$comment_swallow_cmd"

# #133: an EVEN run of backslashes (2 here) immediately before a real
# newline pairs off into literal characters -- the newline itself is a real,
# unescaped separator, not a continuation. The naive regex only matched a
# SINGLE trailing backslash+newline, leaving one backslash unconsumed with
# no separator emitted at all, gluing the next line's tokens onto the prior
# command's argument list instead of splitting them into their own window
# (silent allow, confirmed pre-fix above).
parity_even_cmd=$(printf 'echo hi \\\\\ngh pr merge 123')
assert_ask "backslash-parity: EVEN backslash run before a real newline is not a continuation -> ask (#133)" "$parity_even_cmd"

# #132/#129: `g$(true)h pr merge 123` resolves to `gh pr merge 123` in real
# bash (command substitution splices "g" and "h" together), but neither "gh"
# nor "merge" survives as a contiguous substring in the bash-level fast-path
# normalization, so pre-#132-fix this exited 0 and never spawned python3 at
# all (confirmed pre-fix: rc=0, no output). Proven two ways, since a bare
# rc=0 cannot distinguish "python3 ran and correctly allowed" from "python3
# never ran": (a) with python3 removed from PATH, the announced
# "python3 not found" fail-open note must fire -- which can only happen if
# the fast path deferred past its own allow and reached that guard (same
# black-box technique as tests/hooks/test-verifier-protect.sh's
# check_reaches_pyguard, for the sibling GH #128/#130 fix); (b) with python3
# present, python3 now correctly resolves the splice and asks -- the GH #129
# gap (a spliced dispatch token surviving tokenization as its own garbled
# token and evading the exact-match checks) is closed here the same way it
# was closed in irrecoverable.sh: a placeholder-blanking pass plus
# candidate duplication at every dispatch position a splice could land on.
NOPY_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-md-nopy.XXXXXX")
ln -s /bin/cat "$NOPY_BIN/cat"
ln -s /bin/bash "$NOPY_BIN/bash"
ln -s /usr/bin/sed "$NOPY_BIN/sed"
ln -s /usr/bin/tr "$NOPY_BIN/tr"

check_reaches_pyguard() { # check_reaches_pyguard <desc> <command> <expect:reach|noreach>
  local desc="$1" cmd="$2" expect="$3" rc errf
  errf=$(mktemp "${TMPDIR:-/tmp}/kbg-md-nopy-err.XXXXXX")
  rc=$(payload_bash "$cmd" | PATH="$NOPY_BIN" bash "$GATE" 2>"$errf"; echo $?)
  local reached=1
  [ "$rc" = "0" ] && /usr/bin/grep -q 'python3 not found' "$errf" && reached=0
  local ok=1
  if [ "$expect" = "reach" ] && [ "$reached" -eq 0 ]; then ok=0; fi
  if [ "$expect" = "noreach" ] && [ "$reached" -eq 1 ]; then ok=0; fi
  check "$desc" "$ok"
  rm -f "$errf"
}

check_reaches_pyguard "command-sub splice defers past the fast path -> reaches python3 (#132)" 'g$(true)h pr merge 123' "reach"
assert_ask "command-sub splice, python3 reached -> ask (GH #129 fix: candidate duplication resolves the argv0 splice)" 'g$(true)h pr merge 123'
check_reaches_pyguard "unrelated \$-free command -> still fast-exits, never reaches python3" 'echo hello world' "noreach"

# #132 false-positive check: A2 makes ANY $/backtick/backslash-bearing
# command defer to python3 now, not just gh+merge-shaped ones -- confirm
# that wider net does not cause a false ask on an ordinary harmless command.
check_reaches_pyguard "\$-bearing harmless command -> reaches python3 (#132 wider net)" 'echo "$HOME/x"' "reach"
assert_noask "\$-bearing harmless command, python3 reached -> still correctly noask" 'echo "$HOME/x"'

# GH #129 3-position duplication: this gate dispatches on argv0 AND the two
# tokens right after it ("pr"/"merge"), so a splice landing on either of
# those is an equally live bypass, not just an argv0 splice.
assert_ask "rest[0] splice resolving to pr -> ask (GH #129)" 'gh p$()r merge 123'
assert_ask "rest[1] splice resolving to merge -> ask (GH #129)" 'gh pr m$(true)erge 123'

# Negative control: argv0 is spliced but resolves to a benign gh subcommand,
# not a pr-merge pair -- duplication must not over-ask just because a
# splice marker is present somewhere in the window.
assert_noask "argv0 spliced, resolves to a benign gh subcommand -> noask (GH #129 must not over-ask)" '$(which gh) pr view 123'

# GH #139 (2026-09-04): the $(...)/${...} closer-search used to scan forward
# for the FIRST "(" or ")" byte and treat that as the terminator -- not
# depth-aware, so a paren nested INSIDE the span (a function definition)
# aborted the match early, leaving the true end of the span un-blanked.
# "g$(f() { :; }; f)h pr merge 123" really runs as "gh pr merge 123" (the
# function body is a no-op, so the substitution resolves to empty), but
# pre-fix the un-blanked "(", ")", "{", "}" bytes fragment the shlex
# tokenization so no window's argv0 ever reads "gh" -- confirmed live:
# noask before this fix. Fixed by depth-counting same-type brackets in the
# closer-search (same technique irrecoverable.sh's sibling GH #139 fix and
# main-exec-guard.sh's own _inner_cmds already use).
assert_ask "nested function-construct inside \$(...) defeats the old first-byte closer-search, real bash resolves to gh pr merge (GH #139, was noask)" 'g$(f() { :; }; f)h pr merge 123'

# Companion DoS check: depth-counting a closer-search that never balances
# (an adversarial flood of unclosed "$(" starts) must stay bounded by a
# work budget instead of costing O(remaining length) PER start -- O(n^2)
# total (same fix/rationale as irrecoverable.sh, GH #139). Budget exhaustion
# alone is NOT safe to read as "no gh/pr/merge trio found, noask": that
# fallback path leaves the span un-blanked, the exact bypass shape GH #139
# closed, so an adversary could pad a real dangerous command with just
# enough flood to burn the budget and hide the payload again. Fixed by a
# _DEPTH_BUDGET_BLOWN flag that forces the fail-closed ask outcome instead
# (this file's primary mechanism is emit_ask) -- so this must complete fast
# AND ask.
depth_flood_cmd=$(python3 -c 'print("$(" * 50000)')
depth_flood_start=$(date +%s)
depth_flood_out=$(payload_bash "$depth_flood_cmd" | timeout 10 bash "$GATE" 2>/dev/null)
depth_flood_rc=$?
depth_flood_elapsed=$(( $(date +%s) - depth_flood_start ))
depth_flood_ask=1; echo "$depth_flood_out" | /usr/bin/grep -q '"permissionDecision": "ask"' && depth_flood_ask=0
depth_flood_ok=1
if [ "$depth_flood_rc" -eq 0 ] && [ "$depth_flood_elapsed" -le 10 ] && [ "$depth_flood_ask" -eq 0 ]; then depth_flood_ok=0; fi
check "50,000x unclosed \"\$(\" flood completes within a generous ceiling and asks (GH #139 fail-closed budget-exhaustion fix)" "$depth_flood_ok"

# An English contraction sitting in an unrelated, earlier window must not
# mask a real splice-based match later in the same input -- same shape as
# the it-is-shaped bypass irrecoverable.sh own history already found for a
# flat apostrophe-pairing regex; this gate uses real shell-quote-state
# tracking instead, so the contraction stays inert text.
assert_ask "contraction in an earlier window does not mask a real splice -> ask" 'echo "it'"'"'s" ; g$(true)h pr merge 123'

# PREFIX_WRAPPERS unwrap PH-splice bypass: the _blank_substitutions pass
# leaves a literal, non-empty PH byte glued to the front of a token whose
# preceding $(...)/backtick span resolves to empty at runtime (same
# mechanism as the GH #129 dispatch-token fix above), but the env/nice/
# sudo/generic wrapper-unwrap loops below the dispatch check test each
# token with a raw startswith("-") or isidentifier() check. A PH-prefixed
# token no longer starts with "-" and no longer isidentifier()-passes once
# a "=" is present, so the unwrap loop stops early and misreads the
# PH-prefixed wrapper flag itself as the argv0 of the wrapped command. That
# shifts the trio-dispatch window by one token, so the real gh/pr/merge
# trio sitting one position later never lines up with the checked
# positions, and the ask silently does not fire. Each payload below
# resolves in real bash (verified with `bash -c echo`, no exec) to the
# exact unspliced control on the following line, which already asks
# correctly, so any input where the spliced form fails to ask while the
# control succeeds is a confirmed silent-allow bypass, not a tokenizer
# quirk.
assert_ask "env VAR=value unwrap, PH-spliced assignment -> ask (real bash: env FOO=bar gh pr merge 123)" 'env $(true)FOO=bar gh pr merge 123'
assert_ask "env VAR=value unwrap, control (no splice) -> ask" 'env FOO=bar gh pr merge 123'
assert_ask "sudo bundled short flag unwrap, PH-spliced -nu -> ask (real bash: sudo -nu alice gh pr merge 123)" 'sudo $(true)-nu alice gh pr merge 123'
assert_ask "nice -n unwrap, PH-spliced flag -> ask (real bash: nice -n 5 gh pr merge 123)" 'nice $(true)-n 5 gh pr merge 123'
assert_ask "generic wrapper (command -p) unwrap, PH-spliced flag -> ask (real bash: command -p gh pr merge 123)" 'command $(true)-p gh pr merge 123'
# Negative control: a PH-spliced env assignment ahead of a non-merge gh
# subcommand must still correctly noask -- the fix must not turn every
# PH-bearing wrapper token into an over-broad ask.
assert_noask "env VAR=value unwrap, PH-spliced assignment ahead of a non-merge subcommand -> noask" 'env $(true)FOO=bar gh pr view 123'

# Layer 3 bug (found by an independent adversarial reviewer, 2026-09-03): a
# STANDALONE, unquoted word that resolves to empty at runtime (its own
# space-separated token, nothing glued to it) vanishes entirely in real bash
# via word-splitting, shifting every later token left by one position. The
# placeholder mechanism above instead leaves a PH-only token sitting in that
# position, so a FIXED-INDEX read (the trio-dispatch check comparing
# argv0/rest[0]/rest[1] against a fixed candidate tuple, or the
# PREFIX_WRAPPERS unwrap loop's flag/assignment shape tests) reads the wrong
# token entirely and the real dispatch is missed. Fixed by also running the
# same dispatch/unwrap pipeline against a second, COMPACTED token list with
# every bare-PH-only token (a token that strips to exactly PH, nothing else
# attached) removed -- the verdict asks if either pass asks.
assert_ask "bare vanish before the whole dispatch (backtick form) -> ask (real bash: gh pr merge 123)" '`true` gh pr merge 123'
assert_ask "bare vanish before the whole dispatch (\$() form) -> ask (real bash: gh pr merge 123)" '$(true) gh pr merge 123'
assert_ask "bare vanish mid-dispatch (\$() form) -> ask (real bash: gh pr merge 123)" 'gh $(true) pr merge 123'
assert_ask "bare vanish mid-dispatch (backtick form) -> ask (real bash: gh pr merge 123)" 'gh `true` pr merge 123'
assert_ask "two bare vanishes -> ask (real bash: gh pr merge 123)" '$(true) gh $(true) pr merge 123'
assert_ask "bare vanish inside env wrapper unwrap -> ask (real bash: env FOO=bar gh pr merge 123)" 'env $(true) FOO=bar gh pr merge 123'
assert_ask "bare vanish inside sudo wrapper unwrap -> ask (real bash: sudo -u alice gh pr merge 123)" 'sudo $(true) -u alice gh pr merge 123'
assert_ask "bare vanish inside nice wrapper unwrap -> ask (real bash: nice -n 5 gh pr merge 123)" 'nice $(true) -n 5 gh pr merge 123'
assert_ask "bare vanish inside command wrapper unwrap -> ask (real bash: command -p gh pr merge 123)" 'command $(true) -p gh pr merge 123'
assert_ask "bare vanish after sudo, before gh -> ask (real bash: sudo gh pr merge 123)" 'sudo gh $(true) pr merge 123'

# Required negative control (task spec): a bare-vanish argv0 that resolves to
# something REAL, not empty, is structurally identical (bare PH token) but
# must stay noask -- a blanket "any bare PH token anywhere -> ask" rule
# would break this. Already covered above as "argv0 spliced, resolves to a
# benign gh subcommand", re-asserted here right beside the new bare-vanish
# coverage for visibility.
assert_noask "bare-PH argv0 resolving to a real, non-empty command -> noask (must not over-ask)" '$(which gh) pr view 123'

# Finding 1 (HIGH, live, 2026-09-04): _blank_substitutions joined recovered
# command-substitution bodies with " ; " (a space, not a real newline). A
# bare "#" anywhere in the string before that append point makes shlex's
# default comment-stripping (commenters="#") silently discard everything
# from that "#" onward -- including the appended body -- since shlex's own
# comment handling reads to the next REAL newline character, not to a
# literal " ; " separator. Fixed by leading each appended body with an
# actual "\n" so shlex's comment-skip stops there, same as a real bash line
# boundary would.
assert_ask "trailing # comment after the append point does not swallow the recovered body -> ask (Finding 1)" 'echo $(gh pr merge 123)  # merge'
assert_ask "# comment embedded INSIDE an earlier recovered body does not swallow a later one -> ask (Finding 1)" 'echo $(echo hi # note) $(gh pr merge 123)'
assert_ask "no-comment control still asks after the join-separator fix -> ask (Finding 1)" 'echo $(gh pr merge 123)'

# Finding 2 (HIGH, live, 2026-09-04): merge-door.sh never ported
# _normalize_ansi_c_quotes (irrecoverable.sh/verifier-protect.sh/
# worktree-guard.py all have it). A $'...' ANSI-C-quoted span decodes to a
# real character in bash ($'\x68' is "h") but shlex has no notion of this
# quoting style at all and splits on the bare $, so "g$'\x68' pr merge 123"
# (real bash: "gh pr merge 123") never reassembles into a "gh" token.
assert_ask "ANSI-C \$'\\x68' splice decodes to h, forming gh -> ask (Finding 2, real bash: gh pr merge 123)" "g\$'\\x68' pr merge 123"
assert_ask "unspliced control still asks -> ask (Finding 2)" 'gh pr merge 123'

# Finding 5 (MEDIUM, live, 2026-09-04): _blank_substitutions's own inner
# _scan_once tracked quote state char-by-char but had no comment-state
# tracking at all, so a substitution-shaped string sitting inside a REAL "#"
# comment (e.g. "# see also: $(gh pr merge 123)") was still matched and its
# body collected into `bodies` as if live -- escaping the comment entirely
# once appended as its own statement at the end, producing a false ask on a
# genuinely innocent command. Fixed by porting the same in_comment
# char-by-char state machine _newlines_to_seps already uses.
assert_noask "substitution-shaped text inside a real # comment is inert commentary -> noask (Finding 5)" "$(printf 'gh pr view 1 # see also: $(gh pr merge 123)\necho done')"

# Finding 4 (2026-09-04): _blank_substitutions's ${...}/$(...)/backtick
# closer-search scans forward for a terminating char without tracking quote
# state for characters it skips over. A span crossing a real quote -- an
# everyday shell idiom like ${x:-"a}b"}, not a contrived one -- desyncs the
# scan (it stops at the FIRST "}", which sits inside the quoted "a}b", not
# the real closer at the end), leaving the blanked-and-reassembled command
# quote-unbalanced even though the ORIGINAL command was perfectly valid.
# Since Finding 1 already removed the old cmd.split() fallback for a
# shlex.shlex() ValueError, this used to hard-ask/deny on a legitimate
# command. Fixed by, on ValueError, validating the ORIGINAL pre-blanking
# string with shlex.split() as a pure validity predicate -- if THAT parses,
# the corruption was self-inflicted by blanking, so fall back to a
# separator-aware split (";"/"&&"/"||"/"&"/"|", each piece tokenized with
# shlex.split()) instead of a naive whitespace split, which would have
# missed a dangerous second command in a chain entirely.
assert_ask "quote-crossing ValueError, dangerous cmd BEFORE the bad span -> ask (Finding 4)" 'gh pr merge 123; echo ${x:-"a}b"}'
assert_ask "quote-crossing ValueError, dangerous cmd AFTER the bad span -> ask (Finding 4)" 'echo ${x:-"a}b"}; gh pr merge 123'
assert_noask "quote-crossing ValueError alone, no dispatch anywhere -> noask (Finding 4, must not over-ask)" 'echo ${x:-"a}b"}'
assert_ask "genuinely malformed command (real unbalanced quote) -> still ask (Finding 4 control)" 'gh pr merge 123 "unterminated'

# Finding 4 follow-up (2026-09-04, cross-file review, live confirmed): the
# Finding-4 fallback above tokenizes from the ORIGINAL, never-blanked
# command text, so a fallback token can never carry a PH byte -- the
# GH #129 trio-duplication gate (PH in argv0/rest[0]/rest[1]) never fires on
# this path, and a spliced argv0 like g$(true)h sailed through unrecognized.
# This combined "quote-crossing ValueError forces the fallback, PLUS a
# splice in the fallback's own dispatch window" cell was never in this
# suite before -- exactly why it shipped. Fixed by widening the duplication
# trigger to also fire on a token still carrying raw "`"/"$("/"${" syntax,
# not just a PH byte.
assert_ask "quote-crossing fallback + spliced argv0, dangerous cmd AFTER the bad span -> ask (Finding 4 follow-up, real bash: echo ...; gh pr merge 123)" 'echo ${y:-"a}b"} ; g$(true)h pr merge 123'
assert_ask "quote-crossing fallback + spliced argv0, dangerous cmd BEFORE the bad span -> ask (Finding 4 follow-up)" 'g$(true)h pr merge 123 ; echo ${y:-"a}b"}'
assert_noask "spliced argv0 resolving to a benign gh subcommand -> noask (Finding 4 follow-up, must not over-ask)" 'g$(true)h status'
assert_noask "bare \$VAR command must not trigger the raw-subst widening -> noask (Finding 4 follow-up)" '$PYTHON -m pytest'

# PH-site sweep (2026-09-04, second adversarial reviewer): the argv0/rest[0]/
# rest[1] trio-duplication fix above is not the only place a token reaching
# the Finding-4 fallback can carry raw, never-blanked substitution syntax --
# every PREFIX_WRAPPERS unwrap-loop shape test (env/nice/sudo/generic) and
# _drop_bare_vanish_tokens read a token's shape too, and both were still
# blind to raw syntax before this fix (confirmed live, silent allow on each
# shape below prior to the fix). Fixed by a shared _reveal() helper that
# peels a leading raw substitution span the same way .lstrip(PH) already
# peels a placeholder, so the SAME downstream shape tests recognize either
# kind of token; _drop_bare_vanish_tokens gets the analogous _raw_token_
# vanishes() check for a token that is ENTIRELY substitution syntax.
assert_ask "env VAR=value unwrap, raw (never-blanked) assignment prefix reaching the fallback -> ask (real bash: env FOO=bar gh pr merge 123)" 'echo ${z:-"a}b"} ; env $(true)FOO=bar gh pr merge 123'
assert_noask "env VAR=value unwrap, raw assignment prefix ahead of a non-merge subcommand -> noask" 'echo ${z:-"a}b"} ; env $(true)FOO=bar gh pr view 123'
assert_ask "env -u value-taking flag with a raw prefix reaching the fallback -> ask (real bash: env -u alice gh pr merge 123, must also consume the value token)" 'echo ${z:-"a}b"} ; env $(true)-u alice gh pr merge 123'
assert_ask "sudo -u value-taking flag with a raw prefix reaching the fallback -> ask (real bash: sudo -u alice gh pr merge 123, must also consume the value token)" 'echo ${z:-"a}b"} ; sudo $(true)-u alice gh pr merge 123'
assert_ask "nice -n flag with a raw prefix reaching the fallback -> ask (real bash: nice -n 5 gh pr merge 123)" 'echo ${z:-"a}b"} ; nice $(true)-n 5 gh pr merge 123'
assert_ask "generic wrapper (command -p) with a raw-prefixed flag reaching the fallback -> ask (real bash: command -p gh pr merge 123)" 'echo ${z:-"a}b"} ; command $(true)-p gh pr merge 123'
assert_ask "bare-vanish-drop: a standalone raw substitution token reaching the fallback -> ask (real bash: gh pr merge 123)" 'echo ${z:-"a}b"} ; $(true) gh pr merge 123'
assert_noask "bare-vanish-drop: a standalone raw substitution token ahead of a non-merge subcommand -> noask" 'echo ${z:-"a}b"} ; $(true) gh pr view 123'
assert_noask "sudo -u benign wrapped command (no fallback forced) -> noask, unaffected by the _reveal redesign" 'sudo -u alice echo hi'

# PH-site sweep, 4th cross-file review (2026-09-04): _reveal() above still
# did t.lstrip(PH) -- leading-only -- while the equivalent sites in the 3
# sibling files had already been converted to t.replace(PH, ""). A
# TRAILING placeholder inside a short value-taking flag (the substitution
# glued onto the END of "-u"/"-n"/"-g", not the front) survives a
# leading-only strip: "-uPH" still has PH as its 3rd character, so the
# bundled-flag length check (`m.end() < len(t[1:])`) counts it as a real
# extra character and wrongly concludes the flag value is already
# attached, skipping only the flag token and never the value token after
# it -- shifting the trio-check off target (confirmed live, all 4 shapes
# below silently allowed prior to this fix; the raw-subst-via-fallback
# analogue of the same shape was equally live). Fixed by removing PH and
# every raw substitution span WHEREVER they occur in the token (not
# leading-only), so the length comparison downstream measures the correct
# revealed remainder either way.
assert_ask "sudo -u, trailing placeholder inside the flag -> ask (real bash: sudo -u alice gh pr merge 123)" 'sudo -u$(true) alice gh pr merge 123'
assert_ask "nice -n, trailing placeholder inside the flag -> ask (real bash: nice -n 5 gh pr merge 123)" 'nice -n$(true) 5 gh pr merge 123'
assert_ask "sudo -g, trailing placeholder inside the flag -> ask (real bash: sudo -g staff gh pr merge 123)" 'sudo -g$(true) staff gh pr merge 123'
assert_ask "env -u, trailing placeholder inside the flag -> ask (real bash: env -u FOO gh pr merge 123)" 'env -u$(true) FOO gh pr merge 123'
assert_ask "sudo -u, trailing raw (never-blanked) substitution reaching the fallback -> ask" 'echo ${z:-"a}b"} ; sudo -u$(true) alice gh pr merge 123'
assert_noask "sudo -u, trailing placeholder, benign wrapped command -> noask (must not over-ask)" 'sudo -u$(true) alice echo hi'
assert_noask "env -u, trailing placeholder, non-merge subcommand -> noask (must not over-ask)" 'env -u$(true) FOO gh pr view 123'
# Bounded controls (already correctly asking before this fix; must not break)
assert_ask "sudo -u, leading placeholder before the flag -> ask (control, unaffected)" 'sudo $(true)-u alice gh pr merge 123'
assert_ask "sudo -u, placeholder mid-flag (between the dash and u) -> ask (control, unaffected)" 'sudo -$(true)u alice gh pr merge 123'
assert_ask "sudo --user=, placeholder inside the = value -> ask (control, unaffected)" 'sudo --user=$(true)alice gh pr merge 123'

# PH-site sweep, 5th cross-file review (2026-09-04): the trailing-splice fix
# above closed the 4 empty-resolving bypasses but opened the mirror-image
# bug on the SAME 4 flags -- "-u$(true)" and "-u$(id -un)" both reveal to
# the identical "-u", but the first resolves to empty at runtime (value is
# a SEPARATE next token) and the second resolves to something real fused
# onto the flag (value is ATTACHED, the wrapped command is the next token
# instead). No comparison on the revealed token text can tell these apart
# -- the information genuinely is not there. Fixed by NOT picking a side:
# _sudo_classify/_env_classify/_nice_classify return BOTH candidate
# continuations whenever the token actually had a substitution removed,
# and _unwrap_all/_window_is_merge_dispatch ask if EITHER candidate's
# resulting token stream reaches a real gh/pr/merge trio -- same
# enumerate-every-candidate pattern the dispatch-trio duplication above
# already uses, applied to the unwrap-loop position instead of the final
# compare. Both directions are pinned in this ONE suite run on purpose --
# round 4b only tested the empty-resolving direction and immediately
# regressed the non-empty one.
assert_ask "sudo -u, empty-resolving substitution -> ask (real bash: sudo -u alice gh pr merge 123)" 'sudo -u$(true) alice gh pr merge 123'
assert_ask "nice -n, empty-resolving substitution -> ask (real bash: nice -n 5 gh pr merge 123)" 'nice -n$(true) 5 gh pr merge 123'
assert_ask "sudo -g, empty-resolving substitution -> ask (real bash: sudo -g staff gh pr merge 123)" 'sudo -g$(true) staff gh pr merge 123'
assert_ask "env -u, empty-resolving substitution -> ask (real bash: env -u FOO gh pr merge 123)" 'env -u$(true) FOO gh pr merge 123'
assert_ask "sudo -u, NON-empty-resolving substitution fused onto the flag -> ask (real bash: sudo -u<username> gh pr merge 123, the value is attached, not a separate token)" 'sudo -u$(id -un) gh pr merge 123'
assert_ask "nice -n, NON-empty-resolving substitution fused onto the flag -> ask (real bash: nice -n5 gh pr merge 123)" 'nice -n$(echo 5) gh pr merge 123'
assert_ask "env -u, NON-empty-resolving substitution fused onto the flag -> ask (real bash: env -uFOO gh pr merge 123)" 'env -u$(echo FOO) gh pr merge 123'
assert_ask "sudo -g, NON-empty-resolving substitution fused onto the flag -> ask (real bash: sudo -gstaff gh pr merge 123)" 'sudo -g$(echo staff) gh pr merge 123'
# Negative controls: same ambiguous flag shape, but no gh/pr/merge trio
# reachable via EITHER candidate -- must stay clean. Duplication-based
# over-asking on an ambiguous flag PLUS a real dispatch elsewhere in the
# window is the deliberate, correct fail-closed direction for this
# ask-gate (matches the stance the other 3 sibling files already take for
# their own duplication mechanisms) -- it is not narrowed away here, but
# these controls have no dispatch-trio match down any path at all, so
# they must not ask regardless.
assert_noask "sudo -u ambiguous flag, benign wrapped command (no dispatch trio down either candidate) -> noask" 'sudo -u$(true) alice ls'
assert_noask "env -u ambiguous flag, non-merge subcommand -> noask" 'env -u$(true) FOO gh pr view 123'
assert_noask "sudo -u ambiguous flag, non-empty-resolving, benign wrapped command -> noask" 'sudo -u$(id -un) ls'

# PH-site sweep, 6th cross-file review (2026-09-04, live DoS confirmed): the
# enumeration fix above (round 5) explores the SAME (argv0, rest) state
# repeatedly on a CHAIN of several ambiguous prefix-wrapper flags in a row,
# with no memoization -- work compounds into exponential blowup instead of
# genuine branching growth. A repeated "env -u$(true) " chain (this is a
# synchronous PreToolUse gate: a hang here blocks every Bash tool call, not
# just this one) hung past a 15s timeout at 24 repeats pre-fix and past 60s
# at 26. Fixed by memoizing _unwrap_all on the exact (argv0, tuple(rest))
# state: every state here is (argv0, a SUFFIX of the top-level token list),
# and a list of length n has only n+1 distinct suffixes, so the DISTINCT
# STATE COUNT is linear -- the blowup was pure re-computation of the same
# states, not real branching growth. Skipping an already-seen state only
# skips re-deriving finals already added the first time that exact state
# was reached, so this does not change WHICH candidates are explored
# (verified separately: all round-5 payloads plus the sudo -u/-nu/-Sku/-un
# baselines produced byte-identical verdicts before and after this fix).
#
# 7th-round correction (2026-09-04): linear STATE COUNT does not make the
# total WORK linear -- _wrapper_stop_positions is not itself memoized, so
# total work summed across all states is polynomial (roughly
# O(n^2)-O(n^3)), not linear (independently measured: 1600 repeats takes
# about 10s). Not a tight wall-clock assertion below (flaky on a loaded
# machine) -- a generous ceiling well above the previously-hanging
# payload; the fixed code clears it with room to spare (confirmed
# manually: 24 repeats completes in well under a second after the fix,
# versus a 15s timeout before it).
dos_chain_cmd="$(printf 'env -u$(true) %.0s' $(seq 1 30))gh pr merge 123"
dos_start=$(date +%s)
dos_out=$(payload_bash "$dos_chain_cmd" | timeout 10 bash "$GATE" 2>/dev/null)
dos_rc=$?
dos_elapsed=$(( $(date +%s) - dos_start ))
dos_ask=1; echo "$dos_out" | /usr/bin/grep -q '"permissionDecision": "ask"' && dos_ask=0
dos_ok=1
if [ "$dos_rc" -eq 0 ] && [ "$dos_elapsed" -le 10 ] && [ "$dos_ask" -eq 0 ]; then dos_ok=0; fi
check "chained ambiguous wrapper flags (30x env -u\$(true)) completes within a generous ceiling and still asks -- polynomial, not exponential (6th-round DoS fix)" "$dos_ok"

# 8th-round fix (2026-09-04, live DoS confirmed still exploitable after
# round 6/7): round 6 bounded the DISTINCT state count but not the total
# WORK spent discovering them -- an independent adversarial measurement
# found 1600 repeats of this exact chain took 9.7s, 2000 took 19.3s, 3000
# took 76.6s, and 4000 took 192.2s (3.2 minutes), with no cap anywhere in
# this file. Fixed by a process-wide work-volume budget inside _unwrap_all
# (_UNWRAP_WORK_BUDGET, currently 5,000,000) that trips at ~195-200 repeats
# of this chain -- 1600 repeats below is ~8x past the trip point, previously
# the single slowest measured case this suite can practically assert a tight
# bound on. _window_is_merge_dispatch asks immediately when the budget is
# exhausted, before even looking at whatever candidates were already found,
# so this must complete FAST now (well under a second in practice; the 2s
# bound below is generous headroom, not the actual target) and still ask.
budget_chain_cmd="$(printf 'env -u$(true) %.0s' $(seq 1 1600))gh pr merge 123"
budget_start=$(date +%s)
budget_out=$(payload_bash "$budget_chain_cmd" | timeout 2 bash "$GATE" 2>/dev/null)
budget_rc=$?
budget_elapsed=$(( $(date +%s) - budget_start ))
budget_ask=1; echo "$budget_out" | /usr/bin/grep -q '"permissionDecision": "ask"' && budget_ask=0
budget_ok=1
if [ "$budget_rc" -eq 0 ] && [ "$budget_elapsed" -le 2 ] && [ "$budget_ask" -eq 0 ]; then budget_ok=0; fi
check "work-volume budget: 1600x env -u\$(true) chain (previously measured 9.7s, well past the ~200-repeat trip point) completes within a strict 2s bound and still asks -- fail-to-ask on budget exhaustion (8th-round fix)" "$budget_ok"

# Direction-pinning test: the assertion above alone does not prove the
# budget-exhaustion PATH is what fired -- the payload's tail is a real
# "gh pr merge 123", so a DFS that happens to still reach that tail before
# tripping the budget would append it to finals and the trio check would
# ask anyway, passing this suite even if a future round wrongly changed
# exhaustion to return (finals, False) (silent "no match" -> allow). Using
# the SAME oversized chain but a NON-merge tail closes that gap: pre-fix
# this was noask (after ~9s+, since the full unwrap eventually resolves and
# finds no gh/pr/merge trio); post-fix it must be ask, FAST, purely because
# _window_is_merge_dispatch returns True the instant budget_exceeded is
# True -- before ever looking at finals, regardless of what candidates a
# truncated scan did or did not turn up.
budget_benign_cmd="$(printf 'env -u$(true) %.0s' $(seq 1 1600))gh pr view 123"
assert_ask "work-volume budget exhausted, NON-merge tail -> still ask (pins the fail-to-ask direction: an exhaustion path that fell through to 'no match' would wrongly noask here, 8th-round fix)" "$budget_benign_cmd"

# Negative control (task spec): a legitimate-shaped, modestly-sized wrapper
# chain -- many orders of magnitude under the budget -- must still resolve
# CORRECTLY, not just fast: ask when a real merge dispatch sits at the end,
# noask when it does not. Proves the budget does not cause a false-ask (or
# a false-noask) on any realistic input; nobody chains sudo+nice+env around
# an ordinary command in practice, and this is still tiny next to the
# ~195-200 repeats needed to even approach the budget.
assert_ask "modest realistic wrapper chain (sudo+nice+env, far under budget) -> ask (real dispatch present, 8th-round fix must not disturb this)" 'sudo nice -n 5 env FOO=bar gh pr merge 123'
assert_noask "modest realistic wrapper chain (sudo+nice+env, far under budget), no merge dispatch -> noask (8th-round fix must not over-ask)" 'sudo nice -n 5 env FOO=bar gh pr view 123'

# --- GH #140: unbounded shlex tokenize cost on an oversized raw command
# string -- a SEPARATE, upstream issue from the _UNWRAP_WORK_BUDGET fix
# above (that one bounds _unwrap_all's own state-exploration cost; this one
# bounds the shlex.shlex(..., punctuation_chars=True) tokenize call at line
# ~451, and its shlex.split() ValueError fallback, which run BEFORE
# _unwrap_all ever sees a token and had no cap of their own). Cost is
# superlinear in the length of a single long token. Measured live against
# this exact file (single token appended ahead of a real "; gh pr merge
# 123", python3 cold-start included): 100,000 chars ~0.22s, 150,000
# ~0.38s, 200,000 ~0.54s, 300,000 ~0.91s -- a 700,000-char payload blows
# straight past a 2s timeout pre-fix (confirmed live: rc=124). This also
# retires the residual "pre-existing linear text-processing cost over a
# multi-megabyte payload" the 8th-round fix's own comment left explicitly
# unbounded (~1.15s at 200,000 repeats there) -- a 150,000-char cap now
# bounds that too.
LEN_PAD=$(python3 -c "print('A' * 700000)")

len_start=$(date +%s)
len_out=$(payload_bash "echo $LEN_PAD ; gh pr merge 123" | timeout 2 bash "$GATE" 2>/dev/null)
len_rc=$?
len_elapsed=$(( $(date +%s) - len_start ))
len_ask=1; echo "$len_out" | /usr/bin/grep -q '"permissionDecision": "ask"' && len_ask=0
len_ok=1
if [ "$len_rc" -eq 0 ] && [ "$len_elapsed" -le 2 ] && [ "$len_ask" -eq 0 ]; then len_ok=0; fi
check "oversized single-token command ahead of a real gh pr merge still asks within a strict 2s bound (GH #140 length cap)" "$len_ok"

# Direction-pinning: the SAME oversized padding ahead of a NON-merge tail
# (the literal substring "merge" only appears in a trailing "#" comment,
# which shlex's own default comment-stripping discards before the trio
# check ever runs) must ALSO ask, fast -- proving the LENGTH CAP fired on
# size alone, not a real gh/pr/merge trio match that happened to still
# resolve inside the timeout. A cap-exceeded path that fell through to "no
# match, allow" would wrongly resolve this one to noask instead.
len_benign_start=$(date +%s)
len_benign_out=$(payload_bash "echo $LEN_PAD ; gh pr view 123 # merge notes" | timeout 2 bash "$GATE" 2>/dev/null)
len_benign_rc=$?
len_benign_elapsed=$(( $(date +%s) - len_benign_start ))
len_benign_ask=1; echo "$len_benign_out" | /usr/bin/grep -q '"permissionDecision": "ask"' && len_benign_ask=0
len_benign_ok=1
if [ "$len_benign_rc" -eq 0 ] && [ "$len_benign_elapsed" -le 2 ] && [ "$len_benign_ask" -eq 0 ]; then len_benign_ok=0; fi
check "oversized padding, NON-merge tail -> still asks fast (pins the length cap, not a trio match, GH #140)" "$len_benign_ok"

# Negative control: a realistic, modestly-sized legitimate command -- well
# under the cap -- must still resolve CORRECTLY (noask here: argv0 is git,
# not gh, so the trio check never matches regardless of the "gh pr merge"
# substring inside the quoted commit message). Proves the cap does not
# false-positive on ordinary usage merely for being longer than trivial.
assert_noask "realistic longer commit message mentioning gh pr merge in prose, well under the GH #140 length cap -> still noask" 'git commit -m "Add detailed changelog entry describing the upcoming gh pr merge process and rollback steps for this release"'

echo ""
echo "=== missing sibling .py (corrupted/partial plugin install; follow-up to #146) ==="
# Same contract as verifier-protect.sh's sibling fix (GH #146 follow-up): a
# missing/unreadable merge-door.py must resolve to an ask JSON (exit 0),
# never a bare nonzero exit carrying a raw "python3: can't open file ..."
# message -- this gate's own header promises "never a hard deny", and its
# documented all-outcomes-are-exit-0 contract (same tier verifier-protect.sh
# uses) already covers internal errors this way. Simulate by copying ONLY
# the .sh into an isolated scratch dir (never touch the real repo file) so
# $(dirname "$0") resolves to a directory with no merge-door.py sibling.
MISSPY_MD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kbg-misspy-md.XXXXXX")
cp "$GATE" "$MISSPY_MD_DIR/merge-door.sh"
_errf=$(mktemp "${TMPDIR:-/tmp}/kbg-misspy-md-err.XXXXXX")
_out=$(payload_bash "gh pr merge 123" | bash "$MISSPY_MD_DIR/merge-door.sh" 2>"$_errf")
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
check "missing sibling merge-door.py -> ask JSON (exit 0), no raw traceback" "$_ok"
rm -f "$_errf"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
