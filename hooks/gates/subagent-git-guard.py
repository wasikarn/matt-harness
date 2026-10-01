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
                    j += 1
                if (j - i) % 2 == 1 and j < n and s[j] == "\n":  # GH #286: odd run + newline = line continuation
                    out.append("\\" * (j - i - 1))
                    if j - i == 1 and at_word_start:
                        out.append("  ")  # blanks: a following git / # stays visible at a word start
                    else:
                        out.append("QQ"); at_word_start = False  # glues to the previous word
                    i = j + 1
                    continue
                out.append("\\" * (j - i))
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
_WRAPPER_WORDS = ("env", "command", "nohup", "nice", "time", "sudo", "doas", "xargs",
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
# GH #273: eval joins its arguments into a command line, so `eval A=1 env git stash` runs git; the
# other three treat `A=1` as a command name. Only eval takes assignments.
_ASSIGN_RUN = r"(?:[A-Za-z_][A-Za-z0-9_]*=\S*[ \t]+)*"
_EVAL_PASS = r"eval[ \t]+(?:--[ \t]+)?" + _ASSIGN_RUN
_SHELL_PASS = r"(?:" + _EVAL_PASS + r"|(?:builtin|command|exec)[ \t]+(?:--[ \t]+)?)"
_RTK_PREFIX = r"(?:rtk[ \t]+(?:-\S+[ \t]+)*(?:(?:proxy|run|err|test|summary)[ \t]+(?:-\S+[ \t]+)*)?)"
_CHAIN_PREFIX = r"(?:" + _SHELL_PASS + r"|" + _RTK_PREFIX + r")*"
# GH #248: `{ git stash; }` -- a brace group opens a command position (`{` then blank).
# GH #273: a chain word may come BEFORE a wrapper (eval sudo git stash, rtk proxy time git stash).
# One optional leading run of the chain words that are NOT wrapper words (eval, builtin, rtk), taken
# only when a wrapper word follows it, covers it. command and exec are wrapper words, so the walk
# already takes them and what follows. Letting the leading run take them too made every split of a
# run a second parse (command x 700 before eval "git stash" took 8 s), and a chain/wrapper loop was
# exponential (sudo eval x 250 never finished). The lookahead makes the end of the run unique.
# The lookahead names the wrapper words minus command/exec: with them, `rtk exec git stash; git status`
# lost the anchor develop gave it through _CHAIN_PREFIX (deep-audit whole-picture pass).
_LEAD_WRAPPER_ALT = r"(?:" + "|".join(w for w in _WRAPPER_WORDS if w not in ("command", "exec")) + r")(?=\s)"
_LEAD_CHAIN = (r"(?:(?:" + _EVAL_PASS + r"|builtin[ \t]+(?:--[ \t]+)?|" + _RTK_PREFIX + r")+(?=" + _LEAD_WRAPPER_ALT + r"))?")
# GH #285: a redirection (operator + its word) may sit before the command word and hid it
# (`</dev/null git stash`, `<<EOF git stash`); skipped like a VAR=val, in any mix with them.
_REDIR = r"(?:(?:\d+|\{\w+\})?(?:<<<?-?|&>>?|[<>]&|<>|>\||[<>]>?)[ \t]*[^\s;&|()<>]+[ \t]+)"
def _cmd_start(wrapper_prefix):
    return (r"(?:^|[|;&(]|&&|\|\||\{(?=\s))\s*" + _KEYWORD_PREFIX +
            r"(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)|" + _REDIR + r")*" + _LEAD_CHAIN + wrapper_prefix + _CHAIN_PREFIX)
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

_GIT_WORD = r"\\?(?:\S*/)?git\b"
_ANCHOR_RES = _plain_and_overlapping(_GIT_WORD)
_LAZY = 2  # index of the lazy pass in _plain_and_overlapping's tuple
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
    r"\\?(?:\S*/)?(?:(?:bash|sh|zsh|dash|ksh)\s+(?:-\S+\s+)*?-[^\Wc]*c\w*|eval|" + _RTK_BODY + r")(?=\s)"
)
# GH #275: `-[^\Wc]*c\w*` is the same language as `-\w*c\w*` but splits at the FIRST `c` only; the old
# form retried every split of a long `-ccc...` token (quadratic, 60 KB ran past 20 s, a timeout allows).
# Masking blanks the quote characters, so the raw body is found by skipping
# whitespace from the end of the shell word.
_QUOTED_RE = re.compile(r'\s*(?:"((?:[^"\\]|\\.)*)"|' + "'([^']*)')")
# Only stash/reset/clean (see header); read-only `stash list|show` carved out.
_DENY_SUBCMD_RE = re.compile(r"\s+(stash(?!\s+(list|show)\b)|reset|clean)\b")

# Git global flags walked past before the subcommand check, so `git -C /repo
# stash` / `git --no-pager clean` do not land the check on sub="-C".
_GIT_VALUE_GLOBALS = ("-C", "-c", "--git-dir", "--work-tree", "--config-env", "--namespace", "--attr-source")

# GH #276: the next git word in the same statement (matched at the offset of a non-flag token, so
# each hit moves forward).
_NEXT_GIT_RE = re.compile(r"[^;&|\n()]*?\s" + _GIT_WORD)
_FLAG_TOKEN_RE = re.compile(r"\s+(\S+)")
_FLAG_VALUE_RE = re.compile(r"\s+\S+")

def _skip_git_globals(s, i):
    # i is the offset right after the "git" anchor on the masked string. Returns the offset of the
    # first non-flag token's leading whitespace, so _DENY_SUBCMD_RE's \s+ still matches there.
    # GH #246: walk by offset, never re-slice the string per flag (quadratic on a long flag run).
    while True:
        m = _FLAG_TOKEN_RE.match(s, i)
        if not m:
            return i
        tok = m.group(1)
        if not tok.startswith("-"):
            return i
        if tok in _GIT_VALUE_GLOBALS:
            i = m.end()
            m2 = _FLAG_VALUE_RE.match(s, i)
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
# rare huge script (about 16-23 KB, ~5e7 over six scans) is refused.
# Deep-audit 5: a run of chain words (_CHAIN_PREFIX: eval/builtin/command/exec/rtk) after a wrapper
# is re-read from every walk position, so it costs about run x run per command start even with a
# single start (`true; ` + `command ` x 8000 before a `git stash` took 9 s). Each maximal run charges
# its length squared per start, plus one for the line start.
_WORK_BUDGET = 45_000_000  # was 60M; the slowest allowed shape (GH #273) took 5.1 s of the 8 s hook timeout
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
        pos = m.end(1)
        while True:
            pos = _skip_git_globals(masked_cmd, pos)
            dm = _DENY_SUBCMD_RE.match(masked_cmd, pos)
            if dm:
                return dm.group(1)
            # GH #276: the lazy pass lands on the first git word, which can be a wrapper's argument
            # (sudo -u git git stash); a later git word in the same statement may be the real one.
            # Offsets only, no re-slicing: each hit moves pos forward, so the walk is linear.
            nxt = _NEXT_GIT_RE.match(masked_cmd, pos) if overlap == _LAZY else None
            if not nxt:
                break
            pos = nxt.end()
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

# GH #274: the quote mask hides a double-quoted `$(...)` body and a backtick body, so git run
# there was never checked. One linear pass over the raw command pulls every `$(...)` / backtick
# body out (nested ones too, each as its own entry); each body is then checked as a command
# line, same as a `bash -c` body. Single-quoted text and a backslash-escaped `$(` / backtick are
# literal and skipped. An unterminated body runs to the end (over-deny is the safe side).
def _substitution_bodies(s):
    bodies, frames, n, i = [], [], len(s), 0
    # frame: [kind "$"|"`", body start, open quote char or "", paren depth]
    top = ["", 0, "", 0]
    while i < n:
        c, f = s[i], (frames[-1] if frames else top)
        if c == "\\" and f[2] != "'":  # a backslash is literal inside single quotes
            i += 2
            continue
        if c == "`" and f[0] == "`":
            bodies.append(s[f[1]:i]); frames.pop()
        elif f[2] == "'":
            if c == "'":
                f[2] = ""
        elif c == "`":
            frames.append(["`", i + 1, "", 0])
        elif c == "'" and not f[2]:
            f[2] = "'"
        elif c == '"':
            f[2] = "" if f[2] else '"'
        elif c == "$" and s[i + 1:i + 2] == "(":
            frames.append(["$", i + 2, "", 0]); i += 1
        elif f[0] == "$" and not f[2] and c in "()":
            if c == "(":
                f[3] += 1
            elif f[3]:
                f[3] -= 1
            else:
                bodies.append(s[f[1]:i]); frames.pop()
        i += 1
    bodies.extend(s[f[1]:] for f in frames)
    return bodies

def _violation_everywhere(overlap):
    hit = _violation(masked, overlap) or _violation_in_bodies(cmd, masked, overlap)
    if hit:
        return hit
    for body in _substitution_bodies(cmd):
        mb = _mask_quotes(body)
        hit = _violation(mb, overlap) or _violation_in_bodies(body, mb, overlap)
        if hit:
            return hit
    return None

try:
    hit = _violation_everywhere(False) or _violation_everywhere(True) or _violation_everywhere(_LAZY)
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
