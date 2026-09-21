#!/usr/bin/env python3
# Shared bash quote/comment masker, extracted 2026-09-20 (deferred finding #10
# follow-up) after subagent-git-guard.py's _mask_quotes and test-integrity.py's
# _mask_quotes_bash drifted into byte-identical copies that independently
# missed, then independently fixed, the same "#" comment bug -- the exact
# same-bug-twice pattern GH #154/#155 already hit once for agent_id truthiness.
#
# Import defensively, same posture as _journal.py: every caller does
# `try: from _quotemask import mask_quotes / except Exception: <inline copy>`,
# never a bare import -- irrecoverable.sh's wrapper turns any non-{0,2} exit
# into a hard deny, so an ImportError here must never become a machine-wide
# Bash lockout on a deny-tier gate.
#
# Parsing/masking only, never a verdict or fail-direction -- callers still own
# what regex/anchor runs against the masked string and their own fail
# direction, per operating-model.md's "each gate owns its error path" line.

# ")" added 2026-09-21 (deep-audit): "(true)#don't" is a comment from "#" on
# in real bash. "}" and a backtick are NOT metacharacters ("}#x" is one
# word), so they stay out on purpose.
_WORD_BOUNDARY_CHARS = set(" \t\n;&|()")


def mask_quotes(s):
    # Every char inside a quoted span (quotes included) becomes a placeholder
    # that matches neither a separator, a keyword, nor a flag; output length
    # equals input so match positions found against the masked string still
    # line up with the original. Single-quote spans are literal, double-quote
    # spans honor backslash escapes, as in bash. A "#" at a word boundary
    # (start of string, or right after whitespace/;/&/|/(/)/newline) opens a
    # bash comment that masks to end-of-line with no quote semantics inside
    # it -- the fix for the live bug both prior copies independently hit.
    #
    # ponytail: heuristic word-boundary check, not full tokenization (no
    # backtick/$()-aware nesting either) -- widen _WORD_BOUNDARY_CHARS if a
    # real miss traces to an omitted operator. No handling for a backslash-
    # escaped quote OUTSIDE a span; add a one-char lookback if a real false
    # positive/negative traces to it.
    out = []
    i, n = 0, len(s)
    at_word_start = True
    while i < n:
        c = s[i]
        if c == "#" and at_word_start:
            while i < n and s[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if c == "'":
            out.append(" ")
            i += 1
            while i < n and s[i] != "'":
                out.append("Q")
                i += 1
            if i < n:
                out.append(" ")
                i += 1
            at_word_start = False
        elif c == '"':
            out.append(" ")
            i += 1
            while i < n and s[i] != '"':
                if s[i] == "\\" and i + 1 < n:
                    out.append("Q")
                    out.append("Q")
                    i += 2
                else:
                    out.append("Q")
                    i += 1
            if i < n:
                out.append(" ")
                i += 1
            at_word_start = False
        else:
            out.append(c)
            i += 1
            at_word_start = c in _WORD_BOUNDARY_CHARS
    return "".join(out)
