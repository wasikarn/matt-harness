#!/usr/bin/env bash
# Advisory: immediately after an Edit/Write to a hooks/gates/*.sh or
# hooks/advisory/*.sh file, run `bash -n` on it and surface a loud warning if
# it's now syntactically broken. PostToolUse hook, matcher "Edit|Write" --
# fires on tool completion regardless of the edit's own success.
#
# Why this exists: 2026-09-01, an edit to hooks/gates/verifier-protect.sh
# introduced a literal apostrophe inside its embedded `python3 -c '...'`
# block (bash single-quoted string -- see that file's own header comment,
# and memory kbg-gate-python-c-quoting-lockout), breaking bash's ability to
# parse the whole file. Since hooks/dispatch-pretooluse.sh invokes every
# gate on every PreToolUse call, this became a repo-wide lockout -- every
# subsequent Bash/Edit/Write/NotebookEdit call started failing, mid-session,
# before any commit. git-hooks/pre-commit and scripts/run-gauntlet.sh both
# already run `bash -n`+shellcheck on hooks/*.sh, and harness-audit check 18
# now also scans hooks/ (2026-09-01 fix, same incident) -- but all three are
# commit/push-time or manually-invoked backstops. None of them fire at the
# moment the bad edit actually lands, which is the only point a warning can
# reach the model before it wastes turns diagnosing a lockout it doesn't yet
# know is self-inflicted. This hook is that missing immediate signal.
#
# Deliberately advisory, not a gate: PostToolUse fires AFTER the edit has
# already landed on disk -- there is nothing left to deny. The value here is
# speed of diagnosis (a warning appears in the same turn as the bad edit),
# not prevention (prevention would need a PreToolUse check inspecting the
# edit's own diff content, a materially different and heavier mechanism, not
# built here). Never blocks; always exits 0 -- this hook cannot recreate the
# exact lockout it exists to warn about.
#
# Scope: hooks/gates/*.sh and hooks/advisory/*.sh only -- the two directories
# whose scripts are invoked synchronously on every PreToolUse call (per
# CLAUDE.md's Architecture section: gates/ deny, advisory/ journal). A syntax
# break in hooks/session/*.sh or hooks/stop/*.sh doesn't cause the same
# repo-wide PreToolUse lockout, so they're out of scope for this specific
# fast, cheap, narrowly-targeted check (harness-audit check 18 already covers
# ALL of hooks/ for the broader, slower, manually-invoked case).
#
# NotebookEdit is not in the matcher: it only ever targets .ipynb files,
# which can never match hooks/gates/*.sh or hooks/advisory/*.sh -- adding it
# would be dead code, not defense in depth.
set -uo pipefail

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

# Truncate to the head of the payload, before "tool_response" -- same
# decoy-avoidance idiom as compliance-audit-nudge.sh (tool_input always
# serializes first in this hook's JSON schema).
INPUT_HEAD=$(printf '%s' "$INPUT" | sed 's/"tool_response".*//')

FILE_PATH=$(printf '%s' "$INPUT_HEAD" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$FILE_PATH" ] || exit 0

case "$FILE_PATH" in
  */hooks/gates/*.sh|*/hooks/advisory/*.sh) : ;;
  *) exit 0 ;;
esac

[ -f "$FILE_PATH" ] || exit 0

ERR=$(bash -n "$FILE_PATH" 2>&1) && exit 0

NAME=${FILE_PATH##*/}
NUDGE="[mh:gate-syntax-nudge] '$NAME' has a bash syntax error after this edit — bash -n: ${ERR}. Since dispatch-pretooluse.sh invokes every hooks/gates and hooks/advisory script on every PreToolUse call, a broken one here can lock out the whole session's Bash/Edit/Write/NotebookEdit tools (this exact incident happened 2026-09-01 with an apostrophe inside an embedded python3 -c '...' block in verifier-protect.sh). Fix the syntax error now, before any other tool call — Read still works even if the gate is already broken. See memory kbg-gate-python-c-quoting-lockout and dispatch-pretooluse-prefilter-substring-lockout-recovery-2026-09-01 for the recovery technique if a lockout has already started."

python3 -c '
import json, sys
print(json.dumps(
    {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": sys.argv[1]}},
    ensure_ascii=False,
))
' "$NUDGE" 2>/dev/null

exit 0
