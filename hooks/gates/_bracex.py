"""Bash-style brace expansion of a whole command text, shared by the Bash gates (GH #309).

Bash, ksh and zsh (not dash) expand `a{b,c}d` into words before anything else reads them, so a brace
inside a word can hide a verb, a flag or a wrapper from a gate that reads the text literally
(`git {,"reset"} --hard`, `--fo{r,}{ce,}`, `r{m,} -rf`). expand_text() returns the command with every
brace group expanded the way the shell does it; a gate then runs its normal checks on that text too.

Outside quotes a brace group expands as the shell does (a quoted comma or brace is literal, a quote
inside an alternative is kept). Inside a quoted span the content is expanded as text of its own, because
the span may be the body of `bash -c '...'`, where the inner shell expands it; the quotes stay in the
text, so the gate's own tokenizer still reads `"git push --force"` as one word.
"""
import re

MAX_DEPTH = 64          # nesting of braces, and braces chained in one word
MAX_QDEPTH = 16         # quoted spans inside quoted spans
MAX_RANGE = 10_000      # alternatives one range may produce

class TooBig(Exception):
    """The expansion is over the budget: the caller denies instead of skipping the reading."""

_SEP = re.compile(r"([\s;&|()<>]+)")
_INT_RANGE = re.compile(r"^(-?\d+)\.\.(-?\d+)(?:\.\.(-?\d+))?$")
_CHR_RANGE = re.compile(r"^([A-Za-z])\.\.([A-Za-z])(?:\.\.(-?\d+))?$")
# inside a quoted span these stay literal for the outer expansion: private-use stand-ins, restored after
_PROT = {c: chr(0xE000 + i) for i, c in enumerate("{},;&|()<> \t\n")}
_TO_PROT = str.maketrans(_PROT)
_FROM_PROT = str.maketrans({v: k for k, v in _PROT.items()})

def _pairs(w):
    # {index of "{": index of its closing "}"} in one pass; "\x" is one literal character
    out, stack, j, n = {}, [], 0, len(w)
    while j < n:
        c = w[j]
        if c == "\\":
            j += 2
            continue
        if c == "{":
            stack.append(j)
        elif c == "}" and stack:
            out[stack.pop()] = j
        j += 1
    return out

def _split_top(body):
    # split on commas that sit outside nested braces
    parts, cur, depth, j, n = [], [], 0, 0, len(body)
    while j < n:
        c = body[j]
        if c == "\\" and j + 1 < n:
            cur.append(body[j:j + 2])
            j += 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
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
    # the items of {a..e}, {1..9}, {a..e..2}, {01..10}; None when body is not a range
    m = _INT_RANGE.match(body)
    if m:
        lo, hi = int(m.group(1)), int(m.group(2))
        width = max(len(m.group(1)), len(m.group(2))) if any(
            len(g.lstrip("-")) > 1 and g.lstrip("-").startswith("0") for g in m.group(1, 2)) else 0
        fmt = lambda v: str(v).zfill(width) if v >= 0 else "-" + str(-v).zfill(max(width - 1, 0))
    else:
        m = _CHR_RANGE.match(body)
        if not m:
            return None
        lo, hi = ord(m.group(1)), ord(m.group(2))
        fmt = chr
    step = abs(int(m.group(3))) if m.group(3) else 1
    step = step or 1
    if abs(hi - lo) // step + 1 > MAX_RANGE:
        raise TooBig("range over %d items" % MAX_RANGE)
    return [fmt(v) for v in (range(lo, hi + 1, step) if lo <= hi else range(lo, hi - 1, -step))]

def _expand_word(w, budget, depth):
    # all expansions of one word, leftmost group first; budget[0] counts the characters still allowed
    if depth > MAX_DEPTH:
        raise TooBig("brace nesting over %d" % MAX_DEPTH)
    i, n, pairs = 0, len(w), _pairs(w)
    while i < n:
        c = w[i]
        if c == "\\":
            i += 2
            continue
        if c == "{" and not (i and w[i - 1] == "$"):
            j = pairs.get(i, -1)
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
                            budget[0] -= len(s) + 1
                            if budget[0] < 0:
                                raise TooBig("expansion over the character cap")
                            out.append(s)
                    return out
        i += 1
    return [w]

def _quoted_spans(t):
    # [(quote char, content, closed)] for each quoted span and (None, run, True) for the text between;
    # a backslash escapes inside "..." and $'...', never inside '...'; an unclosed span runs to the end
    out, run, i, n = [], [], 0, len(t)
    while i < n:
        c = t[i]
        if c == "\\" and i + 1 < n:
            run.append(t[i:i + 2])
            i += 2
            continue
        if c in "'\"":
            ansi = c == "'" and run and run[-1].endswith("$")
            if ansi:
                run[-1] = run[-1][:-1]
            if run:
                out.append((None, "".join(run), True))
                run = []
            j = i + 1
            while j < n:
                if t[j] == "\\" and (c == '"' or ansi):
                    j += 2
                    continue
                if t[j] == c:
                    break
                j += 1
            out.append((("$" if ansi else "") + c, t[i + 1:j], j < n))
            i = j + 1
            continue
        run.append(c)
        i += 1
    if run:
        out.append((None, "".join(run), True))
    return out

def _expand(t, budget, qdepth):
    if qdepth > MAX_QDEPTH:
        raise TooBig("quote nesting over %d" % MAX_QDEPTH)
    if "{" not in t:
        return t
    pieces = []
    for q, text, closed in _quoted_spans(t):
        if q is None:
            pieces.append(text)
        else:
            inner = _expand(text, budget, qdepth + 1).translate(_TO_PROT)
            pieces.append(q + inner + (q[-1] if closed else ""))
    parts = _SEP.split("".join(pieces))
    for k in range(0, len(parts), 2):
        words = _expand_word(parts[k], budget, 0)
        if words != [parts[k]]:
            parts[k] = " ".join(words)
    return "".join(parts).translate(_FROM_PROT)

def expand_text(cmd, cap):
    """cmd with every brace group expanded; unchanged when none expands. Raises TooBig over cap."""
    if "{" not in cmd:
        return cmd
    out = _expand(cmd.replace("\\\n", ""), [cap], 0)
    if len(out) > cap:
        raise TooBig("expansion over the character cap")
    return cmd if out == cmd else out
