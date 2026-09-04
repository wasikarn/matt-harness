#!/usr/bin/env python3
import json, re, shlex, sys

sys.path.insert(0, sys.argv[1])
from _hook_output import emit_ask

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)  # malformed payload — nothing to classify, allow (this is ask-tier, not deny)

if not isinstance(d, dict) or not isinstance(d.get("tool_input"), dict):
    sys.exit(0)

SQ = chr(39)
DQ = chr(34)
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
_ANSI_C_QUOTE_RE = re.compile(r"\$" + SQ + r"((?:[^" + SQ + r"\\]|\\.)*)" + SQ)
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")

def _strip_heredocs(cmd):
    # Ported from irrecoverable.sh (function of the same name — that file
    # ported it from verifier-protect.sh, itself from worktree-guard.py
    # 2026-08-04). Without this, a HEREDOC commit message that merely
    # MENTIONS "gh pr merge" in prose (this repo commits that way by
    # convention) would tokenize as a real command and false-positive the
    # ask — reproduced as a live bug in irrecoverable.sh 2026-08-06 for the
    # exact same shape.
    lines = cmd.split("\n")
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

def _normalize_ansi_c_quotes(cmd):
    # shlex does not understand ANSI-C quoting ($SQ...SQ, SQ = single quote)
    # -- it splits on the bare $ instead of treating the whole span as one
    # token, so a spliced argv0 like $SQ\x68SQ (decodes to "h") never
    # reassembles into the character it resolves to in real bash. This file
    # own dispatch checks compare tokens by EXACT STRING ("gh"/"pr"/"merge"),
    # so the span must be resolved, not just re-quoted. Ported verbatim
    # (decode logic and regex unchanged) from the same-named function in
    # verifier-protect.sh -- read that file for the full rationale (bounded
    # \xHH/\nnn/simple-escape decode set, the SQ-inside-decoded-text
    # re-splice, why a decoded newline must stay inside the quote wrapper).
    OCTAL = "01234567"
    HEXDIGITS = "0123456789abcdefABCDEF"
    SIMPLE = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", SQ: SQ, DQ: DQ}
    def _decode_ansi_c(m):
        body = m.group(1)
        decoded = []
        i, n = 0, len(body)
        while i < n:
            c = body[i]
            if c == "\\" and i + 1 < n:
                nxt = body[i + 1]
                if nxt in SIMPLE:
                    decoded.append(SIMPLE[nxt])
                    i += 2
                elif nxt == "x":
                    j, digits = i + 2, ""
                    while j < n and len(digits) < 2 and body[j] in HEXDIGITS:
                        digits += body[j]
                        j += 1
                    if digits:
                        decoded.append(chr(int(digits, 16)))
                        i = j
                    else:
                        decoded.append(body[i:i + 2])
                        i += 2
                elif nxt in OCTAL:
                    j, digits = i + 1, ""
                    while j < n and len(digits) < 3 and body[j] in OCTAL:
                        digits += body[j]
                        j += 1
                    decoded.append(chr(int(digits, 8) & 0xFF))
                    i = j
                else:
                    decoded.append(body[i:i + 2])
                    i += 2
            else:
                decoded.append(c)
                i += 1
        spliced = []
        for ch in decoded:
            if ch == SQ:
                spliced.append(SQ + "\\" + SQ + SQ)
            else:
                spliced.append(ch)
        return SQ + "".join(spliced) + SQ
    return _ANSI_C_QUOTE_RE.sub(_decode_ansi_c, cmd)

cmd = _normalize_ansi_c_quotes(_strip_heredocs(d["tool_input"].get("command", "")))

# Insert a literal ";" after each real newline (not in place of it, so a
# following "#" comment still stops there) -- a backslash immediately
# before the newline is a real line continuation, not a separator: bash
# removes BOTH characters entirely, joining the two lines with nothing
# between them, so nothing is emitted for that pair either (2026-09-03,
# GH #126 -- mirrors the same fix already shipped in irrecoverable.sh /
# main-exec-guard.sh / worktree-guard.py / verifier-protect.sh). The
# prior version put the literal "\<newline>" back unchanged, which left
# a stray embedded newline glued onto a token when there was no
# whitespace around the continuation (e.g. "g\<newline>h pr merge 123"
# tokenized argv0 as "g\nh", never "gh") -- confirmed live, ground-truthed
# against real bash, and a genuine bypass of the exact-match argv0/token
# dispatch below. Ported from the _newlines_to_seps helper in
# worktree-guard.py (2026-08-04).
#
# EXCEPT inside a "#" comment: a bash comment already ends at the literal
# newline no matter what precedes it, so a trailing backslash right
# before that newline has no continuation effect there -- the newline is
# still a real separator. The naive blind backslash-newline regex did not
# know it was inside a comment and joined the next physical line onto
# the same window as the comment, so only the FIRST command in
# "git status # comment \" + newline + "gh pr merge 123" ever reached
# the dispatch check below -- confirmed live 2026-09-03, GH #131, the
# same shape of bug already fixed the same way in main-exec-guard.sh.
# Comment state is tracked char by char alongside quotes (a "#"/backslash
# inside a quoted string is never comment/escape syntax) and backslash-
# escape parity (an escaped hash does not start a comment; an EVEN run of
# backslashes before a newline pairs off into literal characters, so the
# newline stays a real separator -- confirmed live 2026-09-03, GH #133),
# matching the posix escaping shlex does on its own and this function
# downstream (shlex.shlex(..., commenters="#") default). SQ and DQ are the
# single- and double-quote constants defined near the top of this file
# (DQ also used by _normalize_ansi_c_quotes above).
# Ported VERBATIM (state-machine body unchanged) from the same-named
# function in irrecoverable.sh.
def _newlines_to_seps(s):
    out = []
    in_squote = in_dquote = in_comment = False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_comment:
            if c == "\n":
                # comment ends at the literal newline, same as bash --
                # emit the same "; " separator a normal newline gets so
                # the window that follows still splits off correctly.
                out.append(c); out.append(";"); out.append(" ")
                in_comment = False
            else:
                out.append(c)
            i += 1
            continue
        if in_squote:
            out.append(c)
            if c == SQ:
                in_squote = False
            i += 1
            continue
        if in_dquote:
            if c == "\\" and i + 1 < n and s[i + 1] == "\n":
                # real continuation inside a double-quoted string: bash
                # strips backslash-newline here too (same full removal as
                # the unquoted case below), so nothing is appended.
                i += 2
                continue
            if c == "\\" and i + 1 < n and s[i + 1] in (DQ, "\\", "$", "`"):
                out.append(c); out.append(s[i + 1])
                i += 2
                continue
            out.append(c)
            if c == DQ:
                in_dquote = False
            i += 1
            continue
        # unquoted, not in a comment
        if c == SQ:
            in_squote = True
            out.append(c); i += 1
        elif c == DQ:
            in_dquote = True
            out.append(c); i += 1
        elif c == "\\" and i + 1 < n and s[i + 1] == "\n":
            # real line continuation: bash removes the backslash AND the
            # newline entirely, joining the two lines with nothing at
            # all between them -- so nothing is appended here. Passing
            # the pair through unchanged (the old behavior) left a stray
            # "\n" attached to whatever followed, and when there was no
            # whitespace after the continuation shlex glued that residual
            # newline onto the very next token (e.g. "\n--force" instead
            # of "--force"), which the exact-match force-push check
            # missed entirely -- confirmed live 2026-09-03, GH #126.
            i += 2
        elif c == "\\" and i + 1 < n:
            # any other backslash-escaped pair -- consumed together so
            # the escaped character is never re-examined as an
            # unescaped hash/quote marker.
            out.append(c); out.append(s[i + 1])
            i += 2
        elif c == "#":
            in_comment = True
            out.append(c); i += 1
        elif c == "\n":
            out.append(c); out.append(";"); out.append(" ")
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)

# Command-substitution placeholder pass, ported from irrecoverable.sh own GH
# #129 fix -- read that file for the full rationale, this is the same
# mechanism verbatim. A backtick/$(...)/${...} span vanishes in real bash
# once it expands ("g$(true)h" IS "gh"), but shlex treats the punctuation
# as literal characters, so a spliced dispatch token survives tokenization
# as its own garbled token and evades the exact-match checks below --
# unlike irrecoverable.sh, THIS gate also dispatches on the two tokens
# right after argv0 ("pr"/"merge"), so a splice landing on either of those
# is an equally live bypass, not just an argv0 splice. This blanks every
# such span to one placeholder byte (PH, added to shlex wordchars below so
# it fuses into the surrounding token instead of splitting it) and
# re-collects backtick/$(...) BODIES (never ${...} -- a variable
# reference, not a command) as their own ";"-joined statement afterward, so
# a real embedded command inside the substitution keeps getting scanned
# instead of just erased.
#
# Real shell-quote-state tracking (not a naive apostrophe-pairing regex):
# a substitution only counts as live when found unquoted or inside a
# DOUBLE-quoted span -- never inside a genuine SINGLE-quoted one, where $
# and backtick are inert text. Modeled on the _newlines_to_seps scanner
# above (same in_squote/in_dquote/backslash-escape state machine),
# precisely because irrecoverable.sh own history shows a flat regex here
# has a real, confirmed bypass: an English contraction (a single-quote
# byte used as a shorthand mark, e.g. spelling "it is" in shortened form)
# sitting inside a real double-quoted string can shift what a regex thinks
# is a quote boundary, either masking a live splice or falsely flagging
# inert single-quoted text as live.
#
# No apostrophes anywhere in this python3 -c block: it lives inside the
# bash single-quoted wrapper below, and a literal apostrophe closes that
# string early.
#
# Fixed-point iteration (capped at 5 passes), kept as defense-in-depth: the
# $(...)/${...} closer-search below depth-counts same-type brackets (GH
# #139), so a same-type nested span ("$(echo $(date))") already resolves
# within a single pass -- the loop no longer carries that specific case, it
# just costs nothing extra when a pass finds no change and breaks
# immediately. A dispatch-FLAG splice is still out of scope here, same as
# in irrecoverable.sh -- this pass only re-derives which candidate name a
# garbled DISPATCH token might be, it does not re-scan already-clean flag/
# argument tokens, and it stays a mechanical scan, not a parser. Bare
# $VAR/$@/$* are never touched.
PH = "\x01"
# GH #139: work budget for the depth-counting closer-search below, charged
# per character the search itself walks -- ported from irrecoverable.sh own
# identical fix. Without it, an adversarial run of unclosed "$(" starts
# costs O(remaining length) EACH, for O(length) starts -- O(n^2) total.
# Once spent, the while loop below exits with depth still non-zero, the
# same fallback-to-literal path an already-unbalanced span already takes.
#
# GH #139 follow-up: that fallback-to-literal path is NOT safe on its own
# when budget exhaustion (not a genuinely unbalanced span) is why it was
# taken -- an un-blanked span is exactly the bypass shape this issue closed,
# so an adversary could pad a real dangerous command with just enough
# leading "$(" flood to burn the budget and hide the payload again. This
# module-level flag (mutated in place, never rebound, so no "global"
# needed) records that a search stopped BECAUSE the budget ran out --
# checked once after tokenization below, before any dispatch, so
# exhaustion asks instead of silently falling through to literal.
_DEPTH_BUDGET_BLOWN = [False]
_DEPTH_SCAN_BUDGET = 2_000_000
def _blank_substitutions(s):
    bodies = []

    def _scan_once(s):
        out = []
        in_squote = in_dquote = in_comment = False
        i, n = 0, len(s)
        # GH #139 work budget (see _DEPTH_SCAN_BUDGET above), shared across
        # every $(...)/${...} closer-search this one _scan_once call makes.
        depth_work_used = [0]
        while i < n:
            c = s[i]
            if in_comment:
                # A "#" starts a real bash comment here (Finding 5,
                # 2026-09-04, same in_comment tracking _newlines_to_seps
                # above already uses) -- everything until the next literal
                # newline is inert commentary, not a live substitution, even
                # when it is shaped like one ("$(gh pr merge 123)" inside a
                # "# ..." note must never be collected into bodies).
                if c == "\n":
                    in_comment = False
                out.append(c)
                i += 1
                continue
            if in_squote:
                out.append(c)
                if c == SQ:
                    in_squote = False
                i += 1
                continue
            if in_dquote:
                if c == "\\" and i + 1 < n and s[i + 1] in (DQ, "\\", "$", "`"):
                    out.append(c); out.append(s[i + 1])
                    i += 2
                    continue
                if c == DQ:
                    out.append(c)
                    in_dquote = False
                    i += 1
                    continue
                # else: ordinary char while in_dquote (a bare apostrophe
                # included, deliberately not toggling in_squote) -- fall
                # through, $(...)/`...`/${...} are live inside double quotes.
            else:
                if c == SQ:
                    in_squote = True
                    out.append(c); i += 1
                    continue
                if c == DQ:
                    in_dquote = True
                    out.append(c); i += 1
                    continue
                if c == "\\" and i + 1 < n:
                    out.append(c); out.append(s[i + 1])
                    i += 2
                    continue
                if c == "#":
                    in_comment = True
                    out.append(c); i += 1
                    continue
            if c == "`":
                j = s.find("`", i + 1)
                if j != -1:
                    bodies.append(s[i + 1:j])
                    out.append(PH)
                    i = j + 1
                    continue
            elif c == "$" and s[i + 1:i + 2] == "(":
                depth, j = 1, i + 2
                while j < n and depth and depth_work_used[0] <= _DEPTH_SCAN_BUDGET:
                    depth_work_used[0] += 1
                    if s[j] == "(":
                        depth += 1
                    elif s[j] == ")":
                        depth -= 1
                    j += 1
                if depth and depth_work_used[0] > _DEPTH_SCAN_BUDGET:
                    _DEPTH_BUDGET_BLOWN[0] = True
                if not depth:
                    bodies.append(s[i + 2:j - 1])
                    out.append(PH)
                    i = j
                    continue
            elif c == "$" and s[i + 1:i + 2] == "{":
                depth, j = 1, i + 2
                while j < n and depth and depth_work_used[0] <= _DEPTH_SCAN_BUDGET:
                    depth_work_used[0] += 1
                    if s[j] == "{":
                        depth += 1
                    elif s[j] == "}":
                        depth -= 1
                    j += 1
                if depth and depth_work_used[0] > _DEPTH_SCAN_BUDGET:
                    _DEPTH_BUDGET_BLOWN[0] = True
                if not depth:
                    out.append(PH)
                    i = j
                    continue
            out.append(c)
            i += 1
        return "".join(out)

    for _ in range(5):
        new = _scan_once(s)
        if new == s:
            break
        s = new
    if bodies:
        # A real "\n" (not just " ; ") leads each appended body: shlex own
        # default comment-stripping (commenters="#") reads to the next
        # LITERAL newline, not to a " ; " separator -- a bare "#" anywhere
        # earlier in s (including one embedded inside an already-recovered
        # body) would otherwise make shlex silently discard everything from
        # that "#" onward, appended bodies included, with no decision
        # emitted at all (Finding 1, 2026-09-04).
        s = s + "\n; " + "\n; ".join(bodies)
    return s

# shlex.split() only recognizes ;/&&/||/|/& as separators when whitespace
# already surrounds them -- "git push;gh pr merge 123" tokenized as one
# glued word "push;gh", so the second command in the chain never had its
# own argv0 checked (deep-audit 2026-08-28). punctuation_chars=True makes
# shlex split these out as their own tokens even with no surrounding
# space, while still respecting quotes -- a genuinely-quoted ";" inside
# an argument stays inside that one token. Grouping tokens ( ) { } get
# the same treatment: without it, "(gh pr merge 123)" or "{ gh pr merge
# 123; }" left a bare "(" / "{" as argv0 instead of "gh" -- a subshell/
# brace-group bypass of the identical shape. Ported from
# verifier-protect.sh / worktree-guard.py, which already use this
# pattern for their own write-target detection.
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}

_CMD_LEN_CAP = 150_000
# GH #140: the shlex.shlex(..., punctuation_chars=True) call below (and its
# shlex.split() ValueError fallback) has no length cap of its own, and its
# cost is superlinear in the length of a single long token -- not merely
# proportional to total input length. Measured fresh against this exact
# file, single token appended ahead of a real "gh pr merge", python3
# cold-start included: 100,000 chars ~0.22s, 150,000 ~0.38s, 200,000
# ~0.54s, 300,000 ~0.91s -- a 700,000-char payload blows straight past a
# 2s timeout. Checked separately: many short tokens summing to the same
# total length stay fast (roughly linear) -- the blowup tracks the longest
# single token, not raw input length. A total-length cap still bounds the
# worst case either way, since no single token can exceed the total. Same
# cap value as irrecoverable.sh/verifier-protect.sh/worktree-guard.py, so
# all four gates bound this identical shlex cost the same way. This also
# retires the residual unbounded cost that sibling commit 7b37691e own
# _UNWRAP_WORK_BUDGET fix left explicitly open for this exact tokenize
# call. This file own primary mechanism is emit_ask (see module docstring)
# -- fail toward ASKING, not a silent allow, matching the existing
# fallback ValueError handling a few lines below.
if len(cmd) > _CMD_LEN_CAP:
    emit_ask(
        "merge-door: command too long to safely tokenize (%d chars, cap %d) "
        "-- approve it manually, or use mh:ship-merge for the reviewed path."
        % (len(cmd), _CMD_LEN_CAP)
    )
    sys.exit(0)

try:
    # _blank_substitutions must run BEFORE shlex ever sees the command:
    # without it, an unresolved "(...)" span gets read by punctuation_chars
    # as real grouping operators, splitting a window apart mid-splice --
    # the placeholder byte PH added to wordchars below is what lets a
    # blanked span fuse into its surrounding token instead.
    lex = shlex.shlex(_blank_substitutions(_newlines_to_seps(cmd)), posix=True, punctuation_chars=True)
    lex.wordchars += PH
    tokens = list(lex)
    windows, cur = [], []
    for tok in tokens:
        if tok in OPERATORS:
            if cur:
                windows.append(cur)
            cur = []
        else:
            cur.append(tok)
    if cur:
        windows.append(cur)
except ValueError:
    # Finding 4 (2026-09-04): the ${...}/$(...)/backtick closer-search in
    # _blank_substitutions above scans forward for a terminating char
    # without tracking quote state for characters it skips over -- a span
    # crossing a real quote (an everyday idiom like ${x:-"a}b"}) desyncs
    # the toggle, and the blanked string above can come out quote-unbalanced
    # even when the ORIGINAL command was perfectly valid. Since the old
    # cmd.split() fallback was already removed (a real bypass for a
    # genuinely malformed command, GH #129), this ValueError can no longer
    # tell "blanking broke a valid command" apart from "the command really
    # is malformed" -- so check which one this is: shlex.split(cmd) on the
    # ORIGINAL, pre-blanking string (ansi-c-normalized and heredoc-stripped
    # already, nothing else) as a pure validity predicate. If it parses,
    # the corruption was self-inflicted by blanking; fall back to
    # tokenizing that original string instead of asking blind. A naive
    # whitespace split has no separator awareness, so a dangerous SECOND
    # command in a ";"/"&&"/"||"/"&" chain would never get its own
    # dispatch-token checked -- the exact bypass this file own
    # punctuation_chars=True windowing exists to close -- so split on the
    # same separator set instead (braces excluded on purpose: they show up
    # far more often inside ${...} than as a real brace group) and tokenize
    # each piece with shlex.split() individually, feeding the result
    # through the same per-window dispatch below. If the original string
    # also fails to parse, it really is malformed -- keep this file
    # existing ask response.
    try:
        shlex.split(cmd)
        windows = []
        for piece in re.split(r"(&&|\|\||;|\||&)", cmd):
            if piece in ("&&", "||", ";", "|", "&") or not piece.strip():
                continue
            windows.append(shlex.split(piece))
    except ValueError:
        emit_ask(
            "merge-door: could not safely tokenize this command (unbalanced "
            "quote or substitution) -- approve it manually, or use mh:ship-merge "
            "for the reviewed path."
        )
        sys.exit(0)

# GH #139 follow-up: see _DEPTH_BUDGET_BLOWN above -- a scan that could not
# finish leaves a span un-blanked, the same bypass shape this issue closed.
# Checked once here, after either branch above has had its chance to run,
# before any token reaches dispatch.
if _DEPTH_BUDGET_BLOWN[0]:
    emit_ask(
        "merge-door: command too long to safely tokenize (nested substitution "
        "exceeded depth-scan budget) -- approve it manually, or use "
        "mh:ship-merge for the reviewed path."
    )
    sys.exit(0)

def basename(p):
    return p.rsplit("/", 1)[-1]

PREFIX_WRAPPERS = {"env", "command", "nohup", "nice", "time", "sudo"}

def _has_raw_subst(t):
    # Follow-up fix (2026-09-04, cross-file review) to the Finding-4 fallback
    # below: a token reaching the trio-dispatch check through that fallback
    # is built from the ORIGINAL, never-blanked command text -- it can never
    # carry a PH byte, so the PH-only duplication gate the trio check uses
    # never fires on that path, and a spliced argv0 like g$(true)h sails
    # through unrecognized (confirmed live: an unbalanced-quote span forcing
    # the fallback, followed by a "; g$(true)h pr merge 123" second command,
    # exited 0 with no ask). Narrow on purpose: only a literal backtick,
    # "$(", or "${" substring in THIS ONE token -- never a bare "$", which
    # would misfire on every ordinary "$PYTHON -m pytest"-shaped command and
    # cause a false ask where none should happen.
    return "`" in t or "$(" in t or "${" in t

_RAW_SUBST_SPAN_RE = re.compile(r"`[^`]*`|\$\([^()]*\)|\$\{[^{}]*\}")

def _reveal(t):
    # PH-site sweep follow-up (2026-09-04): a first pass at this fix tried
    # bolting `elif _has_raw_subst(rest[i]): i += 1` onto each branch below,
    # treating any raw-subst-bearing token as one opaque flag to skip -- but
    # that breaks a VALUE-TAKING flag whose own token carries a leading
    # raw-subst prefix (e.g. sudo/env "-u"): "sudo $(true)-u alice gh pr
    # merge 123" resolves in real bash to "sudo -u alice gh pr merge 123",
    # where "-u" must ALSO consume "alice" as its value -- but the bolt-on
    # only skipped the "$(true)-u" token itself, leaving "alice" to be
    # misread as the wrapped command own argv0, missing the real trio one
    # position later (confirmed live, silent allow).
    #
    # A second pass at this fix stripped only a LEADING placeholder run
    # (.lstrip(PH)) and a LEADING raw-subst span, mirroring the old
    # PH-only code -- but a TRAILING placeholder inside a SHORT flag (e.g.
    # "-u" + a substitution that resolves to empty, glued as one token) is
    # exactly as live: "sudo -u$(true) alice gh pr merge 123" blanks on the
    # PRIMARY path to "-uPH", and the bundled-flag length check right below
    # (`m.end() < len(t[1:])`) misreads that leftover placeholder byte as a
    # REAL bundled character -- deciding the value is already attached to
    # this token when it is not, so the loop skips only 1 token instead of
    # 2 and misses "alice", shifting the trio-check off target (confirmed
    # live 2026-09-04, a 4th cross-file reviewer, all 4 shapes -- sudo -u/
    # -g, nice -n, env -u -- silently allowed). A raw-subst version of the
    # exact same trailing shape is equally live once forced through the
    # Finding-4 fallback ("sudo -u$(true) alice ..." reached via a
    # quote-crossing prefix, confirmed live).
    #
    # Fixed by removing every PH byte and every raw substitution span
    # WHEREVER it occurs in the token, not just a leading run -- this
    # changes what the length comparisons downstream actually measure
    # (verified against the live payload above, not assumed from the flag
    # name matching alone: "-uPH" -> "-u" makes t[1:] == "u" instead of
    # "uPH", so the bundled-flag length check correctly reports nothing
    # left over and takes the value-taking branch). A token built entirely
    # from PH/substitution syntax (a standalone vanish, e.g. a lone
    # "$(true)" token) reveals to "", which correctly falls through to the
    # existing "else: break" in every branch below and relies on the
    # separate _drop_bare_vanish_tokens compacted retry, same as before --
    # this function only ever removes vanish markers, it does not decide
    # whether the surrounding wrapper logic keeps unwrapping.
    return _RAW_SUBST_SPAN_RE.sub("", t.replace(PH, ""))

# Same leading-PH-erases-flag-shape bypass as the dispatch-trio duplication
# above (ported from irrecoverable.sh own GH #129 fix), found live in this
# unwrap loop 2026-09-03: a command substitution that resolves to empty at
# runtime splices directly onto whatever follows it in real bash --
# "env $(true)FOO=bar gh pr merge 123" IS "env FOO=bar gh pr merge 123" once
# bash evaluates it -- but _blank_substitutions leaves a non-empty PH byte
# glued to the front, so the token becomes "PH FOO=bar" (as one word), which
# no longer starts with "-" and no longer isidentifier()-passes on its
# "=" split. Every branch below then falls through to "break", so the loop
# stops early and misreads the PH-prefixed wrapper flag/assignment itself as
# the argv0 of the wrapped command -- shifting the trio-dispatch window by
# one token so the real gh/pr/merge trio sitting one position later never
# lines up with the checked positions, and the ask silently does not fire
# (confirmed live 2026-09-03: env/sudo/nice/generic-wrapper splices this
# shape all silently allowed). _reveal() (defined above) resolves this for
# the ordinary flag/assignment shapes: it assumes the substitution vanishes
# and removes the marker wherever it sits in the token, then every classify
# function below tests the SAME revealed shape a plain, unspliced token
# would have had.
LONG_VALUE_FLAGS = {"--user", "--group"}

def _env_classify(rest, i):
    # Returns the SET of index positions the env unwrap scan could
    # continue from after consuming rest[i], or None if rest[i] is not
    # flag/assignment-shaped at all (i.e. it is the wrapped command).
    # Exact "-u" is the only value-taking flag env models -- see the
    # ambiguity note on _sudo_classify below for why a token that
    # underwent a real substitution removal (raw != t) branches into BOTH
    # candidates instead of picking one.
    raw = rest[i]
    t = _reveal(raw)
    if t == "-u" and i + 1 < len(rest):
        return {i + 1, i + 2} if raw != t else {i + 2}
    if t.startswith("-"):
        return {i + 1}
    if "=" in t and t.split("=", 1)[0].isidentifier():
        return {i + 1}
    return None

def _nice_classify(rest, i):
    t = _reveal(rest[i])
    if not t.startswith("-"):
        return None
    if t == "-n" and i + 1 < len(rest):
        raw = rest[i]
        return {i + 1, i + 2} if raw != t else {i + 2}
    return {i + 1}

def _sudo_classify(rest, i):
    # sudo -u/-g (short or long) select the effective identity and take a
    # value. Handles space-joined, "="-joined long form, and attached
    # short form ("-ualice") in one pass, PLUS bundled short flags where
    # u/g sits anywhere in a combined token -- standard getopt
    # short-option semantics: once a value-taking character is hit,
    # everything after it in that same token is the value for that flag,
    # and only an empty remainder falls through to the next token. So
    # "-nu alice" (n takes no value, u is last in the token) reads
    # "alice" as the value for -u, taken from the next token -- but
    # "-un alice" (u first, "n" left over in the same token) reads the
    # attached "n" as the value for -u, so "alice" is the real wrapped
    # command, not a value (deep-audit 2026-08-28, issue #115).
    #
    # 5th-round fix (2026-09-04): whether the value sits in THIS token
    # (attached) or the NEXT one (separate) is genuinely ambiguous when
    # this token carries a substitution -- "-u$(true)" and "-u$(id -un)"
    # both reveal to the identical "-u", but the first resolves to empty
    # (value is the NEXT token) and the second resolves to something
    # real fused onto the flag (value is attached, the wrapped command is
    # the NEXT token instead). No comparison on the revealed text can
    # tell these apart -- the information genuinely is not in the token
    # (confirmed live both ways: a length-heuristic fix for one direction
    # silently broke the other, 2026-09-04). Rather than pick a side, a
    # token that actually had something removed (raw != t) returns BOTH
    # candidate continuations, same as the dispatch-trio duplication
    # mechanism above tries every candidate a spliced token might
    # resolve to -- the caller asks if EITHER path reaches a real gh pr
    # merge dispatch. This can over-ask on an ambiguous flag combined
    # with a real dispatch further down a candidate path that would not
    # actually occur in real bash -- deliberate and correct for an
    # ask-gate (same fail-closed-on-ambiguity stance the other 3 sibling
    # files already take), not a bug to narrow away.
    #
    # Other sudo flags that also take a value (-p, -C, -R, -T, -U) are
    # not modeled here -- a bundle mixing one of those with u/g (e.g.
    # "-pu") is an accepted non-goal, same tier as the
    # habit-guard-not-adversarial-sandbox stance this file already takes
    # in its header comment above.
    raw = rest[i]
    t = _reveal(raw)
    bare = t.split("=", 1)[0]
    if bare in LONG_VALUE_FLAGS:
        return {i + 1} if "=" in t else {min(i + 2, len(rest))}
    if t.startswith("--"):
        return {i + 1}
    if t.startswith("-") and len(t) > 1:
        m = re.search(r"[ug]", t[1:])
        if m:
            if raw != t:
                return {i + 1, min(i + 2, len(rest))}
            attached = m.end() < len(t[1:])
            return {i + 1} if attached else {min(i + 2, len(rest))}
        return {i + 1}
    return None

def _generic_classify(rest, i):  # command, nohup, time -- bare flags only
    return {i + 1} if _reveal(rest[i]).startswith("-") else None

_WRAPPER_CLASSIFY = {"env": _env_classify, "nice": _nice_classify, "sudo": _sudo_classify}

def _wrapper_stop_positions(rest, classify):
    # Explores every index position reachable by repeatedly applying
    # classify() from position 0, branching whenever classify() returns
    # more than one candidate (the ambiguous-substitution case above).
    # Returns the SET of positions where classify() says "not a flag" --
    # each is a candidate start of the wrapped command.
    seen = set()
    frontier = {0}
    stops = set()
    while frontier:
        i = frontier.pop()
        if i in seen:
            continue
        seen.add(i)
        if i >= len(rest):
            continue  # ran off the end on this branch -- no wrapped
                       # command reachable this way, drop it (matches the
                       # original single-path "if i >= len(rest): break")
        nxt = classify(rest, i)
        if nxt is None:
            stops.add(i)
        else:
            frontier |= (nxt - seen)
    return stops

_UNWRAP_WORK_BUDGET = 5_000_000
# Process-wide, not reset per call: shared across every window AND across
# the compacted-retry call the driving loop below can make for the SAME
# window (see _drop_bare_vanish_tokens) -- a per-call budget would let an
# attacker multiply total allowed work by the number of ";"-separated
# windows packed into one command. A fresh python3 -c process is spawned
# per gate invocation (see the top of this file), so this naturally resets
# to 0 for every new Bash tool call -- no explicit reset needed.
_UNWRAP_WORK_USED = [0]

def _unwrap_all(argv0, rest):
    # Returns every (argv0, rest) state reachable by fully resolving
    # PREFIX_WRAPPERS unwrapping, branching at each ambiguous flag found
    # along the way (see _sudo_classify above) -- normally a list of one,
    # more only when an ambiguous substitution was actually present.
    #
    # 6th-round fix (2026-09-04, live DoS confirmed): a CHAIN of several
    # ambiguous wrapper flags in a row branches at each one, and without
    # memoization the SAME (argv0, rest) state gets rediscovered and fully
    # re-expanded from multiple different branches, compounding into
    # exponential work -- "env -u$(true) " repeated 24 times before a
    # real "gh pr merge 123" hung past a 15s timeout; 26 repeats hung
    # past 60s. Every state here is (argv0, a SUFFIX of the top-level
    # rest), and a list of length n has only n+1 distinct suffixes, so
    # the DISTINCT STATE COUNT is linear in token count -- seen_states
    # turns this into an ordinary bounded graph traversal, each distinct
    # state expanded exactly once instead of exponentially many times.
    # This remains true and is unaffected by the 8th-round fix below --
    # it is about the number of DISTINCT states, not the total work spent
    # discovering them.
    #
    # 7th-round correction (2026-09-04) -- SUPERSEDED, see 8th round below:
    # this round claimed linear state count made the remaining cost "a
    # several-thousand-token wrapper chain reaching multi-second delays,
    # not a proven need worth chasing further." That severity call was
    # wrong. This is a SYNCHRONOUS PreToolUse gate blocking every Bash tool
    # call, and a fresh adversarial measurement found: 1600 repeats of the
    # same chain takes 9.7s, 2000 takes 19.3s, 3000 takes 76.6s, and 4000
    # takes 192.2s (3.2 minutes) -- with no cap anywhere in this file. A
    # ~64KB payload hanging the gate for over 3 minutes was not "not worth
    # chasing further."
    #
    # 8th-round fix (2026-09-04): total work is polynomial for two separate
    # reasons, not one -- (a) total states.pop() iterations are O(n^2) (a
    # triangular number: many different ambiguous predecessor branches
    # "fan in" onto the same later suffix before seen_states discards the
    # duplicate), and (b) the _wrapper_stop_positions call each DISTINCT
    # state makes, plus the states.append(..., r[i+1:]) slice made for every
    # stop position it returns, costs O(len(r)) apiece -- summing to O(n^3)
    # overall (confirmed via cProfile). Capping just the NUMBER of
    # states.pop() iterations is NOT sufficient on its own: a single popped
    # state with a large "r" can already cost O(len(r)^2) inside the
    # stops-loop of just ONE iteration, before a pop-count check between iterations
    # ever gets a chance to fire (measured directly: even a 1-pop budget
    # still took ~15s at 50000 repeats, because the stops-loop inside that
    # ONE iteration was the slow part, not the number of iterations run).
    # Fixed by budgeting WORK VOLUME instead of pop count -- charging
    # len(r)+1 before processing a popped state (this pays for both the
    # tuple(r) memo-key conversion and the _wrapper_stop_positions call)
    # and len(r)-i before each candidate append/slice inside the stops
    # loop, checked BEFORE the corresponding expensive operation runs, so
    # exceeding the budget stops the algorithm from ever PERFORMING the
    # operation that would have paid for it, not just from looping again.
    # len() is O(1) on a list, so every check is cheap no matter how large
    # an adversarial "r" already is.
    #
    # _UNWRAP_WORK_BUDGET = 5,000,000 was picked empirically. It trips at
    # around 195-200 repeats of the "env -u$(true) " chain -- about 6-7x
    # the 30-repeat chain the existing DoS regression test below already
    # exercises (over 200x in raw work units: that test consumes ~21,944),
    # and nowhere near a real command, which never chains anywhere close to
    # 195 env/sudo/nice wrappers around one gh pr merge. Worst-case
    # wall-clock time to REACH the budget was measured directly at repeat
    # counts from 200 up through 4000 (the previously-hanging range) and
    # stayed at ~35-40ms throughout -- confirming the cap bounds time by
    # budget, not by input size. Pushed further out to 200,000 repeats
    # (a multi-megabyte payload), total time was ~1.15s, but that residual
    # is pre-existing linear text-processing cost this file already pays
    # elsewhere over a huge raw string (shlex/regex passes unrelated to and
    # untouched by this fix) -- the contribution from _unwrap_all itself
    # stays flat at the ~35-40ms figure regardless.
    #
    # Exhaustion returns budget_exceeded=True alongside whatever finals
    # were already found -- the caller (_window_is_merge_dispatch) MUST ask
    # immediately on that signal, before even looking at finals, since a
    # truncated traversal can under-report real candidates and must never
    # be read as "no candidates matched, allow" (same fail-to-ask-on-doubt
    # direction this whole file already takes everywhere else). This does
    # not change WHICH candidates are found on any input that stays under
    # budget -- skipping an already-seen state still only skips re-deriving
    # finals already added the first time, same as before this round.
    states = [(argv0, rest)]
    seen_states = set()
    finals = []
    while states:
        a, r = states.pop()
        _UNWRAP_WORK_USED[0] += len(r) + 1
        if _UNWRAP_WORK_USED[0] > _UNWRAP_WORK_BUDGET:
            return finals, True
        key = (a, tuple(r))
        if key in seen_states:
            continue
        seen_states.add(key)
        if not (r and a in PREFIX_WRAPPERS):
            finals.append((a, r))
            continue
        classify = _WRAPPER_CLASSIFY.get(a, _generic_classify)
        for i in _wrapper_stop_positions(r, classify):
            _UNWRAP_WORK_USED[0] += len(r) - i
            if _UNWRAP_WORK_USED[0] > _UNWRAP_WORK_BUDGET:
                return finals, True
            states.append((basename(r[i]), r[i + 1:]))
    return finals, False

def _window_is_merge_dispatch(w):
    # Runs the unwrap-then-trio-check pipeline against one window and
    # reports match/no-match instead of asking directly -- factored out so
    # the driving loop below can run this SAME logic a second time against a
    # compacted window (see _drop_bare_vanish_tokens), not just once against
    # the raw one.
    if not w:
        return False
    _unwrap_finals, _unwrap_budget_exceeded = _unwrap_all(basename(w[0]), w[1:])
    if _unwrap_budget_exceeded:
        # 8th-round fix: never fall through to the trio check below on a
        # truncated traversal -- ask now regardless of what finals already
        # contains, so a budget-cut-short scan can never be silently read
        # as "no gh pr merge found here, allow".
        return True
    # GH #129-shaped duplication (ported from irrecoverable.sh, adapted to
    # 3 dispatch positions): this gate dispatches on argv0 AND the two
    # tokens right after it ("pr"/"merge"), so a splice landing on any of
    # the 3 is an equally live bypass -- each position tries its own fixed
    # candidate whenever it carries a PH byte (a real, non-spliced token is
    # tried as-is), and any resulting combination that completes the
    # ("gh", "pr", "merge") trio counts as a match. Checked against EVERY
    # unwrap candidate from _unwrap_all -- ask if any one of them matches.
    for argv0, rest in _unwrap_finals:
        if len(rest) >= 2:
            GH, PR, MERGE = "gh", "pr", "merge"
            argv0_c = (GH,) if (PH in argv0 or _has_raw_subst(argv0)) else (argv0,)
            rest0_c = (PR,) if (PH in rest[0] or _has_raw_subst(rest[0])) else (rest[0],)
            rest1_c = (MERGE,) if (PH in rest[1] or _has_raw_subst(rest[1])) else (rest[1],)
            if any((a, b, c) == (GH, PR, MERGE) for a in argv0_c for b in rest0_c for c in rest1_c):
                return True
    return False

# Layer 3 fix (found by an independent adversarial reviewer, 2026-09-03,
# distinct from the GH #129 placeholder mechanism above): a STANDALONE,
# unquoted word that resolves to empty at runtime -- its own space-separated
# token, nothing else attached -- vanishes entirely in real bash via
# word-splitting, shifting every later token left by one position ("gh
# $(true) pr merge 123" runs as "gh pr merge 123"). _blank_substitutions
# above cannot know a substitution resolves to empty without running it, so
# it leaves a PH-only token sitting in that position instead of removing it,
# and every FIXED-INDEX read in _window_is_merge_dispatch (argv0/rest[0]/
# rest[1] against a fixed candidate tuple, or a PREFIX_WRAPPERS unwrap-loop
# flag/assignment shape test) then reads the wrong token entirely, missing
# the real dispatch one position later (confirmed live 2026-09-03: bare
# vanishes before, mid, and inside a wrapper-unwrap chain all silently
# allowed). This is a distinct, narrower shape than the GH #129 fix: that
# one duplicates a candidate at a position whose token is still THERE but
# garbled; this one is about a position whose token is GONE in real bash.
#
# Fixed by building a second, compacted token list per window with every
# bare-vanish token dropped -- a token counts as bare-vanish only when
# EVERY character in it is the placeholder byte (stripping PH from it
# leaves nothing), never a token that merely CONTAINS PH glued to real
# content (e.g. a PH-prefixed flag/assignment from the GH #129 fix above --
# those already resolve correctly via _reveal() and must not be touched
# here). The full unwrap-then-trio-check pipeline runs against BOTH the
# original window and the compacted one; a match on either asks.
#
# This must not become a blanket "any bare-vanish token anywhere -> ask"
# rule: "$(which gh) pr view 123" also produces a bare-vanish argv0 token,
# but it resolves to a real, non-empty command at runtime, not an empty
# one, and must stay noask. Compacting drops the argv0 token, leaving
# [pr, view, 123] -- position 0 is "pr", not "gh", so the trio check
# correctly fails to match and this stays noask; only a genuine vanish
# whose compacted form lines up on the real ("gh", "pr", "merge") trio
# triggers ask.
#
# Fallback-path follow-up (2026-09-04, PH-site sweep): the check above
# only recognizes a vanish shaped as an all-PH token, which a token
# reaching this function through the Finding-4 ValueError fallback can
# never be -- it was never blanked, so a standalone substitution that
# resolves to empty at runtime (e.g. a bare "$(true)" token) still carries
# its raw "$("/"`"/"${" syntax and strip(PH) is a no-op on it, leaving it
# in the compacted list untouched (confirmed live: an unbalanced-quote
# span forcing the fallback, followed by "; $(true) gh pr merge 123",
# exited 0 with no ask). A token counts as a raw vanish only when
# stripping every backtick/$(...)/${...} span out of it leaves nothing
# behind -- the same "resolves to empty" test the PH case encodes, just
# applied to text that still has its substitution syntax literally in it.
# Same non-goal already accepted above applies here too: a token like
# "$(which gh)" also strips to empty by this test even though it resolves
# to something real at runtime, but the OR-with-the-uncompacted-window
# check right after this function is what keeps that case noask, not
# this function refusing to drop it -- identical reasoning already
# accepted for the PH case a few lines up, now extended to the raw case.
# One more accepted imprecision unique to the fallback path: this regex
# runs on a token already produced by shlex.split(), which has already
# removed quote characters, so a genuinely INERT, single-quoted literal
# spelled like a substitution (real bash never expands it) is
# indistinguishable here from a live one. The only possible effect of
# treating it as a vanish is dropping it from the compacted retry, which
# can only ever ADD a spurious ask on an unusual benign shape, never
# remove a real one -- the primary path keeps its own quote-aware
# blanking for the common case, and the fallback only runs at all once a
# genuinely quote-unbalanced or splice-corrupted command has already
# forced it. _RAW_SUBST_SPAN_RE is the same shared regex _reveal() above
# already uses -- defined once, near _has_raw_subst.
def _raw_token_vanishes(t):
    return _RAW_SUBST_SPAN_RE.sub("", t) == ""

def _drop_bare_vanish_tokens(w):
    return [t for t in w if t.strip(PH) != "" and not _raw_token_vanishes(t)]

for w in windows:
    if not w:
        continue
    compacted = _drop_bare_vanish_tokens(w)
    matched = _window_is_merge_dispatch(w)
    if not matched and compacted != w:
        matched = _window_is_merge_dispatch(compacted)
    if matched:
        emit_ask(
            "merge-door: a raw `gh pr merge` was about to run outside the "
            "ship-merge skill flow. Use mh:ship-merge for the reviewed path, "
            "or approve this specific merge now."
        )
        sys.exit(0)

sys.exit(0)
