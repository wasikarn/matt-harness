#!/usr/bin/env bash
# Gate: ask on non-SELECT tathep-db MCP calls (mcp__tathep-db__execute_sql_*).
#
# Restores the coverage lost when hooks/db-write-gate.sh (a mature, previously
# reviewed implementation) was deleted in the v0.6.0 blanket reset — that
# deletion was a scope cut, not a decision that prod-SQL access needed no
# gate. Found live and ungated again in the 2026-07-07 whole-system audit:
# tathep-db exposes execute_sql_production/_staging/_anpr_staging with only
# the host's default per-call permission prompt as a backstop, no read-vs-
# write classification.
#
# Adapted to the current gate convention (pure python3 -c, JSON stdin,
# permissionDecision: ask, no env-var bypass) rather than restored verbatim
# (the original depended on a since-deleted hooks/_lib.sh shared library and
# a CLAUDE_DISABLED_HOOKS bypass this architecture no longer uses). The SQL
# read/write classification logic itself is reused as-is: strip -- comments
# per LINE before collapsing to one line (order is load-bearing — collapsing
# first lets a leading comment line eat the real verb on the next line), then
# check for a leading write verb or a WITH-CTE whose outer statement writes.
#
# Not airtight — a raw driver, a subprocess bypass, or a future MCP tool with
# a non query/sql/statement/text argument shape is not caught. Intent is to
# flag the common case (METHODOLOGY Rule 2 — don't over-engineer a single-
# operator harness's gate beyond the proven need).
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import sys, json, re

WRITE_VERBS = r"INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER|CREATE|MERGE|REPLACE|GRANT|REVOKE|RENAME|COMMENT|CALL"

def emit_ask(target, preview):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": (
                "db-write-gate: non-SELECT statement on tathep-db server <" + target +
                "> (" + preview + "...). State the exact statement and target DB, "
                "get explicit approval, then run."
            ),
        }
    }))

try:
    d = json.load(sys.stdin)
    tool = d.get("tool_name", "") or ""
    ti = d.get("tool_input", {}) or {}

    if not re.match(r"^mcp__tathep-db__execute_sql", tool):
        sys.exit(0)

    statement = ti.get("query") or ti.get("sql") or ti.get("statement") or ti.get("text") or ""
    statement = str(statement)
    if not statement.strip():
        sys.exit(0)

    # Strip /* */ block comments first (can span lines, found in the
    # compliance-audit adversarial pass: a leading block comment before the
    # verb was not stripped at all, unlike -- line comments below).
    statement = re.sub(r"/\*.*?\*/", " ", statement, flags=re.DOTALL)

    # Strip -- line comments PER LINE first, then collapse to one line. Doing
    # this in the reverse order (collapse first) lets a leading "-- comment"
    # line greedily eat the real SQL verb on the next line — a documented
    # bypass in the original implementation this restores.
    stripped_lines = [re.sub(r"--.*$", "", line) for line in statement.splitlines()]
    normalized = " ".join(stripped_lines).strip()

    if not normalized:
        sys.exit(0)  # comment-only statement is a no-op, not a write

    # Check each ;-delimited segment, not just the leading verb of the whole
    # string -- a write stacked after a lead SELECT (SELECT 1; DELETE ...)
    # would otherwise read as a SELECT and slip through (found in the
    # compliance-audit adversarial pass). Naive ;-split: a ; inside a string
    # literal yields a false ASK, never a false ALLOW -- safe direction.
    is_write = False
    for seg in (s.strip() for s in normalized.split(";")):
        if not seg:
            continue
        # EXPLAIN ANALYZE (unlike plain EXPLAIN) actually executes the
        # statement on MySQL/MariaDB -- strip the prefix and classify what it
        # analyzes, not the EXPLAIN wrapper itself (added: CALL, a stored-
        # procedure invocation that can write internally, in the same pass).
        seg = re.sub(r"^EXPLAIN\s+ANALYZE\s+", "", seg, flags=re.IGNORECASE)
        if re.match(r"^(" + WRITE_VERBS + r")\b", seg, re.IGNORECASE):
            is_write = True
            break
        if re.match(r"^WITH\b", seg, re.IGNORECASE) and \
           re.search(r"\b(" + WRITE_VERBS + r")\b", seg, re.IGNORECASE):
            is_write = True  # WITH-CTE whose outer statement writes
            break

    if not is_write:
        sys.exit(0)  # read-only (SELECT / EXPLAIN / pure-SELECT CTE) → allow

    preview = normalized[:80]
    target = re.sub(r"^mcp__", "", tool)
    target = re.sub(r"__.*$", "", target)
    emit_ask(target, preview)
except Exception:
    # Cannot confirm this statement is a safe read — fail toward asking.
    emit_ask("tathep-db", "<unparsed tool input>")
'
