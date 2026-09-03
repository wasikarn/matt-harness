#!/usr/bin/env bash
# Gate: ask before a raw `gh pr merge` runs outside the `ship-merge` skill flow.
# `convergence-merge-gate.sh` used to cover this and was retired 2026-08-24
# with the review pipeline (#82) — ship-merge/SKILL.md's own text admits its
# in-flow gates are "now the only merge-door protection", but those only fire
# when the model goes through the Skill call; a raw Bash `gh pr merge` had
# zero hook coverage until this file. Reads the PreToolUse JSON payload from
# stdin; emits `permissionDecision: ask` (exit 0) on a match, never a hard
# deny — a human can still approve a legitimate emergency merge in the
# moment, same tier `verifier-protect.sh` uses for tamper-sensitive edits.
#
# Known, deliberate non-goal: the REST equivalent (`gh api ... /pulls/N/merge`)
# is NOT covered. Catching every way to reach that endpoint is an arms race
# this gate does not try to win — `gh pr merge` is the documented, ordinary
# path `ship-merge` itself uses and the one operators actually type. Unlike
# irrecoverable.sh, PREFIX_WRAPPERS below has no xargs/docker-exec unwrap, so
# a wrapped form like `echo x | xargs -I{} gh pr merge {}` also isn't caught
# (deep-audit 2026-08-28) — same reasoning: not the ordinary typed path.
set -uo pipefail

# Fast path: skip the python3 cold-start unless both "gh" and "merge" survive
# a light normalize — same optimization idiom as irrecoverable.sh's own
# fast-path (a false positive here just spawns python; safe direction).
_input="$(cat)"
_norm="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ' | tr -d "\"'\\")"
# A backslash-newline continuation splitting "gh" or "merge" itself (e.g.
# "g\<newline>h pr merge 123") turns the \n escape into a space above, so
# neither candidate substring survives and the case below would exit 0
# without ever reaching the python scanner that reassembles it correctly
# -- confirmed live 2026-09-03, GH #126 (same "GH #122 adjacent finding"
# shape already fixed this way in irrecoverable.sh). A second, fully
# whitespace-collapsed variant catches that shape too; a false positive
# here just costs a python spawn, same safe direction as above.
_norm_nows="$(printf '%s' "$_norm" | tr -d '[:space:]')"
# A backtick, $(...) command substitution, or ${x}/$'...'/$@ splice vanishes
# (or resolves to unrelated text) in real bash but survives here as literal
# characters -- "g$(true)h pr merge 123" never contains a contiguous "gh"
# substring under either normalization pass above, so the case below would
# otherwise exit 0 and fully bypass this gate on a real `gh pr merge`-shaped
# command spliced this way (confirmed live 2026-09-03: rc=0, python3 never
# spawned). A raw backslash gets the same treatment for the same reason
# verifier-protect.sh's sibling _has_bs guard (GH #125/#134-adjacent) does:
# multiple backslashes ahead of a JSON-encoded newline can leave a residual
# character the substring match above doesn't expect. Same conservative-
# deferral direction as the sibling fixes in irrecoverable.sh/verifier-
# protect.sh: detect the PRESENCE of a marker on the RAW input and refuse the
# fast-allow regardless of what the substring match finds, rather than
# resolving/stripping the marker here -- python3's own tokenizer is a
# separate, deeper question and does not itself resolve command-substitution
# splicing (out of scope here, same as GH #129 for the sibling gates).
# Tradeoff: this moves merge-door.sh from "fast-exit unless gh+merge
# substrings survive" to "python3 spawns on any $/backtick/backslash
# command" -- a meaningfully larger share of real commands than the narrow
# gh+merge substring test above, since $ and backslash both appear in
# ordinary non-merge commands too. Accepted: a false positive here only
# costs a python3 cold start, never a wrong verdict.
_defer=0
case "$_input" in *\\*|*'`'*|*'$'*) _defer=1 ;; esac
case "$_norm$_norm_nows" in
  *gh*merge*) : ;;                    # candidate -> python
  *) [ "$_defer" -eq 1 ] || exit 0 ;; # no candidate token, but a splice marker is present -> defer to python
esac

# Portability guard (#93): announced fail-open when python3 is missing;
# doctrine-bootstrap.sh names the missing dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — merge-door gate cannot run; allowing (install python3 to restore the gh pr merge ask)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
printf '%s' "$_input" | python3 -c '
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
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
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

cmd = _strip_heredocs(d["tool_input"].get("command", ""))

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
# downstream (shlex.shlex(..., commenters="#") default). SQ is the
# single-quote constant already defined above; DQ is its double-quote
# counterpart, scoped here since nothing else in this file needs it.
# Ported VERBATIM (state-machine body unchanged) from the same-named
# function in irrecoverable.sh.
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
# Fixed-point iteration (capped at 5 passes) handles nesting
# ("$(echo $(date))"). A dispatch-FLAG splice and a paren crossing INSIDE
# $(...) are both out of scope here, same as in irrecoverable.sh -- this
# pass only re-derives which candidate name a garbled DISPATCH token might
# be, it does not re-scan already-clean flag/argument tokens, and it stays
# a mechanical scan, not a parser. Bare $VAR/$@/$* are never touched.
PH = "\x01"
def _blank_substitutions(s):
    bodies = []

    def _scan_once(s):
        out = []
        in_squote = in_dquote = False
        i, n = 0, len(s)
        while i < n:
            c = s[i]
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
            if c == "`":
                j = s.find("`", i + 1)
                if j != -1:
                    bodies.append(s[i + 1:j])
                    out.append(PH)
                    i = j + 1
                    continue
            elif c == "$" and s[i + 1:i + 2] == "(":
                j = i + 2
                while j < n and s[j] not in "()":
                    j += 1
                if j < n and s[j] == ")":
                    bodies.append(s[i + 2:j])
                    out.append(PH)
                    i = j + 1
                    continue
            elif c == "$" and s[i + 1:i + 2] == "{":
                j = i + 2
                while j < n and s[j] not in "{}":
                    j += 1
                if j < n and s[j] == "}":
                    out.append(PH)
                    i = j + 1
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
        s = s + " ; " + " ; ".join(bodies)
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
try:
    # _blank_substitutions must run BEFORE shlex ever sees the command:
    # without it, an unresolved "(...)" span gets read by punctuation_chars
    # as real grouping operators, splitting a window apart mid-splice --
    # the placeholder byte PH added to wordchars below is what lets a
    # blanked span fuse into its surrounding token instead.
    lex = shlex.shlex(_blank_substitutions(_newlines_to_seps(cmd)), posix=True, punctuation_chars=True)
    lex.wordchars += PH
    tokens = list(lex)
except ValueError:
    # This file has no deny outcome -- ask is the only fail-closed option
    # available. The old fallback re-tokenized cmd.split() on the raw,
    # PRE-BLANKING string -- PH was never in it, so a spliced dispatch
    # token built this way could never match a candidate, making the whole
    # placeholder mechanism inert (the exact bypass shape already found and
    # fixed in irrecoverable.sh own GH #129 work).
    emit_ask(
        "merge-door: could not safely tokenize this command (unbalanced "
        "quote or substitution) -- approve it manually, or use mh:ship-merge "
        "for the reviewed path."
    )
    sys.exit(0)
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

def basename(p):
    return p.rsplit("/", 1)[-1]

PREFIX_WRAPPERS = {"env", "command", "nohup", "nice", "time", "sudo"}

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
# shape all silently allowed). Stripping a leading placeholder before every
# shape test below assumes the conservative (still-a-wrapper-token)
# resolution -- same direction as the rm -rf fix in irrecoverable.sh -- so a
# token that becomes flag-shaped or VAR=value-shaped once the substitution
# is assumed empty is treated as that flag/assignment and skipped, keeping
# the unwrap loop aligned on the real wrapped command.
def _window_is_merge_dispatch(w):
    # Runs the unwrap-then-trio-check pipeline against one window and
    # reports match/no-match instead of asking directly -- factored out so
    # the driving loop below can run this SAME logic a second time against a
    # compacted window (see _drop_bare_vanish_tokens), not just once against
    # the raw one.
    if not w:
        return False
    argv0, rest = basename(w[0]), w[1:]

    while rest and argv0 in PREFIX_WRAPPERS:
        if argv0 == "env":
            i = 0
            while i < len(rest):
                t = rest[i].lstrip(PH)
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
            while i < len(rest) and rest[i].lstrip(PH).startswith("-"):
                t = rest[i].lstrip(PH)
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
            # gh pr merge 123" still bypassed this gate after that fix).
            # Other sudo flags that also take a value (-p, -C, -R, -T, -U)
            # are not modeled here -- a bundle mixing one of those with
            # u/g (e.g. "-pu") is an accepted non-goal, same tier as the
            # habit-guard-not-adversarial-sandbox stance this file already
            # takes in its header comment above.
            LONG_VALUE_FLAGS = {"--user", "--group"}
            i = 0
            while i < len(rest):
                t = rest[i].lstrip(PH)
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
            while i < len(rest) and rest[i].lstrip(PH).startswith("-"):
                i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]

    # GH #129-shaped duplication (ported from irrecoverable.sh, adapted to
    # 3 dispatch positions): this gate dispatches on argv0 AND the two
    # tokens right after it ("pr"/"merge"), so a splice landing on any of
    # the 3 is an equally live bypass -- each position tries its own fixed
    # candidate whenever it carries a PH byte (a real, non-spliced token is
    # tried as-is), and any resulting combination that completes the
    # ("gh", "pr", "merge") trio counts as a match.
    if len(rest) >= 2:
        GH, PR, MERGE = "gh", "pr", "merge"
        argv0_c = (GH,) if PH in argv0 else (argv0,)
        rest0_c = (PR,) if PH in rest[0] else (rest[0],)
        rest1_c = (MERGE,) if PH in rest[1] else (rest[1],)
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
# those already resolve correctly via lstrip(PH) and must not be touched
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
def _drop_bare_vanish_tokens(w):
    return [t for t in w if t.strip(PH) != ""]

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
' "$(dirname "$0")/lib"
