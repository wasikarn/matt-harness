"""Bash-style brace expansion of a whole command text, shared by the Bash gates (GH #309).

Bash, ksh and zsh (not dash) expand `a{b,c}d` into words before anything else reads them, so a brace
inside a word can hide a verb, a flag or a wrapper from a gate that reads the text literally
(`git {,"reset"} --hard`, `--fo{r,}{ce,}`, `r{m,} -rf`). expand_text() returns the command with every
brace group expanded the way the shell does it; a gate then runs its normal checks on that text too.

The text is lexed first, so what the shell treats as one unit stays one unit: a backslash pair, a
quoted span, `$(...)` and backticks (their content is expanded as command text of its own, because the
inner shell expands it, and bash -c '...' bodies likewise), and a comment (left alone: bash never reads
it). Only the unquoted words are expanded as the shell does, so a quoted comma or brace is literal and a
quote inside an alternative is kept. The quotes stay in the text, so the gate's own tokenizer still
reads `"git push --force"` as one word.

Fail-closed, never skipped: nesting, a range or a product over the budget, or a raw stand-in
character (a noncharacter, U+FDD0-U+FDEF; see _PROT) raises TooBig, and the caller denies. A numeric range over MAX_NUM_RANGE
items is left literal instead: digits cannot spell a verb or a flag.
"""
import json
import re

MAX_DEPTH = 64          # nesting of braces, and braces chained in one word
MAX_QDEPTH = 16         # quoted spans and substitutions inside each other
MAX_NUM_RANGE = 64      # a larger numeric range stays literal (digits hide nothing)

class TooBig(Exception):
    """The expansion is over the budget: the caller denies instead of skipping the reading."""

_SEP = re.compile(r"([\s;&|()<>]+)")
_INT_RANGE = re.compile(r"^(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?$")
# zsh reads any two single characters as a range ({x..3} is x w v ... 3, so "gi{t..3}" holds "git"); bash
# leaves a mixed one literal. Expanding it is the safe reading: more words are checked, never fewer.
_RANGE_SYNTAX = frozenset(";&|()<>`$'\"\\#{},!~")
_CHR_RANGE = re.compile(r"^([^\s{},\\'\"`$.])\.\.([^\s{},\\'\"`$.])(?:\.\.(-?\d+))?$")
# a protected span keeps these literal for the outer expansion: noncharacter stand-ins, restored after
_PROT = {c: chr(0xFDD0 + i) for i, c in enumerate("{},;&|()<> \t\n#\\")}
_TO_PROT = str.maketrans(_PROT)
_FROM_PROT = str.maketrans({v: k for k, v in _PROT.items()})
_PRIVATE = re.compile("[" + chr(0xFDD0) + "-" + chr(0xFDEF) + "]")   # noncharacters: never in real text
_WORD_START = " \t\n;&|()<>"

def _max_depth(t):
    # deepest nesting of matched braces, one pass; a "\x" pair is one literal character
    stack, deepest, j, n = 0, 0, 0, len(t)
    while j < n:
        c = t[j]
        if c == "\\":
            j += 2
            continue
        if c == "{":
            stack += 1
        elif c == "}" and stack:
            deepest = max(deepest, stack)
            stack -= 1
        j += 1
    return deepest

_SCAN = [0]  # characters read while looking for closing braces, per expand_text call
MAX_SCAN = 4_000_000

def _closing(w, i):
    # Bash's brace_gobbler: index of the "}" that closes the "{" at w[i], or -1. A "}" at the group's own
    # level closes it only once a comma (at that level) or ".." not followed by "}" (at any level) has been seen; before that
    # it is a literal character of the group, so "{A=1}},git}" is two words ("A=1}}" and "git"). A "}"
    # inside a nested group closes that group. "\x" is one character.
    level, commas, j, n = 0, 0, i + 1, len(w)
    while j < n:
        c = w[j]
        if c == "\\":
            j += 2
            continue
        if c == "}" and level == 0 and commas:
            break
        if c == "{":
            level += 1
        elif c == "}":
            if level:
                level -= 1
        elif c == "," and level == 0:
            commas += 1
        elif c == "." and w.startswith("..", j) and w[j + 2:j + 3] != "}":
            commas += 1
        j += 1
    else:
        j = -1
    _SCAN[0] += (n if j < 0 else j) - i
    if _SCAN[0] > MAX_SCAN:
        raise TooBig("brace scan over %d characters" % MAX_SCAN)
    return j

def _split_top(body):
    # split on commas outside nested braces; a stray "}" at the top level is a literal character
    parts, cur, depth, j, n = [], [], 0, 0, len(body)
    while j < n:
        c = body[j]
        if c == "\\" and j + 1 < n:
            cur.append(body[j:j + 2])
            j += 2
            continue
        if c == "{":
            depth += 1
        elif c == "}" and depth:
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        j += 1
    parts.append("".join(cur))
    return parts

def _range(body):
    # the items of {a..e}, {1..9}, {a..e..2}, {01..10}; None when body is not a range (or a numeric
    # range too large to matter)
    m = _INT_RANGE.match(body)
    if m:
        lo, hi = int(m.group(1)), int(m.group(2))
        step = abs(int(m.group(3))) if m.group(3) else 1
        step = step or 1
        if abs(hi - lo) // step + 1 > MAX_NUM_RANGE:
            return None
        width = max(len(m.group(1)), len(m.group(2))) if any(
            len(g.lstrip("-")) > 1 and g.lstrip("-").startswith("0") for g in m.group(1, 2)) else 0
        fmt = lambda v: str(v).zfill(width) if v >= 0 else "-" + str(-v).zfill(max(width - 1, 0))
    else:
        m = _CHR_RANGE.match(body)
        if not m:
            return None
        lo, hi = ord(m.group(1)), ord(m.group(2))
        # a character the shell would read as syntax stays a literal word character: {Z..a} holds "`", "\\"
        # and zsh's {+..9} holds ",", ";" and "(": backslash-escaped, so the text read later has the same words
        fmt = lambda v: "\\" + chr(v) if chr(v) in _RANGE_SYNTAX else chr(v)
        step = abs(int(m.group(3))) if m.group(3) else 1
        step = step or 1
    return [fmt(v) for v in (range(lo, hi + 1, step) if lo <= hi else range(lo, hi - 1, -step))]

def _expand_word(w, budget, depth):
    # all expansions of one word, leftmost group first; budget[0] counts the characters still allowed
    if depth > MAX_DEPTH:
        raise TooBig("brace nesting over %d" % MAX_DEPTH)
    i, n = 0, len(w)
    while i < n:
        c = w[i]
        if c == "\\":
            i += 2
            continue
        # bash never opens a group at a "{" that starts the text and is followed by "}" or a blank
        if c == "{" and not (i and w[i - 1] == "$") and not (depth == 0 and i == 0 and (n == 1 or w[1] == "}")):
            j = _closing(w, i)
            if j > 0:
                body = w[i + 1:j]
                alts = _split_top(body)
                items = _range(body) if len(alts) == 1 else None
                if len(alts) > 1 or items is not None:
                    pre, post = w[:i], w[j + 1:]
                    heads = [x for a in alts for x in _expand_word(a, budget, depth + 1)] if items is None else items
                    tails = _expand_word(post, budget, depth + 1)
                    out = []
                    for h in heads:
                        for t in tails:
                            s = pre + h + t
                            # With no text before or after, s is h itself: an alternative that a nested
                            # group already charged. Charging it again made a nested expansion over half
                            # the cap deny early; every new string is still charged, at every level, so
                            # chained groups cannot build a huge list before anything is checked.
                            if pre or t:
                                budget[0] -= len(s) + 1
                                if budget[0] < 0:
                                    raise TooBig("expansion over the character cap")
                            out.append(s)
                    return out
        i += 1
    return [w]

def _close(t, i, opener, depth=0):
    # index just past the span that starts at t[i]: a quote, "$(", "$((" or a backtick; len(t) if unclosed
    if depth > MAX_QDEPTH:
        raise TooBig("quote nesting over %d" % MAX_QDEPTH)
    n = len(t)
    if opener == "$(":
        parens, j = 0, i + 2
        while j < n:
            c = t[j]
            if c == "\\":
                j += 2
                continue
            if c in "'\"`":
                j = _close(t, j, c, depth + 1)
                continue
            if c == "$" and t[j + 1:j + 2] == "(":
                parens += 1
                j += 2
                continue
            if c == "(":
                parens += 1
            elif c == ")":
                if parens == 0:
                    return j + 1
                parens -= 1
            j += 1
        return n
    ansi = opener == "$'"
    q = opener[-1]
    j = i + len(opener)
    while j < n:
        c = t[j]
        if c == "\\" and (q != "'" or ansi):
            j += 2
            continue
        if q == '"' and c == "$" and t[j + 1:j + 2] == "(":
            j = _close(t, j + 1, "$(", depth + 1)
            continue
        if c == q:
            return j + 1
        j += 1
    return n

def _segments(t):
    # [(kind, opener, content, closer)]: kind "u" plain text, "q" a quoted span, "s" a substitution or
    # backticks, "c" a comment; opener/closer are the delimiters kept around the content
    out, run, i, n, prev = [], [], 0, len(t), "\n"
    def flush():
        if run:
            out.append(("u", "", "".join(run), ""))
            run.clear()
    while i < n:
        c = t[i]
        if c == "\\" and i + 1 < n:
            run.append(t[i:i + 2])
            prev = t[i + 1]
            i += 2
            continue
        if c == "#" and prev in _WORD_START:
            flush()
            j = t.find("\n", i)
            j = n if j < 0 else j
            out.append(("c", "", t[i:j], ""))
            prev = "x"
            i = j
            continue
        opener = None
        if c == "$" and t[i + 1:i + 2] == "(":
            opener = "$((" if t[i + 2:i + 3] == "(" else "$("
        elif c == "$" and t[i + 1:i + 2] == "'":
            opener = "$'"
        elif c in "'\"`":
            opener = c
        if opener:
            flush()
            end = _close(t, i, "$(" if opener.startswith("$(") else opener)
            lo = i + len(opener)
            closed = end <= n and end > lo and t[end - 1] == (")" if opener.startswith("$(") else opener[-1])
            hi = end - 1 if closed else end
            if opener == "$((":
                out.append(("u", "", t[i:end], ""))   # arithmetic, not command text: a literal run
            else:
                out.append(("s" if opener[0] in "$`" and opener != "$'" else "q", opener, t[lo:hi],
                            (")" if opener.startswith("$(") else opener[-1]) if closed else ""))
            prev = "x"
            i = end
            continue
        run.append(c)
        prev = c
        i += 1
    flush()
    return out

def _is_json_data(text):
    # a single-quoted span that is valid JSON object/array text is data: it is no runnable command, and a
    # brace-hidden verb cannot ride in it (chained objects there multiplied past the cap and denied)
    s = text.strip()
    if not s or s[0] not in "{[" or s[-1] not in "}]":
        return False
    try:
        json.loads(s)
    except (ValueError, RecursionError):
        return False
    return True

def _expand(t, budget, qdepth):
    if qdepth > MAX_QDEPTH:
        raise TooBig("quote nesting over %d" % MAX_QDEPTH)
    if "{" not in t:
        return t
    pieces = []
    for kind, opener, text, closer in _segments(t):
        if kind == "u":
            pieces.append(text)
        elif kind == "c":
            pieces.append(text.translate(_TO_PROT))
        elif opener == "'" and closer and _is_json_data(text):
            pieces.append((opener + text + closer).translate(_TO_PROT))
        else:
            pieces.append(opener.translate(_TO_PROT) + _expand(text, budget, qdepth + 1).translate(_TO_PROT)
                          + closer.translate(_TO_PROT))
    # an escaped blank or operator ("\ ", "\;") belongs to its word; pairs are read left to right
    joined = re.sub(r"\\(.)", lambda m: "\\" + _PROT.get(m.group(1), m.group(1)), "".join(pieces), flags=re.S)
    parts = _SEP.split(joined)
    for k in range(0, len(parts), 2):
        words = _expand_word(parts[k], budget, 0)
        if words != [parts[k]]:
            # a word the expansion makes start with "#" is literal in bash, but a gate would read a comment
            parts[k] = " ".join("\\" + x if x.startswith("#") else x for x in words)
    return "".join(parts).translate(_FROM_PROT)

def expand_text(cmd, cap):
    """cmd with every brace group expanded; unchanged when none expands. Raises TooBig over cap."""
    if "{" not in cmd:
        return cmd
    if _PRIVATE.search(cmd):
        raise TooBig("expander stand-in character in the command")
    if _max_depth(cmd) > MAX_DEPTH:
        raise TooBig("brace nesting over %d" % MAX_DEPTH)
    _SCAN[0] = 0
    out = _expand(cmd.replace("\\\n", ""), [cap], 0)
    if len(out) > cap:
        raise TooBig("expansion over the character cap")
    return cmd if out == cmd else out
