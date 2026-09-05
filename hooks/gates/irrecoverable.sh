#!/usr/bin/env bash
# Gate: block irrecoverable Bash patterns before they execute.
# Reads the PreToolUse JSON payload from stdin; exits 2 to block.
set -uo pipefail

# --- Fast path: skip the python3 cold-start on commands that cannot match a
# deny pattern. Every deny in irrecoverable.py dispatches on an argv0 in {rm,
# find, git, dd, mysql, psql, sqlite3, mariadb, claude}; a wrapper (sudo/env/
# nice/xargs/docker exec) never hides that token from the raw string, so if
# NONE of these substrings survives normalization the command is allow-safe
# and we exit 0 without spawning python. (`claude` feeds the subagent
# nested-spawn deny.) Quote/backslash stripping (tr -d) exposes the one
# shlex obfuscation the python catches -- a quote-concatenated `r""m` -> `rm`.
# ponytail: coarse pre-filter for a habit-guard, not an adversarial sandbox;
# command-substitution/eval unwrapping stays out of scope (see line 83 below).
# False positives (digit/warm/scheduling) just spawn python -- safe direction.
_input="$(cat)"
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ' | tr -d "\"'\\")"
# A backslash-newline continuation splitting an argv0 itself (e.g. "gi" +
# "\<newline>" + "t push --force") turns the \n escape into a space above,
# so "git" never survives as one substring and the case below would exit 0
# without ever reaching the python scanner that reassembles it correctly --
# confirmed live 2026-09-03, GH #122 adjacent finding. A second, fully
# whitespace-collapsed variant catches that shape too; false positives here
# (two unrelated words happening to concatenate into a candidate substring)
# just cost a python spawn, the same safe direction the comment above
# already accepts for quote/backslash stripping.
_norm_nows="$(printf '%s' "$_norm" | tr -d '[:space:]')"
# A backtick or $(...) command substitution vanishes in real bash (its own
# output splices into the surrounding text with zero width) but survives
# here as literal characters -- "gi`true`t" or "gi$(true)t" never contains
# a contiguous "git" substring under either normalization pass above, so
# the case below would otherwise exit 0 and fully bypass this DENY gate on
# a real ` git push --force`-shaped command (confirmed live 2026-09-03:
# rc=0, python3 never spawned). Conservative deferral: detect the PRESENCE of a substitution marker on the
# RAW input and refuse the fast-allow regardless of what the substring match
# below finds, rather than resolving/stripping the substitution here.
# Whether python3's own tokenizer classifies the reassembled command
# correctly is a separate, deeper question (it does not resolve
# command-substitution splicing today either -- out of scope for this fix,
# which only closes the fast-path short-circuit).
# Enumerating specific spellings (${x} unset, $'...' ANSI-C quoting, $@/$*
# with zero positional parameters -- each found and fixed one at a time,
# 2026-09-03) kept finding gaps, so this is the general form instead: ANY
# bare $ or backtick anywhere in the raw input is treated as a possible
# zero-width splice and forces the defer -- a strict superset of every
# enumerated marker, since each one itself contains a $ or a backtick.
#
# GH #134, checked and ruled out (2026-09-04): this scan reads the RAW
# input string, so a $ or backtick that instead arrives JSON-escaped as
# $ / ` (json.loads would still decode it to a real $/backtick
# on the python3 side below) is invisible here -- the case below would
# only see the literal bytes \, u, 0, 0, 2, 4, none of which is $ or a
# backtick, so _has_subst stays 0 and a "gi${x}t push --force"-shaped
# payload fast-exits with zero python3 spawn. Verified NON-LIVE by
# capturing this session's own real PreToolUse hook payload for a Bash
# command containing a literal $ and backtick: Claude Code's actual
# serializer emitted the literal bytes ("command":"...probe$var...
# probe`date`end...") -- no \uXXXX escaping of plain ASCII, consistent
# with ordinary JSON.stringify behavior. This is a live capture, not a
# docs citation. Locked in by the "documented gap" test in
# tests/hooks/test-gates.sh (search GH #134). Would need re-checking if
# Claude Code's hook payload serializer ever starts ASCII-escaping (e.g.
# an added \uXXXX-escape-non-ASCII-and-punctuation mode) -- re-capture a
# real payload the same way before deciding this is live.
_has_subst=0
case "$_input" in *'`'*|*'$'*) _has_subst=1 ;; esac
case "$_norm$_norm_nows" in
  *rm*|*find*|*git*|*dd*|*mysql*|*psql*|*sqlite3*|*mariadb*|*claude*) : ;;  # candidate -> python
  *) [ "$_has_subst" -eq 1 ] || exit 0 ;;                          # no destructive token possible -> allow (unless obfuscated)
esac

# Portability guard (#93): without python3 the deny logic below cannot run,
# and the rc!=0/2 tail reads the resulting 127 as "internal error — fail
# closed" — which on a python3-less machine blocks EVERY command carrying an
# rm/find/git/dd token, `git status` included. Announced fail-open is the
# lesser harm; doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — irrecoverable-pattern gate cannot run; allowing (install python3 to restore deny coverage)" >&2
  exit 0
fi

_py="$(dirname "$0")/irrecoverable.py"
# Corrupted/partial plugin install (follow-up to #146): without this check,
# python3 itself exits 2 on the missing file with a raw "can't open file
# ..." message -- the rc-handling below already reads rc==2 as a legitimate
# deny and passes it through (fail-closed is already correct), but the
# stderr the operator sees is an ugly unlabeled python3 error instead of
# this repo's own [mh:gate] convention. Same exit code (2), same fail-closed
# outcome -- only the diagnostic changes.
if [ ! -r "$_py" ]; then
  echo "[mh:gate] internal error: sibling script irrecoverable.py missing or unreadable — failing closed" >&2
  exit 2
fi

printf '%s' "$_input" | python3 "$_py"
rc=$?
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  echo "[mh:gate] internal error (rc=$rc) — failing closed" >&2
  exit 2
fi
exit "$rc"
