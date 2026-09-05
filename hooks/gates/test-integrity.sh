#!/usr/bin/env bash
# Gate: ask when an edit to an existing test file removes an assertion-
# shaped line, or adds a skip/disable marker that wasn't there before.
# METHODOLOGY.md Rule 4 ("write the failing test first, don't weaken it
# while fixing") had no backing mechanism anywhere — pure prose, the exact
# same-role-grades-its-own-work case CLAUDE.md's maker≠checker doctrine
# argues against trusting.
#
# Stateless by design: no session-phase marker exists (or should exist —
# building one just relocates the self-discipline problem onto remembering
# to set/clear it). The diff itself is the classifier, computed fresh per
# call, the same "prove it from content" shape db-write-gate.sh uses for
# SQL. New-file test creation needs no old-side assertion to remove, so it
# is silent by construction — no separate carve-out required.
#
# Known, deliberate gap: this catches a REMOVED assertion line, an ADDED
# skip marker, an ADDED always-false conditional/loop wrap around
# otherwise-unchanged content — `if`/`elif`/`while` opening on a bare
# `false`/`0`, or a `[ ]`/`[[ ]]`/bare-`test` numeric comparison that is
# itself statically false (`0 -eq 1`, `1 -eq 2`, `2 -ne 2`, any literal
# pair, not just 0/1) — a REDEFINED `check()` oracle (the call sites stay
# byte-identical, only the helper's own body changes), a DELETED final
# `[ "$fail" -eq 0 ]` exit-gate line (this repo's own test files, this
# gate's own included, all use it to turn an accumulated fail count into
# a real exit code), a duplicate assertion line reduced to fewer copies
# (multiset-tracked, not a plain line SET, so removing one of two
# identical lines is no longer invisible), and an assertion relocated into
# an inert HEREDOC body or a `: '...'` colon no-op block (both stripped
# before scanning, same "heredoc is inert data unless it feeds an
# interpreter" distinction `irrecoverable.sh` already uses
# — ported, not reinvented). A same-day deep-audit fresh-context check
# found the first version of this (2026-08-28, `if false` only)
# overclaimed: `elif false`, `while false`, `if [ 1 -eq 2 ]`, and bare
# `if test 0 -eq 1` all bypassed it silently — verified live, each is a
# real always-false wrap, same family as the original finding, just a
# different spelling. A later deep-audit pass (also 2026-08-28) found the
# oracle-redefinition, exit-gate-deletion, multiset-collapse, and
# heredoc/colon-noop-relocation gaps above; all four were vocabulary gaps
# in this same line-based diff, not cases that needed real control-flow
# analysis — closed the same way as the `elif`/`while` gap before them.
# Deliberately NOT flagged, and not a gap: `if [ 0 ]` / `if [[ false ]]`
# (single-operand tests) — bash treats a non-empty string as true regardless
# of its text, so both of those are always-TRUE, not a skip (verified live;
# matching them would be a false positive, not a closed gap).
# Still not detected, and these genuinely DO need real control-flow /
# reachability analysis rather than a vocabulary addition: moving an
# assertion into a function that is never called, a `case` statement with
# no matching branch, a `continue`/`return`/`exit` inserted immediately
# before the assertion in the same block, or a runtime-variable-gated skip
# (`if [ "$SKIP" = 1 ]`) — out of scope for a lightweight PreToolUse
# content-diff gate, a real residual, not claimed as covered.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — test-integrity gate cannot run; allowing (install python3 to restore the ask)" >&2
  exit 0
fi

# Corrupted/partial plugin install (deep-audit follow-up to #146): this
# gate's embedded python
# does `from _hook_output import emit_ask`, resolved from this gate's
# sibling lib/ dir (passed as argv[1] below). A missing lib module raises
# ModuleNotFoundError -> exit 1 (confirmed live), a nonzero non-2 exit that
# hooks/dispatch-pretooluse.py's own dispatch contract treats as
# non-blocking -- the gated edit proceeds regardless, i.e. this
# tamper-resistance gate fails OPEN. Emit the same ask-JSON shape
# emit_ask() would produce instead of letting the traceback exit nonzero.
_lib="$(dirname "$0")/lib"
if [ ! -r "$_lib/_hook_output.py" ]; then
  printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "test-integrity: required module lib/_hook_output.py is missing or unreadable -- failing safe, approve manually or investigate the plugin install."}}'
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, os, re, sys
from collections import Counter

sys.path.insert(0, sys.argv[1])
from _hook_output import emit_ask

# Real test-root shapes only — not a bare "test"/"spec" substring, which
# false-positived on spec-miner.md, anything containing "specific"/"inspect",
# and 67 tracked-file path matches total (found by the adversarial plan
# review that sank the original any-substring design).
PATH_RE = re.compile(
    r"(^|/)tests?/"
    r"|(^|/)test_[^/]+\.py$"
    r"|_test\.[^/]+$"
    r"|\.test\.[^/]+$"
    r"|\.spec\.[^/]+$",
    re.IGNORECASE,
)

# This repo'"'"'s actual assertion idiom is the shared check() helper
# (tests/hooks/*.sh: `check "desc" "$ok"`), not assert/expect — checked
# against this repo'"'"'s own test files before writing this pattern, per the
# plan'"'"'s own instruction not to assume a vocabulary that is not actually in
# use here. Also covers pytest, jest/vitest `expect(`/`toThrow`, Go `t.Fatal*`, and chai `should`.
ASSERT_RE = re.compile(r"\bcheck\s*\"|\bassert\b|\bself\.assert|\bpytest\.raises\b|\bpytest\.fail\b|\bexpect\s*\(|\btoThrow\b|\bt\.(Fatal|Error|Fail)\w*\(|\bshould\b")
SKIP_RE = re.compile(r"#\s*SKIP\b|@pytest\.mark\.(skip|xfail)|\.skip\s*\(|\bxit\s*\(|\bit\.skip\s*\(", re.IGNORECASE)
# Bash has no marker-string idiom for disabling a line the way pytest/jest do
# -- it disables via control flow instead. `if`/`elif`/`while` opening on a
# bare false/0, or a bracket/test numeric comparison that'"'"'s statically
# false, all fully neuter a kept assertion while leaving the assertion'"'"'s
# own line text -- and the diff -- byte-identical, so SKIP_RE alone misses
# every one of them. Deliberately excludes `[ 0 ]`/`[[ false ]]`-style
# single-operand tests: those are non-empty-string checks and evaluate TRUE
# in bash (verified live), so matching them would be a false positive.
DEAD_KEYWORD_RE = re.compile(
    r"^\s*(if|elif|while)\s*\(?\s*(false|0)\b", re.IGNORECASE
)
DEAD_NUMERIC_RE = re.compile(
    r"^\s*(?:if|elif|while)\s*(?:\[+|test\s+)\s*(\d+)\s*(-eq|-ne)\s*(\d+)\b",
    re.IGNORECASE,
)
# A kept assertion can also be hidden by relocating its own line text into
# an inert region instead of wrapping it in a false conditional -- a
# HEREDOC body, or bash'"'"'s "colon-quoted string" no-op-comment idiom
# (`: '"'"'...'"'"'`). Both are stripped before the line-scan below sees them,
# UNLESS the heredoc feeds an interpreter (bash/python/etc), in which case
# its body really does execute and must stay scannable -- same
# interpreter distinction irrecoverable.sh already uses for
# its own heredoc handling, ported rather than reinvented (deep-audit
# 2026-08-28).
SQ = chr(39)
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")

def _strip_heredocs(text):
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        m = _HEREDOC_RE.search(line)
        i += 1
        if not m:
            continue
        if _INTERPRETER_RE.search(line[:m.start()]):
            continue
        strip_tabs, delim = bool(m.group(1)), m.group(3)
        body_start, found = i, False
        while i < len(lines):
            body_line = lines[i].lstrip("\t") if strip_tabs else lines[i]
            i += 1
            if body_line == delim:
                found = True
                break
        if not found:
            out.extend(lines[body_start:i])
    return "\n".join(out)

_COLON_NOOP_OPEN_RE = re.compile(r"^\s*:\s*([" + SQ + r"\"])")

def _strip_colon_noop(text):
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        m = _COLON_NOOP_OPEN_RE.match(line)
        i += 1
        if not m:
            out.append(line)
            continue
        out.append(line)
        quote = m.group(1)
        if quote in line[m.end():]:
            continue  # closed on the same line -- no block to skip
        while i < len(lines) and quote not in lines[i]:
            i += 1
        if i < len(lines):
            i += 1  # consume the closing-quote line too
    return "\n".join(out)

def _inert(text):
    return _strip_colon_noop(_strip_heredocs(text))

def assertion_lines(text):
    return Counter(ln.strip() for ln in _inert(text).splitlines() if ASSERT_RE.search(ln))

def skip_lines(text):
    return Counter(ln.strip() for ln in _inert(text).splitlines() if SKIP_RE.search(ln))

def dead_cond_lines(text):
    out = Counter()
    for raw in _inert(text).splitlines():
        ln = raw.strip()
        if DEAD_KEYWORD_RE.search(ln):
            out[ln] += 1
            continue
        m = DEAD_NUMERIC_RE.search(ln)
        if m:
            a, op, b = int(m.group(1)), m.group(2), int(m.group(3))
            is_dead = (op == "-eq" and a != b) or (op == "-ne" and a == b)
            if is_dead:
                out[ln] += 1
    return out

# The final `[ "$fail" -eq 0 ]` (or `[[ ]]`) line is what turns an
# accumulated fail count into the script'"'"'s real exit code -- this
# repo'"'"'s own test files, this gate'"'"'s own test included, all use it.
# Deleting it (or leaving check() itself untouched) silently disables a
# test file'"'"'s ability to ever fail CI, invisible to a call-site diff
# (deep-audit 2026-08-28).
EXIT_GATE_RE = re.compile(r"^\[\[?\s*\"?\$\{?fail\}?\"?\s*-eq\s*0\s*\]\]?")

def exit_gate_lines(text):
    return Counter(ln.strip() for ln in _inert(text).splitlines() if EXIT_GATE_RE.match(ln.strip()))

# Redefining the check() oracle itself is a total gate defeat, not a single
# skipped assertion -- call sites stay byte-identical, only the helper'"'"'s
# own body changes, which ASSERT_RE'"'"'s call-site-only pattern cannot see
# (deep-audit 2026-08-28, confirmed live). Compares the function'"'"'s full
# body text, not just its definition line, so a reformatted-but-unchanged
# body does not false-positive.
FUNC_BLOCK_RE = re.compile(r"^\s*(?:function\s+)?check\s*\(\s*\)\s*\{(.*?)^\s*\}", re.MULTILINE | re.DOTALL)

def check_helper_body(text):
    m = FUNC_BLOCK_RE.search(text)
    return m.group(1) if m else None

def weakened(old_text, new_text):
    removed_assert = assertion_lines(old_text) - assertion_lines(new_text)
    added_skip = skip_lines(new_text) - skip_lines(old_text)
    added_dead_cond = dead_cond_lines(new_text) - dead_cond_lines(old_text)
    removed_exit_gate = exit_gate_lines(old_text) - exit_gate_lines(new_text)
    helper_changed = check_helper_body(old_text) != check_helper_body(new_text)
    return (
        bool(removed_assert)
        or bool(added_skip)
        or bool(added_dead_cond)
        or bool(removed_exit_gate)
        or helper_changed
    )

def reason(path):
    return (
        "test-integrity: this edit to " + path + " appears to remove an "
        "assertion or add a skip/disable marker. If this is a legitimate "
        "test change, approve; if it is weakening a test to make a fix "
        "pass, write the fix instead (METHODOLOGY.md Rule 4)."
    )

try:
    d = json.load(sys.stdin)
    tool = d.get("tool_name", "") or ""
    ti = d.get("tool_input")
    if not isinstance(ti, dict):
        sys.exit(0)

    path = ti.get("file_path") or ""
    if not path or not PATH_RE.search(path):
        sys.exit(0)

    if tool == "Edit":
        old_s, new_s = ti.get("old_string", ""), ti.get("new_string", "")
        if weakened(old_s, new_s):
            emit_ask(reason(path))
        sys.exit(0)

    if tool == "MultiEdit":
        for e in ti.get("edits") or []:
            if not isinstance(e, dict):
                continue
            if weakened(e.get("old_string", ""), e.get("new_string", "")):
                emit_ask(reason(path))
                sys.exit(0)
        sys.exit(0)

    if tool == "Write":
        if not os.path.exists(path):
            sys.exit(0)  # new-file creation — no old side to weaken
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                old_text = f.read()
        except Exception:
            sys.exit(0)  # cannot read the old side — nothing to compare, allow
        new_text = str(ti.get("content", ""))
        if weakened(old_text, new_text):
            emit_ask(reason(path))
        sys.exit(0)

    sys.exit(0)
except Exception:
    # Cannot confirm this edit did not weaken a test — fail toward asking,
    # same direction db-write-gate.sh takes on an unclassifiable statement.
    emit_ask("test-integrity: could not classify this edit to a test-shaped path; approve manually or deny.")
' "$_lib"
