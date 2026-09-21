#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal \$ in test payload strings is intentional
# Gate unit tests: simulates PreToolUse JSON payloads and asserts allow/deny/ask.
# Each test_deny call expects exit 2; test_allow expects exit 0 + empty stdout;
# test_ask expects exit 0 + a permissionDecision: ask JSON on stdout.
# Run standalone: bash tests/hooks/test-gates.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Isolate the gate-verdict journal (hooks/gates/_journal.py) from this file's
# 165+ deny/ask assertions -- run standalone (this file's own header
# invites it), it would otherwise silently append rows to the operator's
# real ~/.local/share/kbg/metrics/gate-decisions.jsonl.
_JOURNAL_TMP="$(mktemp -d)"
trap 'trash "$_JOURNAL_TMP" 2>/dev/null || true' EXIT
export MH_GATE_JOURNAL_PATH="$_JOURNAL_TMP/gate-decisions.jsonl"
IRRECOVERABLE="$ROOT/hooks/gates/irrecoverable.sh"
TASK_COMPLETE="$ROOT/hooks/gates/task-complete-separation.sh"
SUBAGENT_GIT_GUARD="$ROOT/hooks/gates/subagent-git-guard.sh"
SUBAGENT_SPAWN_GUARD="$ROOT/hooks/gates/subagent-spawn-guard.sh"

pass=0
fail=0

# Build a minimal Bash tool payload. Uses json.dumps (not printf %s) so
# commands containing quotes/backslashes (e.g. mysql -e "DROP TABLE...",
# find -exec ... \;) don't produce malformed JSON that silently degrades
# to an empty command downstream. Piped via stdin, not argv: a GH #140-style
# oversized command (700k chars) as a literal exec() argument exceeds Linux's
# MAX_ARG_STRLEN (128 KiB per argument, a hard kernel cap absent on macOS),
# so python3 itself fails to exec with "Argument list too long" before ever
# reaching the gate under test -- confirmed live on Ubuntu 24.04. stdin has
# no such limit, and it also matches how the real hook receives its payload.
bash_payload() { printf '%s' "$1" | python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.stdin.read()}}))'; }

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

# Same shape as taskupdate_payload but the agent_id KEY is always forced
# present at an explicit value, including "" or JSON null -- taskupdate_payload
# above treats a falsy $3 as "omit the key" (main session shape), which cannot
# express "key present but empty/null" (GH #155: the .py gate's old `if not
# agent_id` check treated presence-with-empty/null the same as absence, same
# gap as GH #154 fixed in subagent-spawn-guard.py). $3 == "__NULL__" emits
# JSON null; anything else is used as the literal string value (including "").
taskupdate_payload_forced_id() {
  python3 -c '
import json, sys
status, agent, agent_id_raw = sys.argv[1], sys.argv[2], sys.argv[3]
ti = {"taskId": "T1"}
if status:
    ti["status"] = status
d = {"tool_name": "TaskUpdate", "tool_input": ti}
if agent:
    d["agent_type"] = agent
d["agent_id"] = None if agent_id_raw == "__NULL__" else agent_id_raw
print(json.dumps(d))
' "$1" "$2" "$3"
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

# Build a Bash tool-call payload with the agent_id KEY forced present at an
# explicit value, including "" or JSON null (C1b, harness gap-audit
# 2026-09-20) -- mirrors agent_payload_forced_id() below for the Bash tool,
# needed because irrecoverable.py's two nested-spawn call sites (top-level
# command and the bash -c/eval unwrapped body) are gated on agent_id
# PRESENCE, not truthiness, and bash_agent_payload() above can't express
# "key present but empty/null" (it omits the key entirely when $2 is falsy).
# $2 == "__NULL__" emits JSON null; anything else is the literal string value.
bash_agent_payload_forced_id() {
  python3 -c '
import json, sys
cmd, agent_id_raw = sys.argv[1], sys.argv[2]
d = {"tool_name": "Bash", "tool_input": {"command": cmd}}
d["agent_id"] = None if agent_id_raw == "__NULL__" else agent_id_raw
print(json.dumps(d))
' "$1" "$2"
}

# Build an Agent tool-call payload. $1=subagent_type for the dispatch (tool_input),
# $2=agent_id of the CALLER (empty = main session), $3=agent_type of the caller
# (optional, for the deny message only — the gate's logic keys on agent_id, not
# this field, same distinction task-complete-separation.py documents).
agent_payload() {
  python3 -c '
import json, sys
subagent_type, agent_id, agent_type = sys.argv[1], sys.argv[2], sys.argv[3]
d = {"tool_name": "Agent", "tool_input": {"prompt": "do work", "description": "task", "subagent_type": subagent_type}}
if agent_id:
    d["agent_id"] = agent_id
if agent_type:
    d["agent_type"] = agent_type
print(json.dumps(d))
' "$1" "$2" "${3-}"
}

# Build an Agent tool-call payload with the agent_id KEY forced present at an
# explicit value, including "" or JSON null -- agent_payload() above treats a
# falsy $2 as "omit the key" (main session shape), which cannot express
# "key present but empty/null" (GH #154 gap 2: the .py gate's old `if not
# agent_id` check treated presence-with-empty/null the same as absence).
# $2 == "__NULL__" emits JSON null; anything else is used as the literal string
# value (including "").
agent_payload_forced_id() {
  python3 -c '
import json, sys
subagent_type, agent_id_raw = sys.argv[1], sys.argv[2]
d = {"tool_name": "Agent", "tool_input": {"prompt": "do work", "description": "task", "subagent_type": subagent_type}}
d["agent_id"] = None if agent_id_raw == "__NULL__" else agent_id_raw
print(json.dumps(d))
' "$1" "$2"
}

# Build an Agent tool-call payload where the agent_id KEY is written as the
# JSON _ escape for the underscore (agent_id) instead of a literal
# underscore -- valid JSON decoding to the key "agent_id", but the RAW text
# never contains the substring "agent_id" (GH #154 gap 1: the .sh gate's old
# bash fast-path was a raw-text substring match performed before any JSON
# parsing, so an escaped key silently bypassed it). Built with chr(92) rather
# than a literal backslash so the escape survives untouched through argv/tool
# transports that would otherwise decode _ before it reaches this script.
agent_payload_escaped_id_key() {
  python3 -c '
key = "agent" + chr(92) + "u005f" + "id"
print("{\"tool_name\": \"Agent\", \"tool_input\": {\"prompt\": \"do work\", "
      "\"description\": \"task\", \"subagent_type\": \"general-purpose\"}, \"" + key + "\": \"agent-1\"}")
'
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
# H3 (harness gap-audit, 2026-09-20): the same DROP/TRUNCATE check names all
# four SQL clients (line 938's argv0 tuple) but only mysql had a test.
test_deny  "$IRRECOVERABLE" "SQL DROP DATABASE via psql (H3, was untested)" \
  "$(bash_payload 'psql -c "DROP DATABASE x"')"
test_deny  "$IRRECOVERABLE" "SQL DROP TABLE via sqlite3 (H3, was untested)" \
  "$(bash_payload 'sqlite3 db.sqlite "DROP TABLE users"')"
test_deny  "$IRRECOVERABLE" "SQL TRUNCATE via mariadb (H3, was untested)" \
  "$(bash_payload 'mariadb -e "TRUNCATE orders"')"
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
# 2026-09-20 audit: the -c branch did an exact-case startswith("core.hooksPath=")
# check while the sibling `git config` branch two lines below already lowercased --
# git itself treats the key case-insensitively, so a differently-cased key bypassed
# this gate while still working as a real hook-path override.
test_deny  "$IRRECOVERABLE" "git -c core.HOOKSPATH= (case-insensitive hookspath bypass, was silently ALLOWed)" \
  "$(bash_payload 'git -c core.HOOKSPATH=/tmp/evil commit -m x')"
test_deny  "$IRRECOVERABLE" "git -cCore.HooksPath= (joined form, mixed case, was silently ALLOWed)" \
  "$(bash_payload 'git -cCore.HooksPath=/tmp/evil commit -m x')"
# 2026-09-21 deep-audit: real git honors --config-env=KEY=VAR / --config-env KEY=VAR
# exactly like -c KEY=<value of VAR>, but only -c was checked.
test_deny  "$IRRECOVERABLE" "git --config-env=core.hooksPath=VAR (joined form, hook bypass, was silently ALLOWed)" \
  "$(bash_payload 'git --config-env=core.hooksPath=EVIL commit -m x')"
test_deny  "$IRRECOVERABLE" "git --config-env core.hookspath=VAR (split form, lowercase key, was silently ALLOWed)" \
  "$(bash_payload 'git --config-env core.hookspath=EVIL commit -m x')"
test_allow "$IRRECOVERABLE" "git --config-env=user.name=X (benign key, must not over-block)" \
  "$(bash_payload 'git --config-env=user.name=X commit -m x')"
# 2026-09-21 deep-audit: a bare NAME=value assignment prefix made argv0 "FOO=bar",
# so every token-dispatched deny (rm, git push --force, ...) fell through.
test_deny  "$IRRECOVERABLE" "FOO=bar rm -rf (assignment prefix, was silently ALLOWed)" \
  "$(bash_payload 'FOO=bar rm -rf /tmp/x')"
test_deny  "$IRRECOVERABLE" "FOO=bar git push --force (assignment prefix, was silently ALLOWed)" \
  "$(bash_payload 'FOO=bar git push --force origin main')"
test_deny  "$IRRECOVERABLE" "GIT_CONFIG_PARAMETERS=core.hooksPath=... git commit (env-var hook bypass, was silently ALLOWed)" \
  "$(bash_payload 'GIT_CONFIG_PARAMETERS="'"'"'core.hooksPath=/dev/null'"'"'" git commit -m x')"
test_deny  "$IRRECOVERABLE" "env GIT_CONFIG_PARAMETERS=core.hooksPath=... git commit (same via env wrapper)" \
  "$(bash_payload 'env GIT_CONFIG_PARAMETERS="'"'"'core.hooksPath=/dev/null'"'"'" git commit -m x')"
test_allow "$IRRECOVERABLE" "FOO=bar ls (assignment prefix on a benign command)" \
  "$(bash_payload 'FOO=bar ls')"
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
# 2026-09-20 audit: git accepts an unambiguous prefix of any long flag
# (--no-veri for --no-verify, etc). Every exact-string `== "--force"`-style
# check below was bypassed live by git's own long-option abbreviation feature.
# push --force is deliberately NOT tested here: git rejects a shortened
# --forc as ambiguous with --force-with-lease/--force-if-includes, so that
# call site is confirmed non-exploitable and was left untouched by the fix.
test_deny  "$IRRECOVERABLE" "git commit --no-veri (abbreviated --no-verify, was silently ALLOWed)" \
  "$(bash_payload 'git commit --no-veri -m msg')"
test_deny  "$IRRECOVERABLE" "git reset --ha (abbreviated --hard, was silently ALLOWed)" \
  "$(bash_payload 'git reset --ha HEAD~1')"
test_deny  "$IRRECOVERABLE" "git commit --amen (abbreviated --amend, was silently ALLOWed)" \
  "$(bash_payload 'git commit --amen')"
test_deny  "$IRRECOVERABLE" "git clean --forc (abbreviated --force, was silently ALLOWed)" \
  "$(bash_payload 'git clean --forc')"
test_deny  "$IRRECOVERABLE" "git branch --del --forc (abbreviated delete+force, was silently ALLOWed)" \
  "$(bash_payload 'git branch --del --forc featurex')"
test_deny  "$IRRECOVERABLE" "git switch --discard-ch (abbreviated --discard-changes, was silently ALLOWed)" \
  "$(bash_payload 'git switch --discard-ch main')"
test_deny  "$IRRECOVERABLE" "git add --al (abbreviated --all, was silently ALLOWed)" \
  "$(bash_payload 'git add --al')"
# deep-audit fix-round 3, 2026-09-20: the len()>3 guard excluded 2-char-
# after-"--" tokens from ever being checked, regardless of whether real git
# accepts them unambiguously -- live-confirmed `git reset --h` and
# `git clean --f` both ran for real and destroyed data.
test_deny  "$IRRECOVERABLE" "git reset --h (1-char abbreviated --hard, was silently ALLOWed)" \
  "$(bash_payload 'git reset --h')"
test_deny  "$IRRECOVERABLE" "git clean --f (1-char abbreviated --force, was silently ALLOWed)" \
  "$(bash_payload 'git clean --f')"
# Dangerous-direction control: the abbreviation helper must not itself start
# denying git's own already-documented noisy neighbors (an ambiguous prefix
# these long forms don't uniquely resolve to, or a flag never named in the
# specific per-call-site long_forms list).
test_allow "$IRRECOVERABLE" "git push --force-with-lease still allowed (prefix helper is call-site-scoped, not global)" \
  "$(bash_payload 'git push --force-with-lease origin develop')"
test_allow "$IRRECOVERABLE" "git diff --find-renames still allowed (unrelated long flag, not a --force/--hard/--amend prefix)" \
  "$(bash_payload 'git diff --find-renames')"
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
# GH #155: same truthiness-vs-presence gap GH #154 fixed in subagent-spawn-guard.py --
# the gate's own stated intent is to key on PRESENCE of agent_id, not a
# non-empty/non-null value. A real payload capture (2026-09-07) never observed an
# empty/null agent_id in practice -- these are hardening tests for a theoretical gap.
test_deny "$TASK_COMPLETE" "GH #155 gap: agent_id present but an empty string still denied" \
  "$(taskupdate_payload_forced_id completed mh:build-error-resolver '')"
test_deny "$TASK_COMPLETE" "GH #155 gap: agent_id present but JSON null still denied" \
  "$(taskupdate_payload_forced_id completed mh:build-error-resolver '__NULL__')"

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
# H4 (harness gap-audit, 2026-09-20): the ABOVE case allows only because it
# has no destructive token, so the bash fast-path exits before python3 ever
# runs -- it never actually reached the python-side malformed-payload deny
# branch (lines 27-31). A malformed payload that DOES carry a destructive
# substring passes the fast path, then must fail closed once python3's
# json.load() chokes on the truncation -- the two branches must not be
# conflated (one's a pre-python allow, the other's a post-python deny).
test_deny "$IRRECOVERABLE" "truncated JSON carrying a destructive substring reaches python and fails closed (H4, was untested)" \
  '{"tool_input": {"command": "rm -rf /"'

# C1 (harness gap-audit, 2026-09-20): _nested_spawn's outer loop over every
# anchor match times an unbounded inner token scan is O(anchors x
# remaining-length) -- live-reproduced before the fix: 6,000 "claude ("
# anchors in a 48,000-char command (well under _CMD_LEN_CAP's 150,000) took
# 22s, far past this gate's own 8s hooks.json PreToolUse timeout, and Claude
# Code's own hooks reference confirms a timed-out PreToolUse command hook
# lets the tool call continue -- so a slow enough payload silently bypassed
# this whole check. `timeout 5` wraps the assertion itself: a regression
# back to the unbounded scan would make this whole test time out (rc 124),
# not just fail the deny assertion.
dos_payload="$(python3 -c 'print("claude (" * 6000)')"
dos_rc=$(echo "$(bash_agent_payload "$dos_payload" fork)" | timeout 5 bash "$IRRECOVERABLE" 2>/dev/null; echo $?)
if [[ "$dos_rc" == "2" ]]; then
  echo "  ✅ DENY (bounded time): 6,000-anchor nested-spawn scan denies well under the 8s PreToolUse timeout, not a silent bypass"
  pass=$((pass + 1))
else
  echo "  ❌ DENY EXPECTED (bounded time) but got exit $dos_rc (124 = timed out, budget regressed): 6,000-anchor nested-spawn scan" >&2
  fail=$((fail + 1))
fi

# C1b (harness gap-audit, 2026-09-20): both _nested_spawn call sites (line
# ~302 top-level command, line ~621 bash -c/eval unwrapped body) gate on
# `"agent_id" in d` -- presence, not truthiness. An empty-string or JSON-null
# agent_id is still a subagent call and must still deny, not fall through as
# if agent_id were absent (main session).
test_deny  "$IRRECOVERABLE" "C1b: agent_id present but empty string still denies a top-level nested spawn" \
  "$(bash_agent_payload_forced_id 'claude -p "sneaky"' '')"
test_deny  "$IRRECOVERABLE" "C1b: agent_id present but JSON null still denies a top-level nested spawn" \
  "$(bash_agent_payload_forced_id 'claude -p "sneaky"' '__NULL__')"
test_deny  "$IRRECOVERABLE" "C1b: agent_id present but empty string still denies a bash -c-wrapped nested spawn" \
  "$(bash_agent_payload_forced_id 'bash -c "claude -p sneaky"' '')"
test_deny  "$IRRECOVERABLE" "C1b: agent_id present but JSON null still denies a bash -c-wrapped nested spawn" \
  "$(bash_agent_payload_forced_id 'bash -c "claude -p sneaky"' '__NULL__')"

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
# 2026-09-20 audit: _SPAWN_ANCHOR_RE required "claude" immediately after the
# separator/VAR=val chain, with no allowance for a wrapper word -- env/sudo/
# nohup/nice/time/command prefixes, chained or repeated, all bypassed it live.
test_deny  "$IRRECOVERABLE" "subagent: env-wrapped claude -p (wrapper-prefix bypass, was silently ALLOWed)" \
  "$(bash_agent_payload 'env claude -p "evil"' fork)"
test_deny  "$IRRECOVERABLE" "subagent: chained sudo env claude -p (multi-level wrapper bypass, was silently ALLOWed)" \
  "$(bash_agent_payload 'sudo env claude -p "evil"' fork)"
test_deny  "$IRRECOVERABLE" "subagent: backslash-escaped \\claude -p (was silently ALLOWed)" \
  "$(bash_agent_payload '\claude -p "evil"' fork)"
test_deny  "$IRRECOVERABLE" "subagent: env with its own -u flag and a VAR=val before claude -p (was silently ALLOWed)" \
  "$(bash_agent_payload 'env -u X FOO=bar claude -p "evil"' fork)"
# compliance-audit fix-round 2, 2026-09-20: a first fix bounded the wrapper
# chain at depth<=3 to dodge a catastrophic-backtracking shape; an
# independent verifier chained 13 wrappers and got past that cap live.
long_chain="$(python3 -c 'print("env sudo nohup nice time command " * 13 + "claude -p \"evil\"")')"
test_deny  "$IRRECOVERABLE" "subagent: 13-deep wrapper chain past the old depth<=3 bound (was silently ALLOWed)" \
  "$(bash_agent_payload "$long_chain" fork)"
test_allow "$IRRECOVERABLE" "main session: env-wrapped claude -p (no agent_id — always allowed)" \
  "$(bash_agent_payload 'env claude -p "evil"' '')"
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
# GH #152: the anchor matched "claude" as a mid-token substring (a path segment
# like /tmp/claude-501/... contains a word-bounded "claude"), and the forward
# flag scan did not stop at a newline, so an unrelated later line's flag got
# credited to that false match.
test_allow "$IRRECOVERABLE" "GH #152 exact repro: scratchpad-shaped path plus a later mkdir -p on its own line" \
  "$(bash_agent_payload $'BASE=/private/tmp/claude-501/foo\nmkdir -p "$BASE/work"' fork)"
# Newline-as-separator control, independent of the mid-token anchor fix: a real
# (flag-free) claude mention followed by an unrelated command's -p on the next
# line must not leak back either -- the same property already covered above
# for a ";" separator must also hold for "\n".
test_allow "$IRRECOVERABLE" "unrelated later LINE's flag does not leak back to claude (newline, not semicolon)" \
  "$(bash_agent_payload $'claude --version\nothertool -p' fork)"
# Dangerous-direction control: a false substring match on an earlier line must
# not blind the scan to a REAL spawn on a later line.
test_deny  "$IRRECOVERABLE" "GH #152 control: false path-substring on line 1 does not mask a real spawn on line 2" \
  "$(bash_agent_payload $'BASE=/private/tmp/claude-501/foo\nclaude -p "evil"' fork)"
# Deep-audit adversarial pass, 2026-09-07: the newline-stops-scan rule the GH #152 fix added has
# no concept of $(...) nesting depth. Real bash executes `claude $(\nprintf x\n) -p evil` as ONE
# command (the newline inside the substitution is not a top-level separator), but the scanner's
# flat token walk treated that embedded newline as scan-stopping regardless of nesting, so the
# flag scan never reached `-p` after the substitution closed.
test_deny  "$IRRECOVERABLE" "spawn flag after a command substitution containing an embedded newline must still be caught" \
  "$(bash_agent_payload $'claude $(\nprintf x\n) -p "evil"' fork)"
# code-review round on the GH #152 fix (before it shipped) caught two
# dangerous-direction regressions the fix itself would have introduced --
# both fixed, both locked in here so neither regresses again.
test_deny  "$IRRECOVERABLE" "GH #152 review catch: a shell metacharacter (not just \\s;&|)) right after claude must still anchor" \
  "$(bash_agent_payload 'claude>out.log -p "evil"' fork)"
test_deny  "$IRRECOVERABLE" "GH #152 review catch: a backslash-continued line is still one statement, spawn on the continuation line still caught" \
  "$(bash_agent_payload $'bash <<EOF\nclaude \\\\\n  -p "evil"\nEOF' fork)"
# Deep-audit 2026-09-07 paren-depth fix control (advisor-flagged gap): a
# BALANCED $(...) group between an unrelated claude mention and the real
# top-level separator must still let that separator stop the scan once the
# group closes depth back to 0 -- the same GH #152 leak-back property, now
# proven with parens in the mix rather than only newline/semicolon.
test_allow "$IRRECOVERABLE" "GH #152-class control: balanced \$(...) between claude and the real separator does not leak a later command's flag back" \
  "$(bash_agent_payload 'claude --version $(date) ; othertool -p' fork)"
# A stray unmatched ")" before the real separator must clamp at depth 0, not
# go negative -- going negative would require an unrelated later "(" to
# numerically return to 0, incorrectly swallowing everything in between
# (including a real separator) into the scan.
test_allow "$IRRECOVERABLE" "paren-depth clamp control: a stray unmatched ')' before the real separator does not swallow a later command's flag" \
  "$(bash_agent_payload 'claude --version) ; othertool -p' fork)"
# Codex-validator round on the paren-depth fix itself, deep-audit 2026-09-07:
# a backslash-escaped "(" is a literal argument character to claude, NOT a
# real subshell opener -- the depth tracker must not count it, or the real
# ";" right after gets swallowed and an unrelated later command's -p leaks
# back (reproduced live pre-fix: this exact payload was denied).
test_allow "$IRRECOVERABLE" "escaped literal paren control: a backslash-escaped '\\(' is not a real subshell opener, does not leak a later command's flag back" \
  "$(bash_agent_payload 'claude --version \( ; othertool -p' fork)"
# Same property, double backslash before a real newline: an EVEN count of
# backslashes right before a real newline is not a continuation in real bash
# (the pair is one escaped backslash, then the newline is unescaped and
# ends the statement) -- but this file deliberately still treats it as one,
# same safe-direction precedent as the single-backslash case, so a spawn on
# the "continuation" line must still be caught, not narrowed away.
test_deny "$IRRECOVERABLE" "double-backslash-before-newline control: even backslash count still treated as continuation (safe-direction precedent), spawn on the next line still caught" \
  "$(bash_agent_payload $'claude \\\\\n  -p "evil"' fork)"
# Round-2 codex-validator catch on the FIRST attempt at the escaped-paren fix
# (a fixed "backslash + one of these chars" rule with no parity check): an
# EVEN backslash count before a backtick leaves the backtick unescaped and
# LIVE in real bash (the pair is one literal backslash; the backtick opens a
# real command substitution) -- treating it as escaped/inert was a false
# ALLOW, a genuine bypass, reproduced live pre-fix (bash-stub trace showed
# claude actually receiving -p as an argument). Parity tracking (an odd-
# length run escapes the next char, an even-length run doesn't) fixes this.
test_deny "$IRRECOVERABLE" "backslash-parity control: an EVEN backslash count before a backtick leaves it live -- real command substitution still caught, not treated as escaped" \
  "$(bash_agent_payload 'claude \\`printf x; printf y` -p evil' fork)"
# Mirror case, ALLOW direction: an even backslash count before a semicolon
# also leaves the semicolon a real, live separator in real bash (same
# pairing rule) -- must still stop the scan normally, not get swallowed as
# an escaped/inert semicolon.
test_allow "$IRRECOVERABLE" "backslash-parity control: an EVEN backslash count before ';' leaves it a real separator -- later command's flag does not leak back" \
  "$(bash_agent_payload 'claude --version \\; othertool -p' fork)"

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
# deep-audit 2026-09-06: the unwrap ran before the prefix-wrapper unwrap, never
# blanked a single-quoted body, and the nested-spawn deny never saw inside it.
test_deny  "$IRRECOVERABLE" "sudo bash -c with rm -rf inside (wrapper before shell)" \
  "$(bash_payload "sudo bash -c 'rm -rf x'")"
test_deny  "$IRRECOVERABLE" "env bash -c with git reset --hard inside" \
  "$(bash_payload "env bash -c 'git reset --hard'")"
test_deny  "$IRRECOVERABLE" "bash -c single-quoted body with a spliced argv0" \
  "$(bash_payload "bash -c 'gi\$(true)t push --force origin main'")"
test_deny  "$IRRECOVERABLE" "bash -c single-quoted body hiding the deny inside a substitution" \
  "$(bash_payload "bash -c 'echo \$(git push --force origin main)'")"
test_deny  "$IRRECOVERABLE" "bash -c single-quoted body with a bare-PH slot shift (stash \$(true) drop)" \
  "$(bash_payload "bash -c 'git stash \$(true) drop'")"
test_deny  "$IRRECOVERABLE" "subagent: bash -c hiding a nested claude -p spawn" \
  "$(bash_agent_payload "bash -c 'claude -p hi'" fork)"
test_deny  "$IRRECOVERABLE" "subagent: eval hiding a nested claude --bg spawn" \
  "$(bash_agent_payload "eval 'claude --bg'" fork)"
test_allow "$IRRECOVERABLE" "main session: bash -c claude -p (no agent_id, not a nested spawn)" \
  "$(bash_payload "bash -c 'claude -p hi'")"
test_allow "$IRRECOVERABLE" "sudo bash -c with a harmless body" \
  "$(bash_payload "sudo bash -c 'ls -la'")"
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
  && git -c user.email=t@t -c user.name=t merge -q side >/dev/null 2>&1; true )
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

# M7 (harness gap-audit, 2026-09-20): a bad cwd makes _mid_merge()'s own
# subprocess.run raise (FileNotFoundError), caught by its except -- the deny
# that follows must be distinguishable from a genuine "not mid-merge" deny.
mid_merge_err=$(bash_cwd_payload 'git add -A' "/nonexistent/kbg-mid-merge-probe-$$" | bash "$IRRECOVERABLE" 2>&1 1>/dev/null)
mid_merge_rc=$(bash_cwd_payload 'git add -A' "/nonexistent/kbg-mid-merge-probe-$$" | bash "$IRRECOVERABLE" >/dev/null 2>/dev/null; echo $?)
if [[ "$mid_merge_rc" == "2" ]] && printf '%s' "$mid_merge_err" | /usr/bin/grep -q "mid-merge check itself failed"; then
  echo "  ✅ DENY + diagnostic: git add -A with an unreachable cwd denies AND names that the mid-merge check itself failed"
  pass=$((pass + 1))
else
  echo "  ❌ DENY+diagnostic EXPECTED but got exit $mid_merge_rc, stderr: $mid_merge_err" >&2
  fail=$((fail + 1))
fi

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

echo ""
echo "=== subagent-spawn-guard (GH #151: a dispatched subagent may not call the Agent tool itself) ==="
test_deny "$SUBAGENT_SPAWN_GUARD" "subagent (general-purpose) calling Agent to spawn its own reviewer" \
  "$(agent_payload 'general-purpose' 'agent-1' 'general-purpose')"
test_deny "$SUBAGENT_SPAWN_GUARD" "subagent (fork) calling Agent with a DIFFERENT subagent_type still denied (closes the same-type-switch evasion from the 2026-08-31 fork-recursive-spawn incident -- the gate never inspects subagent_type)" \
  "$(agent_payload 'general-purpose' 'agent-2' 'fork')"
test_deny "$SUBAGENT_SPAWN_GUARD" "subagent with no agent_type recorded (agent_id alone is the signal) still denied" \
  "$(agent_payload 'mh:silent-failure-hunter' 'agent-3' '')"
test_allow "$SUBAGENT_SPAWN_GUARD" "main session calling Agent (no agent_id) allowed" \
  "$(agent_payload 'general-purpose' '' '')"
test_allow "$SUBAGENT_SPAWN_GUARD" "subagent calling a non-Agent tool (Bash) is out of scope for this gate" \
  "$(bash_agent_payload 'ls -la' fork)"
# GH #154: the gate's own stated intent is to key on PRESENCE of agent_id, not
# a non-empty/non-null value -- these three exercise cases the old bash
# fast-path (raw-text substring match) and old python truthiness check
# (`if not agent_id`) both mishandled as "no agent_id" when the key was in
# fact present. A real payload capture (2026-09-07, matt-harness issue #154)
# never observed an empty/null/escaped agent_id in practice -- these are
# hardening tests for a theoretical gap the gate's own contract should still
# hold against, not evidence the gap is live-exploitable.
test_deny "$SUBAGENT_SPAWN_GUARD" "GH #154 gap 2: agent_id present but an empty string still denied" \
  "$(agent_payload_forced_id 'general-purpose' '')"
test_deny "$SUBAGENT_SPAWN_GUARD" "GH #154 gap 2: agent_id present but JSON null still denied" \
  "$(agent_payload_forced_id 'general-purpose' '__NULL__')"
test_deny "$SUBAGENT_SPAWN_GUARD" "GH #154 gap 1: agent_id key JSON-escaped (\\u005f for the underscore) still denied, not fast-pathed past on raw-text match" \
  "$(agent_payload_escaped_id_key)"
# The .sh gate has no bash-level fast path (removed for GH #154) -- every
# payload always reaches python3, so these exercise the json.load()/
# isinstance() fail-safe branches directly.
test_allow "$SUBAGENT_SPAWN_GUARD" "malformed stdin (fail-safe allow)" \
  '{"agent_id": invalid'
test_allow "$SUBAGENT_SPAWN_GUARD" "valid JSON but non-object payload (fail-safe allow)" \
  '["agent_id"]'
# GH #156: a 5000-digit UNQUOTED int literal used to raise ValueError inside
# json.load() itself (CPython 3.11+'s int-string digit limit), caught by the
# same broad `except Exception: allow` as ordinary malformed JSON -- a
# well-formed-but-huge-int payload bypassed this gate's actual logic instead
# of being parsed and denied normally.
test_deny "$SUBAGENT_SPAWN_GUARD" "GH #156: 5000-digit unquoted agent_id parses and denies, doesn't fail-open past the int-digit limit" \
  "$(printf '{"tool_name":"Agent","tool_input":{"prompt":"x","description":"y","subagent_type":"general-purpose"},"agent_id":%s}' "$(python3 -c "print('9'*5000)")")"

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
test_nopython_allow "$SUBAGENT_SPAWN_GUARD" "subagent-spawn-guard: subagent calling Agent passes with note" \
  "$(agent_payload 'general-purpose' 'agent-1' 'general-purpose')"

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
