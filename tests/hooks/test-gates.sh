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

# Raw-substring matching produced both false positives (blocked safe commands merely mentioning
# a pattern in quoted text) and bypasses (quoted/tokenization tricks slipped past the regex).
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
test_allow "$IRRECOVERABLE" "git checkout -b new branch from start-point (create, not tree+path)" \
  "$(bash_payload 'git checkout -b feat origin/develop')"
test_deny  "$IRRECOVERABLE" "git checkout -b with tree-ish AND path still denied" \
  "$(bash_payload 'git checkout -b feat HEAD~1 file.txt')"
# The force check only matched the exact token "-f"/ "--force", missing a bundled short-flag
# cluster like "-qf" (quiet+force).
test_deny "$IRRECOVERABLE" "git checkout -qf bundled force flag (was a bypass)" \
  "$(bash_payload 'git checkout -qf other-branch')"
test_deny "$IRRECOVERABLE" "git switch -fq bundled force flag (was a bypass)" \
  "$(bash_payload 'git switch -fq other-branch')"
# The fix scans bundled clusters for "f" but must stop at a value-taking flag letter (checkout's
# -b/-B, switch's -c/-C) so the branch-name argument itself isn't misread as more bundled flags.
test_allow "$IRRECOVERABLE" "git checkout -bfoo (branch name starting with f, must not over-block)" \
  "$(bash_payload 'git checkout -bfoo')"
test_allow "$IRRECOVERABLE" "git switch -cfoo (branch name starting with f, must not over-block)" \
  "$(bash_payload 'git switch -cfoo')"
test_allow "$IRRECOVERABLE" "git checkout -Bfoo (uppercase stop-char variant, must not over-block)" \
  "$(bash_payload 'git checkout -Bfoo')"
test_allow "$IRRECOVERABLE" "git switch -Cfoo (uppercase stop-char variant, must not over-block)" \
  "$(bash_payload 'git switch -Cfoo')"
# A HEREDOC-authored commit message (this repo's own documented convention) that merely mentions
# "git checkout X Y" in prose was tokenized as a real command and falsely denied.
test_allow "$IRRECOVERABLE" "quoted-delimiter heredoc body mentioning checkout no longer false-blocks" \
  "$(bash_payload $'git commit -m "$(cat <<\'EOF\'\nthis mentions git checkout old new extra in prose\nEOF\n)"')"
test_deny "$IRRECOVERABLE" "dangerous cmd inside a heredoc feeding an interpreter still blocked" \
  "$(bash_payload $'bash <<EOF\nrm -rf /tmp/danger\nEOF')"
# Newline and '&' are command separators in bash but shlex ate newline as whitespace and '&'
# wasn't in OPERATORS — a dangerous command after either hid inside the first command's window.
test_deny  "$IRRECOVERABLE" "dangerous cmd after newline" \
  "$(bash_payload $'echo hi\nrm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "dangerous cmd after & (background)" \
  "$(bash_payload 'echo done & rm -rf /tmp/x')"

# A backslash-newline inside a "#" comment is not a continuation: the newline still separates.
test_deny  "$IRRECOVERABLE" "backslash-newline inside a # comment does not hide the next real command (exact repro)" \
  "$(bash_payload $'git status # comment \\\ngit push origin develop --force')"
test_deny  "$IRRECOVERABLE" "same shape, comment with no trailing backslash (pre-existing case, must stay denied)" \
  "$(bash_payload $'git status # comment\ngit push origin develop --force')"
test_deny  "$IRRECOVERABLE" "real backslash-newline continuation (no comment) still joins tokens for detection" \
  "$(bash_payload $'git push --force \\\n  origin develop')"
test_allow "$IRRECOVERABLE" "legit backslash-newline continuation outside a comment still allows (no false split)" \
  "$(bash_payload $'git log --oneline \\\n  -5')"

# A backslash-newline continuation with NO leading whitespace on the continuation line bypassed
# force-push detection.
test_deny  "$IRRECOVERABLE" "backslash-newline continuation with NO leading whitespace on the next line (exact repro, was a bypass)" \
  "$(bash_payload $'git push \\\n--force origin develop')"
test_deny  "$IRRECOVERABLE" "same shape, leading whitespace on the next line (already worked, stays denied)" \
  "$(bash_payload $'git push \\\n  --force origin develop')"
# Adjacent shapes: back-to-back continuations gluing flags, and a trailing continuation.
test_deny  "$IRRECOVERABLE" "two whitespace-less continuations back to back, force flag glued onto the second (adjacent-shape check)" \
  "$(bash_payload $'git push origin\\\ndevelop --for\\\nce')"
test_allow "$IRRECOVERABLE" "trailing whitespace-less continuation at the very end of the command, nothing after it (no crash, no dangerous token)" \
  "$(bash_payload $'git push origin develop\\\n')"
# The DQ-quoted branch of _newlines_to_seps had the identical unremoved- newline defect for a
# continuation inside a double-quoted string (bash strips backslash-newline there too).
test_deny  "$IRRECOVERABLE" "whitespace-less continuation inside a double-quoted flag still reassembles (adjacent-shape check)" \
  "$(bash_payload $'git push "--for\\\nce" origin develop')"
test_deny  "$IRRECOVERABLE" "trailing # comment on the same line does not hide the command before it" \
  "$(bash_payload 'git push origin develop --force # not a real flag, just a comment')"

# ANSI-C ($'...') quoting resolves escape sequences in real bash.
test_deny "$IRRECOVERABLE" "ANSI-C quoted argv0 splice (gi\$'\x74' push --force, was a bypass)" \
  "$(bash_payload "gi\$'\\x74' push --force origin develop")"
# Negative control 1: an ordinary single-quoted argument (no \$'...' form, never enters the
# ANSI-C regex at all) must stay correctly classified.
test_allow "$IRRECOVERABLE" "ordinary single-quoted commit message unaffected by ANSI-C normalization" \
  "$(bash_payload "git commit -m 'a normal message'")"
# Negative control 2: a REAL \$'...' payload that DOES enter the new decode path.
test_allow "$IRRECOVERABLE" "ANSI-C commit message with embedded \\n stays one window, not force-push (real decode-path exercise)" \
  "$(bash_payload $'git commit -m $\'line1\\nline2\'')"

# A command-substitution splice (backtick or \$(...)) vanishes in real bash once its output
# splices into the surrounding text.
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
# Blanking a substitution SPAN must not DISCARD its body.
test_deny "$IRRECOVERABLE" "substitution BODY is the dangerous command, not just the dispatch token (echo \$(git push --force), was silently allowed by a blank-only pass)" \
  "$(bash_payload 'echo $(git push --force)')"
test_allow "$IRRECOVERABLE" "re-appended substitution body is ordinary commit-message prose, not a command (git commit -m \"\$(cat msg.txt)\") -- proves body re-append does not false-deny" \
  "$(bash_payload 'git commit -m "$(cat msg.txt)"')"
# A SINGLE-quoted $(...) is inert in bash and must not be extracted as a body; a DOUBLE-quoted
# one is live and must still be caught.
test_allow "$IRRECOVERABLE" "single-quoted \$(...) is inert prose, must not be extracted and re-denied (git commit -m single-quote prose mentioning \$(git push --force))" \
  "$(bash_payload "git commit -m 'prose mentioning \$(git push --force)'")"
test_deny "$IRRECOVERABLE" "double-quoted argv0 splice stays a live vector, not given the single-quote passthrough (\"gi\$(true)t\" push --force)" \
  "$(bash_payload '"gi$(true)t" push --force')"

# An apostrophe inside a blanked substitution body raises ValueError in shlex; the old raw
# cmd.split() fallback carried no PH, so the splice was silently allowed.
test_deny "$IRRECOVERABLE" "backtick splice with an apostrophe inside the body defeats the old raw cmd.split() fallback (gi\`it's\`t push --force, was silently ALLOWed)" \
  "$(bash_payload $'gi`it\'s`t push --force')"
test_deny "$IRRECOVERABLE" "\$(...) splice with an apostrophe inside the body, same bypass shape (gi\$(it's)t push --force, was silently ALLOWed)" \
  "$(bash_payload $'gi$(it\'s)t push --force')"

# Bug 2 (false-DENY): the KNOWN_DANGEROUS/KNOWN_GIT_SUBS candidate duplication runs every
# candidate's check against the SAME rest/scan tokens, and two of those checks were bare letter-
# containment against a whole joined-flags string rather than a real flag-boundary test.
test_allow "$IRRECOVERABLE" "substitution dispatch token resolving to a benign command, long flag falsely read as rm -rf (\$(which node) --before=1, was a false DENY)" \
  "$(bash_payload '$(which node) --before=1')"
test_allow "$IRRECOVERABLE" "git diff splice, long flag falsely read as git clean -f (git di\$(true)ff --find-renames, was a false DENY)" \
  "$(bash_payload 'git di$(true)ff --find-renames')"
test_allow "$IRRECOVERABLE" "git show splice, long flag falsely read as git clean -f (git sh\$(true)ow --format=fuller, was a false DENY)" \
  "$(bash_payload 'git sh$(true)ow --format=fuller')"

# The _SQ_SPAN regex used to detect inert single-quoted text paired literal apostrophe
# CHARACTERS wherever they fell, with zero notion of real shell quote state.
test_deny "$IRRECOVERABLE" "contraction apostrophes inside double quotes pair up ACROSS a real \$(...) splice, hiding it as inert single-quoted data (was a live bypass)" \
  "$(bash_payload $'echo "it\'s" ; gi$(true)t push --force ; echo "isn\'t"')"
test_allow "$IRRECOVERABLE" "same stray contraction apostrophe shifts pairing so a REAL single-quoted -m argument is no longer matched as one span (was a false DENY of inert commit-message text)" \
  "$(bash_payload $'echo "it\'s" ; git commit -m \'see $(git push --force)\'')"

# "$(true)-rf" IS "-rf" in bash but blanks to "PH-rf", which no longer starts with "-", so every
# flag-shape check missed it; PH is stripped before each such check.
test_deny "$IRRECOVERABLE" "empty-substitution splice hides rm -rf's dash (rm \$(true)-rf /tmp/x, was silently ALLOWed)" \
  "$(bash_payload 'rm $(true)-rf /tmp/x')"
test_deny "$IRRECOVERABLE" "same bug via backticks (rm \`true\`-rf /tmp/x, was silently ALLOWed)" \
  "$(bash_payload 'rm `true`-rf /tmp/x')"
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git push --force's dashes (git push \$(true)--force, was silently ALLOWed)" \
  "$(bash_payload 'git push $(true)--force')"
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git clean -f's dash (git clean \$(true)-f, was silently ALLOWed)" \
  "$(bash_payload 'git clean $(true)-f')"
# Negative control: the substitution sits inside a QUOTED ARGUMENT VALUE (a real -m message),
# not in flag position.
test_allow "$IRRECOVERABLE" "substitution inside a quoted -m message value, not a bare flag position (git commit -m \"\$(cat msg.txt)\") -- must stay ALLOW" \
  "$(bash_payload 'git commit -m "$(cat msg.txt)"')"

# The $(...)/${...} closer-search used to stop at the FIRST ")" byte, not the matching one, so
# a nested paren left the span un-blanked.
test_deny "$IRRECOVERABLE" "nested function-construct inside \$(...) defeats the old first-byte closer-search, real bash resolves to git push --force (GH #139, was a silent bypass)" \
  "$(bash_payload 'gi$(f() { :; }; f)t push --force origin develop')"

# Companion DoS check for the same fix: depth-counting a closer-search that never balances (an
# adversarial flood of unclosed "$(" starts) must stay bounded by a work budget instead of
# costing O(remaining length) PER start.
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

# Leading-PH strip applied to every flag check (Layer 1), the wrapper/re-pointing loops
# (Layer 2), and standalone vanish tokens compacted out (Layer 3).
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git stash drop (git stash \$(true)drop, was silently ALLOWed)" \
  "$(bash_payload 'git stash $(true)drop')"
test_deny "$IRRECOVERABLE" "empty-substitution splice hides git stash clear (git stash \$(true)clear, was silently ALLOWed)" \
  "$(bash_payload 'git stash $(true)clear')"
test_deny "$IRRECOVERABLE" "baseline: plain git stash drop, no splice at all (must still deny)" \
  "$(bash_payload 'git stash drop')"
test_deny "$IRRECOVERABLE" "baseline: plain git stash clear, no splice at all (must still deny)" \
  "$(bash_payload 'git stash clear')"
# A splice landing mid-basename or mid-SQL-keyword needs full PH removal, not a leading strip.
test_deny "$IRRECOVERABLE" "empty-substitution splice hides dd's of=/dev/ prefix (was silently ALLOWed)" \
  "$(bash_payload 'dd if=/dev/zero $(true)of=/dev/sda')"
test_deny "$IRRECOVERABLE" "baseline: plain dd of=/dev, no splice (must still deny)" \
  "$(bash_payload 'dd if=/dev/zero of=/dev/sda')"
test_deny "$IRRECOVERABLE" "splice lands mid-keyword in a destructive SQL statement (DR\$(true)OP TABLE, was silently ALLOWed -- the old check only handled a LEADING splice, not one INSIDE a keyword)" \
  "$(bash_payload 'mysql -e "DR$(true)OP TABLE users"')"
test_deny "$IRRECOVERABLE" "baseline: plain destructive SQL, no splice (must still deny)" \
  "$(bash_payload 'mysql -e "DROP TABLE users"')"
# --- Layer 2, exhaustive-grep finds: the prefix-wrapper unwrap loops
# (env/nice/sudo/command/nohup/time) and the xargs/docker-exec re-pointing never stripped a
# leading PH from the flags they read either.
test_deny "$IRRECOVERABLE" "docker exec flag splice defeats the inner-command re-point, hiding destructive SQL (docker exec \$(true)-i c1 mysql -e DROP TABLE, was silently ALLOWed)" \
  "$(bash_payload 'docker exec $(true)-i c1 mysql -e "DROP TABLE users"')"
test_deny "$IRRECOVERABLE" "docker exec-itself splice defeats the inner-command re-point, hiding destructive SQL (docker \$(true)exec c1 mysql -e DROP TABLE, was silently ALLOWed)" \
  "$(bash_payload 'docker $(true)exec c1 mysql -e "DROP TABLE users"')"
# --- Layer 3: a standalone unquoted vanish token shifts fixed-index reads.
test_allow "$IRRECOVERABLE" "Layer 3 negative control: \$(which git) status -- compacted window drops argv0 entirely, must stay ALLOW" \
  "$(bash_payload '$(which git) status')"

# Appending recovered substitution bodies with a plain " ; " separator left no newline to
# terminate an earlier, still-open "#" comment.
test_deny "$IRRECOVERABLE" "trailing comment after a live substitution buried the recovered body in an open shlex comment (echo \$(git push --force)  # push it, was silently ALLOWed)" \
  "$(bash_payload 'echo $(git push --force)  # push it')"
test_deny "$IRRECOVERABLE" "same bug via a # embedded inside an EARLIER recovered body (echo \$(echo hi # note) \$(git push --force), was silently ALLOWed)" \
  "$(bash_payload 'echo $(echo hi # note) $(git push --force)')"
test_deny "$IRRECOVERABLE" "baseline: same splice with no comment at all, no bug involved (must stay denied)" \
  "$(bash_payload 'echo $(git push --force)')"

# Finding 5 (MEDIUM, live, universal): _scan_once tracked in_squote/ in_dquote but had no
# in_comment state, so a substitution-shaped string sitting INSIDE a real "#" comment still got
# matched, blanked, and its body collected as if it were live code.
test_allow "$IRRECOVERABLE" "a substitution-shaped fake payload sitting inside a real # comment must not be recovered as a live body (git status # see also: \$(git push --force), followed by a real newline and echo done, was a false DENY)" \
  "$(bash_payload $'git status # see also: $(git push --force)\necho done\n')"

# The closer-search does not track quotes INSIDE a span, so a span crossing a quote char left a
# valid command unbalanced and falsely denied; re-parse of the original cmd tells the cases apart.
test_allow "$IRRECOVERABLE" "read-only python3 heredoc with an unmatched \${ inside a properly-quoted string desyncs _blank_substitutions own quote tracking (was a false DENY with no override)" \
  "$(bash_payload $'python3 - <<\'PY\'\n "10k unmatched ${ (20KB)": "${ "*10000,\n}\nPY\n')"
# Negative control: a genuinely malformed command (unterminated quote, no _scan_once span
# involved at all) must still deny with the same message.
test_deny "$IRRECOVERABLE" "genuinely malformed command, unterminated quote unrelated to any substitution span (must still deny)" \
  "$(bash_payload "echo 'unterminated")"
# Negative control: the two GH #129 apostrophe-in-body bypass tests already above
# (backtick/\$(...) splice with an apostrophe inside the recovered body) must still deny.
test_deny "$IRRECOVERABLE" "Finding 4 fix must not reopen the GH #129 apostrophe-in-body bypass, backtick form (gi\`it's\`t push --force, must stay DENY)" \
  "$(bash_payload $'gi`it\'s`t push --force')"
test_deny "$IRRECOVERABLE" "Finding 4 fix must not reopen the GH #129 apostrophe-in-body bypass, \$(...) form (gi\$(it's)t push --force, must stay DENY)" \
  "$(bash_payload $'gi$(it\'s)t push --force')"

# The fallback split must be separator-aware: a bare cmd.split() glued "};git" into one token.
test_deny "$IRRECOVERABLE" "Finding 4 fallback must not glue a dangerous SECOND command onto its no-space ; separator (echo \${y:-\"a}b\"};git push --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"};git push --force')"
test_deny "$IRRECOVERABLE" "same bug via a no-space && separator (echo \${y:-\"a}b\"}&&git push --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"}&&git push --force')"
test_deny "$IRRECOVERABLE" "baseline: same compound command with the ; surrounded by whitespace, no bug involved (must stay denied)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; git push --force')"

# A splice reaching only the fallback path carries raw substitution syntax, no PH; duplication
# also fires on raw syntax.
test_deny "$IRRECOVERABLE" "Finding 4 fallback duplication trigger missed a spliced ARGV0 with no PH (echo \${y:-\"a}b\"} ; gi\$(true)t push --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; gi$(true)t push --force')"
test_deny "$IRRECOVERABLE" "same bug, spliced git SUBCOMMAND instead of argv0 (echo \${y:-\"a}b\"} ; git pu\$(true)sh --force, was silently ALLOWed)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; git pu$(true)sh --force')"
test_deny "$IRRECOVERABLE" "same argv0 bug with the dangerous command BEFORE the quote-crossing span (gi\$(true)t push --force ; echo \${y:-\"a}b\"}, was silently ALLOWed)" \
  "$(bash_payload 'gi$(true)t push --force ; echo ${y:-"a}b"}')"
test_deny "$IRRECOVERABLE" "same subcommand bug with the dangerous command BEFORE the quote-crossing span (git pu\$(true)sh --force ; echo \${y:-\"a}b\"}, was silently ALLOWed)" \
  "$(bash_payload 'git pu$(true)sh --force ; echo ${y:-"a}b"}')"
# Negative controls: the widened trigger must not over-deny once the fallback path is live.
test_allow "$IRRECOVERABLE" "fallback-path splice resolving to a benign git subcommand (echo \${y:-\"a}b\"} ; gi\$(true)t status, must stay ALLOW even though duplication tries argv0==git -- the quote-crossing span forces the fallback so this token never gets PH at all, only _has_raw_subst catches it)" \
  "$(bash_payload 'echo ${y:-"a}b"} ; gi$(true)t status')"

# The fallback path must tokenize the SAME blanked pipeline as the primary path, or every
# downstream PH-based check is blind on it.
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

# A PH/raw-subst splice landing MID-FLAG (not leading) defeated every flag-recovery check
# written as "t.lstrip(PH) == '--force'".
test_deny "$IRRECOVERABLE" "mid-flag splice, git push --force (--for\$(true)ce, was silently ALLOWed)" \
  "$(bash_payload 'git push --for$(true)ce origin develop')"
test_deny "$IRRECOVERABLE" "mid-flag splice, git reset --hard (--har\$(true)d, was silently ALLOWed)" \
  "$(bash_payload 'git reset --har$(true)d HEAD~1')"
test_deny "$IRRECOVERABLE" "mid-flag splice, git commit --amend (--am\$(true)end, was silently ALLOWed)" \
  "$(bash_payload 'git commit --am$(true)end -m x')"
test_deny "$IRRECOVERABLE" "mid-flag splice reaches the flag check via the fallback path too, not just the primary shlex path (was silently ALLOWed)" \
  "$(bash_payload "${FORCE_FALLBACK}git push --for\$(true)ce origin develop")"
# Negative controls: the same flags with no splice at all must stay denied exactly as before.
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
test_allow "$IRRECOVERABLE" "git push --force-with-lease --force-if-includes (safest variant)" \
  "$(bash_payload 'git push --force-with-lease --force-if-includes origin develop')"
test_allow "$IRRECOVERABLE" "git push normal (no force)" \
  "$(bash_payload 'git push origin develop')"

# A leading git GLOBAL flag (-C/-c/--git-dir/--work-tree/ --config-env, bare or
# combined -Cpath/--git-dir=path) set sub to the flag itself, so the push/worktree/--no-verify
# gates were bypassable by prefixing it.
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

# The gate correctly denies each idiom below TODAY, but no test held the deny path, so a
# mutation to the wrapper-unwrap / hooksPath / branch-delete / backstop logic survived the whole
# suite (fail-open, undetected).
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

# --- operator-glue / grouping-token bypass: without punctuation_chars, "echo hi;rm -rf x"
# tokenized as one glued word "hi;rm" and "(rm -rf x)" left "(" as argv0.
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
test_deny  "$IRRECOVERABLE" "git config core.hooksPath <other> (persistent hook bypass)" \
  "$(bash_payload 'git config core.hooksPath /dev/null')"
test_deny  "$IRRECOVERABLE" "git config --unset core.hooksPath (persistent hook bypass)" \
  "$(bash_payload 'git config --unset core.hooksPath')"
test_allow "$IRRECOVERABLE" "git config core.hooksPath git-hooks (documented wiring)" \
  "$(bash_payload 'git config core.hooksPath git-hooks')"
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
# --- fail-closed internal-error backstop: a payload that makes the
# Python raise (command is a JSON array, not a string) must still exit 2, never fall open.
test_deny  "$IRRECOVERABLE" "non-string command payload triggers the fail-closed backstop (exit 2, not fail-open)" \
  '{"tool_name":"Bash","tool_input":{"command":["rm","-rf","/x"]}}'

# --- GH #140: unbounded shlex tokenize cost on an oversized raw command string.
_len_pad=$(python3 -c "print('A' * 700000)")

_rc=$(bash_payload "git push --force origin $_len_pad" | timeout 2 bash "$IRRECOVERABLE" 2>/dev/null; echo $?)
if [[ "$_rc" == "2" ]]; then
  echo "  ✅ DENY (<2s): oversized single-token dangerous command still denies (GH #140 length cap)"
  pass=$((pass + 1))
else
  echo "  ❌ DENY EXPECTED (<2s) but got exit $_rc: oversized dangerous command (GH #140 length cap)" >&2
  fail=$((fail + 1))
fi

# Direction-pinning: the SAME oversized padding on a BENIGN tail (git status matches no deny
# pattern at all) must ALSO deny fast.
_rc=$(bash_payload "git status $_len_pad" | timeout 2 bash "$IRRECOVERABLE" 2>/dev/null; echo $?)
if [[ "$_rc" == "2" ]]; then
  echo "  ✅ DENY (<2s): oversized BENIGN-tail command still denies -- pins the cap, not a pattern match (GH #140)"
  pass=$((pass + 1))
else
  echo "  ❌ DENY EXPECTED (<2s) but got exit $_rc: oversized benign-tail command (GH #140 length cap)" >&2
  fail=$((fail + 1))
fi

# Negative control: a realistic, modestly-sized legitimate command.
test_allow "$IRRECOVERABLE" "realistic longer commit message, well under the GH #140 length cap -> still allows" \
  "$(bash_payload 'git commit -m "Implement feature X with detailed rationale covering edge cases and rollback plan for the release"')"

echo ""
echo "=== task-complete-separation gate (maker≠checker: subagent cannot self-complete) ==="
# Maker self-completion is the one thing the harness forbids — a subagent (agent_type present)
# calling TaskUpdate(completed) is blocked at exit 2.
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
# Security-review finding (2026-08-31): agent_type is also present for a top-level `claude
# --agent <name>` MAIN session (not a subagent) — keying on it over-blocks that legitimate case.
test_allow "$TASK_COMPLETE" "--agent main session (agent_type set, no agent_id) may still complete" \
  "$(taskupdate_payload completed some-agent-name '')"

echo ""
echo "=== nested-spawn deny (irrecoverable.py: a subagent may not spawn a nested claude session via Bash) ==="
# Security-review finding: a subagent retains Bash access, so `claude -p` from Bash spawns a
# nested session that never routes through the Agent tool.
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
# Deep-audit fresh adversarial pass, 2026-08-31: the un-anchored regex denied these three real,
# harmless commands because they merely CONTAIN the substring "claude -p" as prose/data, not as
# an invocation.
test_allow "$IRRECOVERABLE" "subagent commits a message mentioning the flag (prose, not invocation)" \
  "$(bash_agent_payload 'git commit -m "mention claude -p in docs"' fork)"
test_allow "$IRRECOVERABLE" "subagent echoes the pattern as a string, not a real invocation" \
  "$(bash_agent_payload 'echo "claude -p"' fork)"
test_allow "$IRRECOVERABLE" "subagent greps for the pattern (auditing this gate itself)" \
  "$(bash_agent_payload 'grep -r "claude -p" docs/' fork)"
# A flat [^|;&]* scan treated any &/;/| as end-of-invocation even inside a quoted prompt, so a
# spawn flag after a quoted separator evaded detection.
test_deny  "$IRRECOVERABLE" "spawn hidden behind an ampersand inside a quoted prompt" \
  "$(bash_agent_payload 'claude "fix A & B" -p' fork)"
test_deny  "$IRRECOVERABLE" "spawn hidden behind a semicolon inside a quoted prompt" \
  "$(bash_agent_payload 'claude "note; then" --print x' fork)"
test_deny  "$IRRECOVERABLE" "spawn hidden behind a pipe inside a single-quoted prompt" \
  "$(bash_agent_payload "claude 'use A | B' --agent x" fork)"
# Cross-segment separation must survive the quote-aware rewrite: a LATER, unrelated command's
# flag must never get credited to an earlier claude invocation that itself carries no spawn
# flag.
test_allow "$IRRECOVERABLE" "unrelated later command's flag does not leak back to claude" \
  "$(bash_agent_payload 'claude --version ; othertool -p' fork)"

# Heredoc-body stripping regression coverage.
test_allow "$IRRECOVERABLE" "heredoc-authored commit message mentioning feat(claude): and --bg in unrelated prose lines no longer false-blocks (GH #121 exact repro)" \
  "$(bash_agent_payload $'git commit -m "$(cat <<\'EOF\'\nfeat(claude): document the nested-spawn gate heredoc fix\nunrelated later line just happens to mention --bg here\nEOF\n)"' fork)"
# Dangerous-direction control: a heredoc body that DOES feed an interpreter is executable code,
# not inert data, so a real nested `claude -p` spawn hidden inside one must still be caught.
test_deny  "$IRRECOVERABLE" "nested claude spawn hidden inside an interpreter-fed heredoc body still blocked (bash <<EOF ... claude -p ... EOF, GH #121 dangerous-direction control)" \
  "$(bash_agent_payload $'bash <<EOF\nclaude -p "evil"\nEOF' fork)"

# --- bash -c / eval one-level unwrap ---
test_deny  "$IRRECOVERABLE" "bash -c with rm -rf inside" \
  "$(bash_payload 'bash -c "rm -rf build"')"
test_deny  "$IRRECOVERABLE" "sh -c with git push --force inside" \
  "$(bash_payload "sh -c 'git push --force origin main'")"
test_deny  "$IRRECOVERABLE" "bash -lc (bundled) with rm -rf inside" \
  "$(bash_payload 'bash -lc "cd x && rm -rf y"')"
test_deny  "$IRRECOVERABLE" "eval with rm -rf inside" \
  "$(bash_payload 'eval "rm -rf build"')"
test_allow "$IRRECOVERABLE" "bash -c with a harmless body" \
  "$(bash_payload 'bash -c "ls -la && git status"')"
test_allow "$IRRECOVERABLE" "bash -c body mentioning rm -rf as data" \
  "$(bash_payload 'bash -c "echo rm -rf is dangerous"')"
# Non-goal: cat <<EOF | bash, eval "$(cat <<EOF)", fish <<EOF, and a << lookalike inside quotes.
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
# Irrecoverable gained a bash fast-path so a benign command skips the python3 cold-start.
test_deny  "$IRRECOVERABLE" "r\"\"m -rf (quote-concatenation -> fast-path quote-strip)" \
  "$(bash_payload 'r""m -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "r\\m -rf (backslash-concatenation -> fast-path strip)" \
  "$(bash_payload 'r\m -rf /tmp/x')"
# A backslash-newline continuation splitting the argv0 ITSELF (not just a flag) turns the \n
# escape into a space at the fast-path's own sed step, so "git"/"rm" never survives as one
# substring and the fast path exits 0 before python3.
test_deny  "$IRRECOVERABLE" "gi + backslash-newline + t (argv0 split, was a fast-path bypass)" \
  "$(bash_payload $'gi\\\nt push --force origin develop')"
test_deny  "$IRRECOVERABLE" "r + backslash-newline + m (argv0 split, was a fast-path bypass)" \
  "$(bash_payload $'r\\\nm -rf /tmp/x')"

echo ""
echo "=== python3-missing fail-open (#93: every deny gate must exit 0 with ONE stderr note, never rc=127 or a silent block) ==="
# A PATH stub dir with the gates' shell dependencies (cat/sed/tr/grep + bash) but NO python3.
NOPY_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-nopy.XXXXXX")
for _t in bash cat sed tr grep; do
  _src=$(PATH="/usr/bin:/bin" command -v "$_t" || command -v "$_t")
  ln -s "$_src" "$NOPY_BIN/$_t"
done

# Test_nopython_allow <gate> <desc> <payload> [extra env VAR=VAL...]
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

# Test_documented_fastpath_allow <gate> <desc> <payload> [extra env VAR=VAL...] Inverse of
# test_nopython_allow above (same NOPY_BIN instrument, opposite expectation): asserts rc=0
# WITHOUT the "python3 not found" note, i.e.
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
# Backtick/$(...) fast-path bypass: a command substitution vanishes in real bash ("gi`true`t" IS
# "git" once bash evaluates it) but survives as literal characters through the fast path's
# normalization, so neither "git" nor any other tracked argv0 forms a contiguous substring and
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: backtick-split argv0 (gi\`true\`t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi`true`t push --force origin develop')"
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$(...)-split argv0 (gi\$(true)t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi$(true)t push --force origin develop')"
# Same class, two more splicing spellings found alongside the backtick/$(...) fix: ${x} with x
# unset expands to nothing ("gi${x}t" IS "git"), and $'...' ANSI-C quoting resolves escapes
# ("gi$'\x74'" IS "git").
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \${x}-split argv0 (gi\${x}t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi${x}t push --force origin develop')"
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$'...'-split argv0 (gi\$'\x74' push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload "gi\$'\\x74' push --force origin develop")"
# Fresh-context review finding (2026-09-03): $@ and $* are a 5th zero-width splicer the 4-marker
# enumeration above never covered.
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$@-split argv0 (gi\$@t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi$@t push --force origin develop')"
test_nopython_allow "$IRRECOVERABLE" "irrecoverable: \$*-split argv0 (gi\$*t push --force) still reaches the guard, not fast-path-exited" \
  "$(bash_payload 'gi$*t push --force origin develop')"
# A $ that arrives JSON-\uXXXX-escaped instead of as a literal byte is invisible to the raw
# _has_subst scan above.
test_documented_fastpath_allow "$IRRECOVERABLE" "irrecoverable: JSON \\u0024-escaped \$ around a \${x} splice (gi\\u0024{x}t push --force) -- raw scan blind, documented non-live gap" \
  '{"tool_name":"Bash","tool_input":{"command":"gi\u0024{x}t push --force origin develop"}}'
test_nopython_allow "$TASK_COMPLETE" "task-complete-separation: subagent completion passes with note" \
  "$(taskupdate_payload 'completed' 'refactor-cleaner')"

# Trash-fallback deny message (#93): with python3 present but NO trash CLI on PATH, the rm -rf
# deny must still fire (rc=2) and the message must route to the user instead of prescribing a
# binary the machine doesn't have.
TRASHLESS_BIN=$(mktemp -d "${TMPDIR:-/tmp}/kbg-notrash.XXXXXX")
# Dirname: GH #146 extracted irrecoverable.sh's embedded python3 -c block to a sibling
# irrecoverable.py, resolved via "$(dirname "$0")".
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
# Extracted this gate's embedded python3 -c block into a sibling irrecoverable.py, resolved via
# "$(dirname "$0")/irrecoverable.py".
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
