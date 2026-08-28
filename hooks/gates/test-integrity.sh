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
# Known, deliberate gap: this only catches a REMOVED assertion line or an
# ADDED skip marker. An edit that inserts an early return/exit before
# existing assertions (making them unreachable without deleting them) is
# not detected — a real residual, not claimed as covered.
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — test-integrity gate cannot run; allowing (install python3 to restore the ask)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, os, re, sys

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
# use here. Also covers the python/pytest idiom for the non-bash test files.
ASSERT_RE = re.compile(r"\bcheck\s*\"|\bassert\b|\bself\.assert|\bpytest\.raises\b|\bpytest\.fail\b")
SKIP_RE = re.compile(r"#\s*SKIP\b|@pytest\.mark\.(skip|xfail)|\.skip\s*\(|\bxit\s*\(|\bit\.skip\s*\(", re.IGNORECASE)

def assertion_lines(text):
    return {ln.strip() for ln in text.splitlines() if ASSERT_RE.search(ln)}

def skip_lines(text):
    return {ln.strip() for ln in text.splitlines() if SKIP_RE.search(ln)}

def weakened(old_text, new_text):
    removed_assert = assertion_lines(old_text) - assertion_lines(new_text)
    added_skip = skip_lines(new_text) - skip_lines(old_text)
    return bool(removed_assert) or bool(added_skip)

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
' "$(dirname "$0")/lib"
