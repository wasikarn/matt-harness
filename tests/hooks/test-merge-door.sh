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

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
