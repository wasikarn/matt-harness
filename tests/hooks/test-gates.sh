#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in test payload strings is intentional
# Gate unit tests: simulates PreToolUse JSON payloads and asserts allow/deny/ask.
# Each test_deny call expects exit 2; test_allow expects exit 0 + empty stdout;
# test_ask expects exit 0 + a permissionDecision: ask JSON on stdout.
# Run standalone: bash tests/hooks/test-gates.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IRRECOVERABLE="$ROOT/hooks/gates/irrecoverable.sh"
TASK_COMPLETE="$ROOT/hooks/gates/task-complete-separation.sh"
SUBAGENT_GIT_GUARD="$ROOT/hooks/gates/subagent-git-guard.sh"

pass=0
fail=0

# Build a minimal Bash tool payload. Uses json.dumps (not printf %s) so
# commands containing quotes/backslashes (e.g. mysql -e "DROP TABLE...",
# find -exec ... \;) don't produce malformed JSON that silently degrades
# to an empty command downstream.
bash_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1"; }

# Build a Write tool payload. Uses json.dumps (see bash_payload above) so
# content containing quotes/backslashes doesn't produce malformed JSON.
write_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))' "$1" "$2"
}

# Build an Edit tool payload. Same json.dumps rationale as write_payload.
edit_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": sys.argv[1], "new_string": sys.argv[2]}}))' "$1" "$2"
}

# Build a TaskUpdate payload. $1=status (or empty to omit the field),
# $2=agent_type (or empty = main session, field omitted). Uses json.dumps so
# the agent_type string is safely encoded.
taskupdate_payload() {
  python3 -c '
import json, sys
status, agent, agent_id = sys.argv[1], sys.argv[2], sys.argv[3]
ti = {"taskId": "T1"}
if status:
    ti["status"] = status
d = {"tool_name": "TaskUpdate", "tool_input": ti}
if agent:
    d["agent_type"] = agent
if agent_id:
    d["agent_id"] = agent_id
print(json.dumps(d))
' "$1" "$2" "${3-$2}"
}

# Build a Bash tool-call payload carrying agent_id (or empty = main
# session). Separate from bash_payload() (used by many pre-existing tests
# with no agent fields at all) to avoid touching that signature.
bash_agent_payload() {
  python3 -c '
import json, sys
cmd, agent_id = sys.argv[1], sys.argv[2]
d = {"tool_name": "Bash", "tool_input": {"command": cmd}}
if agent_id:
    d["agent_id"] = agent_id
print(json.dumps(d))
' "$1" "$2"
}

# Expect the gate to BLOCK (exit 2).
test_deny() {
  local gate="$1" desc="$2" payload="$3"
  local rc
  rc=$(echo "$payload" | bash "$gate" 2>/dev/null; echo $?)
  if [[ "$rc" == "2" ]]; then
    echo "  ✅ DENY: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ DENY EXPECTED but got exit $rc: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the gate to ALLOW (exit 0 + empty stdout — no permissionDecision JSON).
test_allow() {
  local gate="$1" desc="$2" payload="$3" envvar="${4:-}"
  local rc
  if [ -n "$envvar" ]; then
    rc=$(echo "$payload" | env "$envvar" bash "$gate" 2>/dev/null; echo $?)
  else
    rc=$(echo "$payload" | bash "$gate" 2>/dev/null; echo $?)
  fi
  if [[ "$rc" == "0" ]]; then
    echo "  ✅ ALLOW${envvar:+ (env)}: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ ALLOW EXPECTED but got exit $rc: $desc" >&2
    fail=$((fail + 1))
  fi
}

# Expect the gate to ASK (exit 0 + permissionDecision: ask JSON on stdout).
test_ask() {
  local gate="$1" desc="$2" payload="$3"
  local out rc
  out=$(echo "$payload" | bash "$gate" 2>/dev/null); rc=$?
  if [[ "$rc" == "0" ]] && echo "$out" | /usr/bin/grep -q '"permissionDecision": "ask"'; then
    echo "  ✅ ASK: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ ASK EXPECTED but got exit $rc out='$out': $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== irrecoverable gate ==="
test_deny  "$IRRECOVERABLE" "rm -rf"                    "$(bash_payload 'rm -rf /tmp/test')"
test_deny  "$IRRECOVERABLE" "rm -fr variant"            "$(bash_payload 'rm -fr /tmp/test')"
test_deny  "$IRRECOVERABLE" "git push --force"          "$(bash_payload 'git push --force origin develop')"
test_deny  "$IRRECOVERABLE" "git push -f"               "$(bash_payload 'git push -f origin develop')"
test_deny  "$IRRECOVERABLE" "--no-verify"               "$(bash_payload 'git commit --no-verify -m msg')"
test_deny  "$IRRECOVERABLE" "git reset --hard"          "$(bash_payload 'git reset --hard HEAD~1')"
test_deny  "$IRRECOVERABLE" "git clean -f"              "$(bash_payload 'git clean -f')"
test_deny  "$IRRECOVERABLE" "git clean -fd"             "$(bash_payload 'git clean -fd')"
test_allow "$IRRECOVERABLE" "safe rm (no -rf)"          "$(bash_payload 'rm /tmp/file.txt')"
test_allow "$IRRECOVERABLE" "git push no force"         "$(bash_payload 'git push origin develop')"
test_allow "$IRRECOVERABLE" "git reset soft"            "$(bash_payload 'git reset --soft HEAD~1')"
test_allow "$IRRECOVERABLE" "normal bash command"       "$(bash_payload 'ls -la')"

# 2026-07-01 constitution audit: raw-substring matching produced both false
# positives (blocked safe commands merely mentioning a pattern in quoted
# text) and bypasses (quoted/tokenization tricks slipped past the regex).
# Fixed via shlex-based tokenization; these lock the fix in place.
test_allow "$IRRECOVERABLE" "grep for rm -rf text (was a false positive)" \
  "$(bash_payload 'grep -rn "rm -rf" scripts/')"
test_allow "$IRRECOVERABLE" "commit msg mentioning rm -rf (was a false positive)" \
  "$(bash_payload 'git commit -m "docs: warn against rm -rf usage"')"
test_deny  "$IRRECOVERABLE" "quoted rm word (was a bypass)" \
  "$(bash_payload "'rm' -rf /tmp/x")"
test_deny  "$IRRECOVERABLE" "find -exec rm (was a bypass)" \
  "$(bash_payload 'find /tmp/x -exec rm {} \;')"
test_deny  "$IRRECOVERABLE" "git checkout -- discards changes (was a bypass)" \
  "$(bash_payload 'git checkout -- .')"
test_deny  "$IRRECOVERABLE" "git switch --force (was a bypass)" \
  "$(bash_payload 'git switch --force main')"
test_deny  "$IRRECOVERABLE" "git commit --amend (was a bypass)" \
  "$(bash_payload 'git commit --amend')"
test_deny  "$IRRECOVERABLE" "dd to raw device (was a bypass)" \
  "$(bash_payload 'dd if=/dev/zero of=/dev/disk2')"
test_deny  "$IRRECOVERABLE" "SQL DROP TABLE (was a bypass)" \
  "$(bash_payload 'mysql -e "DROP TABLE users"')"
test_deny  "$IRRECOVERABLE" "git add -A (was prose-only)" \
  "$(bash_payload 'git add -A')"
test_deny  "$IRRECOVERABLE" "git add . (was prose-only)" \
  "$(bash_payload 'git add .')"
test_allow "$IRRECOVERABLE" "git add named file (must not over-block)" \
  "$(bash_payload 'git add foo.txt')"
test_allow "$IRRECOVERABLE" "git checkout branch (must not over-block)" \
  "$(bash_payload 'git checkout main')"
test_allow "$IRRECOVERABLE" "git checkout -b new branch (must not over-block)" \
  "$(bash_payload 'git checkout -b new-branch')"
# 2026-08-17 bug sweep: the force check only matched the exact token "-f"/
# "--force", missing a bundled short-flag cluster like "-qf" (quiet+force).
# Live-verified bypass: this discarded uncommitted work with no gate block.
test_deny "$IRRECOVERABLE" "git checkout -qf bundled force flag (was a bypass)" \
  "$(bash_payload 'git checkout -qf other-branch')"
test_deny "$IRRECOVERABLE" "git switch -fq bundled force flag (was a bypass)" \
  "$(bash_payload 'git switch -fq other-branch')"
# The fix scans bundled clusters for "f" but must stop at a value-taking flag
# letter (checkout's -b/-B, switch's -c/-C) so the branch-name argument
# itself isn't misread as more bundled flags.
test_allow "$IRRECOVERABLE" "git checkout -bfoo (branch name starting with f, must not over-block)" \
  "$(bash_payload 'git checkout -bfoo')"
test_allow "$IRRECOVERABLE" "git switch -cfoo (branch name starting with f, must not over-block)" \
  "$(bash_payload 'git switch -cfoo')"
test_allow "$IRRECOVERABLE" "git checkout -Bfoo (uppercase stop-char variant, must not over-block)" \
  "$(bash_payload 'git checkout -Bfoo')"
test_allow "$IRRECOVERABLE" "git switch -Cfoo (uppercase stop-char variant, must not over-block)" \
  "$(bash_payload 'git switch -Cfoo')"
# 2026-08-06: a HEREDOC-authored commit message (this repo's own documented
# convention) that merely mentions "git checkout X Y" in prose was tokenized
# as a real command and falsely denied -- reproduced live during this
# repo's own commit for v0.68.205. The first fix (strip quoted-delimiter
# heredoc bodies before scanning) introduced its own regression, caught by
# the second test below: a heredoc feeding an interpreter (bash <<EOF) is
# executable code, not inert prose, and must stay scannable.
test_allow "$IRRECOVERABLE" "quoted-delimiter heredoc body mentioning checkout no longer false-blocks" \
  "$(bash_payload $'git commit -m "$(cat <<\'EOF\'\nthis mentions git checkout old new extra in prose\nEOF\n)"')"
test_deny "$IRRECOVERABLE" "dangerous cmd inside a heredoc feeding an interpreter still blocked" \
  "$(bash_payload $'bash <<EOF\nrm -rf /tmp/danger\nEOF')"
# 2026-07-03 audit: newline and '&' are command separators in bash but shlex
# ate newline as whitespace and '&' wasn't in OPERATORS — a dangerous command
# after either hid inside the first command's window. Also --force-with-lease
# (the safe variant) was caught by the --force prefix match.
test_deny  "$IRRECOVERABLE" "dangerous cmd after newline" \
  "$(bash_payload $'echo hi\nrm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "dangerous cmd after & (background)" \
  "$(bash_payload 'echo done & rm -rf /tmp/x')"

# 2026-09-03: comment-aware continuation fix. A "#" comment already ends
# at the literal newline in real bash no matter what precedes it, but the
# old _newlines_to_seps treated EVERY backslash-newline as a protected
# continuation, even one sitting inside a comment -- so "git status #
# comment \" + newline + "git push origin develop --force" glued the
# second (real, dangerous) command onto the first (inert, comment)
# window and it was never checked. Confirmed live as a bypass before
# this fix: exit 0, no deny reason, even though real bash runs both
# commands. Adjacent shapes locked down alongside the exact repro so a
# narrow patch cannot re-open the same hole from a slightly different
# angle.
test_deny  "$IRRECOVERABLE" "backslash-newline inside a # comment does not hide the next real command (exact repro)" \
  "$(bash_payload $'git status # comment \\\ngit push origin develop --force')"
test_deny  "$IRRECOVERABLE" "same shape, comment with no trailing backslash (pre-existing case, must stay denied)" \
  "$(bash_payload $'git status # comment\ngit push origin develop --force')"
test_deny  "$IRRECOVERABLE" "real backslash-newline continuation (no comment) still joins tokens for detection" \
  "$(bash_payload $'git push --force \\\n  origin develop')"
test_allow "$IRRECOVERABLE" "legit backslash-newline continuation outside a comment still allows (no false split)" \
  "$(bash_payload $'git log --oneline \\\n  -5')"

# GH #122: a backslash-newline continuation with NO leading whitespace on the
# continuation line bypassed force-push detection. Real bash removes the
# backslash AND the newline entirely (line-continuation), joining the two
# physical lines with nothing between them -- so "git push \" + newline +
# "--force origin develop" is, to bash, identical to one clean line
# "git push --force origin develop". The old _newlines_to_seps left the
# newline character attached to whatever followed instead of fully removing
# it; shlex then glued that residual "\n" onto the very next token, producing
# "\n--force" instead of "--force", which the exact-match force-push check
# (`t in ("-f", "--force")`) missed. Confirmed live 2026-09-03: exit 0
# (allowed) before this fix. The whitespace-present sibling above already
# worked and stays a live control for the same case.
test_deny  "$IRRECOVERABLE" "backslash-newline continuation with NO leading whitespace on the next line (exact repro, was a bypass)" \
  "$(bash_payload $'git push \\\n--force origin develop')"
test_deny  "$IRRECOVERABLE" "same shape, leading whitespace on the next line (already worked, stays denied)" \
  "$(bash_payload $'git push \\\n  --force origin develop')"
# Adjacent shapes a narrow patch could still miss: back-to-back
# whitespace-less continuations gluing two flags together with nothing
# between them (true bash also glues here -- no separator survives), a
# continuation immediately followed by another continuation before any
# real content, and a continuation as the very last two characters of the
# whole command (no crash, no false deny -- there is no dangerous token).
test_deny  "$IRRECOVERABLE" "two whitespace-less continuations back to back, force flag glued onto the second (adjacent-shape check)" \
  "$(bash_payload $'git push origin\\\ndevelop --for\\\nce')"
test_allow "$IRRECOVERABLE" "trailing whitespace-less continuation at the very end of the command, nothing after it (no crash, no dangerous token)" \
  "$(bash_payload $'git push origin develop\\\n')"
# The DQ-quoted branch of _newlines_to_seps had the identical unremoved-
# newline defect for a continuation inside a double-quoted string (bash
# strips backslash-newline there too) -- fixed alongside the unquoted case
# since it is the same defect shape in the same function.
test_deny  "$IRRECOVERABLE" "whitespace-less continuation inside a double-quoted flag still reassembles (adjacent-shape check)" \
  "$(bash_payload $'git push "--for\\\nce" origin develop')"
test_deny  "$IRRECOVERABLE" "trailing # comment on the same line does not hide the command before it" \
  "$(bash_payload 'git push origin develop --force # not a real flag, just a comment')"

# ANSI-C ($'...') quoting resolves escape sequences in real bash -- $'\x74'
# literally IS the character "t", so "gi$'\x74'" IS "git" once bash evaluates
# it, same zero-width-splice family as the backtick/$(...)/${x} bypasses
# tested under the fast-path section below, but this one survives even the
# real python3 tokenizer (shlex has no concept of $'...' quoting and splits
# on the bare $ instead of treating the whole span as one token). Fix is
# _normalize_ansi_c_quotes, composed BEFORE _newlines_to_seps (same relative
# order verifier-protect.sh uses for its own same-named function) since
# _newlines_to_seps own quote tracking would otherwise toggle on the bare
# quote inside $'\x74' first and silently no-op the normalization. Note this
# file own version actually RESOLVES the escape (\x74 -> "t") rather than
# just re-quoting it -- a boundary-only port (verifier-protect.sh own
# version, sufficient for its write-target scanner) leaves argv0 as the
# literal token "gi\x74", which can never equal "git" under this file own
# exact-string argv0 checks; proven live 2026-09-03 with the token dump
# ['gi\\x74', 'push', '--force', ...] before the escape-resolving version was
# written. Confirmed live: rc=0 (allowed) before either fix.
test_deny "$IRRECOVERABLE" "ANSI-C quoted argv0 splice (gi\$'\x74' push --force, was a bypass)" \
  "$(bash_payload "gi\$'\\x74' push --force origin develop")"
# Negative control 1: an ordinary single-quoted argument (no \$'...' form,
# never enters the ANSI-C regex at all) must stay correctly classified --
# not a force-push, must still allow.
test_allow "$IRRECOVERABLE" "ordinary single-quoted commit message unaffected by ANSI-C normalization" \
  "$(bash_payload "git commit -m 'a normal message'")"
# Negative control 2: a REAL \$'...' payload that DOES enter the new decode
# path -- a commit message with an embedded \n escape. Must both (a) not
# false-deny (a plain commit is not a dangerous pattern) and (b) not get
# window-split: the decoded newline must stay INSIDE the returned quoted
# span, or _newlines_to_seps below would read it as a real statement
# separator and split one "git commit -m \$'...'" window into two.
test_allow "$IRRECOVERABLE" "ANSI-C commit message with embedded \\n stays one window, not force-push (real decode-path exercise)" \
  "$(bash_payload $'git commit -m $\'line1\\nline2\'')"

# GH #129: a command-substitution splice (backtick or \$(...)) vanishes in
# real bash once its output splices into the surrounding text -- \`gi\`true\`t\`
# IS \`git\` once bash evaluates it -- but until now it survived shlex
# tokenization as literal characters, splitting the argv0/subcommand apart
# and evading every exact-match check below. Fixed via a placeholder pass
# (_blank_substitutions) that blanks the substitution span to one byte
# BEFORE shlex runs, then re-fuses it into the surrounding token via
# lex.wordchars, then duplicate-classifies any FINAL argv0/subcommand that
# still carries the placeholder across every candidate name the downstream
# checks actually dispatch on (KNOWN_DANGEROUS / KNOWN_GIT_SUBS) instead of
# trusting the garbled literal. See hooks/gates/irrecoverable.sh for the
# full mechanism comment.
test_deny "$IRRECOVERABLE" "argv0-level backtick splice (gi\`true\`t push --force, GH #129)" \
  "$(bash_payload 'gi`true`t push --force origin develop')"
test_deny "$IRRECOVERABLE" "git-subcommand-level backtick splice (git pu\`true\`sh --force, clean argv0 but spliced sub, GH #129)" \
  "$(bash_payload 'git pu`true`sh --force')"
test_deny "$IRRECOVERABLE" "argv0-level \$(...) splice, different KNOWN_DANGEROUS candidate (gi\$(true)t reset --hard, GH #129)" \
  "$(bash_payload 'gi$(true)t reset --hard')"
# Negative controls: the duplication must not over-deny.
test_allow "$IRRECOVERABLE" "substitution in an ARGUMENT, not the dispatch token (ls \$(pwd)) -- argv0 stays clean, never enters duplication" \
  "$(bash_payload 'ls $(pwd)')"
test_allow "$IRRECOVERABLE" "substitution IS the whole dispatch token but resolves to a benign subcommand (\$(which git) status)" \
  "$(bash_payload '$(which git) status')"
test_allow "$IRRECOVERABLE" "substitution IS the dispatch token, candidate set has no dangerous match (\$(command -v ls) -la)" \
  "$(bash_payload '$(command -v ls) -la')"
test_allow "$IRRECOVERABLE" "argv0-level \$(...) splice resolving to a benign git subcommand (gi\$(true)t status, proves duplication does not over-deny)" \
  "$(bash_payload 'gi$(true)t status')"
test_allow "$IRRECOVERABLE" "ordinary bare \$VAR usage stays untouched by the placeholder pass (git push \$REMOTE \$BRANCH)" \
  "$(bash_payload 'git push $REMOTE $BRANCH')"
# advisor-caught regression (same GH #129 fix): blanking a substitution SPAN
# must not DISCARD its body. Before this whole fix, \$(...) content sat
# between the "(" / ")" operators (both in OPERATORS), so it was split into
# its OWN window and scanned like any other command -- \`\$(git push --force)\`
# already denied today. A blank-only placeholder pass would erase that body
# instead of just fusing the splice, silently turning a working deny into an
# allow. Fix: _blank_substitutions collects each backtick/\$(...) body (not
# \${...} -- that is a parameter expansion, not a command) as it blanks the
# span, then re-appends the collected bodies as extra ";"-joined statements
# so they still land in their own window downstream.
test_deny "$IRRECOVERABLE" "substitution BODY is the dangerous command, not just the dispatch token (echo \$(git push --force), was silently allowed by a blank-only pass)" \
  "$(bash_payload 'echo $(git push --force)')"
test_allow "$IRRECOVERABLE" "re-appended substitution body is ordinary commit-message prose, not a command (git commit -m \"\$(cat msg.txt)\") -- proves body re-append does not false-deny" \
  "$(bash_payload 'git commit -m "$(cat msg.txt)"')"
# advisor-caught second regression, found live in THIS session when a test
# script literally containing this shape tripped the just-fixed gate on
# itself: a SINGLE-quoted \$(...) span is inert in real bash (single quotes
# suppress every expansion), but the body-append fix above has no notion of
# quoting and would extract "git push --force" from inside the quotes
# anyway, manufacturing a live-looking statement out of prose and denying a
# harmless commit message. Fixed by matching a whole SQ...SQ span as its
# own regex alternative FIRST, so it is consumed and passed through
# unchanged before any substitution alternative can match inside it.
# DOUBLE-quoted substitutions must NOT get this treatment -- bash really
# does expand \$(...) inside double quotes, so a double-quoted splice stays
# a live vector and must still be caught.
test_allow "$IRRECOVERABLE" "single-quoted \$(...) is inert prose, must not be extracted and re-denied (git commit -m single-quote prose mentioning \$(git push --force))" \
  "$(bash_payload "git commit -m 'prose mentioning \$(git push --force)'")"
test_deny "$IRRECOVERABLE" "double-quoted argv0 splice stays a live vector, not given the single-quote passthrough (\"gi\$(true)t\" push --force)" \
  "$(bash_payload '"gi$(true)t" push --force')"

# Adversarial-review follow-up on the GH #129 fix (two bugs, 2026-09-03):
#
# Bug 1 (critical bypass): an unbalanced quote inside a blanked
# substitution BODY (a single apostrophe is enough) makes the shlex
# construction below raise ValueError. The old except handler fell back to
# tokenizing cmd.split() on the RAW, PRE-BLANKING string -- PH was never in
# it, so a spliced argv0 like this can never equal "git" and the whole
# GH #129 mechanism went inert, ALLOWing a real `git push --force` once
# bash evaluates the inner failing subshell to empty. Fixed by denying
# closed on that parse failure instead of guessing at a raw fallback.
test_deny "$IRRECOVERABLE" "backtick splice with an apostrophe inside the body defeats the old raw cmd.split() fallback (gi\`it's\`t push --force, was silently ALLOWed)" \
  "$(bash_payload $'gi`it\'s`t push --force')"
test_deny "$IRRECOVERABLE" "\$(...) splice with an apostrophe inside the body, same bypass shape (gi\$(it's)t push --force, was silently ALLOWed)" \
  "$(bash_payload $'gi$(it\'s)t push --force')"

# Bug 2 (false-DENY): the KNOWN_DANGEROUS/KNOWN_GIT_SUBS candidate
# duplication runs every candidate's check against the SAME rest/scan
# tokens, and two of those checks were bare letter-containment against a
# whole joined-flags string rather than a real flag-boundary test -- so an
# ordinary long flag whose plain-English spelling happens to contain the
# right letters tripped them. Fixed by requiring an exact long-option match
# ("--recursive"/"--force") or a genuinely short bundled cluster before
# counting a letter.
test_allow "$IRRECOVERABLE" "substitution dispatch token resolving to a benign command, long flag falsely read as rm -rf (\$(which node) --before=1, was a false DENY)" \
  "$(bash_payload '$(which node) --before=1')"
test_allow "$IRRECOVERABLE" "git diff splice, long flag falsely read as git clean -f (git di\$(true)ff --find-renames, was a false DENY)" \
  "$(bash_payload 'git di$(true)ff --find-renames')"
test_allow "$IRRECOVERABLE" "git show splice, long flag falsely read as git clean -f (git sh\$(true)ow --format=fuller, was a false DENY)" \
  "$(bash_payload 'git sh$(true)ow --format=fuller')"

# Second adversarial-review follow-up (2026-09-03): the _SQ_SPAN regex used
# to detect inert single-quoted text paired literal apostrophe CHARACTERS
# wherever they fell, with zero notion of real shell quote state. An
# ordinary English contraction sitting inside a DOUBLE-quoted string (its
# apostrophe is not a real shell quote boundary at all) shifted the
# pairing in both directions. Fixed by replacing the regex with a real
# left-to-right quote-state scan (same technique _newlines_to_seps already
# uses above).
test_deny "$IRRECOVERABLE" "contraction apostrophes inside double quotes pair up ACROSS a real \$(...) splice, hiding it as inert single-quoted data (was a live bypass)" \
  "$(bash_payload $'echo "it\'s" ; gi$(true)t push --force ; echo "isn\'t"')"
test_allow "$IRRECOVERABLE" "same stray contraction apostrophe shifts pairing so a REAL single-quoted -m argument is no longer matched as one span (was a false DENY of inert commit-message text)" \
  "$(bash_payload $'echo "it\'s" ; git commit -m \'see $(git push --force)\'')"

# Independent-review finding, 2026-09-03: distinct from and broader than the
# already-accepted "--for<PH>ce" residual documented above (PH landing
# INSIDE an already-dash-prefixed flag, which garbles the spelling but keeps
# the flag SHAPE recognizable). This one erases the flag shape entirely --
# a command substitution resolving to empty at runtime splices directly
# onto whatever follows in real bash ("$(true)-rf" IS "-rf"), but the
# placeholder pass leaves a non-empty PH byte glued to the front of the
# dash instead, producing a token like "PH-rf" that no longer even STARTS
# WITH "-" -- so every flag-detection check that tests startswith("-") or
# an exact dash-prefixed string missed it entirely and silently ALLOWed.
# Fixed by stripping a leading placeholder before every such check (rm -rf,
# find -exec/-execdir/-delete, git --no-verify/hooksPath, and every git
# sub == "..." branch that reads from `scan`: push/reset/clean/restore/
# checkout/switch/branch/commit/add).
test_deny "$IRRECOVERABLE" "empty-substitution splice hides rm -rf's dash (rm \$(true)-rf /tmp/x, was silently ALLOWed)" \
  "$(bash_payload 'rm $(true)-rf /tmp/x')"
test_deny "$IRRECOVERABLE" "same bug via backticks (rm \`true\`-rf /tmp/x, was silently ALLOWed)" \
  "$(bash_payload 'rm `true`-rf /tmp/x')"
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git push --force's dashes (git push \$(true)--force, was silently ALLOWed)" \
  "$(bash_payload 'git push $(true)--force')"
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git clean -f's dash (git clean \$(true)-f, was silently ALLOWed)" \
  "$(bash_payload 'git clean $(true)-f')"
# Negative control: the substitution sits inside a QUOTED ARGUMENT VALUE
# (a real -m message), not in flag position -- the existing -m/--message
# value-skip logic empties `scan` before the new lstrip(PH) pass ever runs,
# so this must stay ALLOW, proving the fix does not turn commit-message
# prose into a false deny.
test_allow "$IRRECOVERABLE" "substitution inside a quoted -m message value, not a bare flag position (git commit -m \"\$(cat msg.txt)\") -- must stay ALLOW" \
  "$(bash_payload 'git commit -m "$(cat msg.txt)"')"

# GH #139 (2026-09-04): the $(...)/${...} closer-search used to scan forward
# for the FIRST "(" or ")" byte and treat that as the terminator -- not
# depth-aware, so a paren nested INSIDE the span (a subshell or function
# definition) aborted the match early, leaving the true end of the span
# un-blanked. "gi$(f() { :; }; f)t push --force" really runs as
# "git push --force" (the function body is a no-op, so the substitution
# resolves to empty), but pre-fix the un-blanked "(", ")", "{", "}" bytes
# fragment the shlex tokenization so no window's argv0 ever reads "git" --
# a total silent bypass, confirmed live: rc=0 (allow) before this fix.
# Fixed by depth-counting same-type brackets in the closer-search (same
# technique main-exec-guard.sh's own _inner_cmds already uses).
test_deny "$IRRECOVERABLE" "nested function-construct inside \$(...) defeats the old first-byte closer-search, real bash resolves to git push --force (GH #139, was a silent bypass)" \
  "$(bash_payload 'gi$(f() { :; }; f)t push --force origin develop')"

# Companion DoS check for the same fix: depth-counting a closer-search that
# never balances (an adversarial flood of unclosed "$(" starts) must stay
# bounded by a work budget instead of costing O(remaining length) PER
# start -- O(n^2) total. Measured pre-budget: 65s for a 100,000-char flood,
# well under this file's own 150,000-char total-length cap. Budget
# exhaustion alone is NOT safe to read as "no dangerous token found, allow":
# that fallback path leaves the span un-blanked, the exact bypass shape
# GH #139 closed, so an adversary could pad a real dangerous command with
# just enough flood to burn the budget and hide the payload again. Fixed by
# a _DEPTH_BUDGET_BLOWN flag that forces the fail-closed deny outcome
# instead -- so this must complete fast AND deny.
DEPTH_FLOOD_CMD=$(python3 -c 'print("$(" * 50000)')
depth_flood_start=$(date +%s)
depth_flood_out=$(bash_payload "$DEPTH_FLOOD_CMD" | timeout 10 bash "$IRRECOVERABLE" 2>/dev/null)
depth_flood_rc=$?
depth_flood_elapsed=$(( $(date +%s) - depth_flood_start ))
if [[ "$depth_flood_rc" == "2" ]] && [ "$depth_flood_elapsed" -le 10 ]; then
  echo "  ✅ DENY: 50,000x unclosed \"\$(\" flood completes within a generous ceiling (GH #139 fail-closed budget-exhaustion fix)"
  pass=$((pass + 1))
else
  echo "  ❌ depth-scan work-budget expected fast deny but got rc=$depth_flood_rc elapsed=${depth_flood_elapsed}s out='$depth_flood_out'" >&2
  fail=$((fail + 1))
fi

# GH #129 follow-up (2026-09-03): an adversarial review found the leading-PH
# fix above was applied to some checks but not others, and a third bug class
# (Layer 3 -- a standalone vanish token, not glued to anything, shifts every
# later token left one position, same as real bash word-splitting, but the
# PH-only token stays in place here) had never been tested in this file.
# (The worktree-doctrine splice cases that used to live here went with the
# worktree block itself, v1.0.0 rebuild.)
# Adversarial-review find (2026-09-03): the SUBCOMMAND token itself (args[0]
# == "add") was also compared by exact match, never lstrip(PH)-ed, a
# distinct gap from the -b flag splice tested above -- a splice glued to
# "add" bypassed the single-branch doctrine gate entirely.
# Same review, sibling gap: git stash drop/clear compared args[0] by exact
# match too, never lstrip(PH)-ed.
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git stash drop (git stash \$(true)drop, was silently ALLOWed)" \
  "$(bash_payload 'git stash $(true)drop')"
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git stash clear (git stash \$(true)clear, was silently ALLOWed)" \
  "$(bash_payload 'git stash $(true)clear')"
test_deny "$IRRECOVERABLE" "baseline: plain git stash drop, no splice at all (must still deny)" \
  "$(bash_payload 'git stash drop')"
test_deny "$IRRECOVERABLE" "baseline: plain git stash clear, no splice at all (must still deny)" \
  "$(bash_payload 'git stash clear')"
# Documented non-goal, unaffected by the leading-splice fix above: a splice
# landing MID-WORD, not glued to the leading position (e.g. git stash
# dr$(true)op), stays outside this check own scope and stays ALLOW either
# way. Not encoded as its own test_allow here -- differential testing (this
# fix present vs. reverted) shows the suite passes identically for that
# shape either way, so a test for it would not distinguish buggy from fixed
# behavior (test-honesty "distinguishes-or-it-doesn't" rule; same call
# already made for the bare-vanish-at-argv0 shape a few hundred lines up in
# the sibling worktree-guard test file).
# --- Layer 2: dd of= and destructive SQL, neither was lstrip(PH)-ed ---
test_deny "$IRRECOVERABLE" "empty-substitution splice hides dd's of=/dev/ prefix (was silently ALLOWed)" \
  "$(bash_payload 'dd if=/dev/zero $(true)of=/dev/sda')"
test_deny "$IRRECOVERABLE" "baseline: plain dd of=/dev, no splice (must still deny)" \
  "$(bash_payload 'dd if=/dev/zero of=/dev/sda')"
test_deny "$IRRECOVERABLE" "splice lands mid-keyword in a destructive SQL statement (DR\$(true)OP TABLE, was silently ALLOWed -- the old check only handled a LEADING splice, not one INSIDE a keyword)" \
  "$(bash_payload 'mysql -e "DR$(true)OP TABLE users"')"
test_deny "$IRRECOVERABLE" "baseline: plain destructive SQL, no splice (must still deny)" \
  "$(bash_payload 'mysql -e "DROP TABLE users"')"
# --- Layer 2, exhaustive-grep finds: the prefix-wrapper unwrap loops
# (env/nice/sudo/command/nohup/time) and the xargs/docker-exec re-pointing
# never stripped a leading PH from the flags they read either -- a disguised
# wrapper flag misreads itself as the wrapped command, leaving the REAL
# wrapped command (git, mysql, ...) misplaced one slot into `rest` where the
# position-sensitive worktree/stash checks never look for it (membership
# checks like rm -rf/push --force already tolerate this by accident; the
# fixed-index ones do not). Each pairs the splice with its already-passing
# no-splice baseline from the existing prefix-wrapper battery above.
test_deny "$IRRECOVERABLE" "docker exec flag splice defeats the inner-command re-point, hiding destructive SQL (docker exec \$(true)-i c1 mysql -e DROP TABLE, was silently ALLOWed)" \
  "$(bash_payload 'docker exec $(true)-i c1 mysql -e "DROP TABLE users"')"
test_deny "$IRRECOVERABLE" "docker exec-itself splice defeats the inner-command re-point, hiding destructive SQL (docker \$(true)exec c1 mysql -e DROP TABLE, was silently ALLOWed)" \
  "$(bash_payload 'docker $(true)exec c1 mysql -e "DROP TABLE users"')"
# --- Layer 3: a standalone unquoted vanish token shifts fixed-index reads.
# The worst case is the whole vanish landing right where argv0 would be
# (before "git" itself) -- "git" then ends up misplaced one slot into
# `rest`, and none of this file own git dispatch checks look there.
# Companion: a standalone vanish AFTER git, before the subcommand -- already
# safely denied today via this file own KNOWN_GIT_SUBS candidate duplication
# (the "restore" branch own broad any-nonflag-token condition happens to
# fire), locked in here as a regression test for the exact shape named in
# the fix review, not because it was ever a confirmed bypass.
# Negative control (Layer 3 must not over-deny): a standalone vanish
# resolving to something REAL, not empty, still shifts a token in the SAME
# way at the placeholder level -- but the compacted-window retry must not
# misfire into a false deny just because dropping that token leaves a
# shorter, still-benign list.
test_allow "$IRRECOVERABLE" "Layer 3 negative control: \$(which git) status -- compacted window drops argv0 entirely, must stay ALLOW" \
  "$(bash_payload '$(which git) status')"

# 2026-09-04 fresh-context review, 4 findings around _blank_substitutions
# and its inner _scan_once closure.
#
# Finding 1 (HIGH, live): appending recovered substitution bodies with a
# plain " ; " separator left no newline to terminate an earlier, still-open
# "#" comment -- shlex's default comment-stripping then ate everything
# appended after it, silently turning a real deny into an ALLOW. Fixed by
# leading each appended body with a real newline (same idiom
# _newlines_to_seps already uses for real newlines) so any open comment is
# terminated before the next window starts.
test_deny "$IRRECOVERABLE" "trailing comment after a live substitution buried the recovered body in an open shlex comment (echo \$(git push --force)  # push it, was silently ALLOWed)" \
  "$(bash_payload 'echo $(git push --force)  # push it')"
test_deny "$IRRECOVERABLE" "same bug via a # embedded inside an EARLIER recovered body (echo \$(echo hi # note) \$(git push --force), was silently ALLOWed)" \
  "$(bash_payload 'echo $(echo hi # note) $(git push --force)')"
test_deny "$IRRECOVERABLE" "baseline: same splice with no comment at all, no bug involved (must stay denied)" \
  "$(bash_payload 'echo $(git push --force)')"

# Finding 5 (MEDIUM, live, universal): _scan_once tracked in_squote/
# in_dquote but had no in_comment state, so a substitution-shaped string
# sitting INSIDE a real "#" comment still got matched, blanked, and its
# body collected as if it were live code -- a false DENY on an innocent
# command that real bash never executes. Fixed by porting the same
# in_comment state machine _newlines_to_seps above already uses: checked
# first in the loop, passthrough while active, ends at a literal newline.
test_allow "$IRRECOVERABLE" "a substitution-shaped fake payload sitting inside a real # comment must not be recovered as a live body (git status # see also: \$(git push --force), followed by a real newline and echo done, was a false DENY)" \
  "$(bash_payload $'git status # see also: $(git push --force)\necho done\n')"

# Finding 4 (MEDIUM, live): _blank_substitutions own closer-search for a
# backtick/\$(...)/\${...} span does not track quote state for characters it
# skips while hunting the terminator -- crossing a real quote character
# (ordinary interpreter-heredoc content full of curly braces can do this)
# silently desyncs in_squote/in_dquote for the rest of the scan, leaving the
# final string quote-unbalanced even though the ORIGINAL command was
# perfectly valid. Since commit c2722488 removed the old cmd.split()
# fallback in favor of a hard deny on ValueError, this could turn an
# ordinary read-only heredoc into a false DENY with no override. Fixed by
# re-parsing the ORIGINAL, pre-blanking cmd as a predicate on ValueError: if
# it parses cleanly, the corruption is self-inflicted by our own blanking
# pass, so fall back to a separator-aware split instead of hard-denying a
# benign command; if the original also fails to parse, it really is
# malformed and still denies.
test_allow "$IRRECOVERABLE" "read-only python3 heredoc with an unmatched \${ inside a properly-quoted string desyncs _blank_substitutions own quote tracking (was a false DENY with no override)" \
  "$(bash_payload $'python3 - <<\'PY\'\n "10k unmatched ${ (20KB)": "${ "*10000,\n}\nPY\n')"
# Negative control: a genuinely malformed command (unterminated quote, no
# _scan_once span involved at all) must still deny with the same message --
# proves the fix does not turn a real bypass back on.
test_deny "$IRRECOVERABLE" "genuinely malformed command, unterminated quote unrelated to any substitution span (must still deny)" \
  "$(bash_payload "echo 'unterminated")"
# Negative control: the two GH #129 apostrophe-in-body bypass tests already
# above (backtick/\$(...) splice with an apostrophe inside the recovered
# body) must still deny -- the ORIGINAL cmd has the same unbalanced
# apostrophe as the blanked one, so the re-parse predicate also fails and
# this still falls through to the hard deny, not a naive-split ALLOW.
test_deny "$IRRECOVERABLE" "Finding 4 fix must not reopen the GH #129 apostrophe-in-body bypass, backtick form (gi\`it's\`t push --force, must stay DENY)" \
  "$(bash_payload $'gi`it\'s`t push --force')"
test_deny "$IRRECOVERABLE" "Finding 4 fix must not reopen the GH #129 apostrophe-in-body bypass, \$(...) form (gi\$(it's)t push --force, must stay DENY)" \
  "$(bash_payload $'gi$(it\'s)t push --force')"

# Coordinator review, 2026-09-04: the Finding 4 fallback above first shipped
# as a bare whitespace-only cmd.split(), which is itself exploitable -- this
# file own punctuation_chars=True shlex path (a few lines above this whole
# block) exists specifically so a compound command's LATER segments (after
# ;/&&/||/|/&) each get their own window and argv0 check (see the
# "second command in the chain never had its own argv0 checked" comment
# there). A bare .split() has no separator awareness, so a dangerous
# command placed second in a chain, joined with NO surrounding whitespace
# around the separator, evaded detection entirely through the fallback --
# confirmed live: rc=0 ALLOW on a real force-push. Fixed by regex-splitting
# on the separator set first (keeping each separator its own token) before
# whitespace-splitting each segment, so the fallback tokens flow through
# the same per-window dispatch as the primary path instead of landing in
# one flat undivided window.
test_deny "$IRRECOVERABLE" "Finding 4 fallback must not glue a dangerous SECOND command onto its no-space ; separator (echo \${y:-\"a}b\"};git push --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"};git push --force')"
test_deny "$IRRECOVERABLE" "same bug via a no-space && separator (echo \${y:-\"a}b\"}&&git push --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"}&&git push --force')"
test_deny "$IRRECOVERABLE" "baseline: same compound command with the ; surrounded by whitespace, no bug involved (must stay denied)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; git push --force')"

# Coordinator review, 2026-09-04, second pass: the Finding 4 fallback tokens
# come straight from the ORIGINAL cmd, never through _blank_substitutions --
# so a spliced dispatch token reaching this file only through the fallback
# path (e.g. "gi\$(true)t") still carries its literal substitution syntax
# and never contains PH at all. The GH #129 splice-duplication trigger (both
# the argv0 site against KNOWN_DANGEROUS and the git-subcommand site against
# KNOWN_GIT_SUBS) was gated purely on "PH in ...", so a spliced token on the
# fallback path sailed through unrecognized -- confirmed live: a
# quote-crossing \${...} span forcing the fallback, followed by a spliced
# argv0 OR a spliced git subcommand, both exit 0 silent allow. Fixed by a
# new _has_raw_subst(t) helper (checks only for a literal backtick, "\$(",
# or "\${" in that one token -- deliberately narrower than this file own
# bash-level _has_subst fast-path guard, which also matches a bare "\$" and
# would misfire on an ordinary "\$PYTHON -m pytest"-shaped token) widening
# both duplication triggers.
test_deny "$IRRECOVERABLE" "Finding 4 fallback duplication trigger missed a spliced ARGV0 with no PH (echo \${y:-\"a}b\"} ; gi\$(true)t push --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; gi$(true)t push --force')"
test_deny "$IRRECOVERABLE" "same bug, spliced git SUBCOMMAND instead of argv0 (echo \${y:-\"a}b\"} ; git pu\$(true)sh --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; git pu$(true)sh --force')"
test_deny "$IRRECOVERABLE" "same argv0 bug with the dangerous command BEFORE the quote-crossing span (gi\$(true)t push --force ; echo \${y:-\"a}b\"}, was silently ALLOWed)" \
  "$(bash_payload 'gi$(true)t push --force ; echo ${y:-"a}b"}')"
test_deny "$IRRECOVERABLE" "same subcommand bug with the dangerous command BEFORE the quote-crossing span (git pu\$(true)sh --force ; echo \${y:-\"a}b\"}, was silently ALLOWed)" \
  "$(bash_payload 'git pu$(true)sh --force ; echo ${y:-"a}b"}')"
# Negative controls: the widened trigger must not over-deny once the
# fallback path is live -- a splice resolving to a BENIGN candidate must
# still allow, proving the duplication loop substitutes the candidate name
# for the downstream checks rather than pattern-matching the raw garbled
# literal.
test_allow "$IRRECOVERABLE" "fallback-path splice resolving to a benign git subcommand (echo \${y:-\"a}b\"} ; gi\$(true)t status, must stay ALLOW even though duplication tries argv0==git -- the quote-crossing span forces the fallback so this token never gets PH at all, only _has_raw_subst catches it)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; gi$(true)t status')"

# Second-reviewer systematic sweep, 2026-09-04: EVERY downstream PH-based
# check in the whole dispatch loop (prefix-wrapper unwrap, xargs/docker
# re-pointing, rm -rf, find -exec/-delete, the whole git push/reset/clean/
# restore/checkout/switch/branch/commit/add family via the one shared
# leading-strip, stash/worktree args[0] reads, the worktree -b/-B loop, dd
# of=, the SQL keyword match, and the Layer 3 standalone-vanish compaction)
# assumed its tokens either came from the primary, already-blanked path or
# carried no substitution syntax at all -- the Finding-4 fallback tokens
# come from cmd directly and never contained PH, so a raw splice reaching
# ANY of these sites only via the fallback path sailed through unrecognized
# the same way the two dispatch-duplication sites did before _has_raw_subst
# (confirmed live for each site below: rc=0 before, rc=2 after). Fixed at
# the root instead of one spelling at a time: the fallback now tokenizes
# the SAME _blank_substitutions/_newlines_to_seps/_normalize_ansi_c_quotes
# output the primary path already uses (safe to reuse even though that
# exact output is what raised ValueError on the primary shlex path -- this
# fallback never runs shlex, just a regex+whitespace split, neither of
# which cares whether quotes balance), so a real substitution on this path
# now carries PH into every downstream check exactly like the primary path.
FORCE_FALLBACK='echo ${y:-"a}b"} ; '
test_deny "$IRRECOVERABLE" "sweep: docker exec re-point splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}docker exec \$(true)-i c1 mysql -e \"DROP TABLE users\"")"
test_deny "$IRRECOVERABLE" "sweep: rm -rf leading-dash splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}rm \$(true)-rf /tmp/x")"
test_deny "$IRRECOVERABLE" "sweep: find -exec splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}find /tmp/x \$(true)-exec rm {} \\;")"
test_deny "$IRRECOVERABLE" "sweep: find -delete splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}find /tmp/x \$(true)-delete")"
test_deny "$IRRECOVERABLE" "sweep: git --no-verify splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}git commit \$(true)--no-verify -m msg")"
test_deny "$IRRECOVERABLE" "sweep: git push --force splice reaching scan, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}git push \$(true)--force origin develop")"
test_deny "$IRRECOVERABLE" "sweep: git clean -f splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}git clean \$(true)-f")"
test_deny "$IRRECOVERABLE" "sweep: git stash drop splice on args[0], fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}git stash \$(true)drop")"
test_deny "$IRRECOVERABLE" "sweep: dd of=/dev splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}dd if=/dev/zero \$(true)of=/dev/sda")"
test_deny "$IRRECOVERABLE" "sweep: SQL DROP mid-keyword splice, fallback path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}mysql -e \"DR\$(true)OP TABLE users\"")"
# Negative controls: the systemic fallback-blanking fix must not over-deny.
test_allow "$IRRECOVERABLE" "sweep neg: benign command after a forced fallback (must ALLOW)" \
  "$(bash_payload "${FORCE_FALLBACK}ls -la")"
test_allow "$IRRECOVERABLE" "sweep neg: git status after a forced fallback (must ALLOW)" \
  "$(bash_payload "${FORCE_FALLBACK}git status")"
test_allow "$IRRECOVERABLE" "sweep neg: git push safe after a forced fallback (must ALLOW)" \
  "$(bash_payload "${FORCE_FALLBACK}git push origin develop")"
test_allow "$IRRECOVERABLE" "sweep neg: commit message mentioning rm -rf, fallback path (must ALLOW)" \
  "$(bash_payload "${FORCE_FALLBACK}git commit -m \"docs: warn against rm -rf\"")"

# Third cross-file review, 2026-09-04: a PH/raw-subst splice landing MID-FLAG
# (not leading) defeated every flag-recovery check written as
# "t.lstrip(PH) == '--force'" -- lstrip only strips from the very front of a
# string, so a placeholder byte sitting in the MIDDLE of the token (e.g.
# --for<PH>ce) left the comparison false forever, the same flag silently
# never recognized. Confirmed live at HEAD before this fix: --for$(true)ce,
# --har$(true)d, and --am$(true)end all exit 0 (silent allow) on git
# push/reset/commit respectively -- a real force-push/hard-reset/amend
# bypass, pre-existing, not introduced this session. Root cause is the same
# class already closed at the dispatch-duplication sites (PH/raw-subst
# checked via _has_raw_subst) and at the SQL-keyword check (already using
# full removal) -- fixed here by porting that same treatment
# (str.replace(PH, "") instead of str.lstrip(PH)) to every flag-recovery
# site, so a placeholder anywhere in the token is removed before comparison,
# not just a leading one. Also corrected a stale comment (~line 397) that
# had claimed mid-flag splicing was an accepted out-of-scope non-goal that
# "stays recognizable as a flag" -- that claim was factually wrong per the
# live bypasses just confirmed.
test_deny "$IRRECOVERABLE" "mid-flag splice, git push --force (--for\$(true)ce, was silently ALLOWed)" \
  "$(bash_payload 'git push --for$(true)ce origin develop')"
test_deny "$IRRECOVERABLE" "mid-flag splice, git reset --hard (--har\$(true)d, was silently ALLOWed)" \
  "$(bash_payload 'git reset --har$(true)d HEAD~1')"
test_deny "$IRRECOVERABLE" "mid-flag splice, git commit --amend (--am\$(true)end, was silently ALLOWed)" \
  "$(bash_payload 'git commit --am$(true)end -m x')"
test_deny "$IRRECOVERABLE" "mid-flag splice reaches the flag check via the fallback path too, not just the primary shlex path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}git push --for\$(true)ce origin develop")"
# Negative controls: the same flags with no splice at all must stay denied
# exactly as before -- str.replace(PH, "") on a token with no PH byte is a
# no-op, so this proves the fix is a strict widening, not a behavior change
# for the already-working case.
test_deny "$IRRECOVERABLE" "baseline: plain --force with no splice still denies (unaffected by the fix)" \
  "$(bash_payload 'git push --force origin develop')"
test_deny "$IRRECOVERABLE" "baseline: plain --hard with no splice still denies (unaffected by the fix)" \
  "$(bash_payload 'git reset --hard HEAD~1')"
test_deny "$IRRECOVERABLE" "baseline: plain --amend with no splice still denies (unaffected by the fix)" \
  "$(bash_payload 'git commit --amend -m x')"

test_allow "$IRRECOVERABLE" "git push --force-with-lease (safe variant)" \
  "$(bash_payload 'git push --force-with-lease origin develop')"
test_allow "$IRRECOVERABLE" "git push --force-with-lease with refspec (still safe)" \
  "$(bash_payload 'git push --force-with-lease=main:12345 origin develop')"
test_allow "$IRRECOVERABLE" "git push normal (no force)" \
  "$(bash_payload 'git push origin develop')"

# v0.36.0 audit: a leading git GLOBAL flag (-C/-c/--git-dir/--work-tree/
# --config-env, bare or combined -Cpath/--git-dir=path) set sub to the flag
# itself, so the push/worktree/--no-verify gates were bypassable by prefixing
# it. Also --no-verify was checked outside the per-window loop against the
# loop-leak `tokens` (last line only), so a multi-line --no-verify on an
# earlier line slipped past. And git restore (.) / checkout <tree> <file>
# had no destructive-form coverage.
test_deny "$IRRECOVERABLE" "git -C /repo push --force (global-flag bypass)" \
  "$(bash_payload 'git -C /repo push --force origin develop')"
test_deny "$IRRECOVERABLE" "git -Cpath push --force (combined -C)" \
  "$(bash_payload 'git -C/repo push --force origin develop')"
test_deny "$IRRECOVERABLE" "git --no-pager push --force (non-value global)" \
  "$(bash_payload 'git --no-pager push --force origin develop')"
test_deny "$IRRECOVERABLE" "git -c key=val push --force (value global -c)" \
  "$(bash_payload 'git -c core.foo=bar push --force origin develop')"
test_allow "$IRRECOVERABLE" "git -C /repo status (global flag, safe sub)" \
  "$(bash_payload 'git -C /repo status')"
test_allow "$IRRECOVERABLE" "git -C /repo log (no sub after globals→no-op safe)" \
  "$(bash_payload 'git -C /repo')"
test_deny "$IRRECOVERABLE" "--no-verify on earlier line (multiline bypass)" \
  "$(bash_payload $'echo staging\ngit commit --no-verify -m msg')"
test_allow "$IRRECOVERABLE" "echo --no-verify (git-specific, no false positive)" \
  "$(bash_payload 'echo --no-verify is a git flag')"
test_deny "$IRRECOVERABLE" "git restore . (discards worktree)" \
  "$(bash_payload 'git restore .')"
test_deny "$IRRECOVERABLE" "git restore -- file (discards worktree)" \
  "$(bash_payload 'git restore -- file.txt')"
test_deny "$IRRECOVERABLE" "git restore file (pathspec, no branch ambiguity)" \
  "$(bash_payload 'git restore src/index.ts')"
test_deny "$IRRECOVERABLE" "git restore --worktree file (explicit worktree mode)" \
  "$(bash_payload 'git restore --worktree file.txt')"
test_deny "$IRRECOVERABLE" "git restore --staged --worktree file (worktree touched)" \
  "$(bash_payload 'git restore --staged --worktree file.txt')"
test_allow "$IRRECOVERABLE" "git restore --staged file (index-only, recoverable)" \
  "$(bash_payload 'git restore --staged file.txt')"
test_allow "$IRRECOVERABLE" "git restore --staged . (un-stage all, recoverable)" \
  "$(bash_payload 'git restore --staged .')"
test_allow "$IRRECOVERABLE" "git restore --staged (no pathspec, no-op)" \
  "$(bash_payload 'git restore --staged')"
test_deny "$IRRECOVERABLE" "git checkout HEAD~1 file (tree-ish + path)" \
  "$(bash_payload 'git checkout HEAD~1 src/index.ts')"
test_allow "$IRRECOVERABLE" "git checkout main (1 nonflag = branch switch)" \
  "$(bash_payload 'git checkout main')"

# 2026-08-23 mutation-testing probe (docs/research/mutation-probe-results-2026-08-23.md):
# the gate correctly denies each idiom below TODAY, but no test held the deny path,
# so a mutation to the wrapper-unwrap / hooksPath / branch-delete / backstop logic
# survived the whole suite (fail-open, undetected). These lock the current behavior.
# --- prefix-wrapper unwrap: a destructive command hidden behind sudo/env/nice/xargs/docker ---
test_deny  "$IRRECOVERABLE" "sudo rm -rf (wrapper unwrap)" \
  "$(bash_payload 'sudo rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "sudo -u <user> rm -rf (issue #115: value-taking flag bypass)" \
  "$(bash_payload 'sudo -u alice rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "sudo --user=<user> rm -rf (issue #115, = form)" \
  "$(bash_payload 'sudo --user=alice rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "env VAR=val rm -rf (env-assignment wrapper)" \
  "$(bash_payload 'env FOO=1 rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "env -u VAR rm -rf (env-unset-flag wrapper)" \
  "$(bash_payload 'env -u FOO rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "nice -n 5 rm -rf (nice with value flag)" \
  "$(bash_payload 'nice -n 5 rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "nice rm -rf (bare nice wrapper)" \
  "$(bash_payload 'nice rm -rf /tmp/x')"

# --- operator-glue / grouping-token bypass (deep-audit 2026-08-28): shlex.split()
# without punctuation_chars requires whitespace around ;/&&/|| /| /& to see them
# as separators, so "echo hi;rm -rf x" tokenized as one glued word "hi;rm" and
# the second command's argv0 was never checked. Same fix also closes subshell/
# brace grouping, which hid argv0 behind a bare "(" or "{" token. ---
test_deny  "$IRRECOVERABLE" "glued semicolon, no space (was a bypass)" \
  "$(bash_payload 'echo hi;rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "glued &&, no space (was a bypass)" \
  "$(bash_payload 'echo hi&&rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "glued pipe, no space (was a bypass)" \
  "$(bash_payload 'echo hi|rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "subshell wrap, no space (was a bypass)" \
  "$(bash_payload '(rm -rf /tmp/x)')"
test_deny  "$IRRECOVERABLE" "brace group (was a bypass)" \
  "$(bash_payload '{ rm -rf /tmp/x; }')"
test_allow "$IRRECOVERABLE" "quoted semicolon stays literal (must not over-block)" \
  "$(bash_payload 'git commit -m "a;b"')"
test_deny  "$IRRECOVERABLE" "sudo -nu <user> bundled short flags (was a bypass)" \
  "$(bash_payload 'sudo -nu alice rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "sudo -Sku <user> bundled short flags (was a bypass)" \
  "$(bash_payload 'sudo -Sku alice rm -rf /tmp/x')"
test_allow "$IRRECOVERABLE" "sudo -un <user>: u's value is the attached 'n', alice is the real wrapped cmd (must not over-block)" \
  "$(bash_payload 'sudo -un alice rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "xargs rm -rf (rm via xargs)" \
  "$(bash_payload 'echo /tmp/x | xargs rm -rf')"
test_deny  "$IRRECOVERABLE" "docker exec CONTAINER rm -rf (unwrap inner destructive)" \
  "$(bash_payload 'docker exec c1 rm -rf /data')"
# --- git -c core.hooksPath= : the --no-verify-equivalent hook bypass ---
test_deny  "$IRRECOVERABLE" "git -c core.hooksPath= (hook bypass, space form)" \
  "$(bash_payload 'git -c core.hooksPath=/tmp/evil commit -m x')"
test_deny  "$IRRECOVERABLE" "git -ccore.hooksPath= (hook bypass, joined form)" \
  "$(bash_payload 'git -ccore.hooksPath=/tmp/evil commit -m x')"
test_allow "$IRRECOVERABLE" "git -c user.name= (benign -c config, must not over-block)" \
  "$(bash_payload 'git -c user.name=x commit -m y')"
# --- git branch force-delete: discards unmerged commits ---
test_deny  "$IRRECOVERABLE" "git branch -D (force-delete short flag)" \
  "$(bash_payload 'git branch -D featurex')"
test_deny  "$IRRECOVERABLE" "git branch --delete --force (long-flag force-delete)" \
  "$(bash_payload 'git branch --delete --force featurex')"
test_deny  "$IRRECOVERABLE" "git branch -fD (bundled force-delete flags)" \
  "$(bash_payload 'git branch -fD featurex')"
test_allow "$IRRECOVERABLE" "git branch newbranch (create, must not over-block)" \
  "$(bash_payload 'git branch newbranch')"
test_allow "$IRRECOVERABLE" "git branch featureD (name containing D, must not over-block)" \
  "$(bash_payload 'git branch featureD')"
# --- fail-closed internal-error backstop (irrecoverable.sh:431-433): a payload that makes the
# Python raise (command is a JSON array, not a string) must still exit 2, never fall open. ---
test_deny  "$IRRECOVERABLE" "non-string command payload triggers the fail-closed backstop (exit 2, not fail-open)" \
  '{"tool_name":"Bash","tool_input":{"command":["rm","-rf","/x"]}}'

# --- GH #140: unbounded shlex tokenize cost on an oversized raw command
# string. shlex.shlex(..., punctuation_chars=True) (and its shlex.split()
# ValueError fallback) has no length cap anywhere upstream, and its cost is
# superlinear in the length of a single long token. Measured live against
# this exact file (single token appended to a real "git push --force",
# python3 cold-start included): 100,000 chars ~0.22s, 150,000 ~0.38s,
# 200,000 ~0.54s, 300,000 ~0.90s, 400,000 ~1.38s -- a 700,000-char payload
# blows straight past a 2s timeout pre-fix (confirmed live: rc=124). This
# gate has no "ask" outcome (see its own header comments), so the fix
# denies on an oversized command -- the same fail-closed direction as every
# other ambiguous-input path here.
_len_pad=$(python3 -c "print('A' * 700000)")

_rc=$(bash_payload "git push --force origin $_len_pad" | timeout 2 bash "$IRRECOVERABLE" 2>/dev/null; echo $?)
if [[ "$_rc" == "2" ]]; then
  echo "  ✅ DENY (<2s): oversized single-token dangerous command still denies (GH #140 length cap)"
  pass=$((pass + 1))
else
  echo "  ❌ DENY EXPECTED (<2s) but got exit $_rc: oversized dangerous command (GH #140 length cap)" >&2
  fail=$((fail + 1))
fi

# Direction-pinning: the SAME oversized padding on a BENIGN tail (git status
# matches no deny pattern at all) must ALSO deny fast -- proving the LENGTH
# CAP fired on size alone, not a real pattern match that just happened to
# still finish inside the timeout (a pattern-match-only path would resolve
# this one to ALLOW, since nothing here is dangerous).
_rc=$(bash_payload "git status $_len_pad" | timeout 2 bash "$IRRECOVERABLE" 2>/dev/null; echo $?)
if [[ "$_rc" == "2" ]]; then
  echo "  ✅ DENY (<2s): oversized BENIGN-tail command still denies -- pins the cap, not a pattern match (GH #140)"
  pass=$((pass + 1))
else
  echo "  ❌ DENY EXPECTED (<2s) but got exit $_rc: oversized benign-tail command (GH #140 length cap)" >&2
  fail=$((fail + 1))
fi

# Negative control: a realistic, modestly-sized legitimate command -- well
# under the cap -- must still ALLOW. Proves the cap does not false-positive
# on ordinary usage merely for being longer than trivial.
test_allow "$IRRECOVERABLE" "realistic longer commit message, well under the GH #140 length cap -> still allows" \
  "$(bash_payload 'git commit -m "Implement feature X with detailed rationale covering edge cases and rollback plan for the release"')"

echo ""
echo "=== task-complete-separation gate (maker≠checker: subagent cannot self-complete) ==="
# maker self-completion is the one thing the harness forbids — a subagent
# (agent_type present) calling TaskUpdate(completed) is blocked at exit 2.
# The main session (no agent_type) and any non-completion status pass.
test_deny  "$TASK_COMPLETE" "subagent marks completed (maker self-grade)" \
  "$(taskupdate_payload completed mh:build-error-resolver)"
test_allow "$TASK_COMPLETE" "main session marks completed (no agent_type)" \
  "$(taskupdate_payload completed '')"
test_allow "$TASK_COMPLETE" "subagent sets in_progress (not completion)" \
  "$(taskupdate_payload in_progress mh:build-error-resolver)"
test_allow "$TASK_COMPLETE" "subagent sets pending (not completion)" \
  "$(taskupdate_payload pending mh:build-error-resolver)"
test_allow "$TASK_COMPLETE" "subagent subject/desc update (no status field)" \
  "$(taskupdate_payload '' mh:build-error-resolver)"
test_allow "$TASK_COMPLETE" "malformed stdin (fail-safe allow)" \
  '{not valid json'
# Security-review finding (2026-08-31): agent_type is also present for a
# top-level `claude --agent <name>` MAIN session (not a subagent) — keying on
# it over-blocks that legitimate case. agent_id is the correct discriminant
# (present only for an actual subagent). Passing '' for $3 here means "no
# agent_id" — the exact --agent-main-session shape.
test_allow "$TASK_COMPLETE" "--agent main session (agent_type set, no agent_id) may still complete" \
  "$(taskupdate_payload completed some-agent-name '')"

echo ""
echo "=== nested-spawn deny (irrecoverable.py: a subagent may not spawn a nested claude session via Bash) ==="
# Security-review finding: a subagent retains Bash access, so `claude -p`
# from Bash spawns a nested session that never routes through the Agent
# tool -- and that nested session is a FRESH main session (no agent_id of
# its own), free to dispatch further agents. This leg denies the nested-
# spawn invocation itself, before it can ever run.
test_deny  "$IRRECOVERABLE" "subagent runs 'claude -p' via Bash (the nested-spawn evasion)" \
  "$(bash_agent_payload 'claude -p "do something"' fork)"
test_deny  "$IRRECOVERABLE" "subagent runs 'claude --agent X --print' via Bash" \
  "$(bash_agent_payload 'claude --agent reviewer --print "check this"' fork)"
test_deny  "$IRRECOVERABLE" "subagent hides the spawn after a semicolon" \
  "$(bash_agent_payload 'echo hi; claude -p "sneaky"' fork)"
test_allow "$IRRECOVERABLE" "subagent runs an unrelated claude invocation (no spawn flag)" \
  "$(bash_agent_payload 'claude --version' fork)"
test_allow "$IRRECOVERABLE" "subagent runs an unrelated Bash command" \
  "$(bash_agent_payload 'ls -la' fork)"
test_allow "$IRRECOVERABLE" "main session runs 'claude -p' via Bash (no agent_id — always allowed)" \
  "$(bash_agent_payload 'claude -p "do something"' '')"
test_allow "$IRRECOVERABLE" "malformed stdin on the Bash leg (fail-safe allow)" \
  '{not valid json'
test_deny  "$IRRECOVERABLE" "subagent spawns via command substitution" \
  "$(bash_agent_payload 'echo $(claude -p "evil")' fork)"
test_deny  "$IRRECOVERABLE" "subagent spawns with an env-var prefix before claude" \
  "$(bash_agent_payload 'CLAUDE_API_KEY=x claude -p "do something"' fork)"
# Deep-audit fresh adversarial pass, 2026-08-31: the un-anchored regex denied
# these three real, harmless commands because they merely CONTAIN the
# substring "claude -p" as prose/data, not as an invocation. A subagent
# could not even document or grep this gate's own pattern without tripping
# it. Fixed by anchoring the match on command position (see the gate's own
# header comment for why a shlex-token rewrite was rejected instead).
test_allow "$IRRECOVERABLE" "subagent commits a message mentioning the flag (prose, not invocation)" \
  "$(bash_agent_payload 'git commit -m "mention claude -p in docs"' fork)"
test_allow "$IRRECOVERABLE" "subagent echoes the pattern as a string, not a real invocation" \
  "$(bash_agent_payload 'echo "claude -p"' fork)"
test_allow "$IRRECOVERABLE" "subagent greps for the pattern (auditing this gate itself)" \
  "$(bash_agent_payload 'grep -r "claude -p" docs/' fork)"
# Deep-audit "fix it all" pass, 2026-08-31: the flat [^|;&]* exclusion after
# the anchor treated any &/;/| as end-of-invocation even inside a quoted
# prompt argument, so these three real nested-spawn attempts evaded
# detection entirely (a false negative -- the dangerous direction). Fixed
# with a quote-aware scan; these must now deny.
test_deny  "$IRRECOVERABLE" "spawn hidden behind an ampersand inside a quoted prompt" \
  "$(bash_agent_payload 'claude "fix A & B" -p' fork)"
test_deny  "$IRRECOVERABLE" "spawn hidden behind a semicolon inside a quoted prompt" \
  "$(bash_agent_payload 'claude "note; then" --print x' fork)"
test_deny  "$IRRECOVERABLE" "spawn hidden behind a pipe inside a single-quoted prompt" \
  "$(bash_agent_payload "claude 'use A | B' --agent x" fork)"
# Cross-segment separation must survive the quote-aware rewrite: a LATER,
# unrelated command's flag must never get credited to an earlier claude
# invocation that itself carries no spawn flag.
test_allow "$IRRECOVERABLE" "unrelated later command's flag does not leak back to claude" \
  "$(bash_agent_payload 'claude --version ; othertool -p' fork)"

# GH #121, 2026-09-04: heredoc-body stripping regression coverage. A
# `git commit -m "$(cat <<'EOF' ... EOF)"` commit message (this repo's own
# documented heredoc convention) whose body merely MENTIONS "feat(claude):"
# and, on a later unrelated line, "--bg" was scanned as if the heredoc body
# were real shell syntax and falsely denied -- the body is literal inert
# data, not a command, unless the heredoc feeds an interpreter. Fixed by
# stripping non-interpreter-fed heredoc bodies before the anchor scan (see
# the gate's own "Heredoc-body stripping" comment block). This is the
# issue's exact repro shape, not a paraphrase.
test_allow "$IRRECOVERABLE" "heredoc-authored commit message mentioning feat(claude): and --bg in unrelated prose lines no longer false-blocks (GH #121 exact repro)" \
  "$(bash_agent_payload $'git commit -m "$(cat <<\'EOF\'\nfeat(claude): document the nested-spawn gate heredoc fix\nunrelated later line just happens to mention --bg here\nEOF\n)"' fork)"
# Dangerous-direction control: a heredoc body that DOES feed an interpreter
# is executable code, not inert data, so a real nested `claude -p` spawn
# hidden inside one must still be caught -- proving the #121 fix stripped
# only inert bodies and did not open a bypass via the interpreter-fed path.
test_deny  "$IRRECOVERABLE" "nested claude spawn hidden inside an interpreter-fed heredoc body still blocked (bash <<EOF ... claude -p ... EOF, GH #121 dangerous-direction control)" \
  "$(bash_agent_payload $'bash <<EOF\nclaude -p "evil"\nEOF' fork)"

# Not ported from the retired agent-recursion-guard.sh: its deep-audit
# heredoc model (cat <<EOF | bash, eval "$(cat <<EOF)", fish <<EOF, a <<
# lookalike inside quotes). irrecoverable.py reuses its own _strip_heredocs
# (interpreter word before "<<" only), a documented ponytail residual there.
test_allow "$TASK_COMPLETE" "non-TaskUpdate tool with agent_type (out of scope)" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"ls"},"agent_type":"mh:build-error-resolver"}))')"

echo ""

echo "=== v1.0.0 gate edits (worktree allowed, git add -A merge carve-out, --worktree spawn, stash list) ==="
# Payload with an explicit cwd (irrecoverable.py checks MERGE_HEAD there).
bash_cwd_payload() { python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "cwd": sys.argv[2]}))' "$1" "$2"; }
test_allow "$IRRECOVERABLE" "git worktree add -b x ../y is ALLOWED (single-branch worktree doctrine block removed)" \
  "$(bash_payload 'git worktree add -b x ../y')"
test_allow "$IRRECOVERABLE" "git -C . worktree add -b feature (was denied by the removed worktree block)" \
  "$(bash_payload 'git -C . worktree add -b feature /tmp/wt-feature')"
MERGE_FIX=$(mktemp -d "${TMPDIR:-/tmp}/kbg-merge-fixture.XXXXXX")
NOMERGE_FIX=$(mktemp -d "${TMPDIR:-/tmp}/kbg-nomerge-fixture.XXXXXX")
( cd "$MERGE_FIX" && git init -q -b develop . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
  && echo a > f && git add f && git -c user.email=t@t -c user.name=t commit -q -m a \
  && git checkout -q -b side && echo b > f && git -c user.email=t@t -c user.name=t commit -q -am b \
  && git checkout -q develop && echo c > f && git -c user.email=t@t -c user.name=t commit -q -am c \
  && git merge -q side >/dev/null 2>&1; true )
( cd "$NOMERGE_FIX" && git init -q -b develop . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
if git -C "$MERGE_FIX" rev-parse -q --verify MERGE_HEAD >/dev/null; then
  test_allow "$IRRECOVERABLE" "git add -A ALLOWED while MERGE_HEAD exists in the payload cwd (mid-merge carve-out)" \
    "$(bash_cwd_payload 'git add -A' "$MERGE_FIX")"
  test_allow "$IRRECOVERABLE" "git add . ALLOWED mid-merge" \
    "$(bash_cwd_payload 'git add .' "$MERGE_FIX")"
else
  echo "  ❌ merge fixture failed to reach a conflicted state" >&2; fail=$((fail + 1))
fi
test_deny "$IRRECOVERABLE" "git add -A DENIED in a repo with no MERGE_HEAD" \
  "$(bash_cwd_payload 'git add -A' "$NOMERGE_FIX")"
test_deny "$IRRECOVERABLE" "git add --all DENIED with no cwd in the payload (falls back to process cwd, not mid-merge)" \
  "$(bash_payload 'git add --all')"
trash "$MERGE_FIX" "$NOMERGE_FIX" 2>/dev/null || true
test_deny "$IRRECOVERABLE" "subagent: claude -p hi via Bash denied" \
  "$(bash_agent_payload 'claude -p hi' fork)"
test_deny "$IRRECOVERABLE" "subagent: claude --worktree x denied (new flag in the ported nested-spawn deny)" \
  "$(bash_agent_payload 'claude --worktree x' fork)"
test_deny "$IRRECOVERABLE" "subagent: claude --bg denied" \
  "$(bash_agent_payload 'claude --bg "run it"' fork)"
test_allow "$IRRECOVERABLE" "main session: claude --worktree x allowed (no agent_id)" \
  "$(bash_agent_payload 'claude --worktree x' '')"
test_allow "$SUBAGENT_GIT_GUARD" "subagent: git stash list allowed (read-only carve-out)" \
  "$(bash_agent_payload 'git stash list' fork)"
test_allow "$SUBAGENT_GIT_GUARD" "subagent: git stash show -p allowed (read-only carve-out)" \
  "$(bash_agent_payload 'git stash show -p' fork)"
test_deny "$SUBAGENT_GIT_GUARD" "subagent: git stash (bare) still denied" \
  "$(bash_agent_payload 'git stash' fork)"
test_deny "$SUBAGENT_GIT_GUARD" "subagent: git stash pop still denied" \
  "$(bash_agent_payload 'git stash pop' fork)"
test_deny "$SUBAGENT_GIT_GUARD" "subagent: git stash listing (not the list verb) still denied" \
  "$(bash_agent_payload 'git stash listing' fork)"

echo "=== fast-path (bash pre-filter that skips python3 on commands that cannot match, added 2026-08-14) ==="
# irrecoverable gained a bash fast-path so a benign command skips the python3
# cold-start. The fast-path only exits 0 (never 2), so a deny-case still
# exiting 2 PROVES python ran and the fast-path did not short-circuit it.
# irrecoverable: the quote-strip MUST expose a quote-concatenated `r""m` -> rm
# (the one shlex obfuscation the python catches that a naive substring misses).
test_deny  "$IRRECOVERABLE" "r\"\"m -rf (quote-concatenation -> fast-path quote-strip)" \
  "$(bash_payload 'r""m -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "r\\m -rf (backslash-concatenation -> fast-path strip)" \
  "$(bash_payload 'r\m -rf /tmp/x')"
# GH #122 adjacent finding: a backslash-newline continuation splitting the
# argv0 ITSELF (not just a flag) turns the \n escape into a space at the
# fast-path's own sed step, so "git"/"rm" never survives as one substring
# and the fast path exits 0 before python3 -- and the reassembled _newlines_
# to_seps fix above -- ever runs. Confirmed live 2026-09-03: exit 0 before
# the fast-path's whitespace-collapsed second variant was added.
test_deny  "$IRRECOVERABLE" "gi + backslash-newline + t (argv0 split, was a fast-path bypass)" \
  "$(bash_payload $'gi\\\nt push --force origin develop')"
test_deny  "$IRRECOVERABLE" "r + backslash-newline + m (argv0 split, was a fast-path bypass)" \
  "$(bash_payload $'r\\\nm -rf /tmp/x')"

echo ""
echo "=== python3-missing fail-open (#93: every deny gate must exit 0 with ONE stderr note, never rc=127 or a silent block) ==="
# A PATH stub dir with the gates' shell dependencies (cat/sed/tr/grep + bash)
# but NO python3. Payloads are built FIRST, with python3 still on PATH.
# Each case asserts rc=0 AND the announced note — a bare rc=0 could also mean
# the payload took a fast-path exit and the guard was never reached (proven
# possible during this battery's own smoke run), so the note is the real assert.
NOPY_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-nopy.XXXXXX")
for _t in bash cat sed tr grep; do
  _src=$(PATH="/usr/bin:/bin" command -v "$_t" || command -v "$_t")
  ln -s "$_src" "$NOPY_BIN/$_t"
done

# test_nopython_allow <gate> <desc> <payload> [extra env VAR=VAL...]
test_nopython_allow() {
  local gate="$1" desc="$2" payload="$3"; shift 3
  local rc errf
  errf=$(mktemp "${TMPDIR:-/tmp}/kbg-nopy-err.XXXXXX")
  rc=$(echo "$payload" | env "$@" PATH="$NOPY_BIN" bash "$gate" 2>"$errf"; echo $?)
  if [[ "$rc" == "0" ]] && grep -q 'python3 not found' "$errf"; then
    echo "  ✅ NO-PYTHON ALLOW: $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ NO-PYTHON ALLOW expected (rc=0 + note) but got rc=$rc, stderr: $(cat "$errf")" >&2
    fail=$((fail + 1))
  fi
  rm -f "$errf"
}

# test_documented_fastpath_allow <gate> <desc> <payload> [extra env VAR=VAL...]
# Inverse of test_nopython_allow above (same NOPY_BIN instrument, opposite
# expectation): asserts rc=0 WITHOUT the "python3 not found" note, i.e. the
# fast path exited before ever reaching the deeper guard. Used ONLY for a
# checked-and-ruled-out gap (GH #134: a $/backtick that arrives JSON
# \uXXXX-escaped is invisible to the raw-string _has_subst scan in
# irrecoverable.sh, so it fast-exits even around a spliced destructive argv0
# -- confirmed NON-LIVE by capturing a real Claude Code hook payload, see the
# comment at the _has_subst guard site). This locks in TODAY's designed
# fast-path-allow so a silent regression is noticed; if a future change
# makes this defer to python3 instead, that's a welcome tightening, not a
# failure here -- update this test rather than treating it as broken.
test_documented_fastpath_allow() {
  local gate="$1" desc="$2" payload="$3"; shift 3
  local rc errf
  errf=$(mktemp "${TMPDIR:-/tmp}/kbg-nopy-err.XXXXXX")
  rc=$(echo "$payload" | env "$@" PATH="$NOPY_BIN" bash "$gate" 2>"$errf"; echo $?)
  if [[ "$rc" == "0" ]] && ! grep -q 'python3 not found' "$errf"; then
    echo "  ✅ DOCUMENTED FAST-PATH ALLOW (GH #134, non-live): $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ documented fast-path allow expected (rc=0, no portability note) but got rc=$rc, stderr: $(cat "$errf")" >&2
    fail=$((fail + 1))
  fi
  rm -f "$errf"
}


test_nopython_allow "$IRRECOVERABLE" "irrecoverable: rm -rf passes with note (was: rc=127 read as fail-CLOSED, blocking every git/rm command)" \
  "$(bash_payload 'rm -rf /tmp/x')"
# Backtick/$(...) fast-path bypass (found alongside GH #125): a command
# substitution vanishes in real bash ("gi`true`t" IS "git" once bash
# evaluates it) but survives as literal characters through the fast
# path's normalization, so neither "git" nor any other tracked argv0
# forms a contiguous substring and the old fast path exited 0 BEFORE ever
# reaching this portability guard -- proven here by the missing note: a
# bare rc=0 alone cannot distinguish "fast-path allowed" from "python3
# ran and allowed," but the absence of the guard's stderr note can only
# mean the fast path never got this far. Confirmed live 2026-09-03: rc=0,
# no note, before this fix. Denying the reassembled command end-to-end is
# a separate, deeper fix to python3's own tokenizer (it does not resolve
# command-substitution splicing either) -- out of scope here; this closes
# only the fast-path short-circuit.
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: backtick-split argv0 (gi\`true\`t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi`true`t push --force origin develop')"
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$(...)-split argv0 (gi\$(true)t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi$(true)t push --force origin develop')"
# Same class, two more splicing spellings found alongside the backtick/$(...)
# fix: ${x} with x unset expands to nothing ("gi${x}t" IS "git"), and $'...'
# ANSI-C quoting resolves escapes ("gi$'\x74'" IS "git"). Both vanish in real
# bash but survive as literal characters through the fast path's
# normalization, so the old fast path exited 0 before ever reaching this
# portability guard -- confirmed live 2026-09-03: rc=0, no note, before this
# fix, same as the backtick/$(...) cases above.
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \${x}-split argv0 (gi\${x}t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi${x}t push --force origin develop')"
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$'...'-split argv0 (gi\$'\x74' push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload "gi\$'\\x74' push --force origin develop")"
# Fresh-context review finding (2026-09-03): $@ and $* are a 5th zero-width
# splicer the 4-marker enumeration above never covered -- with zero
# positional parameters (real in a hook-script invocation context), both
# expand to nothing, so "gi$@t push --force origin develop" vanishes in real
# bash into "git push --force origin develop" (ground-truthed via `bash -x`
# first: `+ git push --force origin develop`) but survives here as literal
# characters, splicing the argv0 apart -- same shape as the backtick/$(...)/
# ${x}/$' cases above, one marker spelling short. Confirmed live before this
# fix: fast-path-exited (rc=0, no note), never reaching this portability
# guard. This motivated replacing the whole enumeration with a single "any
# bare $ or backtick" guard rather than adding a 5th/6th marker.
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$@-split argv0 (gi\$@t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi$@t push --force origin develop')"
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$*-split argv0 (gi\$*t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi$*t push --force origin develop')"
# GH #134: a $ that arrives JSON-\uXXXX-escaped instead of as a literal byte
# is invisible to the raw _has_subst scan above -- json.loads would decode
# $ back to $ (recovering the same "gi${x}t push --force" splice as the
# ${x} case above) but the bash-level fast path never sees a $ or backtick
# in this shape, so it currently fast-exits with zero python3 spawn. Checked
# and ruled out as a live bypass (2026-09-04): captured this session's own
# real PreToolUse hook payload for a Bash command with a literal $/backtick
# and confirmed Claude Code's serializer emits the literal byte, never
# \uXXXX, for plain ASCII -- see the comment at the _has_subst guard site in
# irrecoverable.sh. This test locks in TODAY's documented fast-path-allow
# so a future refactor can't silently change it without someone noticing.
test_documented_fastpath_allow "$IRRECOVERABLE" "irrecoverable: JSON \\u0024-escaped \$ around a \${x} splice (gi\\u0024{x}t push --force) -- raw scan blind, documented non-live gap" \
  '{"tool_name":"Bash","tool_input":{"command":"gi\u0024{x}t push --force origin develop"}}'
test_nopython_allow "$TASK_COMPLETE" "task-complete-separation: subagent completion passes with note" \
  "$(taskupdate_payload 'completed' 'refactor-cleaner')"

# trash-fallback deny message (#93): with python3 present but NO trash CLI on
# PATH, the rm -rf deny must still fire (rc=2) and the message must route to
# the user instead of prescribing a binary the machine doesn't have.
TRASHLESS_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-notrash.XXXXXX")
# dirname: GH #146 extracted irrecoverable.sh's embedded python3 -c block to
# a sibling irrecoverable.py, resolved via "$(dirname "$0")" -- this
# minimal PATH must carry it too, or the gate itself (not the trash-CLI
# fallback under test) fails with "dirname: command not found".
for _t in bash cat sed tr grep python3 dirname; do
  _src=$(PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" command -v "$_t" || command -v "$_t")
  ln -s "$_src" "$TRASHLESS_BIN/$_t"
done
_errf=$(mktemp "${TMPDIR:-/tmp}/kbg-notrash-err.XXXXXX")
_rc=$(bash_payload 'rm -rf /tmp/x' | env PATH="$TRASHLESS_BIN" bash "$IRRECOVERABLE" 2>"$_errf"; echo $?)
if [[ "$_rc" == "2" ]] && grep -q 'no trash CLI' "$_errf" && grep -q 'ask the user' "$_errf"; then
  echo "  ✅ DENY: rm -rf without a trash CLI still denies, message routes to the user (#93)"
  pass=$((pass + 1))
else
  echo "  ❌ rm -rf trashless deny expected (rc=2 + user-routing message) but got rc=$_rc, stderr: $(cat "$_errf")" >&2
  fail=$((fail + 1))
fi
rm -f "$_errf"

echo ""
echo "=== missing sibling .py (corrupted/partial plugin install; follow-up to #146) ==="
# GH #146 extracted this gate's embedded python3 -c block into a sibling
# irrecoverable.py, resolved via "$(dirname "$0")/irrecoverable.py". If that
# sibling is missing or unreadable (a corrupted/partial plugin install),
# python3 itself exits 2 with a raw "can't open file ..." message -- which
# the rc-handling tail below already reads as "rc==2, a legitimate deny" and
# passes through as exit 2 (fail-closed is already correct), but the stderr
# the operator sees is an ugly unlabeled python3 error instead of this
# repo's own [mh:gate] convention. Simulate by copying ONLY the .sh into an
# isolated scratch dir (never touch the real repo file) so $(dirname "$0")
# resolves to a directory with no irrecoverable.py sibling.
MISSPY_IRR_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kbg-misspy-irr.XXXXXX")
cp "$IRRECOVERABLE" "$MISSPY_IRR_DIR/irrecoverable.sh"
_errf=$(mktemp "${TMPDIR:-/tmp}/kbg-misspy-irr-err.XXXXXX")
_out=$(bash_payload 'rm -rf /tmp/x' | bash "$MISSPY_IRR_DIR/irrecoverable.sh" 2>"$_errf")
_rc=$?
_ok=1
if [ "$_rc" -eq 2 ] && [ -z "$_out" ] && grep -q '\[mh:gate\]' "$_errf" \
   && ! grep -qi "can't open file\|Traceback" "$_errf"; then
  _ok=0
fi
if [ "$_ok" -eq 0 ]; then
  echo "  ✅ DENY: missing sibling irrecoverable.py -> fails closed (exit 2) with [mh:gate] message, no raw traceback"
  pass=$((pass + 1))
else
  echo "  ❌ missing sibling irrecoverable.py: expected exit 2 + [mh:gate] message + no traceback, got rc=$_rc stdout='$_out' stderr: $(cat "$_errf")" >&2
  fail=$((fail + 1))
fi
rm -f "$_errf"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
