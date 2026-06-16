#!/bin/bash
# db-write-gate — ask on non-SELECT MCP database calls.
#
# Closes the enforcement-asymmetry flagged by the 2026-06-11
# Harness-Loop-Engineer audit (FIX-1 in
# .scratch/harness-loop-engineer-audit/ACCEPTANCE.md): DBGATE and ACLI
# are injected as prompt doctrine only, so a non-SELECT
# mcp__tathep-db__execute_sql_production call has zero deterministic
# backstop, while `rm` and doctrine-file edits have gates. This hook
# adds the matching PreToolUse gate on MCP DB tools so the irreversible
# op goes through the same ask path as every other irreversible op.
#
# Scope: gates any MCP tool whose name contains `execute_sql`,
# `db_write`, or `db_query` with a destructive verb. The hook is
# deliberately broad on tool names (matches any MCP DB tool across
# servers: tathep-db, future prod-db, etc.) and tight on statement
# shape (a leading SELECT/EXPLAIN/WITH clause is allow-through; a
# leading INSERT/UPDATE/DELETE/... is ask; comment-only / empty is
# allow-through as a no-op). information_schema read-onlys are
# allow-through even with a leading SELECT-style wrapper.
#
# This is NOT airtight — Python raw drivers, psql/subprocess bypasses,
# or a future MCP tool with a non-`query` argument shape are not
# caught. Intent is to flag the common case; sophisticated bypasses
# remain possible and acceptable per METHODOLOGY Rule 2 (Simplicity
# first — don't over-engineer). The narrow surface (3 verb patterns,
# well-known tool-name suffixes) is the deliberate trade-off vs the
# doctrine-only baseline.
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=db-write-gate

set -uo pipefail

HOOK_ID="db-write-gate"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat
hook_guard_unreadable  # fail CLOSED (ask) if input unparseable


# jq is mandatory for the query parse below; if missing, fail loud
# (matches block-bash-doctrine-write.sh / doctrine-edit-gate.sh).
if ! command -v jq >/dev/null 2>&1; then
  echo "[$HOOK_ID] ERROR: jq not found — cannot parse hook input" >&2
  exit 1
fi

# Only act on MCP DB tool calls. Other MCP tools (atlassian, etc.)
# stay gated by their own doctrine (ACLI.md) and out of scope for
# this hook — adding them would be a Rule-2 overreach. The matcher
# in hooks.json is `mcp__*` (broad), the suffix filter here is
# tight to the DB surface.
case "$TOOL" in
  mcp__*__execute_sql*|mcp__*__db_write|mcp__*__db_query) ;;
  *) exit 0 ;;
esac

# Read the statement from whichever field the MCP tool happens to
# use. .query / .sql / .statement are the conventions seen across
# the `tathep-db` MCP server and the canonical patterns in
# MCP-server-typical APIs; fall through empty if none match.
STATEMENT=$(printf '%s' "$TOOL_INPUT" | jq -r '
  (.query // .sql // .statement // .text // empty) | tostring
' 2>/dev/null) || {
  echo "[$HOOK_ID] ERROR: failed to parse tool_input" >&2
  exit 1
}
[ -z "$STATEMENT" ] && exit 0

# Strip `--` line comments PER LINE (before collapsing newlines), then
# collapse to one line and trim leading whitespace. Order is load-bearing:
# the previous version did `tr '\n' ' '` FIRST, so a leading `-- comment`
# line then greedily ate the real SQL verb on the next line, leaving an
# empty NORMALIZED that was treated as a no-op — a `-- x\nDELETE FROM users`
# bypass of the production write gate. Stripping `--…EOL` per line first
# means a comment only consumes to its own line end.
NORMALIZED=$(printf '%s' "$STATEMENT" | sed -E 's/--.*$//' | tr '\n' ' ' | sed -E 's/^[[:space:]]+//')

# A comment-only query is effectively a no-op — allow through silently
# rather than nagging the human about a "write" that's actually empty.
[ -z "$NORMALIZED" ] && exit 0

# Classify write vs read. A leading write verb is a write. A WITH-CTE whose
# OUTER statement writes (`WITH t AS (...) DELETE ...`) is also a write — a
# leading `WITH` alone is no longer a free pass. information_schema mention does
# NOT rescue a write: it can sit in a string literal of a DELETE
# (`DELETE ... WHERE note='information_schema.'`). Reads (SELECT / EXPLAIN /
# pure-SELECT CTE / information_schema read) fall through to allow.
WRITE_VERBS='INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER|CREATE|MERGE|REPLACE|GRANT|REVOKE|RENAME|COMMENT'
if printf '%s' "$NORMALIZED" | command grep -qiE "^(${WRITE_VERBS})\b"; then
  : # leading write verb → fall through to the ask gate below
elif printf '%s' "$NORMALIZED" | command grep -qiE '^WITH\b' \
     && printf '%s' "$NORMALIZED" | command grep -qiE "\b(${WRITE_VERBS})\b"; then
  : # WITH-CTE whose outer statement writes → fall through to the ask gate
else
  exit 0  # read-only → allow silently
fi

# Everything else is treated as a write. Surface the first 80 chars
# of the statement (after the verb) so the user can see what they're
# being asked to confirm. The DBGATE doctrine is the source of truth
# for what counts as a write (INSERT/UPDATE/DELETE/TRUNCATE/ALTER/
# DROP/CREATE + anything that mutates), so we don't re-encode that
# list here — the ask-gate defers the taxonomy to DBGATE.
PREVIEW=$(printf '%s' "$NORMALIZED" | head -c 80)
# Target server name = the segment between `mcp__` and `__<tool>`,
# surfaced in the ask message so the user knows which DB they're
# about to touch (staging vs production is a DBGATE-keyed distinction
# the human applies at confirmation time).
TARGET=$(printf '%s' "$TOOL" | sed -E 's/^mcp__//; s/__.*$//')
hook_decision ask "DBGATE: non-SELECT on mcp server <${TARGET}> (${PREVIEW}…). Per DBGATE doctrine: state exact statement + target DB, get explicit OK, then run. Bypass: CLAUDE_DISABLED_HOOKS=db-write-gate"

exit 0
