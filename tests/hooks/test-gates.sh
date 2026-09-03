#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in test payload strings is intentional
# Gate unit tests: simulates PreToolUse JSON payloads and asserts allow/deny/ask.
# Each test_deny call expects exit 2; test_allow expects exit 0 + empty stdout;
# test_ask expects exit 0 + a permissionDecision: ask JSON on stdout.
# Run standalone: bash tests/hooks/test-gates.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IRRECOVERABLE="$ROOT/hooks/gates/irrecoverable.sh"
VERIFIER_PROTECT="$ROOT/hooks/gates/verifier-protect.sh"
TASK_COMPLETE="$ROOT/hooks/gates/task-complete-separation.sh"
AGENT_RECURSION_GUARD="$ROOT/hooks/gates/agent-recursion-guard.sh"
DB_WRITE_GATE="$ROOT/hooks/gates/db-write-gate.sh"

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

# Build an Agent tool-call payload. $1=requested subagent_type (or empty to
# omit the field, matching a Named-Model dispatch with no subagent_type),
# $2=agent_type of the CALLER (or empty = main session, field omitted),
# $3=agent_id of the CALLER (omit the arg entirely to mirror $2 — the
# realistic shape for an actual subagent, which always carries both fields;
# pass '' explicitly to simulate a --agent MAIN session, which carries
# agent_type but never agent_id — code.claude.com/docs/en/hooks.md,
# confirmed 2026-08-31: agent_id is present "only when the hook fires inside
# a subagent call", agent_type is present for --agent sessions too).
agent_payload() {
  python3 -c '
import json, sys
subtype, agent, agent_id = sys.argv[1], sys.argv[2], sys.argv[3]
ti = {}
if subtype:
    ti["subagent_type"] = subtype
d = {"tool_name": "Agent", "tool_input": ti}
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

# Build an MCP tool-call payload with a SQL statement in .query (a common
# execute_sql MCP convention; db-write-gate.sh also checks .sql/.statement/.text).
mcp_sql_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"query": sys.argv[2]}}))' "$1" "$2"
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

# GH #129 follow-up (2026-09-03): an adversarial review found the leading-PH
# fix above was applied to some checks but not others, and a third bug class
# (Layer 3 -- a standalone vanish token, not glued to anything, shifts every
# later token left one position, same as real bash word-splitting, but the
# PH-only token stays in place here) had never been tested in this file.
# --- Layer 2: the single-branch-develop-only worktree doctrine gate ---
# (the highest-severity gap: git worktree add -b was never lstrip(PH)-ed at
# all, unlike every other flag check above).
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git worktree add -b's dash (was silently ALLOWed, bypassing the single-branch doctrine gate)" \
  "$(bash_payload 'git worktree add $(true)-b feature-branch /tmp/wt-feature')"
test_deny "$IRRECOVERABLE" "baseline: plain git worktree add -b, no splice at all (must still deny)" \
  "$(bash_payload 'git worktree add -b feature-branch /tmp/wt-feature')"
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
test_deny "$IRRECOVERABLE" "env wrapper flag splice defeats worktree doctrine gate (env \$(true)-u FOO git worktree add -b evil ..., was silently ALLOWed)" \
  "$(bash_payload 'env $(true)-u FOO git worktree add -b evil /tmp/wt-evil-env')"
test_deny "$IRRECOVERABLE" "sudo wrapper flag splice defeats worktree doctrine gate (sudo \$(true)-u alice git worktree add -b evil ..., was silently ALLOWed)" \
  "$(bash_payload 'sudo $(true)-u alice git worktree add -b evil /tmp/wt-evil-sudo')"
test_deny "$IRRECOVERABLE" "nice wrapper flag splice defeats worktree doctrine gate (nice \$(true)-n5 git worktree add -b evil ..., was silently ALLOWed)" \
  "$(bash_payload 'nice $(true)-n5 git worktree add -b evil /tmp/wt-evil-nice')"
test_deny "$IRRECOVERABLE" "command wrapper flag splice defeats worktree doctrine gate (command \$(true)-p git worktree add -b evil ..., was silently ALLOWed)" \
  "$(bash_payload 'command $(true)-p git worktree add -b evil /tmp/wt-evil-cmd')"
test_deny "$IRRECOVERABLE" "xargs mid-basename splice defeats worktree doctrine gate (xargs g\$(true)it worktree add -b evil ..., was silently ALLOWed)" \
  "$(bash_payload 'echo x | xargs g$(true)it worktree add -b evil /tmp/wt-evil-xargs')"
test_deny "$IRRECOVERABLE" "docker exec flag splice defeats the inner-command re-point, hiding destructive SQL (docker exec \$(true)-i c1 mysql -e DROP TABLE, was silently ALLOWed)" \
  "$(bash_payload 'docker exec $(true)-i c1 mysql -e "DROP TABLE users"')"
test_deny "$IRRECOVERABLE" "docker exec-itself splice defeats the inner-command re-point, hiding destructive SQL (docker \$(true)exec c1 mysql -e DROP TABLE, was silently ALLOWed)" \
  "$(bash_payload 'docker $(true)exec c1 mysql -e "DROP TABLE users"')"
# --- Layer 3: a standalone unquoted vanish token shifts fixed-index reads.
# The worst case is the whole vanish landing right where argv0 would be
# (before "git" itself) -- "git" then ends up misplaced one slot into
# `rest`, and none of this file own git dispatch checks look there.
test_deny "$IRRECOVERABLE" "Layer 3: a standalone vanish sits WHERE argv0 would be, before git itself (\$(true) git worktree add -b evil ..., was silently ALLOWed)" \
  "$(bash_payload '$(true) git worktree add -b evil /tmp/wt-evil-vanish')"
# Companion: a standalone vanish AFTER git, before the subcommand -- already
# safely denied today via this file own KNOWN_GIT_SUBS candidate duplication
# (the "restore" branch own broad any-nonflag-token condition happens to
# fire), locked in here as a regression test for the exact shape named in
# the fix review, not because it was ever a confirmed bypass.
test_deny "$IRRECOVERABLE" "Layer 3 companion: a standalone vanish sits between git and the subcommand (git \$(true) worktree add -b evil ...)" \
  "$(bash_payload 'git $(true) worktree add -b evil /tmp/wt-evil-vanish2')"
# Negative control (Layer 3 must not over-deny): a standalone vanish
# resolving to something REAL, not empty, still shifts a token in the SAME
# way at the placeholder level -- but the compacted-window retry must not
# misfire into a false deny just because dropping that token leaves a
# shorter, still-benign list.
test_allow "$IRRECOVERABLE" "Layer 3 negative control: \$(which git) status -- compacted window drops argv0 entirely, must stay ALLOW" \
  "$(bash_payload '$(which git) status')"

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
test_deny "$IRRECOVERABLE" "git -C . worktree add -b feature (global-flag bypass)" \
  "$(bash_payload 'git -C . worktree add -b feature /tmp/wt-feature')"
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
# --- detached-looking worktree with -b must still deny (no allowlist survives; the former
# review-pr allowlist was removed with the review pipeline, 2026-08-24 #82) ---
test_deny  "$IRRECOVERABLE" "git worktree add --detach -b (disguised new-branch worktree)" \
  "$(bash_payload 'git worktree add --detach -b evil /tmp/review-pr-1')"
# --- fail-closed internal-error backstop (irrecoverable.sh:431-433): a payload that makes the
# Python raise (command is a JSON array, not a string) must still exit 2, never fall open. ---
test_deny  "$IRRECOVERABLE" "non-string command payload triggers the fail-closed backstop (exit 2, not fail-open)" \
  '{"tool_name":"Bash","tool_input":{"command":["rm","-rf","/x"]}}'

echo ""
echo "=== verifier-protect Bash gate (redirect/tee/sed-i writes to verifier surfaces) ==="
VP_BASH="$ROOT/hooks/gates/verifier-protect.sh"
test_ask   "$VP_BASH" "redirect > into hooks/gates/" \
  "$(bash_payload 'echo neutered > hooks/gates/irrecoverable.sh')"
test_ask   "$VP_BASH" "append >> into hooks/hooks.json" \
  "$(bash_payload 'echo x >> hooks/hooks.json')"
test_ask   "$VP_BASH" "sed -i on an audit check" \
  "$(bash_payload 'sed -i s/a/b/ skills/meta/harness-audit/scripts/checks/01-fleet-count.sh')"
test_ask   "$VP_BASH" "tee into a gate file" \
  "$(bash_payload 'echo x | tee hooks/gates/verifier-protect.sh')"
test_ask   "$VP_BASH" "cp over an audit check (dest is verifier path)" \
  "$(bash_payload 'cp foo skills/meta/harness-audit/scripts/checks/05-frontmatter-completeness-skills.sh')"
test_ask   "$VP_BASH" "mv into hooks/gates/ via absolute path" \
  "$(bash_payload "mv x $ROOT/hooks/gates/irrecoverable.sh")"
# v0.36.0 audit: cp/mv/install -t <dir> made nonflag[-1] a SOURCE, so the real
# destination was lost and a verifier-surface write went unasked. dd of= had no
# verifier-protect coverage at all.
test_ask   "$VP_BASH" "cp -t into hooks/gates/ (dest via -t, not source)" \
  "$(bash_payload 'cp -t hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "mv -t into audit checks/ (--target-directory=)" \
  "$(bash_payload 'mv --target-directory=skills/meta/harness-audit/scripts/checks/ evil.sh')"
test_ask   "$VP_BASH" "install -t into hooks/gates/" \
  "$(bash_payload 'install -t hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "dd of= a gate file (was no coverage)" \
  "$(bash_payload 'dd if=/dev/zero of=hooks/gates/irrecoverable.sh bs=1 count=1')"
test_allow "$VP_BASH" "dd of= a normal project file" \
  "$(bash_payload 'dd if=/dev/zero of=src/index.ts bs=1 count=1')"
test_allow "$VP_BASH" "cp -t into a normal source dir" \
  "$(bash_payload 'cp -t src/ foo.sh')"
test_allow "$VP_BASH" "redirect into a normal source file" \
  "$(bash_payload 'echo x > skills/foo/SKILL.md')"
test_allow "$VP_BASH" "cat a gate file (read, not write)" \
  "$(bash_payload 'cat hooks/gates/irrecoverable.sh')"
test_allow "$VP_BASH" "git apply a patch to a non-verifier path" \
  "$(bash_payload 'git apply --check foo.patch')"
test_allow "$VP_BASH" "sed -i on a normal project file" \
  "$(bash_payload 'sed -i s/a/b/ src/index.ts')"
test_allow "$VP_BASH" "ls a gate file (no write)" \
  "$(bash_payload 'ls hooks/gates/irrecoverable.sh')"

# v0.36.0-fix follow-up audit: -t joined to its value (-tDIR) or bundled with
# other short flags (-rtDIR) still bypassed the just-shipped -t fix. rsync,
# tar -x -C, patch, and git apply/am had zero verifier-protect coverage at all.
test_ask   "$VP_BASH" "cp -t joined to its value (-thooks/gates/)" \
  "$(bash_payload 'cp -thooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "cp -t bundled with -r (-rthooks/gates/)" \
  "$(bash_payload 'cp -rthooks/gates/ evil.sh')"
test_allow "$VP_BASH" "cp -t joined to a normal dir" \
  "$(bash_payload 'cp -t/tmp/ x')"

# compliance-audit adversarial pass: -tDIR and -rtDIR (joined) were closed
# above, but -rt DIR (bundled, value in the NEXT token) still fell through to
# nonflag[-1] and was silently allowed.
test_ask   "$VP_BASH" "cp -rt into hooks/gates/ (bundled, space-separated target)" \
  "$(bash_payload 'cp -rt hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "mv -vt into hooks/gates/ (bundled, space-separated target)" \
  "$(bash_payload 'mv -vt hooks/gates/ evil.sh')"
test_ask   "$VP_BASH" "install -vt into hooks/gates/ (bundled, space-separated target)" \
  "$(bash_payload 'install -vt hooks/gates/ evil.sh')"
test_allow "$VP_BASH" "cp -rt into a normal source dir (bundled, space-separated)" \
  "$(bash_payload 'cp -rt /tmp/safe/ myfile.txt')"
test_ask   "$VP_BASH" "rsync into hooks/gates/" \
  "$(bash_payload 'rsync evil.sh hooks/gates/x.sh')"
test_allow "$VP_BASH" "rsync into a normal dir" \
  "$(bash_payload 'rsync a.sh b.sh')"
test_ask   "$VP_BASH" "tar -x -C into hooks/gates/" \
  "$(bash_payload 'tar -xf evil.tar -C hooks/gates/')"
test_allow "$VP_BASH" "tar -x -C into a normal dir" \
  "$(bash_payload 'tar -xf evil.tar -C /tmp')"
test_ask   "$VP_BASH" "patch a gate file via stdin redirect" \
  "$(bash_payload 'patch hooks/gates/irrecoverable.sh < evil.patch')"
test_allow "$VP_BASH" "patch a normal project file" \
  "$(bash_payload 'patch README.md < ok.patch')"

VP_DIFF_BAD="$(mktemp -t kbg-vp-test-bad.XXXXXX)"
VP_DIFF_OK="$(mktemp -t kbg-vp-test-ok.XXXXXX)"
cat > "$VP_DIFF_BAD" <<'EOF'
--- a/hooks/gates/irrecoverable.sh
+++ b/hooks/gates/irrecoverable.sh
@@ -1,1 +1,1 @@
-old
+new
EOF
cat > "$VP_DIFF_OK" <<'EOF'
--- a/README.md
+++ b/README.md
@@ -1,1 +1,1 @@
-old
+new
EOF
test_ask   "$VP_BASH" "git apply a diff whose +++ b/ target is a gate file" \
  "$(bash_payload "git apply $VP_DIFF_BAD")"
test_allow "$VP_BASH" "git apply a diff targeting a normal file" \
  "$(bash_payload "git apply $VP_DIFF_OK")"
rm -f "$VP_DIFF_BAD" "$VP_DIFF_OK"

echo ""
echo "=== path-hardcode deny (folded into verifier-protect Write branch) ==="
# ponytail: split to avoid triggering the pre-commit /Users/<name>/ grep on test source
# These run against verifier-protect.sh (the deny folded in 2026-07-03); the
# file_paths are normal (non-verifier) so the ask branch does not fire -- only
# the path-hardcode deny is exercised. $_UD avoids a literal /Users/<name> in
# this test source (which the gate would otherwise block).
_UP="/Users" _UN="testuser" _UD="$_UP/$_UN"
test_deny  "$VERIFIER_PROTECT" "hardcoded /Users/ in .sh" \
  "$(write_payload 'script.sh' "export PATH=$_UD/bin:\$PATH")"
test_deny  "$VERIFIER_PROTECT" "hardcoded /Users/ in .py" \
  "$(write_payload 'setup.py' "BASE = $_UD/data")"
test_deny  "$VERIFIER_PROTECT" "hardcoded /Users/ in .js (#93: shipped workflow runners)" \
  "$(write_payload 'runner.js' "const base = \"$_UD/data\"")"
test_deny  "$VERIFIER_PROTECT" "Edit new_string with /Users/ in .sh" \
  "$(edit_payload 'deploy.sh' "cd $_UD/app")"
test_allow "$VERIFIER_PROTECT" "\$HOME reference in .sh" \
  "$(write_payload 'script.sh' 'export PATH=$HOME/bin:$PATH')"
test_allow "$VERIFIER_PROTECT" "~ reference in .sh" \
  "$(write_payload 'script.sh' 'cd ~/projects')"
test_allow "$VERIFIER_PROTECT" "/Users/ in .md file (not gated)" \
  "$(write_payload 'README.md' "see $_UD for example")"
test_allow "$VERIFIER_PROTECT" "/Users/ in .json file (not gated)" \
  "$(write_payload 'config.json' "{\\\"path\\\":\\\"$_UD\\\"}")"
test_allow "$VERIFIER_PROTECT" "normal .sh content" \
  "$(write_payload 'run.sh' 'set -uo pipefail\necho hello')"

echo ""
echo "=== verifier-protect gate (tamper-resistance: human approves each verifier-surface edit) ==="
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/irrecoverable.sh" \
  "$(write_payload 'hooks/gates/irrecoverable.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Edit to hooks/gates/verifier-protect.sh (self)" \
  "$(edit_payload 'hooks/gates/verifier-protect.sh' 'exit 0')"
test_ask   "$VERIFIER_PROTECT" "Write to hooks/hooks.json (the wiring)" \
  "$(write_payload 'hooks/hooks.json' 'neutered-wiring')"
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/ via absolute path" \
  "$(write_payload "$ROOT/hooks/gates/task-complete-separation.sh" 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Write to audit.sh (non-model verifier runner)" \
  "$(write_payload 'skills/meta/harness-audit/scripts/audit.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Edit to a check file (grading logic)" \
  "$(edit_payload 'skills/meta/harness-audit/scripts/checks/05-frontmatter-completeness-skills.sh' 'echo neutered')"
test_ask   "$VERIFIER_PROTECT" "Write to a check via absolute path" \
  "$(write_payload "$ROOT/skills/meta/harness-audit/scripts/checks/01-fleet-count.sh" 'echo neutered')"
test_allow "$VERIFIER_PROTECT" "Write to --health reporter (NOT a grader, out of scope)" \
  "$(write_payload 'skills/meta/harness-audit/scripts/harness-health.py' 'print(1)')"
test_allow "$VERIFIER_PROTECT" "Write to health.sh (NOT a grader, out of scope)" \
  "$(write_payload 'skills/meta/harness-audit/scripts/health.sh' 'echo ok')"
test_allow "$VERIFIER_PROTECT" "Write to a skill (normal work)" \
  "$(write_payload 'skills/foo/SKILL.md' '# ok')"
test_allow "$VERIFIER_PROTECT" "Write to another skill (normal work)" \
  "$(write_payload 'skills/review/pr/SKILL.md' '# ok')"

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
echo "=== agent-recursion-guard gate (only the main session may dispatch an agent) ==="
# The exact evasion found 2026-08-31: a rogue fork hit the host's own
# fork->fork block, then switched subagent_type to general-purpose instead —
# which the host allowed. This gate closes that regardless of which
# subagent_type is requested, keyed only on whether the CALLER is itself a
# subagent (agent_type present).
test_deny  "$AGENT_RECURSION_GUARD" "subagent (fork) tries fork->fork (the exact rogue-fork scenario)" \
  "$(agent_payload fork fork)"
test_deny  "$AGENT_RECURSION_GUARD" "subagent (fork) evades via general-purpose instead" \
  "$(agent_payload general-purpose fork)"
test_deny  "$AGENT_RECURSION_GUARD" "subagent (general-purpose) tries to dispatch another" \
  "$(agent_payload general-purpose general-purpose)"
test_deny  "$AGENT_RECURSION_GUARD" "subagent (named agent) tries to dispatch" \
  "$(agent_payload general-purpose mh:build-error-resolver)"
test_deny  "$AGENT_RECURSION_GUARD" "subagent dispatches with no subagent_type specified" \
  "$(agent_payload '' fork)"
test_allow "$AGENT_RECURSION_GUARD" "main session dispatches a fork (no agent_type)" \
  "$(agent_payload fork '')"
test_allow "$AGENT_RECURSION_GUARD" "main session dispatches general-purpose (no agent_type)" \
  "$(agent_payload general-purpose '')"
test_allow "$AGENT_RECURSION_GUARD" "unrelated tool (Bash, no agent_id) passes through untouched" \
  "$(bash_payload 'echo hi')"
test_allow "$AGENT_RECURSION_GUARD" "malformed stdin (fail-safe allow)" \
  '{not valid json'
# Security-review finding: agent_type over-blocks a top-level --agent
# session (see the identical TASK_COMPLETE case above for the doc citation).
test_allow "$AGENT_RECURSION_GUARD" "--agent main session (agent_type set, no agent_id) may still dispatch" \
  "$(agent_payload fork some-agent-name '')"

echo ""
echo "=== agent-recursion-guard gate, Bash leg (nested claude spawn evades the Agent-tool matcher) ==="
# Security-review finding: a subagent retains Bash access, so `claude -p`
# from Bash spawns a nested session that never routes through the Agent
# tool -- and that nested session is a FRESH main session (no agent_id of
# its own), free to dispatch further agents. This leg denies the nested-
# spawn invocation itself, before it can ever run.
test_deny  "$AGENT_RECURSION_GUARD" "subagent runs 'claude -p' via Bash (the nested-spawn evasion)" \
  "$(bash_agent_payload 'claude -p "do something"' fork)"
test_deny  "$AGENT_RECURSION_GUARD" "subagent runs 'claude --agent X --print' via Bash" \
  "$(bash_agent_payload 'claude --agent reviewer --print "check this"' fork)"
test_deny  "$AGENT_RECURSION_GUARD" "subagent hides the spawn after a semicolon" \
  "$(bash_agent_payload 'echo hi; claude -p "sneaky"' fork)"
test_allow "$AGENT_RECURSION_GUARD" "subagent runs an unrelated claude invocation (no spawn flag)" \
  "$(bash_agent_payload 'claude --version' fork)"
test_allow "$AGENT_RECURSION_GUARD" "subagent runs an unrelated Bash command" \
  "$(bash_agent_payload 'ls -la' fork)"
test_allow "$AGENT_RECURSION_GUARD" "main session runs 'claude -p' via Bash (no agent_id — always allowed)" \
  "$(bash_agent_payload 'claude -p "do something"' '')"
test_allow "$AGENT_RECURSION_GUARD" "malformed stdin on the Bash leg (fail-safe allow)" \
  '{not valid json'
test_deny  "$AGENT_RECURSION_GUARD" "subagent spawns via command substitution" \
  "$(bash_agent_payload 'echo $(claude -p "evil")' fork)"
test_deny  "$AGENT_RECURSION_GUARD" "subagent spawns with an env-var prefix before claude" \
  "$(bash_agent_payload 'CLAUDE_API_KEY=x claude -p "do something"' fork)"
# Deep-audit fresh adversarial pass, 2026-08-31: the un-anchored regex denied
# these three real, harmless commands because they merely CONTAIN the
# substring "claude -p" as prose/data, not as an invocation. A subagent
# could not even document or grep this gate's own pattern without tripping
# it. Fixed by anchoring the match on command position (see the gate's own
# header comment for why a shlex-token rewrite was rejected instead).
test_allow "$AGENT_RECURSION_GUARD" "subagent commits a message mentioning the flag (prose, not invocation)" \
  "$(bash_agent_payload 'git commit -m "mention claude -p in docs"' fork)"
test_allow "$AGENT_RECURSION_GUARD" "subagent echoes the pattern as a string, not a real invocation" \
  "$(bash_agent_payload 'echo "claude -p"' fork)"
test_allow "$AGENT_RECURSION_GUARD" "subagent greps for the pattern (auditing this gate itself)" \
  "$(bash_agent_payload 'grep -r "claude -p" docs/' fork)"
# Deep-audit "fix it all" pass, 2026-08-31: the flat [^|;&]* exclusion after
# the anchor treated any &/;/| as end-of-invocation even inside a quoted
# prompt argument, so these three real nested-spawn attempts evaded
# detection entirely (a false negative -- the dangerous direction). Fixed
# with a quote-aware scan; these must now deny.
test_deny  "$AGENT_RECURSION_GUARD" "spawn hidden behind an ampersand inside a quoted prompt" \
  "$(bash_agent_payload 'claude "fix A & B" -p' fork)"
test_deny  "$AGENT_RECURSION_GUARD" "spawn hidden behind a semicolon inside a quoted prompt" \
  "$(bash_agent_payload 'claude "note; then" --print x' fork)"
test_deny  "$AGENT_RECURSION_GUARD" "spawn hidden behind a pipe inside a single-quoted prompt" \
  "$(bash_agent_payload "claude 'use A | B' --agent x" fork)"
# Cross-segment separation must survive the quote-aware rewrite: a LATER,
# unrelated command's flag must never get credited to an earlier claude
# invocation that itself carries no spawn flag.
test_allow "$AGENT_RECURSION_GUARD" "unrelated later command's flag does not leak back to claude" \
  "$(bash_agent_payload 'claude --version ; othertool -p' fork)"
test_allow "$TASK_COMPLETE" "non-TaskUpdate tool with agent_type (out of scope)" \
  "$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"ls"},"agent_type":"mh:build-error-resolver"}))')"

echo ""
echo "=== db-write-gate (ask on non-SELECT execute_sql-shaped MCP calls, any server) ==="
test_ask   "$DB_WRITE_GATE" "DELETE on production" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'DELETE FROM users WHERE id=1')"
test_ask   "$DB_WRITE_GATE" "DROP TABLE on staging" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_staging' 'DROP TABLE sessions')"
test_ask   "$DB_WRITE_GATE" "comment-then-DELETE (comment-strip order)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' $'-- note\nDELETE FROM users')"
test_ask   "$DB_WRITE_GATE" "WITH-CTE whose outer statement writes" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'WITH t AS (SELECT 1) DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "SELECT is read-only" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT * FROM users')"
test_allow "$DB_WRITE_GATE" "WITH-CTE that only reads" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'WITH t AS (SELECT 1) SELECT * FROM t')"
test_allow "$DB_WRITE_GATE" "EXPLAIN is read-only" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN SELECT * FROM users')"
test_allow "$DB_WRITE_GATE" "comment-only statement is a no-op" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '-- just a comment')"
# compliance-audit adversarial pass: a write stacked after a lead SELECT
# classified by leading-verb-only as a read and slipped through.
test_ask   "$DB_WRITE_GATE" "write stacked after a lead SELECT" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1; DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "two stacked SELECTs stay read-only" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1; SELECT 2')"
test_ask   "$DB_WRITE_GATE" "leading block comment before a write verb" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/* comment */ DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "leading block comment before a read stays allowed" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/* comment */ SELECT * FROM users')"
# v0.49.0: quote-aware comment stripping — two silent-allow bypasses that shipped
# in v0.40.0's regex stripper, caught exercising mh:review-pr. String-literal
# blindness: a /* (or --) inside one string literal paired with a */ in a later
# literal erased a stacked write. MySQL /*! ... */ executable comments: the body
# runs on the server but was deleted as if inert. (SQL uses "..." literals so the
# single-quote-heavy cases stay expressible inside the test file's '...' args.)
test_ask   "$DB_WRITE_GATE" "block-comment lookalike across two string literals hides a stacked write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT "/*", 1; DELETE FROM users WHERE x = "*/"')"
test_allow "$DB_WRITE_GATE" "a /* inside a string literal is not a comment (no over-ask)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT "/*" AS a')"
test_ask   "$DB_WRITE_GATE" "-- lookalike inside string literals hides a stacked write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT "--", 1; DELETE FROM x')"
test_ask   "$DB_WRITE_GATE" "MySQL /*! executable-comment body is a real write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!50000 DELETE */ FROM t')"
# Under the ask-by-default inversion (v0.49.0) a /*! ... */ hint that prepends a
# non-read token (SQL_NO_CACHE) to the statement no longer leads with a read verb,
# so it asks. Over-ask on an exotic read hint is the intended safe direction.
test_ask   "$DB_WRITE_GATE" "MySQL /*! read hint prepends a non-read token -> safe over-ask" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!40101 SQL_NO_CACHE */ SELECT 1')"
# The /*! body is real SQL to MariaDB: its closing */ is found respecting inner
# strings and nested /* */ comments. The first cut of this fix sliced the body
# with a raw find("*/"), which closed early on an inner */ and left the write verb
# non-leading -> silent allow. Caught against a live MariaDB while exercising
# mh:review-pr on the fix itself; these lock the second-order fix in.
test_ask   "$DB_WRITE_GATE" "/*! body with a nested block comment before the write verb" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!50000 /* x */ DELETE FROM t2 */')"
test_ask   "$DB_WRITE_GATE" "/*! body with a */ hidden inside a string literal" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!00000 SELECT "*/-- x" */ ; DELETE FROM t')"
test_allow "$DB_WRITE_GATE" "/*! body that is read-only stays allowed (no over-ask)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*!50000 /* x */ SELECT 1 */')"
test_ask   "$DB_WRITE_GATE" "unterminated block comment keeps the trailing write for classification" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1; /* trap; DELETE FROM t')"
# v0.49.0 ask-by-default inversion: the gate now ALLOWs only proven simple reads
# and ASKs on everything else, so verb-list gaps and lexer desyncs fall to a safe
# false-ask instead of a false-allow. All four caught against a live MariaDB in
# round 3 of the review exercise; the last is the -- needs-whitespace lexer rule.
test_ask   "$DB_WRITE_GATE" "LOAD DATA is a write not on any leading-verb list" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'LOAD DATA LOCAL INFILE "/x" INTO TABLE t')"
test_ask   "$DB_WRITE_GATE" "PREPARE/EXECUTE hides the write verb in a string literal" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'PREPARE s FROM "DELETE FROM t"; EXECUTE s')"
test_ask   "$DB_WRITE_GATE" "SELECT ... INTO OUTFILE writes to disk despite the SELECT lead" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT * FROM t INTO OUTFILE "/tmp/x"')"
test_ask   "$DB_WRITE_GATE" "-- without trailing whitespace is arithmetic, not a comment (1--1)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SELECT 1--1;DELETE FROM t')"
test_ask   "$DB_WRITE_GATE" "SET GLOBAL is a server-config write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SET GLOBAL x = 1')"
test_allow "$DB_WRITE_GATE" "SHOW is a proven read" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'SHOW TABLES')"
test_allow "$DB_WRITE_GATE" "plain EXPLAIN never executes what it analyzes (read)" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN SELECT 1')"
# MariaDB honors a SECOND executable-comment form, /*M! ... */, alongside /*! ... */
# (the M form is designed to read as inert to non-MariaDB parsers). Missing it was
# a live silent-allow bypass found in the final round of the review exercise.
test_ask   "$DB_WRITE_GATE" "MariaDB /*M! executable comment runs a write" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*M!100000 DELETE FROM t */')"
test_ask   "$DB_WRITE_GATE" "MariaDB /*M! with no version digits still runs" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*M!DELETE FROM t */')"
test_allow "$DB_WRITE_GATE" "MariaDB /*M! body that is a read stays allowed" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' '/*M!100000 SELECT 1 */')"
# scope expansion (user-approved): CALL invokes a stored procedure that can
# write internally; EXPLAIN ANALYZE (unlike plain EXPLAIN) actually executes
# the analyzed statement on MySQL/MariaDB.
test_ask   "$DB_WRITE_GATE" "CALL a stored procedure" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'CALL delete_all_users()')"
test_ask   "$DB_WRITE_GATE" "EXPLAIN ANALYZE of a write executes it" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN ANALYZE DELETE FROM users')"
test_allow "$DB_WRITE_GATE" "EXPLAIN ANALYZE of a read stays allowed" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'EXPLAIN ANALYZE SELECT * FROM users')"
test_allow "$DB_WRITE_GATE" "unrelated MCP tool (mongodb) out of scope" \
  "$(mcp_sql_payload 'mcp__mongodb__find' 'DELETE')"
# Generalization proof: the matcher/regex is server-name-agnostic now
# (^mcp__.*__execute_sql) — a completely different server name must still ask
# on a write, with zero config. This is the whole point of the de-clienting.
test_ask   "$DB_WRITE_GATE" "a different server name entirely still gates a write (generic match)" \
  "$(mcp_sql_payload 'mcp__postgres__execute_sql' 'DELETE FROM users')"
# hooks.json's matcher ("mcp__.*__execute_sql.*") is zero-or-more on the server
# segment; the script's own check must match that scope exactly, or a
# degenerate empty-server tool name that trips the outer trigger would fall
# through the inner check unclassified -> silent exit 0, no ask (a real
# never-silently-allow violation, even though no live MCP server ever emits
# an empty name). Confirmed live-fire during the compliance audit: `^mcp__.+`
# left this asking nothing; `^mcp__.*` closes it.
test_ask   "$DB_WRITE_GATE" "empty server-name segment still gates a write (outer/inner scope parity)" \
  "$(mcp_sql_payload 'mcp____execute_sql' 'DELETE FROM users')"
test_ask   "$DB_WRITE_GATE" "malformed stdin (fail-safe ask)" \
  '{not valid json'

echo ""
echo "=== atlassian-mcp-gate (cold-start guard: Skill(jira-acli:*) must load before Atlassian MCP) ==="
ATLASSIAN_GATE="$ROOT/hooks/gates/atlassian-mcp-gate.sh"

# Fixture HOME (#93): the gate now feature-detects the jira-acli plugin under
# $HOME/.claude/plugins/cache/*/jira-acli and allows everything when absent —
# so these tests must run under a HOME that HAS it (any publisher dir works),
# or they'd vacuously pass/fail depending on what the dev machine has
# installed. Side benefit: session markers land under the fixture, not the
# real ~/.local/share/kbg/.
AG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/kbg-ag-home.XXXXXX")
mkdir -p "$AG_HOME/.claude/plugins/cache/wasikarn/jira-acli"
AG_REAL_HOME="$HOME"
export HOME="$AG_HOME"

# Build a Skill tool payload.
skill_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": "Skill", "tool_input": {"skill": sys.argv[1]}, "session_id": sys.argv[2]}))' "$1" "$2"
}

# Build an MCP tool-call payload keyed to a session_id.
mcp_session_payload() {
  python3 -c 'import json, sys; print(json.dumps({"tool_name": sys.argv[1], "tool_input": {}, "session_id": sys.argv[2]}))' "$1" "$2"
}

AG_COLD="test-atlassian-gate-cold-$$"
AG_ENGAGED="test-atlassian-gate-engaged-$$"
AG_WRONGSKILL="test-atlassian-gate-wrongskill-$$"
AG_OTHER="test-atlassian-gate-other-$$"
AG_ESCAPE="test-atlassian-gate-escape-$$"

test_deny  "$ATLASSIAN_GATE" "cold connector-family MCP call (mcp__claude_ai_Atlassian_Rovo__*), no skill loaded" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' "$AG_COLD")"
test_deny  "$ATLASSIAN_GATE" "cold plugin-family MCP call (mcp__plugin_atlassian_atlassian__*), no skill loaded" \
  "$(mcp_session_payload 'mcp__plugin_atlassian_atlassian__editJiraIssue' "$AG_COLD")"
test_allow "$ATLASSIAN_GATE" "Skill(jira-acli:acli) load is never itself blocked" \
  "$(skill_payload 'jira-acli:acli' "$AG_ENGAGED")"
test_allow "$ATLASSIAN_GATE" "same-session MCP call allowed once jira-acli:acli loaded" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' "$AG_ENGAGED")"
test_allow "$ATLASSIAN_GATE" "same-session confluence-content fallback (page create) also allowed once engaged" \
  "$(mcp_session_payload 'mcp__plugin_atlassian_atlassian__createConfluencePage' "$AG_ENGAGED")"
test_allow "$ATLASSIAN_GATE" "Skill(other:x) load is never itself blocked" \
  "$(skill_payload 'mh:orchestrate' "$AG_WRONGSKILL")"
test_deny  "$ATLASSIAN_GATE" "a non-jira-acli skill does not engage the session" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__getJiraIssue' "$AG_WRONGSKILL")"
test_deny  "$ATLASSIAN_GATE" "a different, still-cold session stays blocked (marker is per-session)" \
  "$(mcp_session_payload 'mcp__plugin_atlassian_atlassian__editJiraIssue' "$AG_OTHER")"
test_allow "$ATLASSIAN_GATE" "unrelated MCP tool (mongodb) out of scope" \
  "$(mcp_session_payload 'mcp__mongodb__find' "$AG_COLD")"
test_allow "$ATLASSIAN_GATE" "unrelated MCP tool (code-review-graph) out of scope" \
  "$(mcp_session_payload 'mcp__code-review-graph__query_graph_tool' "$AG_COLD")"
test_allow "$ATLASSIAN_GATE" "malformed stdin (fail-safe allow)" \
  '{not valid json'
test_allow "$ATLASSIAN_GATE" "escape hatch MH_ALLOW_DIRECT_ATLASSIAN_MCP=1 bypasses a cold block" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' "$AG_ESCAPE")" \
  "MH_ALLOW_DIRECT_ATLASSIAN_MCP=1"

# Portability (#93): without the jira-acli plugin installed anywhere in the
# cache, a cold Atlassian call must pass untouched — blocking would prescribe
# skills the machine cannot load. Empty fixture HOME = no plugin.
AG_NOPLUGIN_HOME=$(mktemp -d "${TMPDIR:-/tmp}/kbg-ag-nohome.XXXXXX")
test_allow "$ATLASSIAN_GATE" "no jira-acli plugin in cache -> cold Atlassian call allowed (feature-detect)" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' "$AG_COLD")" \
  "HOME=$AG_NOPLUGIN_HOME"

export HOME="$AG_REAL_HOME"

echo ""
echo "=== fast-path (bash pre-filter that skips python3 on commands that cannot match, added 2026-08-14) ==="
# irrecoverable + verifier-protect gained a bash fast-path so a benign command
# skips the python3 cold-start. The fast-path only exits 0 (never 2), so a
# deny-case still exiting 2 / an ask-case still emitting stdout PROVES python ran
# and the fast-path did not short-circuit it. These guard the fast-path's own
# specific risks (the existing suite already covers the git-apply-with-verifier-
# diff fail-open at line ~314, which the carrier fall-through must preserve).
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
# verifier-protect: a Write to a file_path containing "Bash" must NOT be
# mis-routed through the Bash fast-path (which would exit 0 and skip the Write
# ask) -- the tool_name peek matches the quoted value precisely.
test_ask   "$VERIFIER_PROTECT" "Write to hooks/gates/Bash.sh (mis-route guard: file_path contains Bash)" \
  "$(write_payload 'hooks/gates/Bash.sh' 'echo neutered')"
# verifier-protect: write/carrier substrings with no verifier path fast-exit 0
# (the latency win); the fast-path must not deny (it never does) and python
# (if a carrier substring like 'tar' in 'start' reaches it) must allow.
test_allow "$VERIFIER_PROTECT" "npm install (write token 'install', no verifier path -> allow)" \
  "$(bash_payload 'npm install')"
test_allow "$VERIFIER_PROTECT" "npm start (carrier 'tar' in 'start', false-pos -> allow)" \
  "$(bash_payload 'npm start')"
test_allow "$VERIFIER_PROTECT" "ls (no write token -> fast allow)" \
  "$(bash_payload 'ls -la')"
test_allow "$VERIFIER_PROTECT" "echo > /tmp/x (redirect, no verifier path -> allow)" \
  "$(bash_payload 'echo x > /tmp/x')"

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

NOPY_AG_HOME=$(mktemp -d "${TMPDIR:-/tmp}/kbg-nopy-home.XXXXXX")
mkdir -p "$NOPY_AG_HOME/.claude/plugins/cache/wasikarn/jira-acli"

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
test_nopython_allow "$VERIFIER_PROTECT" "verifier-protect: Write to a gate path passes with note" \
  "$(write_payload 'hooks/gates/x.sh' 'echo y')"
test_nopython_allow "$DB_WRITE_GATE" "db-write: SQL write passes with note" \
  "$(mcp_sql_payload 'mcp__example-db__execute_sql_production' 'DELETE FROM users')"
test_nopython_allow "$TASK_COMPLETE" "task-complete-separation: subagent completion passes with note" \
  "$(taskupdate_payload 'completed' 'refactor-cleaner')"
test_nopython_allow "$AGENT_RECURSION_GUARD" "agent-recursion-guard: subagent dispatch passes with note" \
  "$(agent_payload 'general-purpose' 'refactor-cleaner')"
test_nopython_allow "$ATLASSIAN_GATE" "atlassian gate: cold Atlassian call passes with note (jira-acli present in fixture HOME)" \
  "$(mcp_session_payload 'mcp__claude_ai_Atlassian_Rovo__createJiraIssue' 'nopy-session')" \
  "HOME=$NOPY_AG_HOME"
test_nopython_allow "$ROOT/hooks/gates/worktree-guard-dispatch.sh" "worktree-guard-dispatch: guarded workspace passes with note" \
  "$(bash_payload 'echo x')" \
  "MH_GUARDED_WORKSPACE=/tmp/kbg-nopy-ws" "CLAUDE_PROJECT_DIR=/tmp/kbg-nopy-ws" "CLAUDE_PLUGIN_ROOT=$ROOT"

# trash-fallback deny message (#93): with python3 present but NO trash CLI on
# PATH, the rm -rf deny must still fire (rc=2) and the message must route to
# the user instead of prescribing a binary the machine doesn't have.
TRASHLESS_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-notrash.XXXXXX")
for _t in bash cat sed tr grep python3; do
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
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
