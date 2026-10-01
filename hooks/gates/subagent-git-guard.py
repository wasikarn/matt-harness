#!/usr/bin/env python3
import json, re, sys

# GH #156: raise the int-string digit limit before parsing so an oversized
# unquoted int literal doesn't crash json.load() into this gate's fail-open
# except below (full rationale: codex-setup-guard.py). hasattr-guarded: the
# method doesn't exist before Python 3.11.
if hasattr(sys, "set_int_max_str_digits"):
    sys.set_int_max_str_digits(0)

try:
    from _journal import journal
except Exception:
    def journal(*a, **k):
        pass

GATE_ID = "gate:bash:subagent-git-guard"

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW: a parse error must not stall every subagent Bash call.
    print(f"[mh:gate] subagent-git-guard: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    print("[mh:gate] subagent-git-guard: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

if d.get("tool_name") != "Bash":
    sys.exit(0)

# agent_id is present ONLY inside a subagent call. Presence, not truthiness --
# an empty-string or null agent_id is still the signal (same fix already
# applied to subagent-spawn-guard.py:38 (GH #154) and
# task-complete-separation.py:57 (GH #155); this gate predated both and was
# missed until the 2026-09-20 audit).
if "agent_id" not in d:
    sys.exit(0)

ti = d.get("tool_input")
cmd = ti.get("command") if isinstance(ti, dict) else None
if not isinstance(cmd, str):
    sys.exit(0)

def clip(s):
    # Log-injection guard: a crafted command cannot forge/erase a [mh:gate] line.
    s = re.sub(r"[^\x20-\x7e]", "?", str(s))
    return s[:120]

agent_type = clip(d.get("agent_type") or "unknown")

# 2026-09-20: extracted to a shared hooks/gates/_quotemask.py after this
# function and test-integrity.py's identical _mask_quotes_bash drifted into
# byte-for-byte copies that independently missed, then independently fixed,
# the same "#"-comment bug (deep-audit 2026-09-20: an ordinary comment
# apostrophe before a real "git" command opened an unterminated fake quote
# span, masking the literal "git" anchor away -- a full gate bypass).
# Defensive import, same posture as _journal.py: an ImportError here must
# never become a machine-wide Bash lockout on this deny-tier gate, so the
# fallback is the same inline copy this file carried before extraction.
try:
    from _quotemask import mask_quotes as _mask_quotes
except Exception:
    def _mask_quotes(s):
        out = []
        i, n = 0, len(s)
        at_word_start = True
        while i < n:
            c = s[i]
            if c == "#" and at_word_start:
                while i < n and s[i] != "\n":
                    out.append(" "); i += 1
                continue
            if c == "'":
                out.append(" "); i += 1
                while i < n and s[i] != "'":
                    out.append("Q"); i += 1
                if i < n:
                    out.append(" "); i += 1
                at_word_start = False
            elif c == "$":  # GH #161: ANSI-C $'...', backslash escapes the next char; only the last "$" of an odd run opens it ("$$" is the PID)
                j = i
                while j < n and s[j] == "$":
                    out.append("$"); j += 1
                if (j - i) % 2 == 0 or j >= n or s[j] != "'":
                    i = j; at_word_start = False
                    continue
                out[-1] = " "; out.append(" "); i = j + 1
                while i < n and s[i] != "'":
                    if s[i] == "\\" and i + 1 < n:
                        out.append("Q"); out.append("Q"); i += 2
                    else:
                        out.append("Q"); i += 1
                if i < n:
                    out.append(" "); i += 1
                at_word_start = False
            elif c == '"':
                out.append(" "); i += 1
                while i < n and s[i] != '"':
                    if s[i] == "\\" and i + 1 < n:
                        out.append("Q"); out.append("Q"); i += 2
                    else:
                        out.append("Q"); i += 1
                if i < n:
                    out.append(" "); i += 1
                at_word_start = False
            elif c == "\\":  # GH #157 sibling: an odd backslash run escapes a following quote (literal, not a span)
                j = i
                while j < n and s[j] == "\\":
                    out.append("\\"); j += 1
                if (j - i) % 2 == 1 and j < n and s[j] in "'\"$":  # an escaped "$" is literal too, never an ANSI-C opener
                    out.append("Q"); j += 1
                i = j
                at_word_start = False
            else:
                out.append(c); i += 1
                at_word_start = c in set(" \t\n;&|()")
        return "".join(out)

masked = _mask_quotes(cmd)

# Anchor: "git" must sit at a real command-start (string/line start, |;&(, &&,
# ||, optional VAR=val chain, optional prefix wrapper(s), or a /path/git).
# re.MULTILINE so each line of a multi-line command anchors. Runs on the masked
# string, so `git commit -m "fix; git reset was wrong"` never anchors inside
# the quotes.
#
# 2026-09-20 audit: the old wrapper allowance (`sudo`/`xargs` only, one level)
# missed `env`/`command`/`nice` and a bare `\git` (backslash suppresses alias
# lookup; the command itself is unaffected) -- live-confirmed to still reach
# real git for a subagent. Fix: matched against a fixed wrapper-word list.
# `xargs` kept from the original list (this file never runs its own
# xargs-unwrap, so the anchor must still recognize it).
#
# 2026-09-20 fix-round 2 (compliance-audit): a first attempt bounded both
# chain depth and flags-per-wrapper at 3 to dodge the catastrophic-
# backtracking shape of `(?:(?:sudo|env|...)\s+(?:\S+\s+)*)*` (a wrapper word
# also matches the inner generic token, so the two `*`s compete for the same
# input) -- but that bound was itself a live-demonstrated gap (a 13-wrapper
# chain got through). The actual fix is to remove the ambiguity instead: the
# inner flag-scan excludes anything matching a wrapper word via a negative
# lookahead, so a token is always unambiguously "the next wrapper" or "a
# flag", never a choice between the two -- O(n), no backtracking, and both
# axes are genuinely unbounded again, matching irrecoverable.py's identical
# fix to its nested-spawn anchor.
#
# GH #213: the list gained exec/setsid/timeout/gtimeout/stdbuf/ionice (the same
# words as irrecoverable.py's PREFIX_WRAPPERS, which this file still types by
# hand), and a shell keyword may open the command position ("for i in 1; do git
# stash; done"). A wrapper word must be followed by whitespace in the lookahead
# too: with a bare \b a token that only STARTS with one ("timeout=30") is neither
# a wrapper nor an ordinary token, and the regex dead-ends.
_WRAPPER_WORDS = ("env", "command", "nohup", "nice", "time", "sudo", "xargs",
                  "exec", "setsid", "timeout", "gtimeout", "stdbuf", "ionice")
_KEYWORDS = ("!", "if", "elif", "then", "else", "do", "while", "until", "coproc")
_WRAPPER_ALT = r"(?:" + "|".join(_WRAPPER_WORDS) + r")(?=\s)"
_WRAPPER_PREFIX = r"(?:" + _WRAPPER_ALT + r"\s+(?:(?!" + _WRAPPER_ALT + r")\S+\s+)*)*"
# GH #248: the greedy walk above lands on the LAST target, so `time git stash; git status` anchored
# only the second `git`. The lazy twin (`*?`) lands on the FIRST target after the wrappers. It only
# runs as a last, extra pass, so it can only add anchors.
_WRAPPER_PREFIX_LAZY = r"(?:" + _WRAPPER_ALT + r"\s+(?:(?!" + _WRAPPER_ALT + r")\S+\s+)*?)*"
_KEYWORD_PREFIX = r"(?:(?:" + "|".join(re.escape(k) for k in _KEYWORDS) + r")\s+)*"
# Deep-audit 4: eval (its unquoted args are a command line), builtin and rtk run the command
# after them, but they are NOT in _WRAPPER_WORDS. That list drives the greedy argument walk
# above, which crosses `;` / `&&` / newlines to the LAST `git` and lets finditer resume after
# it, so a real `git stash` in an earlier statement was never tested (`eval true; git stash;
# git status`; time, timeout and env leaked this way until GH #245's overlapping scan). These words take
# their own bounded prefix instead: the word itself, `rtk`'s global flags and one runner verb
# with its flags, never an argument walk. It sits AFTER the wrapper walk, so the walk still
# behaves exactly as before for every old wrapper, and it can only add anchors.
_SHELL_PASS = r"(?:(?:eval|builtin|command|exec)[ \t]+(?:--[ \t]+)?)"
_RTK_PREFIX = r"(?:rtk[ \t]+(?:-\S+[ \t]+)*(?:(?:proxy|run|err|test|summary)[ \t]+(?:-\S+[ \t]+)*)?)"
_CHAIN_PREFIX = r"(?:" + _SHELL_PASS + r"|" + _RTK_PREFIX + r")*"
# GH #248: `{ git stash; }` -- a brace group opens a command position (`{` then blank).
def _cmd_start(wrapper_prefix):
    return (r"(?:^|[|;&(]|&&|\|\||\{(?=\s))\s*" + _KEYWORD_PREFIX +
            r"(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*" + wrapper_prefix + _CHAIN_PREFIX)
# GH #245: every anchor regex is scanned with overlapping matches, `(?=(...))`, read through
# m.end(1). The old wrappers' greedy argument walk (`time ls; git stash; git status`) crosses
# `;` / `&&` / newline to the LAST `git`, and a plain finditer resumed after that match, so the
# earlier statement was never checked. The zero-width scan tries every position, so each
# separator inside a walked span still anchors. At any position where finditer matched, the
# inner regex finds the same match, so this only adds checks, never drops one.
# The overlapping scan is quadratic on long padded commands, and a timed-out hook allows, so the
# plain scans (develop's exact behaviour, fast) run first and the overlapping pass only after
# both allowed: a command the plain scans deny is denied just as fast as before.
def _plain_and_overlapping(tail):
    pattern = _cmd_start(_WRAPPER_PREFIX) + tail
    return (re.compile(r"(" + pattern + r")", re.MULTILINE),
            re.compile(r"(?=(" + pattern + r"))", re.MULTILINE),
            re.compile(r"(?=(" + _cmd_start(_WRAPPER_PREFIX_LAZY) + tail + r"))", re.MULTILINE))

_ANCHOR_RES = _plain_and_overlapping(r"\\?(?:\S*/)?git\b")
# `bash -c "<body>"` / `eval "<body>"`: the body is a quoted string, so the masked
# text hides it. The shell word is matched on the masked string (a real command,
# not text inside a message); the body is read from the raw command at the same
# offset (masking is 1:1) and checked as its own command line, one level deep.
# `rtk run [flags] "<body>"` and `rtk err|test|summary [flags] "<body>"` run their args through
# `sh -c` (irrecoverable.py, GH #216), so a quoted arg is a body too. Flags after the verb
# (`-c`, `--command`, `--command='...'`, `--skip-env`, `--ultra-compact`, a bare `--`) come
# before it. The string is quote-masked, so an opening quote is a blank there and a flag
# word ends at it: `--command='git stash'` leaves the quote for _QUOTED_RE.
# The flags after the verb may not hold `;`, `&` or `|`: this alternative can match on its own, and
# with `\S` it would swallow the next statement's separator (`rtk run -n||timeout 5 bash -c '...'`)
# so finditer resumed after it and never saw that statement's shell word.
_RTK_BODY = r"rtk[ \t]+(?:-\S+[ \t]+)*(?:run|err|test|summary)(?:[ \t]+-[^\s;&|]*)*"
_SHELL_RES = _plain_and_overlapping(
    r"\\?(?:\S*/)?(?:(?:bash|sh|zsh|dash|ksh)\s+(?:-\S+\s+)*?-\w*c\w*|eval|" + _RTK_BODY + r")(?=\s)"
)
# Masking blanks the quote characters, so the raw body is found by skipping
# whitespace from the end of the shell word.
_QUOTED_RE = re.compile(r'\s*(?:"((?:[^"\\]|\\.)*)"|' + "'([^']*)')")
# Only stash/reset/clean (see header); read-only `stash list|show` carved out.
_DENY_SUBCMD_RE = re.compile(r"\A\s+(stash(?!\s+(list|show)\b)|reset|clean)\b")

# Git global flags walked past before the subcommand check, so `git -C /repo
# stash` / `git --no-pager clean` do not land the check on sub="-C".
_GIT_VALUE_GLOBALS = ("-C", "-c", "--git-dir", "--work-tree", "--config-env", "--namespace", "--attr-source")

_FLAG_TOKEN_RE = re.compile(r"\s+(\S+)")
_FLAG_VALUE_RE = re.compile(r"\s+\S+")

def _skip_git_globals(tail):
    # tail starts right after the "git" anchor on the masked string. Returns the
    # suffix from the first non-flag token, leading whitespace intact for \A\s+.
    # GH #246: match at offset i, never re-slice the tail per flag (quadratic on a long flag run).
    i = 0
    while True:
        m = _FLAG_TOKEN_RE.match(tail, i)
        if not m:
            return tail[i:]
        tok = m.group(1)
        if not tok.startswith("-"):
            return tail[i:]
        if tok in _GIT_VALUE_GLOBALS:
            i = m.end()
            m2 = _FLAG_VALUE_RE.match(tail, i)
            if m2:
                i = m2.end()
            continue
        i = m.end()  # any other flag, bare or combined: --git-dir=X, --no-pager, -p, ...

# GH #246: every anchor scan tries each command start (a separator or line start) and walks the
# rest of the string when a wrapper word or assignment follows, so the work grows like
# starts x length. `env ; ` x 5000 (30 KB) or 6000 bare newlines run past the 8 s hook timeout,
# and a timed-out hook allows: padding in front of a real `git stash` walked around the deny.
# Each scan charges that upper bound to one shared budget (bodies and all three passes add up) and a
# command over budget is denied, never scanned. Real subagent commands charge far less; only a
# rare huge script (20-28 KB, about 7e7 over six scans) is refused.
# Deep-audit 5: a run of chain words (_CHAIN_PREFIX: eval/builtin/command/exec/rtk) after a wrapper
# is re-read from every walk position, so it costs about run x run per command start even with a
# single start (`true; ` + `command ` x 8000 before a `git stash` took 9 s). Each maximal run charges
# its length squared per start, plus one for the line start.
_WORK_BUDGET = 60_000_000
_work = 0
_CHAIN_RUN_RE = re.compile(r"(?<!\S)(?:" + _SHELL_PASS + r"|" + _RTK_PREFIX + r")+")

class _TooCostly(Exception):
    pass

def _charge(s):
    global _work
    starts = sum(s.count(c) for c in "\n;&|({")
    runs = sum((m.end() - m.start()) ** 2 for m in _CHAIN_RUN_RE.finditer(s))
    _work += starts * len(s) + (starts + 1) * runs
    if _work > _WORK_BUDGET:
        raise _TooCostly

def _violation(masked_cmd, overlap):
    _charge(masked_cmd)
    for m in _ANCHOR_RES[overlap].finditer(masked_cmd):
        dm = _DENY_SUBCMD_RE.match(_skip_git_globals(masked_cmd[m.end(1):]))
        if dm:
            return dm.group(1)
    return None

def _violation_in_bodies(raw_cmd, masked_cmd, overlap):
    _charge(masked_cmd)
    for m in _SHELL_RES[overlap].finditer(masked_cmd):
        q = _QUOTED_RE.match(raw_cmd, m.end(1))
        if q:
            body = q.group(1) if q.group(1) is not None else q.group(2)
            mb = _mask_quotes(body)
            hit = _violation(mb, False) or (overlap and _violation(mb, overlap))
            if hit:
                return hit
    return None

# GH #274: the mask blanks everything inside "..." so `echo "$(git clean -fd)"` and backticks
# hid a real command. One linear pass over the raw command collects every $(...) / `...` body at
# any depth (a frame stack, so nesting costs no rescans); each body is then checked as its own
# command line. Single-quoted text is literal and skipped; an unterminated body runs to the end.
# The pass also knows what a naive bracket count gets wrong: a case pattern's `)`, a `#` comment,
# `${x:-)}`, escaped backticks nested in backticks, and heredoc bodies (a quoted-delimiter body is
# data and is skipped whole; an unquoted one is data too, except for the substitutions in it).
# Every body copy and every scan is charged to the shared work budget, so a pathological nest is
# denied as too costly instead of being scanned (a timed-out hook allows).
_WORD_RE = re.compile(r"\w+")
_CMD_KEYWORDS = ("then", "do", "else", "elif", "if", "while", "until", "time", "!")
_BT_ESCAPE_RE = re.compile(r"\\([`\\$])")
# The delimiter is the whole shell word: a quoted word, or a run of plain characters that must end
# at a blank or a metacharacter (`EOF-1` is one delimiter; `E"O"F` and `$x` are not read at all, so
# the body is scanned as code, never skipped). `<<\EOF` (a backslash-quoted word) is read the same way.
_HD_START_RE = re.compile(
    r"<<-?[ \t]*(?:'([^'\n]+)'|\"([^\"\n]+)\"|(\\?[^\s;&|<>()'\"`$\\]+))(?=[\s;&|<>()]|$)")

def _in_arith(s, i):
    # `$((1<<EOF))` and `((x<<EOF))` shift; they open no heredoc. Looks back on the same line for a
    # `((` that no `))` has closed. Anything unsure is read as arithmetic, so the body is scanned.
    ls = s.rfind("\n", 0, i) + 1
    _scan_cost(i - ls)
    return s.rfind("((", ls, i) > s.rfind("))", ls, i)

def _scan_cost(k):
    global _work
    _work += k
    if _work > _WORK_BUDGET:
        raise _TooCostly

def _heredoc_at(s, i, after=None):
    # A heredoc operator at s[i]: (trigger, body start, body end, terminator end, quoted delimiter),
    # or None. The trigger is the newline where the body begins. A second heredoc on the same line
    # passes `after`, the first one's terminator end: its body starts on the next line and its
    # trigger is that terminator end. The terminator match is lenient (spaces allowed), so it can
    # only end the body sooner than the shell does, never later: a lenient miss scans more, not less.
    m = _HD_START_RE.match(s, i)
    eol = s.find("\n", m.end()) if m else -1
    if eol < 0 or _in_arith(s, i):
        return None
    word = m.group(1) or m.group(2) or m.group(3)
    trigger = eol if after is None else after
    _scan_cost(len(s) - i)
    t = re.compile(r"^[ \t]*" + re.escape(word.lstrip("\\")) + r"[ \t]*$", re.MULTILINE).search(s, trigger + 1)
    return (trigger, trigger + 1, t.start(), t.end(), m.group(3) is None or word.startswith("\\")) if t else None

def _substitution_bodies(s):
    bodies, n, i = [], len(s), 0
    # frame: kind, body start, open quote, paren depth, open `case` count, saw case, at command
    # position, open ${ count
    frames = [["top", 0, None, 0, 0, False, True, 0]]
    pend = []  # heredocs whose bodies start after the current line, in order
    hd_end = hd_depth = -1
    _scan_cost(n * 4)

    def done(f, end):
        body = s[f[1]:end]
        _scan_cost(len(body))
        if f[0] == "bt" and _BT_ESCAPE_RE.search(body):
            # Inside backticks \` \$ and \\ are escapes the shell reads off before it runs the body
            # (`"\$(git stash)"` runs it); read one level off and rescan. Each level of backticks
            # doubles the backslashes, so this recursion is log-deep.
            body = _BT_ESCAPE_RE.sub(r"\1", body)
            bodies.extend(_substitution_bodies(body))
        if f[5]:  # a case pattern's `)` opens a command; make it a separator (same length, offsets hold)
            body = body.replace(")", ";")
        bodies.append(body)

    while i < n:
        if pend and i == pend[0][0]:
            _, bs, be, te, quoted = pend.pop(0)
            if quoted:
                i = te
                continue
            hd_end, hd_depth = be, len(frames)
        f, c = frames[-1], s[i]
        if i < hd_end and len(frames) == hd_depth and c not in "\\`$":
            i += 1  # heredoc text: quotes, parens and # are literal there
            continue
        if f[2] == "'":
            if c == "'":
                f[2] = None
        elif c == "\\":
            i += 1
        elif c == "'" and f[0] != "bt":
            f[2] = "'"
        elif c == '"':
            f[2] = None if f[2] == '"' else '"'
        elif c == "<" and f[2] is None and s.startswith("<<", i) \
                and s[i + 2:i + 3] != "<" and s[i - 1:i] != "<":
            h = _heredoc_at(s, i, pend[-1][3] if pend else None)
            if h:
                pend.append(h)
            i += 1
        elif c == "`":
            if f[0] == "bt" and f[2] is None:
                done(f, i); frames.pop()
            # zsh reads a backtick inside quotes inside backticks as a nested open, bash as the
            # close; scanning it as nested catches what zsh runs.
            else:
                frames.append(["bt", i + 1, None, 0, 0, False, True, 0])
        elif c == "$" and s[i + 1:i + 2] == "(":
            frames.append(["paren", i + 2, None, 0, 0, False, True, 0]); i += 1
        elif c == "$" and s[i + 1:i + 2] == "{":
            f[7] += 1; i += 1
        elif f[0] == "paren" and f[2] is None:
            # f[6]: at a command position, so only a `case` there opens a case (`echo case` does not)
            if c in " \t":
                pass
            elif c == "}" and f[7]:
                f[7] -= 1
            elif c == "(":
                f[3] += 1; f[6] = True
            elif c == ")":
                f[6] = bool(f[4])
                if f[7]:
                    pass  # `${y:-)}`: a literal paren
                elif f[3]:
                    f[3] -= 1
                elif not f[4]:  # a `)` that ends a case pattern is not the end of the body
                    done(f, i); frames.pop()
            elif c == "#" and (i == f[1] or s[i - 1] in " \t\n;&|("):  # a comment: its `)` closes nothing
                j = s.find("\n", i)
                i = n if j < 0 else j
            elif c.isalpha() and not (s[i - 1].isalnum() or s[i - 1] in "_$"):
                m = _WORD_RE.match(s, i)
                w = m.group() if m else c
                if w == "case" and f[6]:
                    f[4] += 1; f[5] = True
                elif w == "esac" and f[4]:
                    f[4] -= 1
                f[6] = w in _CMD_KEYWORDS
                i += len(w) - 1
            else:
                f[6] = c in ";&|\n{"
        i += 1
    for f in frames[1:]:
        done(f, n)
    return bodies

# A heredoc body is data (`git commit -m "$(cat <<'EOF' ... EOF)"`), so blank it before the check.
# A $(...) nested in it is its own entry in _substitution_bodies and is still checked. The operator
# is looked for on the quote-masked text, so a `<<A` inside quotes cannot blank a real command.
_HD_OP_RE = re.compile(r"(?<!<)<<(?!<)")

def _blank_heredocs(s):
    spans, line_end, last = [], -1, None
    for m in _HD_OP_RE.finditer(_mask_quotes(s)):
        p = m.start()
        _scan_cost(len(spans))
        if any(a <= p < b for a, b in spans):  # inside a body already blanked
            continue
        chained = p < line_end  # a second heredoc on the same line as the previous one
        h = _heredoc_at(s, p, last[3] if chained else None)
        if h:
            if not chained:
                line_end = s.find("\n", p)
            last = h
            spans.append((h[1], h[2]))
    out, i = [], 0
    for a, b in sorted(spans):
        out.append(s[i:a]); out.append(re.sub(r"[^\n]", "Q", s[a:b])); i = b
    return "".join(out) + s[i:]

# The bodies of `bash -c '<body>'` / `eval "<body>"` in a text (one level, like _violation_in_bodies).
def _shell_bodies(raw):
    mt = _mask_quotes(raw)
    out = []
    for overlap in (False, True, 2):
        _charge(mt)
        for m in _SHELL_RES[overlap].finditer(mt):
            q = _QUOTED_RE.match(raw, m.end(1))
            if q:
                out.append(q.group(1) if q.group(1) is not None else q.group(2))
    return out

def _violation_in_substitutions(raw_cmd):
    subs = _substitution_bodies(raw_cmd)
    texts = list(subs)
    for t in [raw_cmd] + subs:  # `bash -c 'echo "$(git stash)"'`: the shell body has substitutions too
        for sb in _shell_bodies(t):
            texts.extend(_substitution_bodies(sb))
    for body in texts:
        body = _blank_heredocs(body)
        mb = _mask_quotes(body)
        for overlap in (False, True, 2):
            hit = _violation(mb, overlap) or _violation_in_bodies(body, mb, overlap)
            if hit:
                return hit
    return None

try:
    hit = (_violation(masked, False) or _violation_in_bodies(cmd, masked, False)
           or _violation(masked, True) or _violation_in_bodies(cmd, masked, True)
           or _violation(masked, 2) or _violation_in_bodies(cmd, masked, 2)
           or _violation_in_substitutions(cmd))
except _TooCostly:
    print(f"[mh:gate] BLOCKED: subagent ({agent_type}) command is too long or too dense to check "
          f"safely ({len(cmd)} bytes); write it to a file with the Write tool and run the file, "
          f"or split it into smaller commands.", file=sys.stderr)
    journal(GATE_ID, "Bash", "deny", d.get("session_id"))
    sys.exit(2)
if hit:
    print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not run `git {hit}` "
          f"(command: {clip(cmd)!r}) -- no repo-wide git in a concurrent wave "
          f"(docs/METHODOLOGY.md Rule 13); scope every git command to files you own.", file=sys.stderr)
    journal(GATE_ID, "Bash", "deny", d.get("session_id"))
    sys.exit(2)
sys.exit(0)
