#!/usr/bin/env bash
# Gate: ask on any MCP execute_sql-shaped call (mcp__<server>__execute_sql*) unless the
# statement is provably a simple read. Generic — matches any server, no config needed.
#
# THIS HOOK IS A BEST-EFFORT NUDGE, NOT THE SECURITY BOUNDARY. Classifying
# arbitrary SQL as read-vs-write from the string is not something a hand-rolled
# scanner can do airtight -- three rounds of adversarial review against a live
# MariaDB (2026-07-13, while exercising mh:review-pr) each found a silent-allow
# bypass in the previous "block the write verbs" design: string-literal-blind
# comment stripping, /*! executable-comment mis-scan, the -- needs-whitespace
# lexer rule, and writes reachable by verbs/indirection off the list (LOAD,
# PREPARE/EXECUTE, SELECT ... INTO OUTFILE). The real write-protection for any DB an
# MCP server exposes must live where it can be deterministic: a READ-ONLY DB grant /
# connection for any non-production environment (production should already be readonly).
# The database refusing a write is a real gate; a regex guessing at SQL is not.
#
# Given that, this gate is inverted to fail SAFE: it ALLOWS only statements it
# can positively prove are simple reads (every ;-segment leads with a read verb,
# no INTO OUTFILE/DUMPFILE, WITH-CTE that does not write) and ASKS on everything
# else -- an unknown verb, a shape it cannot classify, or any ambiguity. A miss
# is now a false ASK (harmless friction), never a false ALLOW (a prod write
# slipping through silently). It will over-ask on exotic reads; that is the
# intended, safe direction. Comment stripping is quote-aware (strip_comments)
# so ordinary commented reads are not gratuitously flagged.
#
# Still out of reach by construction: a raw driver / subprocess bypass, or a
# future MCP tool with a non query/sql/statement/text argument shape.
set -uo pipefail

# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — db-write gate cannot run; allowing (install python3 to restore SQL-write asks)" >&2
  exit 0
fi

# Corrupted/partial plugin install (deep-audit follow-up to #146, same fix
# shape as verifier-protect.sh/merge-door.sh): this gate's embedded python
# does `from _hook_output import emit_ask`, resolved from this gate's
# sibling lib/ dir (passed as argv[1] below). A missing lib module raises
# ModuleNotFoundError -> exit 1 (confirmed live), a nonzero non-2 exit that
# hooks/dispatch-pretooluse.py's own dispatch contract treats as
# non-blocking -- the gated SQL write proceeds regardless, i.e. this
# tamper-resistance gate fails OPEN. Emit the same ask-JSON shape
# emit_ask() would produce instead of letting the traceback exit nonzero.
_lib="$(dirname "$0")/lib"
if [ ! -r "$_lib/_hook_output.py" ]; then
  printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "db-write-gate: required module lib/_hook_output.py is missing or unreadable -- failing safe, approve manually or investigate the plugin install."}}'
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import sys, json, re

# lib_dir is argv[1] -- $(dirname "$0")/lib, appended below where this
# python3 -c block is invoked. $0-based resolution because
# CLAUDE_PLUGIN_ROOT can be empty in some invocation contexts;
# $0 cannot, since bash sets it from the literal command that ran this file.
sys.path.insert(0, sys.argv[1])
from _hook_output import emit_ask

# Quote characters as ordinals so this whole program stays free of literal
# apostrophes -- it runs inside a bash single-quoted python3 -c, where a literal
# apostrophe would terminate the shell string (the documented gate quoting trap).
SQ, DQ, BT = chr(39), chr(34), chr(96)

# Leading verbs that make a segment a proven read. Anything not matched here
# (a write verb, LOAD, PREPARE, EXECUTE, CALL, SET, USE, an unknown verb, debris
# left by a scanner desync) falls through to ASK -- the safe direction.
READ_LEADS = r"SELECT|SHOW|DESCRIBE|DESC|TABLE|VALUES"
# Only used to decide whether a WITH-CTE writes.
WRITE_VERBS = r"INSERT|UPDATE|DELETE|TRUNCATE|DROP|ALTER|CREATE|MERGE|REPLACE|GRANT|REVOKE|RENAME|COMMENT|CALL|LOAD|PREPARE|EXECUTE"

def strip_comments(s):
    # Remove SQL comments the way MySQL/MariaDB actually lexes them, tracking
    # string-literal state so a comment marker inside a string literal is not
    # mistaken for a real delimiter. -- only starts a comment when the next char
    # is whitespace/control/end (MySQL rule); otherwise it is arithmetic (1--1).
    # Executable comments /*! ... */ are parsed by MariaDB as live SQL, so we
    # clear the marker and scan the body with this same loop (closing on the
    # first */ seen outside a string/nested-comment) instead of a raw find().
    # Safe direction: keep ambiguous text so it still classifies; the caller
    # asks on anything not proven read.
    out = []
    i, n = 0, len(s)
    quote = None
    exe = False                                           # inside a /*! ... */ executable comment
    while i < n:
        c = s[i]
        nxt = s[i + 1] if i + 1 < n else ""
        if quote is not None:
            out.append(c)
            if c == chr(92) and quote in (SQ, DQ):        # backslash escape
                if nxt:
                    out.append(nxt); i += 2; continue
            elif c == quote:
                if nxt == quote:                          # doubled = escaped quote
                    out.append(nxt); i += 2; continue
                quote = None                              # literal ends
            i += 1; continue
        if c in (SQ, DQ, BT):                             # a literal begins
            quote = c; out.append(c); i += 1; continue
        if exe and c + nxt == "*/":                       # close of the executable comment
            exe = False; i += 2; continue
        # -- is a comment ONLY before whitespace/control/end; # always is.
        if c == "#" or (c + nxt == "--" and (i + 2 >= n or ord(s[i + 2]) <= 32)):
            j = s.find(chr(10), i)
            if j == -1: break
            i = j; continue
        if c + nxt == "/*":
            # Two executable-comment forms run on the server: MySQL /*! ... */
            # and MariaDB-only /*M! ... */ (the M form is meant to read as inert
            # to non-MariaDB parsers -- exactly the trap). Clear the marker and
            # scan the body live so its verbs classify. The dbhub scanner honors
            # both; missing /*M! was a live silent-allow bypass. Match M
            # case-insensitively (safe direction: at worst an over-ask).
            if s[i:i + 3] == "/*!" or s[i:i + 4].upper() == "/*M!":
                exe = True
                i += 4 if s[i:i + 4].upper() == "/*M!" else 3
                m = re.match(r"[0-9]+", s[i:])            # skip optional version digits
                if m:
                    i += m.end()
                continue
            end = s.find("*/", i + 2)                     # ordinary block comment (quote-blind close = MySQL)
            if end == -1:                                 # unterminated: keep rest so a verb still shows
                out.append(s[i:]); break
            out.append(" "); i = end + 2; continue
        out.append(c); i += 1
    return "".join(out)

def is_read(seg):
    # True only if this ;-segment is a statement we positively recognize as a
    # read. Unknown/unrecognized -> False -> the caller asks.
    seg = seg.strip()
    if not seg:
        return True
    # Plain EXPLAIN never executes the analyzed statement (a read). EXPLAIN
    # ANALYZE DOES execute it -- strip that prefix and judge what it analyzes.
    m = re.match(r"^EXPLAIN\s+ANALYZE\s+", seg, re.IGNORECASE)
    if m:
        seg = seg[m.end():].strip()
    elif re.match(r"^EXPLAIN\b", seg, re.IGNORECASE):
        return True
    # SELECT ... INTO OUTFILE/DUMPFILE writes to disk despite the SELECT lead.
    if re.search(r"\bINTO\s+(OUTFILE|DUMPFILE)\b", seg, re.IGNORECASE):
        return False
    if re.match(r"^WITH\b", seg, re.IGNORECASE):
        return not re.search(r"\b(" + WRITE_VERBS + r")\b", seg, re.IGNORECASE)
    return bool(re.match(r"^(" + READ_LEADS + r")\b", seg, re.IGNORECASE))

def _sql_reason(target, preview):
    return (
        "db-write-gate: statement on MCP SQL server <" + target +
        "> is not a proven read (" + preview + "...). State the exact "
        "statement and target DB, get explicit approval, then run."
    )

try:
    d = json.load(sys.stdin)
    tool = d.get("tool_name", "") or ""
    ti = d.get("tool_input")

    if not re.match(r"^mcp__.*__execute_sql", tool):
        sys.exit(0)

    if not isinstance(ti, dict):
        # A present-but-non-dict tool_input (e.g. JSON null) previously
        # collapsed via "or {}" into an empty statement -> silent allow,
        # defeating the read-allowlist ask-on-unknown invariant (same class
        # as the OPEN #1 fix in convergence-merge-gate + the 2026-08-06
        # isinstance guard in verifier-protect; found by the 2026-08-14 fleet sweep).
        emit_ask(_sql_reason("<missing/malformed tool_input>", (
            "db-write-gate received an execute_sql call with no usable "
            "tool_input and cannot confirm the statement is a read. "
            "Fail-safe: state the exact statement, approve manually or deny."
        )))
        sys.exit(0)

    statement = ti.get("query") or ti.get("sql") or ti.get("statement") or ti.get("text") or ""
    statement = str(statement)
    if not statement.strip():
        sys.exit(0)

    normalized = " ".join(strip_comments(statement).split()).strip()
    if not normalized:
        sys.exit(0)  # comment-only statement is a no-op, not a write

    # ASK unless EVERY ;-segment is a proven read (read-allowlist, not a
    # write-blocklist -- an unrecognized statement asks, it does not slip).
    if all(is_read(seg) for seg in normalized.split(";")):
        sys.exit(0)

    preview = normalized[:80]
    target = re.sub(r"^mcp__", "", tool)
    target = re.sub(r"__.*$", "", target)
    emit_ask(_sql_reason(target, preview))
except Exception:
    # Cannot confirm this statement is a safe read -- fail toward asking.
    emit_ask(_sql_reason("mcp-sql", "<unparsed tool input>"))
' "$_lib"
