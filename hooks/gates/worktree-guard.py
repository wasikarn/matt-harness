#!/usr/bin/env python3
# ponytail: generic worktree guard (moved from dotfiles 2026-07-02). Redirects Edit/Write on
# a SUB-repo's main checkout so parallel terminals can't clobber one shared working tree.
# Branch alone can't fix this — one repo dir = one working tree regardless of branch; the
# worktree is the isolation. Auto-creates a session-scoped worktree under WT_ROOT and
# transparently redirects the edit there via PreToolUse updatedInput.
# ponytail: branch name is `wip/<session-id>` — session_id is the only stable identifier
# this hook has. Rename the branch to your ticket key before opening a PR.
# Base selection: MH_WORKTREE_BASE=<branch> fetches origin/<branch> and bases the
# auto-worktree there (hotfix sessions: MH_WORKTREE_BASE=main). Unset = current HEAD of
# the main checkout, which can lag origin; prefer an explicit worktree for hotfix work.
# Fetch failure falls back to HEAD — never blocks editing on network.
# Guarded workspace is opt-in and unset by default: MH_GUARDED_WORKSPACE has NO default,
# so this gate is a total NO-OP for every project unless the operator sets it (this is a
# public plugin — no client/workspace path ships in this file). Exempt even when set: the
# workspace-root repo itself (docs/standups/plans).
# Fails OPEN on any error. Escape: MH_ALLOW_MAIN_EDIT=1.
# Test seams: MH_GUARDED_WORKSPACE / MH_WORKTREE_ROOT override the default roots.
# Bash coverage (2026-07-16): the Write/Edit/NotebookEdit matcher never sees a
# Bash-mediated write (echo >>, sed -i, tee, cp/mv) to a protected checkout —
# the same blind spot verifier-protect.sh closed for the verifier surfaces on
# 2026-07-03. bash_write_targets() below is a straight port of that gate's
# generator. Unlike the Write/Edit path, a raw shell command's target can't be
# transparently rewritten via updatedInput, so the Bash branch denies (exit 2)
# instead of auto-redirecting — this must not be weaker than the Write path's
# unconditional redirect, or the gap this fix closes reopens on the Bash side.
import json, os, re, shlex, subprocess, sys

WORKSPACE = os.path.expanduser(os.environ.get("MH_GUARDED_WORKSPACE", ""))
WT_ROOT = os.path.expanduser(os.environ.get("MH_WORKTREE_ROOT", "~/.worktrees"))
PROTECTED = {"main", "master", "develop"}


def git(args, cwd):
    # 5s: only ever called for a local, no-network rev-parse (see call site) —
    # generous margin over that, not tuned empirically.
    try:
        return subprocess.run(["git", "-C", cwd, *args],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


def git_ok(args, cwd):
    # 15s vs git()'s 5s: this one's call sites are `fetch origin` (network) and
    # `worktree add` (filesystem work), both slower than a local rev-parse —
    # deliberate split, not arbitrary drift, though neither number is
    # empirically tuned.
    try:
        r = subprocess.run(["git", "-C", cwd, *args],
                            capture_output=True, text=True, timeout=15)
        return r.returncode == 0
    except Exception:
        return False


def nearest_dir(path):
    d = path if os.path.isdir(path) else os.path.dirname(path)
    while d and not os.path.isdir(d):
        d = os.path.dirname(d)
    return d or "/"


def under(path, root):
    try:
        return os.path.commonpath([os.path.realpath(path), os.path.realpath(root)]) == os.path.realpath(root)
    except ValueError:
        return False  # different drives / relative mismatch


# Delimiter is any run of non-whitespace, non-quote characters -- bash allows
# hyphens/dots/etc (e.g. <<MY-EOF), not just \w. A too-narrow match here is
# worse than not stripping at all: see the "not found" branch below for why.
_HEREDOC_RE = re.compile(r"<<(-)?\s*(['\"]?)([^\s'\"]+)\2")
_ANSI_C_QUOTE_RE = re.compile(r"\$'((?:[^'\\]|\\.)*)'")


def _strip_heredocs(cmd):
    """Remove heredoc bodies before shlex tokenization. shlex has no concept of
    heredoc syntax and mis-tokenizes on any quote character inside body text --
    heredoc bodies are literal data until the closing delimiter line, not shell
    syntax subject to quoting rules. Confirmed exploitable: an ordinary heredoc
    whose body contains an English contraction (e.g. "it's") trips shlex's
    global quote-balance check, which then falls back to a quote-blind
    cmd.split() that mangles a quoted, space-containing write target -- letting
    a Bash-mediated write silently bypass this gate (2026-08-04)."""
    lines = cmd.split("\n")
    out, i = [], 0
    while i < len(lines):
        out.append(lines[i])
        m = _HEREDOC_RE.search(lines[i])
        i += 1
        if not m:
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
            # Closing delimiter never matched (a still-unhandled bash quoting
            # form, or the command is truncated). Put the lines we scanned
            # BACK instead of silently discarding them -- confirmed the hard
            # way (2026-08-04): an earlier version of this function ate every
            # remaining line as "body" on a no-match, including a real write
            # statement that followed, which is strictly worse than never
            # stripping at all. Worst case here, shlex sees literal heredoc
            # body text and trips its existing ValueError fallback -- a known,
            # already-handled shape, not a silent content loss.
            out.extend(lines[body_start:i])
    return "\n".join(out)


SQ = chr(39)
DQ = chr(34)
PH = "\x01"  # placeholder byte for a blanked command substitution -- see _blank_substitutions()


def _newlines_to_seps(cmd):
    """A bare newline separates Bash statements exactly like ';' does, but
    shlex's whitespace set includes \\n, so it's swallowed as ordinary
    inter-token whitespace and never lands in SEPS below -- a write-only
    statement on any line but the first is invisible to every argv0-dispatch
    branch. Insert ';' AFTER each real newline (not in place of it) before
    tokenizing -- keeping the real newline matters because shlex's default
    commenters='#' handling calls readline() to skip a comment, which stops
    at (and consumes) the next '\\n' in the stream; replacing every newline
    outright would leave no '\\n' anywhere, so a '#' anywhere in the command
    would swallow everything after it as one giant comment (confirmed
    exploitable 2026-08-04, shipped in v0.68.172). A backslash immediately
    before the newline is a real bash line continuation OUTSIDE a comment or
    single-quoted string (same logical statement, not a separator) -- bash
    removes BOTH characters entirely, joining the two physical lines with
    nothing between them, so this does the same (full removal).

    A REGEX substitution over the raw string cannot make that call correctly,
    because it has no notion of quote or comment state: a bash "#" comment
    always ends at the very next literal newline no matter what precedes it
    (comments get zero escape processing -- backslash count is irrelevant
    there), so a backslash right before that newline has NO continuation
    effect inside a comment, and single-quoted content must pass through
    completely untouched (no continuation stripping at all -- bash treats
    every character between quotes as literal, backslash included). A prior
    version of this function used exactly such a context-blind regex
    (`_LINE_CONT_RE.sub(placeholder, cmd)` then `cmd.replace(placeholder,
    "")`) and, after the GH #124 full-removal fix below, erased a
    backslash-newline pair sitting inside a "#" comment too -- deleting the
    only newline that would have terminated the comment for the downstream
    shlex reader, and swallowing the write statement that followed into the
    same comment window (confirmed live 2026-09-03, a fresh-context review
    of the #124 fix: `echo hello #comment \\<newline>cp evil.sh <protected>`
    silently yielded zero write targets -- worse than pre-#124, which at
    least preserved the newline and denied). The SAME context-blindness also
    already mishandled a backslash-newline pair preceded by ANOTHER
    backslash (e.g. two backslashes right before a comment-terminating
    newline) even before GH #124 existed, since the regex matches only the
    last backslash + newline as one "continuation" and does not know it is
    inside a comment either. Ported char-by-char, quote-and-comment-aware
    from irrecoverable.sh's function of the same name (GH #122/#123's fix
    for the identical shape at that file's own top-level flag checks) --
    this generator needed the same scan, one level deeper inside its own
    idiom dispatch (sed/perl's -i detection, dd's of= prefix check, and even
    an argv0 itself split across a continuation, e.g. "&& \\<newline>tee
    ..." -> argv0 '\\ntee', matching no branch -- all still closed by full
    removal here, same as the regex version's own GH #124 fix). Double-quoted
    content still gets the same full-removal continuation treatment bash
    itself applies there, but a "#" inside double quotes is never a comment
    marker."""
    out = []
    in_squote = in_dquote = in_comment = False
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if in_comment:
            if c == "\n":
                # comment ends at the literal newline, same as bash -- emit
                # the same "; " separator a normal newline gets so the
                # window that follows still splits off correctly.
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
            if c == "\\" and i + 1 < n and cmd[i + 1] == "\n":
                # real continuation inside a double-quoted string: bash
                # strips backslash-newline here too (same full removal as
                # the unquoted case below), so nothing is appended.
                i += 2
                continue
            if c == "\\" and i + 1 < n and cmd[i + 1] in (DQ, "\\", "$", "`"):
                out.append(c); out.append(cmd[i + 1])
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
        elif c == "\\" and i + 1 < n and cmd[i + 1] == "\n":
            # real line continuation: bash removes the backslash AND the
            # newline entirely, joining the two lines with nothing at all
            # between them -- so nothing is appended here (GH #124).
            i += 2
        elif c == "\\" and i + 1 < n:
            # any other backslash-escaped pair -- consumed together so the
            # escaped character is never re-examined as an unescaped
            # hash/quote marker.
            out.append(c); out.append(cmd[i + 1])
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


def _normalize_ansi_c_quotes(cmd):
    # shlex doesn't understand bash's ANSI-C quoting ($'...') -- it splits on
    # the bare $ instead of treating the whole span as one token, so a
    # spliced argv0 like $'\x70' never reassembles into the decoded
    # character it resolves to in real bash.
    #
    # This file's dispatch logic below compares argv0 by EXACT STRING
    # (argv0 == "tee", argv0 in ("cp", "mv", "install"), ...) -- a
    # boundary-only rewrite ($'...' becomes a plain '...' token, escapes
    # left raw) is insufficient here: re-wrapping "c$'\x70'" as "c'\x70'"
    # still yields the literal token "c\x70" once glued to a preceding "c",
    # which can never equal "cp". Confirmed exploitable 2026-09-03:
    # `c$'\x70' evil.sh repo1/target.txt` (bash-equivalent to `cp evil.sh
    # repo1/target.txt`) silently bypassed bash_write_targets() (yielded [])
    # before this fix -- same root cause a sibling gate fixed the same
    # session for its own exact-match argv0 dispatch; this is that
    # corrected decode logic ported over (needs no changes itself, only the
    # surrounding names).
    #
    # Bounded escape set, matching what a cp/mv/tee/sed/dd argv0 or write
    # target splice realistically needs: \xHH (hex), \nnn (1-3 octal
    # digits), and the standard single-char escapes \n \t \r \\ \' \".
    # Anything else falls through as its raw two literal characters -- a
    # full ANSI-C decoder is out of scope; those spellings are not
    # realistic splice vectors and an unhandled one just stays a literal
    # (non-matching, safe-direction) token.
    #
    # A literal quote byte can appear in the DECODED result two ways: an
    # explicit \' escape, or an octal/hex escape that happens to resolve to
    # a quote (\047 or \x27, both decimal 39). Either way the byte cannot
    # sit inside the '...' wrapper this function returns -- there is no
    # escape mechanism inside single quotes -- so the decoded text is
    # scanned a SECOND time (after all escapes are resolved, not mid-scan)
    # and any such byte is spliced into the standard bash idiom: close the
    # quote, emit an escaped literal quote OUTSIDE quotes, reopen a new
    # quoted span. Skipping this would leave an unbalanced quote and throw
    # off _newlines_to_seps' own quote-tracking scanner downstream: it
    # opens in_squote at the first quote, never finds a real close, and
    # silently swallows every following newline/write with no separator
    # inserted.
    #
    # A decoded newline (from \n, \012, or \x0a) stays INSIDE the '...'
    # wrapper -- composition order already guarantees this (this function
    # runs BEFORE _newlines_to_seps below), but only because the return
    # value stays fully quoted.
    OCTAL = "01234567"
    HEXDIGITS = "0123456789abcdefABCDEF"
    SIMPLE = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", SQ: SQ, DQ: DQ}

    def _decode(m):
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
    return _ANSI_C_QUOTE_RE.sub(_decode, cmd)


def _blank_substitutions(cmd):
    """Command-substitution placeholder pass (GH #129), ported verbatim (mechanism
    only) from irrecoverable.sh's function of the same name. A backtick/$(...)/
    ${...} span vanishes in real bash once its (possibly empty) output splices into
    the surrounding text -- "gi`true`t" IS "git" once bash evaluates it -- but shlex
    has no concept of this and treats the backticks/parens/braces as literal
    characters, so a spliced argv0 like "c$(true)p" survives tokenization as its own
    garbled token and evades every exact-match dispatch in bash_write_targets()
    (argv0 == "tee", argv0 in ("cp", "mv", "install"), ...). Resolving what a
    substitution actually expands to would mean running a subshell, which no gate in
    this file should ever do -- so this closes it differently, by blanking the whole
    substitution span to one placeholder byte (PH) instead. PH is added to the shlex
    wordchars used in bash_write_targets() so it fuses into the surrounding literal
    text as ONE token instead of splitting it, and any final argv0 token that still
    contains PH is duplicate-classified across every name in KNOWN_WRITE_CMDS
    downstream instead of trusting the garbled literal.

    Fixed-point iteration (not one pass) handles nesting: "$(echo $(date))" blanks
    the innermost $(date) on pass 1, leaving "$(echo PH)", then blanks that on pass
    2. Capped at 5 iterations -- this gate has no business looping on adversarial
    nesting depth, and 5 covers every realistic hand-typed case.

    Blanking a span must not DISCARD its body. "(" and ")" are already grouping
    operators in bash_write_targets()'s own SEPS set, so a bare $(...) already splits
    its content into its own window and gets scanned like any other command window --
    a blank-only substitution would erase that body instead of just fusing the
    splice, silently turning a working deny into an allow. So every backtick/$(...)
    body is collected as it is blanked, and re-appended after the fixed-point loop as
    its own ";"-joined statement, restoring the original window-scan coverage on top
    of the new fusion/duplication behavior. ${...} bodies are deliberately NOT
    collected: that form is a parameter expansion (a variable reference), not a
    command -- re-appending its body as a statement would treat a variable NAME as
    if it were a command line, a false-positive shape this pass has no reason to
    invent.

    Telling a real substitution apart from an inert one needs REAL shell quote
    state, not a regex pairing of apostrophe bytes -- a naive regex pairs literal
    single-quote BYTES wherever they fall, with no notion of whether they are really
    opening/closing a shell quote or sitting inert inside a DOUBLE-quoted string. An
    ordinary English contraction (e.g. "it's") used inside real double quotes breaks
    that in both directions: it can pair across a genuine $(...) splice and hide it
    entirely, or pair across a real single-quoted argument and wrongly treat its
    contents as a live command (confirmed live in irrecoverable.sh, 2026-09-03). This
    uses one left-to-right character scan instead, carrying real in_squote/in_dquote
    state and the same backslash-escape parity (\\$, \\`, \\", \\\\ only mean
    anything inside double quotes; any \\X is a literal pair when unquoted; nothing
    is special inside single quotes, which close on the very next single-quote byte
    no matter what it sits next to). A single-quote can only OPEN when not already
    inside a double-quoted string -- a single-quote byte has no special meaning
    inside "..." in real bash, so it is just an ordinary character there, not a
    quote toggle. $(...)/`...`/${...} are only ever recognized as live substitution
    starts when the scan is unquoted or inside a double-quoted string, matching real
    bash exactly and never crossing into a genuine single-quoted span no matter what
    punctuation that span holds.

    Named residual, deliberately not fixed here (same as irrecoverable.sh): this
    scan cannot cross a paren INSIDE $(...) in one pass -- it stops at the first
    unescaped one -- so nested parens/functions inside a single $(...) rely on the
    fixed-point iteration above, not a depth-counting scanner."""
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
                # else: ordinary char while in_dquote, including a bare apostrophe
                # (no special meaning here) -- fall through to the shared
                # substitution-start check below, since $(...)/`...`/${...} ARE
                # live inside double quotes.
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
                # else: fall through to the shared substitution-start check.
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
        new = _scan_once(cmd)
        if new == cmd:
            break
        cmd = new
    if bodies:
        cmd = cmd + " ; " + " ; ".join(bodies)
    return cmd


def _diff_targets(path):
    """Read a diff/patch file and yield the real write targets named in its
    +++ b/<path> headers -- a patch/git-apply/am command's own argv never
    names the file it actually writes; that lives inside the diff content.
    Best-effort: an unreadable path (nonexistent, a stray redirect-operator
    token, a binary diff) is silently skipped, matching this file's own
    documented fail-open behavior on internal errors."""
    try:
        with open(path, "r", errors="ignore") as f:
            for line in f:
                if line.startswith("+++ "):
                    p = line[4:].strip()
                    if p.startswith("b/"):
                        p = p[2:]
                    if p and p != "/dev/null":
                        yield p
    except OSError:
        pass


# Candidate names for the placeholder-splice duplication (GH #129 Step 3): the
# exact set of argv0 basenames the if/elif dispatch chain below actually branches
# on by exact string match. A garbled token containing PH cannot equal any of
# these directly, so every candidate is tried in turn instead of trusting the
# garbled literal.
KNOWN_WRITE_CMDS = ("tee", "sed", "perl", "cp", "mv", "install", "rsync", "tar",
                     "patch", "git", "dd")

# Real single-letter tar operation/option letters (GNU tar short options). Used to
# tell an old-style bundled flag cluster ("xvf") from an ordinary filename that
# merely CONTAINS the letter "x" (e.g. "extract.sh", "fix.txt", "box.tar") -- a
# bare letter-containment check false-denies on any of those once the PH-candidate
# duplication above starts running the tar branch against whatever the real first
# argument happens to be, even when the real argv0 was never tar at all.
_TAR_FLAG_CHARS = "AbBcCdfFgGhijJkKlLmMnNoOpPrRsStTuUvVwWxXzZ"


def _drop_bare_vanish_tokens(rest):
    """Layer 3 fix (found by an independent adversarial reviewer, 2026-09-03,
    distinct from the GH #129 placeholder-splice fixes above): a STANDALONE,
    unquoted word that resolves to empty at runtime -- its own space-separated
    token, nothing else attached -- vanishes entirely in real bash via
    word-splitting, shifting every later token left by one position
    ("git $(true) -C repo1 apply diff" runs as "git -C repo1 apply diff").
    _blank_substitutions cannot know a substitution resolves to empty without
    running it, so it leaves a PH-only token sitting in that position rather
    than removing it, and a FIXED-INDEX read (rest[0] in the git -C check and
    the tar mode-string check below) then reads the wrong token entirely and
    misses the real flag/mode one position later -- a different, narrower gap
    than GH #129: that one duplicates a candidate at a position whose token is
    still there but garbled; this one is about a position whose token is gone.

    Returns a copy of `rest` with every bare-vanish token dropped -- a token
    counts as bare-vanish only when EVERY character in it is the placeholder
    byte (stripping PH from it leaves nothing), never a token that merely
    contains PH glued to real content (a PH-prefixed flag/assignment from the
    GH #129 fix, e.g. "$(true)-C" -> "\x01-C" -- those already resolve
    correctly via lstrip(PH) and must not be dropped here)."""
    return [t for t in rest if t.strip(PH) != ""]


def _tar_extract_targets(rest):
    """tar extract-mode target detection (the mode-string + -C/--directory
    scan), factored out of bash_write_targets' tar branch so the caller can
    run it against both the raw window and the bare-vanish-compacted one --
    see _drop_bare_vanish_tokens."""
    mode_str = rest[0].lstrip(PH) if rest and not rest[0].lstrip(PH).startswith("--") else ""
    mode_body = mode_str.lstrip("-")
    has_extract = (
        bool(mode_body) and all(ch in _TAR_FLAG_CHARS for ch in mode_body)
        and "x" in mode_body
    ) or any(t.lstrip(PH) == "--extract" for t in rest)
    if not has_extract:
        return
    yielded_dir = False
    for j, t in enumerate(rest):
        dt = t.lstrip(PH)
        if dt in ("-C", "--directory") and j + 1 < len(rest):
            yield rest[j + 1]
            yielded_dir = True
            break
        if dt.startswith("--directory="):
            yield dt[len("--directory="):]
            yielded_dir = True
            break
    if not yielded_dir:
        yield "."


def _git_apply_am_targets(rest):
    """git apply/am target detection (the -C dispatch + diff-content scan),
    factored out of bash_write_targets' git branch so the caller can run it
    against both the raw window and the bare-vanish-compacted one -- see
    _drop_bare_vanish_tokens."""
    sub_idx, directory = 0, None
    if len(rest) > 1 and rest[0].lstrip(PH) == "-C":
        sub_idx, directory = 2, rest[1]
    if len(rest) > sub_idx and rest[sub_idx] in ("apply", "am"):
        diff_args = [t for t in rest[sub_idx + 1:] if not t.startswith("-")]
        for t in diff_args:
            yield t
            for target in _diff_targets(t):
                yield os.path.join(directory, target) if directory else target


def bash_write_targets(cmd):
    """Yield candidate file paths a Bash command writes to. Ported from
    verifier-protect.sh's generator of the same name (bounded idiom set:
    redirects, tee, sed -i, cp/mv/install, rsync, tar -x, patch, git apply/am,
    dd of=; not an adversarial sandbox)."""
    cmd = _blank_substitutions(_newlines_to_seps(_normalize_ansi_c_quotes(_strip_heredocs(cmd))))
    lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    # '$' isn't in shlex's default wordchars, so an unquoted redirect
    # target like $HOME/foo splits into two tokens ('$', 'HOME/foo')
    # instead of one -- the caller below then abspath()s the fragment
    # 'HOME/foo' against cwd, never the real expanded path. Confirmed
    # via direct shlex probe (2026-08-04). PH is added alongside it so a
    # blanked substitution span fuses into the surrounding literal text as
    # ONE token instead of splitting on it (see _blank_substitutions above).
    lex.wordchars += "$" + PH
    tokens = list(lex)
    # No except ValueError fallback here (GH #129 companion fix): an unbalanced
    # quote/substitution that survives to this point is ambiguous input this
    # generator cannot safely tokenize, and a naive cmd.split() fallback tokenizes
    # the RAW, pre-fix string -- PH is never in it, so a spliced argv0 built this
    # way can never match a KNOWN_WRITE_CMDS candidate and the whole mechanism goes
    # inert (same bypass shape irrecoverable.sh closed the same way, 2026-09-03).
    # The exception propagates to main()'s Bash-branch handling, which fails
    # closed on it instead -- matching this file's own Bash-path convention of
    # denying rather than guessing on ambiguous input.
    # "(", ")", "{", "}" are grouping operators, not just tokens -- a subshell
    # "(cp x y)" or brace group "{ cp x y; }" never gets its window split at the
    # grouping boundary without them, so "(" or "{" becomes argv0 instead of the
    # real command and no argv0-dispatch branch below ever matches it (silent
    # bypass). Ported from irrecoverable.sh's OPERATORS set (line 276) -- the
    # already-proven, already-shipped form for this identical gap, closed the
    # same day for verifier-protect.sh's own SEPS-equivalent.
    SEPS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}
    windows, cur = [], []
    for t in tokens:
        if t in SEPS:
            if cur:
                windows.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        windows.append(cur)
    for w in windows:
        if not w:
            continue
        argv0 = w[0].rsplit("/", 1)[-1]
        rest = w[1:]
        i = 0
        while i < len(rest):
            t = rest[i]
            if t in (">", ">>", "&>", ">&"):
                if i + 1 < len(rest):
                    nxt = rest[i + 1]
                    # `N>&M` / `>&-` duplicate a file descriptor (e.g. `2>&1`),
                    # they don't name a file — only bare `>&word` does.
                    if not (t == ">&" and (nxt == "-" or nxt.isdigit())):
                        yield nxt
                i += 2
                continue
            if t.startswith(">"):
                yield t.lstrip(">")
                i += 1
                continue
            i += 1
        nonflag = [t for t in rest if not t.startswith("-")]
        # Layer 3 fix input: see _drop_bare_vanish_tokens. Computed once per
        # window (used only by the tar/git branches below, the two confirmed
        # fixed-index-dependent sites) rather than inside each branch.
        #
        # Scoped to `rest` (w[1:]), not the whole window: a bare-vanish token
        # AT argv0 itself ("$(true) tar -xf archive.tar ...") was also
        # checked (2026-09-03) and is not independently exploitable here --
        # argv0 containing PH already routes through the GH #129
        # KNOWN_WRITE_CMDS duplication loop above, and two of those
        # candidates (tee, patch) unconditionally yield every non-flag token
        # in `rest` regardless of position, so the real -C/target value
        # still surfaces as a candidate through one of them even while the
        # tar/git branches' own rest[0] read is misaligned. Verified by
        # differential testing (this fix present vs. reverted): a command
        # shaped this way passes the full test suite either way, so no test
        # can distinguish the two -- adding one would be decoration, not a
        # regression witness (see the test-honesty "distinguishes-or-it-
        # doesn't" rule). Confirmed genuinely necessary only for the two
        # sites below, where the vanish sits AFTER a real, unspliced argv0
        # ("git"/"tar" already correctly identified) -- there, KNOWN_WRITE_CMDS
        # duplication never triggers (PH is not in a real "git"/"tar" token),
        # so no other branch runs at all and the fixed-index misread is the
        # only thing standing between the input and a silent allow.
        rest_compacted = _drop_bare_vanish_tokens(rest)
        # Window-duplication at argv0 (GH #129 Step 3, same shape as
        # irrecoverable.sh's KNOWN_DANGEROUS loop): a garbled argv0 containing PH
        # (a blanked splice, e.g. "cPHp" from "c$(true)p") can never equal any
        # single dispatch name below by exact string match, so it silently matched
        # nothing and the whole idiom chain went inert. When PH is present, run
        # the entire dispatch chain once per KNOWN_WRITE_CMDS candidate name
        # instead of once against the untrustable literal; when absent, run it
        # once as before against the real argv0.
        for argv0 in (KNOWN_WRITE_CMDS if PH in argv0 else (argv0,)):
            if argv0 == "tee":
                for t in nonflag:
                    yield t
            elif argv0 in ("sed", "perl"):
                # PH-prefixed flag (e.g. $(true)-i -> PH-i) must still count as
                # -i -- strip a leading PH before every flag test below. A
                # command substitution resolving to empty sits IMMEDIATELY
                # before the flag's dash in real bash and simply vanishes
                # (`sed $(true)-i ...` really runs as `sed -i ...`), but PH is
                # a literal non-empty placeholder byte, so every startswith("-")
                # / exact-equality test below silently missed it before this
                # fix (confirmed exploitable 2026-09-03, same shape closed the
                # same day in verifier-protect.sh/irrecoverable.sh for their
                # own -i detection).
                if any(t.lstrip(PH) in ("-i", "--in-place") or t.lstrip(PH) == "-i" for t in rest) or \
                   any(t.lstrip(PH).startswith("-i") and t.lstrip(PH) != "-i" for t in rest):
                    skipnext = False
                    for t in rest:
                        if skipnext:
                            skipnext = False
                            continue
                        if t.lstrip(PH) in ("-e", "--expression"):
                            skipnext = True
                            continue
                        if not t.lstrip(PH).startswith("-") and t not in ("-", ""):
                            yield t
            elif argv0 in ("cp", "mv", "install"):
                # PH-prefixed flag (e.g. $(true)-t -> PH-t) must still count as
                # -t -- strip a leading PH before every flag test below, same
                # fix and same root cause as sed/perl -i above (confirmed
                # exploitable 2026-09-03: without this, PH-t fell through every
                # branch below to the nonflag[-1] fallback, landing on a source
                # arg instead of the real destination directory).
                tgt = None
                for j, t in enumerate(rest):
                    dt = t.lstrip(PH)
                    if dt in ("-t", "--target-directory") and j + 1 < len(rest):
                        tgt = rest[j + 1]
                        break
                    if dt.startswith("--target-directory="):
                        tgt = dt[len("--target-directory="):]
                        break
                    if dt.startswith("-") and not dt.startswith("--") and len(dt) > 2:
                        m = re.match(r"^-[a-zA-Z]*t(.+)$", dt)
                        if m:
                            tgt = m.group(1)
                            break
                    if dt.startswith("-") and not dt.startswith("--") and \
                       re.match(r"^-[a-zA-Z]*t$", dt) and j + 1 < len(rest):
                        tgt = rest[j + 1]
                        break
                if tgt is not None:
                    yield tgt
                elif nonflag:
                    yield nonflag[-1]
            elif argv0 == "rsync":
                if nonflag:
                    yield nonflag[-1]
            elif argv0 == "tar":
                # Extract mode writes files into -C/--directory when present.
                # When absent (tar xf a.tar, the common case -- writes into cwd)
                # this used to yield nothing at all, so nothing downstream ever
                # checked it (confirmed 2026-08-04, silent-failure-hunter round
                # 4). "." lets classify()'s existing cwd-relative abspath()
                # resolution catch it, same as every other relative candidate.
                #
                # mode_str must be a REAL tar flag cluster before "x" inside it
                # means extract -- a bare letter-containment check ("x" in
                # mode_str) false-denies on any first argument that merely
                # CONTAINS the letter x once the candidate duplication above
                # starts running this branch against arbitrary unrelated
                # commands (e.g. "extract.sh", "fix.txt", "box.tar" all contain
                # "x" but are never a real -xvf-style flag cluster). Every
                # character of mode_str must be a genuine tar single-letter
                # flag before "x" is checked for -- same bare-letter-
                # containment-to-real-flag-membership fix irrecoverable.sh
                # already needed for its own rm/git clean flag checks.
                # PH-prefixed mode string (e.g. $(true)-xvf -> PH-xvf, or the
                # no-dash legacy form $(true)xvf -> PHxvf) must still count as
                # extract -- strip a leading PH before every test below, same
                # root cause and same fix as sed/perl -i and cp/mv/install -t
                # above. Unlike those, this splice shape doesn't need a literal
                # dash immediately after PH: legacy tar mode strings are bare
                # words with no dash at all, so the leading PH can sit directly
                # in front of the flag letters too (confirmed exploitable
                # 2026-09-03, both forms).
                #
                # A bare-vanish token (e.g. "$(true)" as its own word, not
                # glued to anything -- see _drop_bare_vanish_tokens) vanishes
                # entirely in real bash via word-splitting, shifting the real
                # mode string one position later ("tar $(true) -xf a.tar -C
                # repo1" runs as "tar -xf a.tar -C repo1"). rest[0] then
                # reads the PH-only token itself, which strips to "", so
                # has_extract is False and the WHOLE branch yields nothing at
                # all -- not even the "." implicit-cwd fallback (confirmed
                # exploitable 2026-09-03). Running the same check a second
                # time against the compacted list (rest_compacted) closes
                # this without touching the already-correct PH-glued-flag
                # handling above, which only needs lstrip(PH), not
                # compaction.
                for target in _tar_extract_targets(rest):
                    yield target
                if rest_compacted != rest:
                    for target in _tar_extract_targets(rest_compacted):
                        yield target
            elif argv0 == "patch":
                # patch <file> < diff rewrites <file> in place -- already handled
                # by the plain nonflag yield below. The common multi-file form
                # (patch -pN < diff.patch, or a patch-file arg instead of stdin)
                # names its real targets inside the diff's +++ b/<path> headers,
                # never in argv -- confirmed exploitable 2026-08-04 (silent-
                # failure-hunter round 4): a diff-content scan on every nonflag
                # token closes it, the same technique already used below for git
                # apply/am. -d/--directory relocates where a relative in-diff
                # target actually resolves; without folding it in, classify()
                # would check the wrong path when patch does not run from the
                # guarded repo's own root.
                # -o/-d/--directory (separate-token forms) are deliberately
                # left as raw `t` here, unlike the bundled --directory= form
                # below -- their VALUE is its own token, so even a PH-disguised
                # flag still leaves that value sitting in `nonflag` (yielded
                # unconditionally below) and lands on the same repo either way
                # (classify() is a per-repo verdict, not per-filename).
                # --directory=X bundles flag and value into ONE token, so a
                # PH-disguised prefix hides the whole value -- that form alone
                # needs the lstrip(PH) fix (confirmed exploitable 2026-09-03).
                directory = None
                for j, t in enumerate(rest):
                    if t in ("-o", "--output") and j + 1 < len(rest):
                        yield rest[j + 1]
                    if t in ("-d", "--directory") and j + 1 < len(rest):
                        directory = rest[j + 1]
                    dt = t.lstrip(PH)
                    if dt.startswith("--directory="):
                        directory = dt[len("--directory="):]
                for t in nonflag:
                    yield t
                    for target in _diff_targets(t):
                        yield os.path.join(directory, target) if directory else target
            elif argv0 == "git":
                # git -C <dir> apply/am puts the real subcommand one slot later
                # than a bare "git apply" -- missing this dispatch left the
                # whole -C form invisible to this generator (confirmed 2026-08-04,
                # silent-failure-hunter round 4, folded into the same fix pass
                # since it is the identical apply/am gap one token over). -C also
                # relocates where a relative in-diff target resolves, same as
                # patch's -d/--directory above -- found the hard way: an earlier
                # version of this fix dispatched into the branch correctly but
                # still resolved the diff's own relative path against the hook's
                # cwd, missing the actual -C directory entirely.
                # PH-prefixed -C (e.g. $(true)-C -> PH-C) must still count as
                # -C -- strip a leading PH before the exact-equality test,
                # same root cause as sed/perl -i above. Unlike patch's -d
                # above, there is no redundant nonflag fallback here: the
                # entire apply/am dispatch below is gated behind this one
                # check succeeding, so a bypass here yields nothing at all,
                # not just an unjoined path (confirmed exploitable 2026-09-03).
                #
                # A bare-vanish token (e.g. "$(true)" as its own word, not
                # glued to anything -- see _drop_bare_vanish_tokens) vanishes
                # entirely in real bash via word-splitting, shifting -C one
                # position later ("git $(true) -C repo1 apply diff" runs as
                # "git -C repo1 apply diff"). rest[0] then reads the PH-only
                # token itself, which strips to "" and never equals "-C", so
                # the -C dispatch is missed and sub_idx stays 0 -- rest[0] is
                # then compared to ("apply", "am") too and also fails,
                # yielding nothing at all (confirmed exploitable 2026-09-03).
                # Running the same check a second time against the compacted
                # list (rest_compacted) closes this without touching the
                # already-correct PH-glued "-C" handling above, which only
                # needs lstrip(PH), not compaction.
                for target in _git_apply_am_targets(rest):
                    yield target
                if rest_compacted != rest:
                    for target in _git_apply_am_targets(rest_compacted):
                        yield target
            elif argv0 == "dd":
                # PH-prefixed of= (e.g. $(true)of= -> PHof=) must still count
                # as of= -- strip a leading PH before the prefix test, same
                # root cause as every other site above even though this one
                # isn't a dash flag (confirmed exploitable 2026-09-03).
                for t in rest:
                    dt = t.lstrip(PH)
                    if dt.startswith("of=") and not dt.startswith("of=/dev/"):
                        yield dt[len("of="):]


def classify(fp):
    """fp is an already-abspath'd candidate file path. Returns
    (repo, top, why, branch) if it sits on a protected main checkout
    or protected branch inside the configured guarded workspace, else None
    (out of scope or already safe — a real worktree on a non-protected
    branch). Shared by both the Write/Edit path and the Bash path so they
    can't drift into two different definitions of "protected"."""
    if not WORKSPACE or not os.path.isabs(WORKSPACE):
        return None  # unset/relative MH_GUARDED_WORKSPACE -> gate is off, not "guard cwd"
    if not under(fp, WORKSPACE):
        return None  # other projects untouched
    cwd = nearest_dir(fp)
    # One subprocess instead of four -- `git rev-parse` accepts multiple query
    # flags and prints one line per flag, in argument order. A LATER flag can
    # fail independently while earlier ones still produced output (confirmed:
    # --abbrev-ref HEAD on a commit-less repo still emits a "HEAD" line while
    # exiting non-zero) -- identical to calling each separately. If instead
    # the FIRST flag fails (bare repo, non-worktree cwd -- confirmed via
    # `--show-toplevel` there), git emits nothing for ANY flag: `lines` comes
    # back empty, `top` is "", and the `if not top` check below already
    # short-circuits before `gd`/`common`/`branch` are used -- so that failure
    # mode reaches the same outcome either way, combined or separate. Hook
    # spawn overhead dominates over git's own compute cost here.
    out = git(["rev-parse", "--show-toplevel", "--absolute-git-dir",
               "--git-common-dir", "--abbrev-ref", "HEAD"], cwd)
    lines = out.split("\n") if out else []
    top, gd, common, branch = (lines + ["", "", "", ""])[:4]
    if not top:
        return None  # not a git repo
    if os.path.realpath(top) == os.path.realpath(WORKSPACE):
        return None  # workspace-root docs repo
    if common and not os.path.isabs(common):
        common = os.path.join(cwd, common)
    in_worktree = bool(gd) and bool(common) and os.path.realpath(gd) != os.path.realpath(common)
    repo = os.path.basename(top)
    if in_worktree and branch not in PROTECTED:
        return None
    why = "main checkout" if not in_worktree else f"protected branch '{branch}'"
    return (repo, top, why, branch)


def deny(repo, top, why):
    print(
        f"⛔ {repo}: editing on {why}. Parallel terminals here clobber one working tree.\n"
        f"Create a worktree first (all worktrees live under {WT_ROOT}/):\n"
        f"  git -C {top} worktree add {WT_ROOT}/{repo}-<ticket> -b feature/<ticket>-slug\n"
        f"  cd {WT_ROOT}/{repo}-<ticket>\n"
        f"then re-run the edit there. One-off override: MH_ALLOW_MAIN_EDIT=1",
        file=sys.stderr,
    )
    return 2


def main():
    if os.environ.get("MH_ALLOW_MAIN_EDIT") == "1":
        return 0
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}

    if tool == "Bash":
        # Gate the new fail-closed tokenize-error handling behind WORKSPACE
        # actually being configured, same early-return-when-unconfigured pattern
        # classify() already uses. classify() alone can't cover this: it only
        # runs once bash_write_targets() has yielded a candidate, and an
        # ambiguous command can now raise ValueError before ever yielding one.
        # Without this gate, that would make an opt-in-only, unset-by-default
        # gate start denying Bash globally, violating its documented total-no-op
        # contract for every project that never set MH_GUARDED_WORKSPACE.
        if not WORKSPACE or not os.path.isabs(WORKSPACE):
            return 0
        cmd = ti.get("command", "") or ""
        try:
            targets = list(bash_write_targets(cmd))
        except ValueError:
            # Mirrors irrecoverable.sh's own stance on the identical shape: a
            # command this file cannot safely tokenize (unbalanced quote/
            # substitution surviving _blank_substitutions) is denied, not
            # silently allowed -- this gate's Bash path already has no "ask"
            # outcome (see the module docstring), so deny is the fail-closed
            # option available.
            print(
                "⛔ could not safely tokenize Bash command for write-target "
                "scanning (unbalanced quote/substitution) — confirm with user first",
                file=sys.stderr,
            )
            return 2
        for p in targets:
            if not p:
                continue
            # A candidate can still carry a literal '~' or '$VAR' here --
            # tokenization alone doesn't expand it, and os.path.abspath()
            # never does either (it prepends cwd to the literal string
            # instead). Expand both before resolving, or a target that
            # really points inside the guarded workspace never matches
            # classify()'s WORKSPACE check (confirmed 2026-08-04).
            expanded = os.path.expandvars(os.path.expanduser(p))
            result = classify(os.path.abspath(expanded))
            if result is not None:
                repo, top, why, _ = result
                return deny(repo, top, why)
        return 0

    field = "file_path" if "file_path" in ti else ("notebook_path" if "notebook_path" in ti else None)
    fp = ti.get(field) if field else None
    if not fp:
        return 0
    fp = os.path.abspath(fp)
    result = classify(fp)
    if result is None:
        return 0
    repo, top, why, branch = result

    session = data.get("session_id", "")
    if not session:
        return deny(repo, top, why)  # no session id to key a scratch worktree off — ask a human

    slug = session[:8]
    wt_dir = os.path.join(WT_ROOT, f"{repo}-wip-{slug}")
    branch_name = f"wip/{slug}"
    base = os.environ.get("MH_WORKTREE_BASE", "").strip()
    start = ""
    if base and git_ok(["fetch", "origin", base], top):
        start = f"origin/{base}"
    try:
        os.makedirs(WT_ROOT, exist_ok=True)
        if not os.path.isdir(wt_dir):
            add_args = ["worktree", "add", wt_dir, "-b", branch_name] + ([start] if start else [])
            if not git_ok(add_args, top):
                if not git_ok(["worktree", "add", wt_dir, branch_name], top):  # branch already exists
                    return deny(repo, top, why)
        # Normalize both sides to realpath before relpath: fp is os.path.abspath
        # (symlink-preserving, e.g. /var/... on macOS) while git rev-parse
        # --show-toplevel resolves symlinks (/private/var/...). Mixing the two
        # forms makes relpath climb to / and back, yielding a
        # ../../../../../../../../../var/.../ws/repo1/f.txt that points back at
        # the main checkout -- defeating the redirect. Found 2026-07-03 via the
        # test-worktree-guard "main-checkout edit" case on a /var-folders TMP.
        rel = os.path.relpath(os.path.realpath(fp), os.path.realpath(top))
        new_fp = os.path.join(wt_dir, rel)
    except Exception:
        return deny(repo, top, why)

    based_on = start or f"current HEAD ({branch or 'detached'})"
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": (
                f"Auto-redirected off {why} to scratch worktree {wt_dir} "
                f"(branch {branch_name}, base {based_on}). Rename the branch before opening a PR."
            ),
            "updatedInput": {field: new_fp},
        },
        "systemMessage": (
            f"{repo}: redirected edit off {why} -> {os.path.basename(wt_dir)} "
            f"(branch {branch_name}, base {based_on}). For hotfix work base must be the "
            f"production branch — set MH_WORKTREE_BASE=main (or create the hotfix worktree explicitly). "
            f"Rename the branch before opening a PR."
        ),
    }))
    return 0


def _selftest():
    assert under("/a/b/c", "/a/b")
    assert not under("/x/y", "/a/b")
    assert nearest_dir("/nonexistent/deep/path/file.py") == "/"
    ti = {"file_path": "/x.py"}
    assert ("file_path" if "file_path" in ti else "notebook_path") == "file_path"
    ti2 = {"notebook_path": "/x.ipynb"}
    assert ("file_path" if "file_path" in ti2 else "notebook_path") == "notebook_path"
    # 2>&1 duplicates fd 1 into fd 2 — not a write to a file named "1".
    assert list(bash_write_targets("acli jira workitem view TP-1 2>&1")) == []
    assert list(bash_write_targets("cmd >&2")) == []
    assert list(bash_write_targets("cmd >&-")) == []
    # `>&word` (non-digit) IS bash's real "redirect both streams to file" form.
    assert list(bash_write_targets("cmd >&outfile")) == ["outfile"]
    print("selftest ok")


if "--selftest" in sys.argv:
    _selftest()
    sys.exit(0)

sys.exit(main())
