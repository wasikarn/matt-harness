#!/usr/bin/env python3
import json, os, re, shlex, sys

try:
    d = json.load(sys.stdin)
except Exception:
    d = None

# A malformed/absent payload must fail closed, not silently become "no
# command to check" — that collapse let empty stdin, truncated JSON, and
# tool_input:null bypass every check below (found 2026-08-06).
if not isinstance(d, dict) or not isinstance(d.get("tool_input"), dict):
    print("[mh:gate] BLOCKED: malformed PreToolUse payload — failing closed", file=sys.stderr)
    sys.exit(2)

SQ = chr(39)
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
# A heredoc feeding an interpreter is executable code, not inert data -- do
# not strip it (checked against the segment of the line BEFORE "<<", i.e.
# the command the heredoc is stdin for, not the body that follows).
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")
_ANSI_C_QUOTE_RE = re.compile(r"\$" + SQ + r"((?:[^" + SQ + r"\\]|\\.)*)" + SQ)

def _strip_heredocs(cmd):
    # Heredoc bodies are literal data until the closing delimiter line, not
    # shell syntax to scan for dangerous subcommands -- UNLESS the heredoc
    # is stdin for an interpreter (bash <<EOF, python3 <<EOF, ...), in which
    # case the body IS executable code and must stay scannable. Without the
    # first half of this, a commit message authored via a quoted HEREDOC
    # (the documented commit convention in this repo) that merely MENTIONS
    # "git checkout X Y" or "rm -rf" in prose gets tokenized as a real
    # command and falsely denied -- reproduced live 2026-08-06. Without the
    # second half, "bash <<EOF\nrm -rf /\nEOF" silently bypasses every check
    # below -- also reproduced live 2026-08-06, by a negative-control test
    # written specifically to probe the first fix for this exact regression.
    # Ported from verifier-protect.sh (function of the same name), itself
    # ported from worktree-guard.py 2026-08-04; neither sibling makes the
    # interpreter distinction because their threat model (detecting writes
    # to specific files) does not need it the way a "catch any dangerous
    # command" gate does.
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
            # Closing delimiter never matched. Put the scanned lines BACK
            # instead of discarding them — silently eating a real write
            # statement that followed an unmatched heredoc open is worse
            # than never stripping at all.
            out.extend(lines[body_start:i])
    return "\n".join(out)

def _normalize_ansi_c_quotes(cmd):
    # shlex does not understand ANSI-C quoting ($SQ...SQ) -- it splits on the
    # bare $ instead of treating the whole span as one token, so a spliced
    # argv0 like $SQ\x74SQ (SQ = single quote) never reassembles into the
    # decoded character it resolves to in real bash.
    #
    # This file own dispatch logic below compares argv0 by EXACT STRING
    # (argv0 == "git", argv0 in ("rm", ...)), unlike verifier-protect.sh own
    # _normalize_ansi_c_quotes (a boundary-only rewrite: $SQ...SQ becomes a
    # plain SQ...SQ token, escapes left raw) -- that boundary-only version is
    # enough for a write-target scanner that only needs correct token EDGES,
    # but insufficient here: re-wrapping "$SQ\x74SQ" as "SQ\x74SQ" still
    # yields the literal token "gi\x74", which can never equal "git". Proven
    # empirically 2026-09-03: porting the boundary-only version verbatim
    # left "gi$SQ\x74SQ push --force" allowed (rc=0) -- this file needs the
    # escape actually RESOLVED, not just re-quoted, so this version diverges
    # from verifier-protect.sh on purpose (sync-seam note: the two files
    # normalize-step comment near the top of this file no longer applies to
    # this function -- only to the shared stdin-capture/fast-path prefix).
    #
    # Bounded escape set, matching what a git/rm/dd argv0 splice realistically
    # needs: \xHH (hex), \nnn (1-3 octal digits), and the standard single-char
    # escapes \n \t \r \\ \SQ \DQ. Anything else (\a \b \e \cX \uHHHH, ...)
    # falls through as its raw two literal characters, same as before -- a
    # full ANSI-C decoder is out of scope; those spellings are not realistic
    # argv0-splice vectors and an unhandled one just stays a literal
    # (non-matching, safe-direction) token.
    #
    # A literal SQ byte can appear in the DECODED result two ways: an
    # explicit \SQ escape, or an octal/hex escape that happens to resolve to
    # SQ (\047 or \x27, both decimal 39). Either way, the byte cannot sit
    # inside the SQ...SQ wrapper this function returns -- there is no escape
    # mechanism inside single quotes -- so the decoded text is scanned a
    # SECOND time (after all escapes are resolved, not mid-scan) and any SQ
    # byte found is spliced into the standard bash idiom: close the quote,
    # emit an escaped literal quote OUTSIDE quotes, reopen a new quoted span.
    # Skipping this second pass and only checking the raw \SQ spelling (the
    # boundary-only version own approach) would miss the octal/hex spellings
    # and leave an unbalanced quote, which throws off _newlines_to_seps own
    # quote-tracking scanner downstream: it opens in_squote at the first SQ
    # and, since the string never closes, stays in_squote for the rest of
    # the command, silently swallowing every following newline/write with no
    # separator inserted.
    #
    # A decoded newline (from \n, \012, or \x0a) must also stay INSIDE the
    # SQ...SQ wrapper, not emitted bare -- composition order already
    # guarantees this (this function runs BEFORE _newlines_to_seps below),
    # but only because the return value stays fully quoted: an unquoted
    # decoded newline would otherwise be read by _newlines_to_seps as a real
    # statement separator and split one command window (e.g. a single
    # "git commit -m $SQ...SQ" call) into two.
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

cmd = _strip_heredocs(d["tool_input"].get("command", ""))

def deny(reason):
    print("[mh:gate] BLOCKED: " + reason, file=sys.stderr)
    sys.exit(2)

def delete_hint():
    # trash is not stock on macOS or Linux (#93) — offer whichever CLI exists,
    # else route the model to the user. Lazy shutil import: only paid on a deny.
    import shutil
    t = next((c for c in ("trash", "trash-put") if shutil.which(c)), None)
    if t:
        return "use " + t + " instead"
    return ("no trash CLI on this machine — ask the user before a destructive "
            "delete, or install one (macOS: brew install trash; Linux: trash-cli)")

# Tokenize respecting quotes. The bare token "rm" and the word rm both
# resolve to a bare rm token. Quoted free text (commit messages, grep
# patterns) stays inside one token instead of being scanned as if it
# were a command.
# ponytail: no command-substitution or eval unwrapping here. This is a
# habit-guard for a single-operator harness, not an adversarial sandbox;
# revisit if that threat model changes.
# Newlines are command separators in bash but shlex eats them as
# whitespace, so a dangerous command after a newline would otherwise
# hide inside the first command window (found 2026-07-03). Insert a
# literal ";" after each real newline -- a backslash immediately before
# the newline is normally a real line continuation, not a separator, and
# both the backslash and the newline are stripped out entirely (real
# bash line-continuation semantics), so the token that follows joins
# cleanly with no residual character glued onto it, whitespace or not.
# Ported from the _newlines_to_seps helper in worktree-guard.py
# (2026-08-04); the full-removal fix for the whitespace-less case is
# 2026-09-03, GH #122.
#
# EXCEPT inside a "#" comment: a bash comment already ends at the literal
# newline no matter what precedes it, so a trailing backslash right
# before that newline has no continuation effect there -- the newline is
# still a real separator. The old blind backslash-newline regex did not
# know it was inside a comment and joined the next physical line onto
# the same window as the comment, so only the FIRST command in
# "git status # comment \" + newline + "git push --force" ever reached
# the deny checks below -- confirmed live 2026-09-03, the same shape of
# bug already fixed the same way in main-exec-guard.sh. Comment state is
# tracked char by char alongside quotes (a "#"/backslash inside a quoted
# string is never comment/escape syntax) and backslash-escape parity (an
# escaped hash does not start a comment), matching the posix escaping
# shlex does on its own and this function downstream
# shlex.shlex(..., commenters="#") default. SQ is the single-quote
# constant already defined above; DQ is its double-quote counterpart,
# scoped here since nothing else in this file needs it.
DQ = chr(34)
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
            # missed entirely -- confirmed live 2026-09-03, GH #122.
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

# Command-substitution placeholder pass (GH #129). A backtick/$(...)/${...}
# span vanishes in real bash once its (possibly empty) output splices into
# the surrounding text -- "gi`true`t" IS "git" once bash evaluates it -- but
# shlex has no concept of this and treats the backticks/parens/braces as
# literal characters, so a spliced argv0 like this survives tokenization as
# its own garbled token and evades every exact-match check below (argv0 ==
# "git", sub == "push", ...). _normalize_ansi_c_quotes above closes the same
# family of bypass for $SQ...SQ quoting by actually RESOLVING the escape;
# resolving what a substitution actually expands to would mean running a
# subshell, which no gate in this file should ever do -- so this closes it
# differently, by blanking the whole substitution span to one placeholder
# byte (PH) instead. PH is added to the shlex wordchars used below so it
# fuses into the surrounding literal text as ONE token instead of splitting
# it, and any FINAL argv0/subcommand token that still contains PH is
# duplicate-classified across every dangerous candidate name downstream
# (KNOWN_DANGEROUS / KNOWN_GIT_SUBS) instead of trusting the garbled token
# literally.
#
# Fixed-point iteration, still capped at 5 passes: before the GH #139 fix
# below, a genuinely nested same-type span ("$(echo $(date))") needed two
# passes -- pass 1 blanked only the innermost $(date), leaving "$(echo PH)"
# for pass 2 to finish. The depth-counting closer-search now resolves that
# case in a single pass. The loop stays anyway as defense-in-depth for any
# residual multi-pass interaction this fix does not specifically target (a
# placeholder one branch inserts can change what a later left-to-right scan
# sees mid-string); it costs nothing extra on an already-stable string,
# since the very next pass finds no change and breaks immediately.
#
# GH #139 fix (2026-09-04): a prior version of this comment named
# "gi$( (true) )t" and "gi$(f() { :; }; f)t" (both valid bash resolving to
# "git") as a deliberately-out-of-scope residual, because the closer-search
# below used to stop at the FIRST "(" or ")" byte instead of the matching
# one -- a paren nested inside a $(...) span (a subshell, a function
# definition) left the true end of the span un-blanked, so the reconstructed
# token never equalled "git" and every downstream exact-match dispatch
# missed it. That claim is now wrong: the closer-search depth-counts
# same-type brackets (same technique main-exec-guard.sh own _inner_cmds
# already used), so both examples above are caught. Still out of scope,
# unchanged by this fix: a paren/brace hidden behind a DIFFERENT quote or
# escape boundary inside the span (this scan already tracks quotes only at
# the top level, not recursively inside a substitution body -- see the
# ValueError-handler comment below for that documented limit).
#
# Mid-flag PH placement (e.g. --for<PH>ce) is NOT a non-goal -- a prior
# version of this comment claimed it "garbles the flag name but stays
# recognizable as a flag" and called it out of scope. That claim was wrong:
# confirmed live (third cross-file review, 2026-09-04) as a total silent
# bypass, not degraded recognition -- an EXACT-MATCH flag comparison
# downstream (t == "--force", t.startswith("--no-verify"), ...) fails the
# moment PH sits anywhere but the very front of the token, the same shape
# of gap a leading-only lstrip already needed fixing for a LEADING splice.
# This function only blanks the SPAN to PH; removing PH from a token before
# comparing it to a known flag name is every downstream comparison own job,
# not this one -- fixed at each of those call sites (full .replace(PH, "")
# now, not a leading-only strip, so a PH anywhere in the token is removed).
#
# Blanking the span must not DISCARD its body. Before this whole fix,
# "(" and ")" were already in OPERATORS (see below), so a bare $(...) split
# its content into its OWN window and got scanned like any other command --
# "$ (git push --force)" already denied today, with no placeholder pass
# involved at all. A blank-only substitution would erase that body instead
# of just fusing the splice, silently turning a working deny into an allow
# (found live 2026-09-03 auditing this exact fix). So every backtick/$(...)
# body is collected as it is blanked, and re-appended after the fixed-point
# loop as its own ";"-joined statement -- restoring the original
# window-scan coverage on top of the new fusion/duplication behavior.
# ${...} bodies are deliberately NOT collected: that form is a parameter
# expansion (a variable reference), not a command -- re-appending its body
# as a statement would treat a variable NAME as if it were a command line,
# a false-positive shape this pass has no reason to invent.
#
# Re-appending a body must not fire on a substitution-looking span that
# real bash would never evaluate at all. A SINGLE-quoted span suppresses
# every expansion -- single-quoted prose mentioning $ (git push --force) is
# inert text, never a command, in real bash. DOUBLE-quoted substitutions do
# NOT get this treatment: bash really does expand $(...) inside double
# quotes (e.g. "gi$(true)t" resolves to "git", a live splice vector), so a
# double-quoted span keeps going through the normal blank-and-collect path.
#
# Telling those two apart needs REAL shell quote state, not a regex. The
# first version here matched a SQ...SQ span as its own regex alternative,
# tried FIRST so Python own leftmost-first alternation would consume a
# whole single-quoted run before any $(...) / backtick alternative got a
# chance to match inside it. That still just pairs literal single-quote
# BYTES wherever they fall, with no notion of whether they are really
# opening/closing a shell quote or sitting inert inside a DOUBLE-quoted
# string -- an ordinary English contraction (a single-quote byte used as
# a shorthand mark, e.g. spelling "it is" or "is not" in shortened form)
# breaks it in both directions when it sits inside real double quotes,
# confirmed live 2026-09-03:
#   - a chain that double-quote-echoes a shortened "it is", then a real
#     $(true) splice fusing a spliced git argv0 ahead of push --force,
#     then double-quote-echoes a shortened "is not": the two shorthand
#     marks (both inside real double quotes, so neither is a real shell
#     quote boundary) paired up ACROSS the genuine $(...) splice, so the
#     regex swallowed the whole span as inert single-quoted data and never
#     blanked the splice at all -- a live bypass, the real force-push goes
#     through.
#   - the same double-quote-echoed shorthand "it is", followed by a git
#     commit whose -m value is a REAL single-quoted argument that merely
#     mentions a $(...) span in its text: the stray shorthand mark shifted
#     the pairing so that real single-quoted -m argument was no longer
#     matched as one span, and the $(...) text inside it got wrongly
#     collected as a live command -- a false deny of inert commit-message
#     text.
# Same root cause both times (a flat regex reasoning about quote state),
# same fix both times, so this uses the ALREADY-proven mechanism from
# _newlines_to_seps above instead of patching the regex a third time: one
# left-to-right character scan carrying real in_squote/in_dquote state and
# the same backslash-escape parity (\$, \`, \", \\ only mean anything
# inside double quotes; any \X is a literal pair when unquoted; nothing is
# special inside single quotes, which close on the very next single-quote
# byte no matter what it sits next to). A single-quote can only OPEN when
# not already inside a double-quoted string -- a single-quote byte has no
# special meaning inside "..." in real bash, so it is just an ordinary
# character there, not a quote toggle. $(...)/`...`/${...} are only ever
# recognized as live substitution starts when the scan is unquoted or
# inside a double-quoted string, matching real bash exactly and never
# crossing into a genuine single-quoted span no matter what punctuation
# that span holds.
#
# Comment state IS tracked in the scan below (in_comment, checked first,
# same state machine _newlines_to_seps above already uses): a
# substitution-shaped span sitting inside a real "#" comment ("# see also:
# $(git push --force)" is never executed in real bash) passes through
# unchanged instead of being blanked or collected as a body. Before this
# fix the gap cut both ways, not just toward a false DENY as an earlier
# version of this comment claimed: a fake payload inside a comment was
# wrongly recovered as a live body (false DENY), and a real substitution
# sitting BEFORE a trailing "#" comment could have its recovered body
# silently swallowed by that same comment once re-appended with no
# newline to end it (false ALLOW, closed separately by the newline join
# a few lines below in this same function). The two fixes are
# complementary: this one stops a fake payload inside a comment from ever
# being collected; the newline join stops a real one recovered earlier
# from being buried by a later comment.
PH = "\x01"
# GH #139: work budget for the depth-counting closer-search below, charged
# per character the search itself walks. Without a cap, an adversarial run
# of unclosed "$(" starts costs O(remaining length) EACH, for O(length)
# starts -- O(n^2) total, measured at 65s for a 100,000-char payload, well
# under this file own 150,000-char total-length cap a few hundred lines
# down. Once spent, the while loop below exits with depth still non-zero --
# the exact same fallback-to-literal path an already-unbalanced span takes
# -- so this only bounds the COST of reaching that outcome, not the outcome
# itself. Picked empirically: 2,000,000 keeps one _scan_once call under
# ~0.15s even on a full-length adversarial flood.
#
# GH #139 follow-up: budget exhaustion alone is NOT safe to treat like an
# ordinary unbalanced span. When the loop below stops early, the span is
# left un-blanked, which is EXACTLY the condition that let a nested
# construct defeat dispatch in the first place -- an adversary can pad a
# real dangerous command with just enough leading "$(" flood (well under
# the 150,000-char cap) to burn the budget, then rely on the un-blanked
# fallback to hide the payload again. This module-level flag (mutated, not
# rebound, so no "global" needed) records that the budget was actually the
# reason a search stopped -- checked once after tokenization below, before
# any dispatch -- so exhaustion denies instead of silently falling through
# to literal. Stays True across both the primary and the ValueError-
# fallback call this file makes (never reset): once a scan proves it could
# not finish, the whole command is untrustworthy regardless of which path
# produced the final token list.
_DEPTH_BUDGET_BLOWN = [False]
_DEPTH_SCAN_BUDGET = 2_000_000
def _blank_substitutions(s):
    bodies = []

    # One left-to-right pass: blanks every backtick/$(...)/${...} span it
    # finds THIS pass to PH, collecting backtick/$(...) bodies (never
    # ${...} -- a parameter expansion, not a command) into the shared
    # `bodies` list. GH #139: the $(...)/${...} closer-search below
    # depth-counts same-type brackets, so a same-type nested span
    # ("$(echo $(date))", or a paren/brace-bearing construct like
    # "$(f() { :; }; f)") resolves within this ONE pass -- the caller still
    # re-runs this to a fixed point (a few lines down) as defense-in-depth,
    # not because this pass itself needs a second look at same-type
    # nesting anymore.
    def _scan_once(s):
        out = []
        in_squote = in_dquote = in_comment = False
        i, n = 0, len(s)
        # GH #139 work budget (see _DEPTH_SCAN_BUDGET above), shared across
        # every $(...)/${...} closer-search this one _scan_once call makes --
        # not reset per search, or an adversarial run of unclosed starts
        # would still pay full-length cost on each one individually.
        depth_work_used = [0]
        while i < n:
            c = s[i]
            if in_comment:
                # A "#" comment already ends at the literal newline no
                # matter what precedes it -- same in_comment state machine
                # as _newlines_to_seps above, checked first so nothing
                # inside a real comment is ever evaluated as a
                # substitution start.
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
                # else: ordinary char while in_dquote, including a bare
                # apostrophe (no special meaning here) -- fall through to
                # the shared substitution-start check below, since
                # $(...)/`...`/${...} ARE live inside double quotes.
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
                # else: fall through to the shared substitution-start check.
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
        # Comment-truncation fix: appending with a plain " ; " separator lets
        # a "#" earlier in `s` (including one embedded inside an EARLIER
        # recovered body already joined here) start a shlex comment that
        # silently swallows everything appended after it -- there is no
        # newline after the appended bodies to end that comment, so a real
        # deny (e.g. a force-push splice followed by a trailing comment)
        # goes silently missing. A real "\n" before each appended body ends
        # any open comment the same way a genuine bash newline would, then
        # "; " starts a fresh statement -- same idiom _newlines_to_seps
        # above already uses for real newlines.
        s = s + "\n; " + "\n; ".join(bodies)
    return s

# shlex.split() only recognizes ;/&&/||/|/& as separators when whitespace
# already surrounds them -- "echo hi;rm -rf x" tokenized as one glued word
# "hi;rm", so the second command in the chain never had its own argv0
# checked (deep-audit 2026-08-28). punctuation_chars=True makes shlex split these out as their
# own tokens even with no surrounding space, while still respecting
# quotes -- a genuinely-quoted ";" inside an argument stays inside that
# one token. Grouping tokens ( ) { } get the same treatment: without it,
# "(rm -rf x)" or "{ rm -rf x; }" left a bare "(" / "{" as argv0 instead
# of "rm" -- a subshell/brace-group bypass of the identical shape. Ported
# from verifier-protect.sh / worktree-guard.py, which already use this
# pattern for their own write-target detection.
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}

# GH #140: shlex.shlex(..., punctuation_chars=True) below (and its
# shlex.split() ValueError fallback further down) has no length cap of its
# own, and its cost is superlinear in the length of a single long token --
# not merely proportional to total input length. Measured fresh against
# this exact file, single token appended to a real "git push --force",
# python3 cold-start included: 100,000 chars ~0.22s, 150,000 ~0.38s,
# 200,000 ~0.54s, 300,000 ~0.90s, 400,000 ~1.38s -- a 700,000-char payload
# blows straight past a 2s timeout. Checked separately: many SHORT tokens
# summing to the same 150,000-char total stayed fast (~0.14s, essentially
# just python3 cold-start) -- the blowup tracks the longest SINGLE token,
# not raw input length. A total-length cap still bounds the worst case
# either way, since no single token can exceed the total length, even
# though it is more conservative than strictly necessary for the
# many-short-tokens shape. 150,000 was picked to keep worst-case added
# latency comfortably under half a second while being enormously generous:
# a real single-line Bash command is essentially never anywhere near this
# size -- a few hundred characters is already a very long one, and even an
# extreme case (a huge inline SQL statement, a long list of glob-expanded
# paths) rarely reaches a few thousand. This file has no "ask" outcome (see
# its own header/comments), so the fix denies on an oversized command --
# the same fail-closed direction every other ambiguous-input path here
# already takes -- and fires on length ALONE, before either the primary
# shlex call or its fallback ever runs, regardless of whether the command
# is otherwise dangerous.
_CMD_LEN_CAP = 150_000
if len(cmd) > _CMD_LEN_CAP:
    deny("command too long to safely tokenize (" + str(len(cmd)) + " chars, cap " + str(_CMD_LEN_CAP) + ") - confirm with user first")

try:
    lex = shlex.shlex(_blank_substitutions(_newlines_to_seps(_normalize_ansi_c_quotes(cmd))), posix=True, punctuation_chars=True)
    lex.wordchars += PH
    tokens = list(lex)
except ValueError:
    # Two different things raise here, and they need different handling.
    #
    # (1) An unbalanced quote SURVIVING the placeholder-blank pass -- e.g. a
    # backtick-wrapped apostrophe-bearing body blanks to something like
    # "giPHt push --force ; " plus that body re-appended bare (the
    # substitution BODY, put back by _blank_substitutions so it stays
    # scannable), and the loose apostrophe inside the re-appended body
    # leaves an unclosed quote. The old fallback re-tokenized cmd.split()
    # on the RAW, PRE-BLANKING string -- PH was never in it, so a spliced
    # argv0 built this way can never equal "git" and the whole GH #129
    # mechanism went inert, ALLOWing a real force-push once bash evaluates
    # the inner failing subshell to empty (confirmed live 2026-09-03: rc=0,
    # no python re-classification at all). Same bypass shape via the
    # dollar-paren substitution form.
    #
    # (2) _blank_substitutions own closer-search for a backtick/$(...)/
    # ${...} span (the `s.find`/while-loop scans a few lines up) does not
    # track quote state for the characters it skips while hunting the
    # terminator -- if that span crosses a real quote character (ordinary
    # interpreter-heredoc content full of curly braces can do this), the
    # quote toggle is silently lost, desyncing in_squote/in_dquote for the
    # rest of the scan and leaving the FINAL string quote-unbalanced even
    # though the ORIGINAL command was perfectly valid. Confirmed live: a
    # read-only python3 heredoc with an unmatched "${" inside a properly-
    # quoted string denied here, even though it never touches a dangerous
    # command at all.
    #
    # Distinguishing (1) from (2) needs no new parser: re-parse the
    # ORIGINAL, pre-blanking cmd as a pure predicate. If it parses cleanly,
    # this ValueError is self-inflicted by our own blanking pass (case 2),
    # so fall back to a separator-aware split instead of hard-denying a
    # benign command (GH #129 own placeholder-splice guarantee is
    # irrelevant here: a cleanly-parsing original has no corruption for a
    # splice to exploit in the first place). If the original ALSO fails to
    # parse, this really is case (1) or a plain malformed command, and this
    # file own malformed-payload stance still applies: deny on ambiguity
    # rather than guess at a third tokenizer -- this gate has no "ask"
    # outcome, so deny is the fail-closed option available.
    #
    # A bare whitespace-only cmd.split() (this file own pre-GH#129 fallback
    # shape) is itself exploitable here: the comment a few lines below this
    # try/except ("the second command in the chain never had its own argv0
    # checked") documents exactly why punctuation_chars=True exists on the
    # primary shlex path above -- a compound command own LATER segments
    # (after ;/&&/||/|/&) each need their own window and argv0 check. A naive
    # .split() has no separator awareness at all, so a dangerous command
    # placed second in a chain with no surrounding whitespace around the
    # separator (confirmed live: cmd.split() on
    # "${y:-\"a}b\"};git push --force" glues the separator onto its
    # neighbors into one token, "git" never becomes its own window) evaded
    # detection entirely -- rc=0 ALLOW on a real force-push. Fixed by
    # regex-splitting on the separator set FIRST, keeping each separator as
    # its own token (a subset of the OPERATORS set the window-builder below
    # already checks against), then whitespace-splitting each remaining
    # segment -- the resulting flat token list flows into the exact same
    # window-building/dispatch loop below as the primary path, so every
    # segment gets its own argv0 checked with no separate dispatch path to
    # keep in sync. ( ) { } deliberately excluded from this split: unlike a
    # bare ;/&&/||/|/&, they show up far more often as ordinary characters
    # inside a ${...} body (this exact bug class) than as a real brace/
    # subshell group in a command already headed for this raw fallback.
    # Second-reviewer sweep, 2026-09-04: every downstream PH-based check in
    # this whole dispatch loop (20+ distinct sites -- prefix-wrapper unwrap,
    # rm -rf, find -exec/-delete, --no-verify, -c core.hooksPath, the git
    # global-flag walk, the whole push/reset/clean/restore/checkout/switch/
    # branch/commit/add family via the one shared leading-strip a few lines
    # below, stash/worktree args[0] reads, the worktree -b/-B loop, dd of=,
    # the SQL keyword match, and the Layer 3 standalone-vanish compaction)
    # assumed its tokens either came from the primary, already-blanked path
    # or contained no substitution syntax at all. Splitting the RAW,
    # never-blanked cmd here (the shape this block shipped with) means EVERY
    # one of those 20+ sites is blind on this fallback path the same way the
    # two dispatch-duplication sites were before _has_raw_subst -- not one
    # isolated gap, the whole downstream dispatch shares the same
    # assumption. Patching each site individually is the same losing,
    # one-spelling-at-a-time game this file own comments already call out
    # elsewhere (GH #122/#123/#125/#129) -- so this fixes the ROOT of it
    # instead: run the SAME _blank_substitutions/_newlines_to_seps/
    # _normalize_ansi_c_quotes pipeline the primary path already uses,
    # tokenize THAT (not the raw cmd) with the separator-aware split, so a
    # real substitution reaching this fallback path carries PH into every
    # downstream check exactly like the primary path already handles it --
    # no per-site widening needed. Safe to reuse here even though this exact
    # pipeline is what raised ValueError on the PRIMARY shlex path: the
    # failure there was shlex own quote-balance requirement choking on a
    # corrupted (quote-crossing) blank -- this fallback never runs shlex at
    # all, just a regex split + whitespace split, neither of which cares
    # whether quotes balance, so the same corruption that broke shlex is
    # harmless here.
    try:
        shlex.split(cmd)
        _fallback_src = _blank_substitutions(_newlines_to_seps(_normalize_ansi_c_quotes(cmd)))
        parts = re.split(r"(&&|\|\||;|\||&)", _fallback_src)
        tokens = []
        for part in parts:
            if part in ("&&", "||", ";", "|", "&"):
                tokens.append(part)
            else:
                tokens.extend(part.split())
    except ValueError:
        deny("could not safely tokenize command for pattern matching (unbalanced quote/substitution) - confirm with user first")

# GH #139 follow-up: see _DEPTH_BUDGET_BLOWN above -- a scan that could not
# finish leaves a span un-blanked, the same bypass shape this issue closed.
# Checked once here, after both the primary and fallback paths above have
# had their chance to run, before any token reaches dispatch.
if _DEPTH_BUDGET_BLOWN[0]:
    deny("command too long to safely tokenize (nested substitution exceeded depth-scan budget) - confirm with user first")

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

# GH #129 Layer 3 (2026-09-03): a standalone UNQUOTED substitution that
# resolves to empty ($(true), `true`) vanishes as its own token in real
# bash, shifting every later token left by one position -- but
# _blank_substitutions above leaves a PH-only token sitting in its place,
# so a fixed-index read anywhere downstream (worktree/stash args[0], the
# git-subcommand extraction below, ...) trusts the wrong position.
# Confirmed live: "$(true) git worktree add -b evil /tmp/x" silently
# ALLOWed the single-branch-develop-only doctrine gate to be bypassed --
# the vanished token becomes argv0 itself, shifting "git" one slot into
# rest where no dispatch check below looks for it. A check that SCANS the
# whole rest/args list (the -b/-B/--branch loop below, once PH-stripped) is
# naturally immune; only a fixed-index read is at risk, and enumerating
# every one individually is the same losing game as #122/#123/#125/#129
# already were, one spelling at a time. Instead: re-run the whole existing
# per-window dispatch a second time against a compacted copy of the window
# with every bare-PH-only token dropped (including several adjacent
# vanishes glued into one all-PH token) -- appended alongside the original,
# so both get the exact same checks with no separate code path, and a
# deny() in either one wins. A token that merely CONTAINS PH as part of a
# larger word (a glued splice) is left untouched -- already handled by the
# leading-PH-strip fixes below. Verified this does not turn a benign
# standalone splice into a false deny: "$(which git) status" compacts to
# ["status"] (argv0 dropped), which stays correctly unmatched by every
# check below.
_aug = []
for _w in windows:
    _wc = [_t for _t in _w if not (_t and all(_c == PH for _c in _t))]
    _aug.append(_w)
    if _wc != _w:
        _aug.append(_wc)
windows = _aug

def basename(p):
    return p.rsplit("/", 1)[-1]

# Candidate names for the placeholder-splice duplication (GH #129 Step 3):
# the exact set of argv0 basenames, and separately git subcommands, that any
# downstream check in this file actually dispatches on by exact string
# match. A garbled token containing PH cannot equal any of these directly,
# so every candidate is tried in turn instead of trusting the garbled
# literal.
KNOWN_DANGEROUS = ("rm", "find", "git", "dd", "mysql", "psql", "sqlite3", "mariadb")
KNOWN_GIT_SUBS = ("push", "reset", "clean", "restore", "checkout", "switch", "branch", "stash", "commit", "add", "worktree")

# Coordinator review, 2026-09-04: the Finding-4 fallback tokens (used when
# cmd raises ValueError under the primary shlex path but parses cleanly on
# its own) come straight from cmd, never through _blank_substitutions -- so
# a spliced dispatch token reaching this file only through the fallback
# path (e.g. "gi$(true)t") still carries its literal substitution syntax
# and never contains PH at all. Both duplication triggers below (this one
# for argv0, the KNOWN_GIT_SUBS one further down for the git subcommand
# token) are gated purely on "PH in ...", so a spliced token on the
# fallback path sailed through unrecognized -- confirmed live:
# "echo ${y:-\"a}b\"} ; gi$(true)t push --force" (the quote-crossing span
# forces the fallback, the second window carries the splice) and the same
# shape one window over with a spliced git SUBCOMMAND ("git pu$(true)sh
# --force" in place of the argv0 splice) both exit 0, silent allow. Widened
# both triggers to also fire on a token that still carries raw, unblanked
# substitution syntax. A narrow, single-token check -- NOT this file own
# bash-level _has_subst guard a few hundred lines up, which also matches a
# bare "$" and would misfire on an ordinary "$PYTHON -m pytest"-shaped
# token with no substitution at all.
def _has_raw_subst(t):
    return "`" in t or "$(" in t or "${" in t

for w in windows:
    if not w:
        continue
    argv0, rest = basename(w[0]), w[1:]

    # Prefix wrappers unwrap one level per iteration so stacked forms like
    # "env nice rm -rf x" resolve to the real command. Found 2026-07-01:
    # "sudo rm -rf x" and "find | xargs rm -rf" bypassed every check because
    # argv0 was the wrapper, not the wrapped command — and these are
    # everyday shell idioms, not adversarial obfuscation, so they are in
    # scope for a habit-guard. env/nice/sudo take their own flags+values
    # before the wrapped command; command/nohup/time only take bare flags.
    PREFIX_WRAPPERS = {"env", "command", "nohup", "nice", "time", "sudo"}
    while rest and argv0 in PREFIX_WRAPPERS:
        if argv0 == "env":
            i = 0
            while i < len(rest):
                # Leading-PH fix: a disguised env flag (env $(true)-u FOO
                # ...) no longer starts with a dash, so this loop misreads
                # it as the wrapped command and the real command ends up
                # misplaced in rest instead of becoming argv0 (found live
                # 2026-09-03).
                t = rest[i].replace(PH, "")
                if t == "-u" and i + 1 < len(rest):
                    i += 2
                elif t.startswith("-"):
                    i += 1
                elif "=" in t and t.split("=", 1)[0].isidentifier():
                    i += 1
                else:
                    break
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        elif argv0 == "nice":
            i = 0
            # Same leading-PH fix as env above.
            while i < len(rest) and rest[i].replace(PH, "").startswith("-"):
                t = rest[i].replace(PH, "")
                i += 1
                if t == "-n" and i < len(rest):
                    i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        elif argv0 == "sudo":
            # sudo -u/-g (short or long) select the effective identity and
            # take a value. Handles space-joined, "="-joined long form, and
            # attached short form ("-ualice") in one pass, PLUS bundled
            # short flags where u/g sits anywhere in a combined token --
            # standard getopt short-option semantics: once a value-taking
            # character is hit, everything after it in that same token is
            # the value for that flag, and only an empty remainder falls
            # through to the next token. So "-nu alice" (n takes no value,
            # u is last in the token) reads "alice" as the value for -u,
            # taken from the next token -- but "-un alice" (u first, "n"
            # left over in the same token) reads the attached "n" as the
            # value for -u, so "alice" is the real wrapped command, not a
            # value -- both resolved correctly below (deep-audit
            # 2026-08-28, issue #115 fix only matched exact "-u"/"-g"
            # tokens and missed every bundled form, e.g. "sudo -nu alice
            # rm -rf x" still bypassed this gate after that fix). Other
            # sudo flags that also take a value (-p, -C, -R, -T, -U) are
            # not modeled here -- a bundle mixing one of those with u/g
            # (e.g. "-pu") is an accepted non-goal, same tier as the
            # habit-guard-not-adversarial-sandbox stance already documented
            # for this file above.
            LONG_VALUE_FLAGS = {"--user", "--group"}
            i = 0
            while i < len(rest):
                # Same leading-PH fix as env/nice above.
                t = rest[i].replace(PH, "")
                bare = t.split("=", 1)[0]
                if bare in LONG_VALUE_FLAGS:
                    i += 1 if "=" in t else min(2, len(rest) - i)
                elif t.startswith("--"):
                    i += 1
                elif t.startswith("-") and len(t) > 1:
                    m = re.search(r"[ug]", t[1:])
                    if m:
                        attached = m.end() < len(t[1:])
                        i += 1 if attached else min(2, len(rest) - i)
                    else:
                        i += 1
                else:
                    break
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        else:  # command, nohup, time — bare flags then the wrapped command
            i = 0
            # Same leading-PH fix as env/nice/sudo above.
            while i < len(rest) and rest[i].replace(PH, "").startswith("-"):
                i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]

    if argv0 == "xargs":
        # Unlike git, xargs args are never a free-text commit message, so
        # scanning for a known-dangerous basename anywhere in its args is
        # safe (no quoted-prose false-positive risk). "git" is included so
        # the per-argv0 git check fires on the xargs-wrapped form of git
        # commands; without it, argv0 stays as "xargs" and the worktree
        # check is silently bypassed (found 2026-07-03 when designing the
        # worktree-create-block gate).
        # Full PH removal (not just leading): a splice can land mid-
        # basename (xargs g$(true)it ..., found live 2026-09-03), same
        # shape as the SQL keyword check below.
        for j, t in enumerate(rest):
            if basename(t).replace(PH, "") in ("rm", "find", "dd", "git"):
                argv0, rest = basename(t), rest[j + 1:]
                break
    elif argv0 == "docker" and rest and rest[0].replace(PH, "") == "exec":
        # "docker exec <flags> <container> <cmd...>" re-points argv0 to the
        # inner command so the SQL check below can fire on the wrapped
        # client (feeds A6 — mysql/psql/sqlite3/mariadb run inside a
        # container is otherwise invisible to this gate).
        # Leading-PH fix: a disguised exec token or a disguised docker flag
        # before the container name each let the real inner command slip
        # past this re-pointing (found live 2026-09-03).
        j = 1
        while j < len(rest) and rest[j].replace(PH, "").startswith("-"):
            j += 1
        if j < len(rest):
            j += 1  # skip the container name/id
        if j < len(rest):
            argv0, rest = basename(rest[j]), rest[j + 1:]

    for argv0 in (KNOWN_DANGEROUS if (PH in argv0 or _has_raw_subst(argv0)) else (argv0,)):
        if argv0 == "rm":
            # Lowercase before matching. "rm -Rf" and "rm -R -f" bypassed
            # the lowercase-only "r"/"f" substring check (found 2026-07-01).
            # Only a SHORT bundled cluster (-rf, -fr, -Rf, lone -r / -f, ...)
            # contributes per-CHARACTER; a LONG option only counts on an
            # exact spelling match against rms real long flags. The old
            # check joined every "-"-looking token -- long options included
            # -- into one string and tested bare letter membership across
            # the whole thing, so a long flag whose plain-English spelling
            # happens to contain both letters (e.g. "--before=1", from
            # "before") false-positived as rm -rf the moment the GH #129
            # candidate duplication started running this check against
            # arbitrary unrelated commands (confirmed live 2026-09-03:
            # "$(which node) --before=1" wrongly denied).
            has_r = has_f = False
            for t in rest:
                # Fail-toward-suspicion for a NEW, broader residual than the
                # already-accepted one above (PH landing INSIDE an
                # already-dash-prefixed flag body, e.g. "--for<PH>ce"): a
                # command substitution resolving to empty at runtime splices
                # directly onto whatever follows it in real bash --
                # "$(true)-rf" IS "-rf" once bash evaluates it -- but the
                # placeholder pass leaves a non-empty PH byte glued to the
                # front, so the token becomes "PH-rf", which no longer even
                # STARTS WITH "-" and evades every check below entirely
                # (confirmed live 2026-09-03: "rm $(true)-rf /tmp/x" and the
                # backtick equivalent both silently ALLOWed). Stripping a
                # leading placeholder assumes the conservative (dangerous)
                # resolution -- same direction as the dispatch-token
                # duplication above -- so a token that becomes flag-shaped
                # once the substitution is assumed empty is treated as that
                # flag.
                t = t.replace(PH, "")
                if t.startswith("--"):
                    has_r = has_r or t == "--recursive"
                    has_f = has_f or t == "--force"
                elif t.startswith("-") and len(t) > 1:
                    body = t[1:].lower()
                    has_r = has_r or "r" in body
                    has_f = has_f or "f" in body
            if has_r and has_f:
                deny("rm -rf detected — " + delete_hint())

        # Same leading-PH-erases-flag-shape fix as the rm block above --
        # "find $(true)-exec rm {} \;" blanks to "find PH-exec rm {} \;",
        # which the old exact "-exec" in rest membership test missed
        # entirely since the token no longer equals "-exec" at all.
        if argv0 == "find" and any(t.replace(PH, "") in ("-exec", "-execdir") for t in rest) and "rm" in [basename(t) for t in rest]:
            deny("find -exec/-execdir rm detected — destructive delete; " + delete_hint())
        if argv0 == "find" and any(t.replace(PH, "") == "-delete" for t in rest):
            deny("find -delete detected — destructive delete; " + delete_hint())

        if argv0 == "git" and rest:
            # --no-verify skips pre-commit/pre-push hooks — block it on any git
            # command, multi-line safe (checked per window, not against the
            # loop-leak `tokens` which only held the last line — found v0.36.0
            # audit: a --no-verify on an earlier line bypassed the old global
            # check). Git-specific so `echo "--no-verify"` does not false-positive.
            # Same leading-PH fix as below: "git commit $(true)--no-verify"
            # blanks to a "PH--no-verify" token that no longer equals
            # "--no-verify" at all, so the old exact membership test missed it.
            if any(t.replace(PH, "") == "--no-verify" for t in w):
                deny("--no-verify bypasses safety hooks")
            # -c core.hooksPath=<path> (split "-c core.hooksPath=X" or joined
            # "-ccore.hooksPath=X") re-points git at a different hooks dir —
            # the same bypass as --no-verify, just spelled as a config
            # override. Only a non-empty value trips it: "=" with nothing after
            # is not a meaningful re-point.
            hooks_path_val = None
            for idx, t in enumerate(w):
                t_pf = t.replace(PH, "")  # same leading-PH fix as --no-verify above
                if t_pf == "-c" and idx + 1 < len(w) and w[idx + 1].startswith("core.hooksPath="):
                    hooks_path_val = w[idx + 1].split("=", 1)[1]
                elif t_pf.startswith("-c") and t_pf[2:].startswith("core.hooksPath="):
                    hooks_path_val = t_pf[2:].split("=", 1)[1]
            if hooks_path_val:
                deny("-c core.hooksPath=<path> re-points git at a different hooks dir — same bypass as --no-verify")
            # Walk past leading global flags before the subcommand so a prefix
            # like ` git -C /repo push --force` (or ` git -Cpath push --force`,
            # ` git --no-pager push --force`) does not set sub="-C"/"--no-pager"
            # and silently bypass the push/worktree gates (found v0.36.0 audit).
            # The WorktreeCreate event does NOT fire for Bash-invoked worktree
            # creation, so this Bash-side guard is the only thing blocking
            # `git -C . worktree add -b newbranch`.
            GIT_VALUE_GLOBALS = {"-C", "-c", "--git-dir", "--work-tree", "--config-env"}
            i = 0
            # Leading-PH fix (hardening): a disguised global flag here
            # stops this walk before the real subcommand, misplacing it
            # into args. Membership checks below already tolerate this;
            # args[0]-based ones (worktree/stash) do not.
            while i < len(rest) and rest[i].replace(PH, "").startswith("-"):
                t = rest[i].replace(PH, "")
                if t in GIT_VALUE_GLOBALS:
                    i += 2  # bare value-taking global → skip flag + its value
                    continue
                # combined form carrying the value in the same token
                # (-Cpath, --git-dir=path, --config-env=name=val) → skip 1
                if (t.startswith("-C") and t != "-C") or \
                   t.startswith(("--git-dir=", "--work-tree=", "--config-env=")):
                    i += 1
                    continue
                i += 1  # any other leading flag (non-value global: --no-pager, -p, …)
            if i >= len(rest):
                continue  # only global flags, no subcommand — safe no-op
            sub, args = rest[i], rest[i + 1:]
            # drop the value token after a free-text flag so message
            # content (e.g. "commit -m ...rm -rf...") is never pattern-
            # matched.
            scan, skip = [], False
            for t in args:
                if skip:
                    skip = False
                    continue
                if t.replace(PH, "") in ("-m", "--message"):
                    skip = True
                    continue
                scan.append(t)
            # Fail-toward-suspicion for the same empty-substitution-splice gap
            # named in the rm -rf block above (GH #129 adjacent, confirmed
            # live 2026-09-03): "$(true)--force" resolves to a genuinely
            # flag-shaped "--force" in real bash, but the placeholder pass
            # leaves a non-empty PH byte glued to the front of the dash, so
            # every startswith("-")/exact-flag check in every sub == "..."
            # branch below (push/reset/clean/restore/checkout/switch/branch/
            # commit/add all read from this one `scan` list) would otherwise
            # see "PH--force" -- not flag-shaped at all -- and silently miss
            # it. Stripping a leading placeholder here, once, before any of
            # those branches run, covers all of them the same way the
            # dispatch-token duplication above already covers argv0/sub.
            scan = [t.replace(PH, "") for t in scan]

            for sub in (KNOWN_GIT_SUBS if (PH in sub or _has_raw_subst(sub)) else (sub,)):
                if sub == "push" and any(
                    t in ("-f", "--force") or (t.startswith("--force") and not t.startswith("--force-with-lease"))
                    or (t.startswith("-") and not t.startswith("--") and "f" in t)
                    or t.startswith("+")  # "+refspec" force-pushes without a -f/--force flag
                    for t in scan
                ):
                    deny("git push --force overwrites remote history — needs explicit user approval (use --force-with-lease for the safe variant)")
                if sub == "reset" and "--hard" in scan:
                    deny("git reset --hard discards uncommitted work — confirm with user first")
                # Same short-vs-long flag boundary the push check above
                # already draws: a SHORT bundled cluster (starts with "-",
                # not "--") contributes per-character, a LONG option only
                # counts on an EXACT "--force" match. The old check was bare
                # letter-containment against the whole token,
                # which also matched an unrelated long flag whose spelling
                # happens to contain the letter f -- "--find-renames" and
                # "--format=fuller" both false-positived as git clean -f the
                # moment the GH #129 candidate duplication ran this check
                # against a garbled subcommand that was really diff/show,
                # not clean (confirmed live 2026-09-03).
                if sub == "clean" and any(
                    t == "--force" or (t.startswith("-") and not t.startswith("--") and "f" in t)
                    for t in scan
                ):
                    deny("git clean -f deletes untracked files — confirm with user first")
                # git restore is the modern checkout -- replacement. The default mode
                # (and --worktree) targets the WORKTREE → discards changes, unrecoverable.
                # --staged (without --worktree) targets the INDEX → recoverable (re-stage
                # with git add), so it is allowed. Unlike checkout, `git restore <path>`
                # is NEVER a branch switch (no ambiguity), so a worktree-targeting
                # pathspec is always destructive.
                if sub == "restore":
                    has_pathspec = ("." in scan or "--" in scan or
                                    any(not t.startswith("-") for t in scan))
                    targets_worktree = "--worktree" in scan or "--staged" not in scan
                    if has_pathspec and targets_worktree:
                        deny("git restore discards working-tree changes — confirm with user first")
                # Bundled short flags: "-qf" means -q -f, and an exact-token check like
                # `t in ("-f", "--force")` misses it (2026-08-17 bug sweep, live-verified
                # bypass). Stop scanning a cluster at a value-taking flag letter
                # (checkout -b/-B, switch -c/-C) so "-bfoo"/"-cfoo" is not misread as
                # -f hiding inside the branch-name argument.
                def _bundled_force(t, stop_chars):
                    if not (t.startswith("-") and not t.startswith("--")):
                        return False
                    for ch in t[1:]:
                        if ch in stop_chars:
                            return False
                        if ch == "f":
                            return True
                    return False
                # checkout: "--"/"." = discard (existing); 2+ nonflag = tree-ish +
                # path (e.g. `git checkout HEAD~1 file`, overwrites worktree from an
                # old commit — unrecoverable). 1 nonflag stays allowed: it may be a
                # legit branch switch (found v0.36.0 audit: HEAD~1+file was missed).
                if sub == "checkout" and ("--" in scan or "." in scan or
                                            len([t for t in scan if not t.startswith("-")]) >= 2 or
                                            any(t in ("-f", "--force") or _bundled_force(t, ("b", "B")) for t in scan)):
                    deny("git checkout -- / git checkout . / git checkout -f / git checkout <tree> <file> discards working-tree changes — confirm with user first")
                if sub == "switch" and any(t in ("-f", "--force", "--discard-changes") or _bundled_force(t, ("c", "C")) for t in scan):
                    deny("git switch --force discards working-tree changes — confirm with user first")
                if sub == "branch" and (
                    any(t == "-D" or (t.startswith("-") and not t.startswith("--") and "D" in t) for t in scan)
                    or ("--delete" in scan and "--force" in scan)
                ):
                    deny("git branch -D / --delete --force force-deletes a branch, discarding unmerged commits — confirm with user first")
                if sub == "stash" and args and args[0].replace(PH, "") in ("drop", "clear"):
                    deny("git stash drop/clear discards stashed changes — confirm with user first")
                if sub == "commit" and "--amend" in scan:
                    deny("git commit --amend rewrites history — confirm with user first")
                if sub == "add" and any(t in ("-A", "--all", ".") for t in scan):
                    deny("git add -A/. stages everything — stage files by name instead")
                if sub == "worktree" and args and args[0].replace(PH, "") == "add":
                    # kbg single-branch doctrine gate. This is the ONLY enforcement
                    # point for the doctrine — a prior companion gate on the native
                    # WorktreeCreate event (worktree-create-block.sh) was removed
                    # 2026-07-31: it read tool_name/tool_input, fields that event
                    # never actually sends (confirmed against code.claude.com/docs/en/hooks
                    # raw HTML), so its deny logic was dead code, and independent of
                    # that bug, registering ANY hook on WorktreeCreate replaces the
                    # Claude Code default worktree creation and requires the hook
                    # to emit the resulting path — this one never did, so it was
                    # silently breaking every legitimate WorktreeCreate-triggered
                    # worktree (isolation:"worktree", claude --worktree, background
                    # sessions) in every repo running this plugin. See
                    # docs/research/official-docs-audit-2026-07-31.md. This Bash-side
                    # check is unaffected: the dedicated WorktreeCreate event never
                    # fires for Bash-invoked `git worktree add` in the first place
                    # (verified against the same docs), so it was never part of the
                    # broken mechanism.
                    #
                    # Find the new-branch name. The git-worktree-add argv
                    # order is flexible — the -b flag may come before or
                    # after the path. Scan ALL args for the -b/-B/--branch
                    # flag pair. If found, capture the value. If absent, no
                    # new branch is being created (existing branch checkout
                    # via positional commit-ish) — allow.
                    branch_name = None
                    for i, t in enumerate(args):
                        # Leading-PH fix (confirmed live): a spliced -b flag
                        # no longer starts with a dash, so this doctrine
                        # gate silently ALLOWed a new non-develop branch.
                        t = t.replace(PH, "")
                        if t in ("-b", "-B", "--branch") and i + 1 < len(args):
                            branch_name = args[i + 1]
                            break
                        # joined forms: -bBRANCH, -BBRANCH, --branch=BRANCH
                        if (t.startswith("-b") and t != "-b") or (t.startswith("-B") and t != "-B"):
                            branch_name = t[2:]
                            break
                        if t.startswith("--branch="):
                            branch_name = t.split("=", 1)[1]
                            break
                    if branch_name is not None and branch_name != "develop":
                        # Resolve project root: CLAUDE_PROJECT_DIR env first,
                        # then walk up from cwd looking for .git OR sentinel.
                        # Expand-not-rename (T10 #89): accept BOTH the old
                        # .kbg-no-worktree and new .mh-no-worktree sentinel names,
                        # indefinitely -- a sentinel file in some OTHER repo is
                        # invisible to this one, so there is no way to force every
                        # other repo to rename when this repo does.
                        _SENTINEL_NAMES = (".kbg-no-worktree", ".mh-no-worktree")
                        root = os.environ.get("CLAUDE_PROJECT_DIR") or ""
                        if not root:
                            d = os.getcwd() or "/"
                            for _ in range(16):
                                if d in ("", "/"):
                                    break
                                try:
                                    if os.path.isdir(os.path.join(d, ".git")) or \
                                       any(os.path.isfile(os.path.join(d, _s)) for _s in _SENTINEL_NAMES):
                                        root = d
                                        break
                                except Exception:
                                    pass
                                parent = os.path.dirname(d)
                                if parent == d:
                                    break
                                d = parent
                        sentinel = ""
                        if root:
                            for _s in _SENTINEL_NAMES:
                                _cand = os.path.join(root, _s)
                                if os.path.isfile(_cand):
                                    sentinel = _cand
                                    break
                        if sentinel:
                            # No allowlist: any new non-develop branch via worktree
                            # is denied in a sentinel repo. (The former review-pr
                            # detached-worktree allowlist was removed with the
                            # review pipeline, 2026-08-24 #82 — it was dead code
                            # anyway: this branch only runs when -b/-B/--branch is
                            # present, and the allowlist required its absence.)
                            deny("git worktree add -b new-branch blocked by matt-harness doctrine "
                                 "(no new non-develop branches via worktree; single branch develop only); "
                                 "use detached worktrees, develop, or an existing branch. "
                                 "Remove /.kbg-no-worktree or /.mh-no-worktree to allow")

        if argv0 == "dd" and any(t.replace(PH, "").startswith("of=/dev/") for t in rest):
            deny("dd writing to a raw device — irrecoverable disk-level destruction")

        if argv0 in ("mysql", "psql", "sqlite3", "mariadb"):
            # SQL genuinely lives inside -e/-c values, unlike git free-text
            # messages — deliberately DO scan inside those here. The check
            # is restricted to known-dangerous statements.
            # TABLE is optional in TRUNCATE grammar (MySQL/MariaDB/Postgres all
            # accept bare "TRUNCATE tbl_name") — matching only "TRUNCATE TABLE"
            # let a fully destructive bare TRUNCATE through undetected.
            # Full PH removal: a splice can land mid-keyword
            # (DR$(true)OP -> DRPHOP), unlike a flag boundary.
            if re.search(r"DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+(TABLE\s+)?\w",
                         " ".join(rest).replace(PH, ""), re.IGNORECASE):
                deny("destructive SQL (DROP TABLE/DATABASE/SCHEMA or TRUNCATE) detected — confirm with user first")

sys.exit(0)
