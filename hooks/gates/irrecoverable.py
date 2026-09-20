#!/usr/bin/env python3
import json, os, re, shlex, sys

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

GATE_ID = "gate:bash:irrecoverable"

try:
    d = json.load(sys.stdin)
except Exception:
    d = None

# A malformed payload that reaches this script fails closed (truncated JSON,
# tool_input:null). irrecoverable.sh short-circuits empty stdin and payloads
# with no destructive token before python runs, so those allow by design.
if not isinstance(d, dict) or not isinstance(d.get("tool_input"), dict):
    print("[mh:gate] BLOCKED: malformed PreToolUse payload — failing closed", file=sys.stderr)
    # d may be None or a non-dict here -- pass literals, never d.get(...).
    journal(GATE_ID, None, "deny", None)
    sys.exit(2)

SQ = chr(39)
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
# A heredoc feeding an interpreter is executable code, not inert data -- checked
# against the segment of the line BEFORE "<<" (the command the heredoc feeds).
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")
_ANSI_C_QUOTE_RE = re.compile(r"\$" + SQ + r"((?:[^" + SQ + r"\\]|\\.)*)" + SQ)

def _strip_heredocs(cmd):
    # Heredoc bodies are literal data (a quoted commit message mentioning
    # "rm -rf" must not deny) UNLESS the heredoc is stdin for an interpreter
    # (bash <<EOF / python3 <<EOF), where the body IS code and stays scannable.
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
            # Unmatched closing delimiter: put the scanned lines BACK rather
            # than silently eat a real write statement that followed.
            out.extend(lines[body_start:i])
    return "\n".join(out)

def _normalize_ansi_c_quotes(cmd):
    # shlex does not understand ANSI-C quoting ($SQ...SQ): a spliced argv0 like
    # $SQ\x74SQ never reassembles into the decoded byte. Dispatch below compares
    # argv0 by EXACT string, so the escape must actually be RESOLVED (a
    # boundary-only re-quote still yields the literal token "gi\x74").
    # Bounded escape set: \xHH, \nnn octal, \n \t \r \\ \SQ \DQ; anything else
    # stays a literal (non-matching, safe-direction) pair.
    # A decoded SQ byte (\SQ, \047, \x27) cannot sit inside the SQ...SQ wrapper
    # returned here, so a second pass splices it into the close-escape-reopen
    # idiom -- otherwise the unbalanced quote desyncs _newlines_to_seps.
    # Decoded newlines stay INSIDE the wrapper so _newlines_to_seps (which runs
    # after this) does not read them as statement separators.
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

def _mid_merge():
    # `git add -A|--all|.` is allowed only mid-merge (resolving-merge-conflicts
    # needs it). Checked in the payload cwd, not this process cwd.
    import subprocess
    cwd = d.get("cwd") or os.getcwd()
    try:
        r = subprocess.run(["git", "rev-parse", "-q", "--verify", "MERGE_HEAD"],
                           cwd=cwd, capture_output=True, timeout=3)
        return r.returncode == 0
    except Exception as e:
        # M7 (harness gap-audit, 2026-09-20): a deny caused by this check itself
        # failing (bad cwd, git missing, timeout) looked identical to a genuine
        # "not mid-merge" deny -- no way to tell them apart from the deny message
        # alone. Diagnostic only; the safe-direction return (deny `git add -A`)
        # is unchanged.
        print(f"[mh:gate] irrecoverable: mid-merge check itself failed (cwd={cwd!r}): {e}",
              file=sys.stderr)
        return False

# --- Nested-spawn deny: a subagent (agent_id present) may not spawn a nested
# `claude -p|--print|--agent|--bg|--worktree` session -- it would run as a fresh
# main session with no agent_id. Anchored on a command-start position so prose
# mentions do not trip it; the flag scan is quote-aware so a separator inside a
# quoted prompt does not end it early. re.MULTILINE: a line inside an
# interpreter-fed heredoc body is its own statement.
# GH #152: `claude\b` alone matched mid-token (a path like /tmp/claude-501/...
# contains a word-bounded "claude", since "-" is a non-word char), and the
# forward flag scan did not stop at a newline, so a later unrelated line's
# flag (e.g. `mkdir -p`) got attributed to that false match. Fixed by
# requiring "claude" to end the token -- next char must not be an
# identifier/path-continuation char (word char, "-", ".", "/") -- and by
# treating an unquoted newline as a scan-stopping separator, same as &/;/|.
# A code-review round on the first attempt caught two dangerous-direction
# regressions before ship, both since covered by tests below: (1) an
# allowlist-shaped exclusion (only \s;&|) rejected legitimate shell
# metacharacters too, e.g. missing `claude>out.log -p x`; a denylist of
# continuation chars is the correct shape. (2) a bare newline-stops-scan rule
# also stopped at a backslash-continued newline (`claude \` + real newline +
# `-p`), which is still ONE shell statement -- the scan now treats a
# `\`-then-newline pair as non-breaking, matching how a real shell (and this
# file's own _newlines_to_seps, used elsewhere) treats line continuations.
# ponytail: only single-backslash continuation is tracked, not escape parity
# (`\\` + newline, an even count, is NOT a continuation in real bash but is
# treated as one here) -- habit-guard, not adversarial sandbox, same posture
# as this file's other documented one-level-only unwraps.
# ponytail: `cat <<EOF | bash` bodies are stripped as inert and not scanned,
# add heredoc-body scanning if a nested-spawn bypass via heredoc is ever demonstrated.
#
# 2026-09-20 audit: a prefix wrapper (env/command/sudo/nice/nohup/time, singly
# or chained -- "env sudo claude -p x") sat between the anchor and "claude"
# with nothing to match it, so the anchor never fired and the deny below
# never ran -- live-confirmed. A bare `\claude` (backslash suppresses alias
# lookup in real bash; the command itself is unaffected) had the same gap.
#
# Fix: an allowance matched against this file's own PREFIX_WRAPPERS word list
# (below), not a generic "any token" skip -- a generic skip was tried first
# and reverted: it made this anchor match `claude` wherever it next appeared,
# including deep inside an unrelated command's quoted argument (broke the
# existing `git commit -m "mention claude -p in docs"` -> ALLOW regression
# test in tests/hooks/test-gates.sh, since this anchor runs on the raw
# command text, not the quote-masked string subagent-git-guard.py's sibling
# anchor uses). Matching only real wrapper WORDS keeps that same precision:
# "git", "commit", "-m", or a quoted-string token never satisfy the
# alternation, so an anchor attempt from string-start still requires
# "claude" immediately, exactly as before this fix.
#
# 2026-09-20 fix-round 2 (compliance-audit vs the plan above): bounding both
# axes at 3 was itself a deviation from the plan's `*`-repeated design and
# left a real gap -- an independent verifier chained 13 wrappers and got
# past the depth<=3 cap live. The catastrophic-backtracking risk that
# motivated the bound is real for a naive `(?:(?:sudo|env)\s+(?:\S+\s+)*)*`
# (a wrapper word also matches the inner generic token, so the two `*`s
# compete for the same input and multiply out) -- but the fix for that is to
# remove the ambiguity, not cap the length. The inner flag-scan below
# excludes anything that matches a wrapper word via a negative lookahead, so
# any given token is always unambiguously "the next wrapper" or "a flag",
# never a choice between the two. That makes the whole prefix scan O(n) with
# no backtracking blowup, so both axes go back to genuinely unbounded,
# matching the plan ("env -u X FOO=bar sudo nice -n 10 command env claude -p x"
# now anchors regardless of chain length).
PREFIX_WRAPPERS = ("env", "command", "nohup", "nice", "time", "sudo")
_WRAPPER_ALT = r"(?:" + "|".join(PREFIX_WRAPPERS) + r")\b"
_WRAPPER_PREFIX = r"(?:" + _WRAPPER_ALT + r"\s+(?:(?!" + _WRAPPER_ALT + r")\S+\s+)*)*"
_SPAWN_ANCHOR_RE = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*" + _WRAPPER_PREFIX +
    r"\\?(?:\S*/)?claude(?![-\w./])",
    re.MULTILINE,
)
_SPAWN_FLAG_RE = re.compile(r"-p\b|--print\b|--agent\b|--bg\b|--worktree\b")
_SPAWN_TOKEN_RE = re.compile(
    "\"(?:[^\"\\\\]|\\\\.)*\"|" + SQ + "[^" + SQ + "]*" + SQ + "|\\\\+|.", re.DOTALL
)
# C1 (harness gap-audit, 2026-09-20): the outer loop over every anchor match
# times an unbounded inner token scan is O(anchors x remaining-length) -- an
# unclosed "(" after each anchor keeps depth > 0 so the inner scan never
# breaks early, consuming the rest of the string every single time. Live-
# reproduced: 6,000 anchors in a 48,000-char command (well under
# _CMD_LEN_CAP's 150,000) took 22s, far past this gate's own 8s hooks.json
# PreToolUse timeout -- and Claude Code's own hooks reference confirms a
# timed-out PreToolUse command hook lets the tool call continue, so a slow
# enough payload silently bypasses this entire check. Same budget magnitude
# and shared-counter pattern as _blank_substitutions's _DEPTH_SCAN_BUDGET
# above; "return True" (deny) on exhaustion is this file's own documented
# safe direction -- widening the scan can only over-deny, never under-deny.
_SPAWN_SCAN_BUDGET = 2_000_000

def _nested_spawn(c):
    # Deep-audit 2026-09-07: a bare separator (&;|\n) inside a paren/backtick
    # group (command substitution, process substitution, a subshell) is NOT a
    # top-level statement separator for the outer command -- real bash parses
    # the whole group as one unit regardless of what's inside it. depth tracks
    # "(" / ")" nesting (clamped at 0, so a stray unmatched ")" can't go
    # negative and mask a later real "("); in_backtick toggles on each "`".
    # While either is active, a separator only ends the CURRENT token's
    # ordinary handling, never the scan -- widening the scan region is the
    # safe direction for a deny gate.
    #
    # Backslashes outside quotes pair up two-at-a-time in real bash: a RUN of
    # N consecutive backslashes escapes the following character only if N is
    # odd (the trailing, unpaired backslash); an even N means every backslash
    # is a literal and the following character keeps its normal meaning.
    # _SPAWN_TOKEN_RE's own "\\+" alternative captures a whole run as one
    # token so its length can be checked directly, rather than matching one
    # backslash at a time (which can't tell an odd run from an even one).
    # Two Codex-validator rounds, deep-audit 2026-09-07, both reproduced
    # live: (1) `claude --version \( ; othertool -p` was denied -- an odd
    # (single) escaped "(" is a literal argument character, not a subshell
    # opener, but got miscounted as depth+=1, swallowing the real ";" and
    # crediting othertool's -p back to claude. (2) a first, simpler fix
    # (fixed-length "\\X" pairing, no parity check) then ALLOWED `claude
    # \\`printf x; printf y` -p evil` -- an EVEN (double) backslash before a
    # backtick leaves the backtick unescaped and live in real bash (the pair
    # is just one literal backslash), so it really does open a command
    # substitution carrying -p back to claude; treating the backtick as
    # escaped there was a false ALLOW, a real bypass, not just an
    # over-cautious false DENY. Parity tracking fixes both directions.
    work = 0  # shared across every anchor's scan, never reset per-anchor -- see _SPAWN_SCAN_BUDGET above
    for m in _SPAWN_ANCHOR_RE.finditer(c):
        buf, depth, in_backtick = [], 0, False
        escape_next = False    # trailing backslash of an odd-length run
        after_backslash = False  # any backslash run, odd or even, just seen
        for tok in _SPAWN_TOKEN_RE.finditer(c[m.end():]):
            work += 1
            if work > _SPAWN_SCAN_BUDGET:
                return True
            t = tok.group()
            if t and t.count("\\") == len(t):
                buf.append(t)
                escape_next = len(t) % 2 == 1
                after_backslash = True
                continue
            if t == "\n" and (escape_next or after_backslash):
                # Any backslash run right before a real newline keeps the
                # scan going, regardless of parity -- this file's own
                # deliberate safe-direction precedent for a deny gate (an
                # even count is not a true continuation in real bash, but
                # treating it as one is the safe direction: it can only
                # widen the scan, never narrow it past a real spawn).
                buf.append(t)
                escape_next = after_backslash = False
                continue
            if escape_next:
                buf.append(t)
                escape_next = after_backslash = False
                continue
            after_backslash = False
            if t == "(":
                depth += 1
            elif t == ")":
                depth = max(0, depth - 1)
            elif t == "`":
                in_backtick = not in_backtick
            elif len(t) == 1 and t in "&;|\n" and depth == 0 and not in_backtick:
                break
            buf.append(t)
        if _SPAWN_FLAG_RE.search("".join(buf)):
            return True
    return False

if ("agent_id" in d) and _nested_spawn(cmd):
    print("[mh:gate] BLOCKED: a subagent may not spawn a nested Claude Code session via Bash "
          "(claude -p/--print/--agent/--bg/--worktree) -- only the main session dispatches",
          file=sys.stderr)
    journal(GATE_ID, d.get("tool_name"), "deny", d.get("session_id"))
    sys.exit(2)

def deny(reason):
    print("[mh:gate] BLOCKED: " + reason, file=sys.stderr)
    journal(GATE_ID, d.get("tool_name"), "deny", d.get("session_id"))
    sys.exit(2)

def delete_hint():
    # trash is not stock on macOS or Linux -- offer whichever CLI exists.
    import shutil
    t = next((c for c in ("trash", "trash-put") if shutil.which(c)), None)
    if t:
        return "use " + t + " instead"
    return ("no trash CLI on this machine — ask the user before a destructive "
            "delete, or install one (macOS: brew install trash; Linux: trash-cli)")

# Tokenize respecting quotes so quoted free text stays one token.
# ponytail: no command-substitution unwrapping (bash -c / eval get one level) -- habit-guard, not sandbox,
# add recursive unwrapping if a real bypass nests bash -c/eval more than one level deep.
# Newlines are command separators in bash but shlex eats them as whitespace,
# so a literal ";" is inserted after each real newline. A backslash-newline is
# a line continuation: both chars are removed entirely so the next token joins
# cleanly (a residual "\n--force" would miss the exact-match flag check).
# Inside a "#" comment the newline still ends the comment (a trailing backslash
# has no continuation effect there), so it still gets the separator. Comment
# and quote state are tracked char by char with backslash-escape parity.
DQ = chr(34)
def _newlines_to_seps(s):
    out = []
    in_squote = in_dquote = in_comment = False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_comment:
            if c == "\n":
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
                # continuation inside double quotes: bash strips both chars
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
            # real line continuation: both chars removed, nothing appended
            i += 2
        elif c == "\\" and i + 1 < n:
            # any other escaped pair is consumed together so the escaped char
            # is never re-examined as a hash/quote marker
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

# Command-substitution placeholder pass. A backtick/$(...)/${...} span vanishes
# in real bash once its output splices in ("gi`true`t" IS "git"), but shlex
# keeps the punctuation literal, so a spliced argv0 evades exact-match dispatch.
# Resolving the substitution would mean running a subshell, so instead the span
# is blanked to one placeholder byte (PH): PH is a shlex wordchar so it fuses
# into the surrounding text as ONE token, and any argv0/subcommand token still
# containing PH is duplicate-classified across every KNOWN_DANGEROUS /
# KNOWN_GIT_SUBS candidate downstream.
# Closer-search depth-counts same-type brackets so nested spans ("$(echo
# $(date))", "$(f() { :; }; f)") resolve in one pass; the fixed-point loop stays
# as defense-in-depth. Out of scope: a bracket hidden behind a quote/escape
# boundary INSIDE the span (quotes tracked at top level only).
# Each downstream flag comparison strips PH itself (full .replace, not a
# leading-only strip: a mid-flag PH like --for<PH>ce is an exact-match bypass).
# Blanking must not DISCARD the body ("$ (git push --force)" is a real deny), so
# every backtick/$(...) body is re-appended as its own statement; ${...} bodies
# are not (parameter expansion, not a command). Single-quoted spans are never
# blanked; double-quoted $(...) IS live in bash -- telling them apart needs the
# real quote-state scan below, not a regex. A span inside a "#" comment passes
# through unchanged.
PH = "\x01"
# Work budget for the depth-counting closer-search, charged per character
# walked and shared across one _scan_once call: without it, a flood of unclosed
# "$(" starts is O(n^2) (65s on a 100,000-char payload under the length cap).
# Exhaustion leaves the span un-blanked -- exactly the bypass shape -- so it is
# recorded here (mutated, not rebound) and denied once after tokenization,
# never reset across the primary and fallback calls.
_DEPTH_BUDGET_BLOWN = [False]
_DEPTH_SCAN_BUDGET = 2_000_000
def _blank_substitutions(s):
    bodies = []

    # One left-to-right pass with real quote/comment state; collects
    # backtick/$(...) bodies (never ${...}) into the shared `bodies` list.
    def _scan_once(s):
        out = []
        in_squote = in_dquote = in_comment = False
        i, n = 0, len(s)
        depth_work_used = [0]
        while i < n:
            c = s[i]
            if in_comment:
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
                # else: fall through -- substitutions ARE live inside double quotes
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
        # A real "\n" before each body ends any open "#" comment (a plain " ; "
        # join let a trailing comment swallow every appended body).
        s = s + "\n; " + "\n; ".join(bodies)
    return s

# shlex.split() only recognizes ;/&&/||/|/& as separators when whitespace
# surrounds them ("echo hi;rm -rf x" glued "hi;rm"); punctuation_chars=True
# splits them out as their own tokens while respecting quotes. ( ) { } get the
# same treatment so "(rm -rf x)" / "{ rm -rf x; }" do not leave "(" as argv0.
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}

# shlex cost is superlinear in the longest SINGLE token (700k chars blows a 2s
# timeout), so an oversized command denies on length ALONE before shlex runs.
_CMD_LEN_CAP = 150_000
if len(cmd) > _CMD_LEN_CAP:
    deny("command too long to safely tokenize (" + str(len(cmd)) + " chars, cap " + str(_CMD_LEN_CAP) + ") - confirm with user first")

try:
    lex = shlex.shlex(_blank_substitutions(_newlines_to_seps(_normalize_ansi_c_quotes(cmd))), posix=True, punctuation_chars=True)
    lex.wordchars += PH
    tokens = list(lex)
except ValueError:
    # Two causes: (1) a genuinely unbalanced quote; (2) the closer-search above
    # does not track quotes INSIDE a span, so a span crossing a quote char
    # desyncs quote state on a valid command. Re-parse the ORIGINAL cmd as a
    # predicate: if it parses, the error is self-inflicted (2) and a separator-
    # aware split of the SAME blanked pipeline is used (never the raw cmd: every
    # downstream PH check assumes blanked tokens, and a bare split glues
    # "};git"). ( ) { } are excluded: inside ${...} they are usually literal.
    # If the original also fails to parse, deny on ambiguity.
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

# A scan that could not finish left a span un-blanked -- deny before dispatch.
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

# A standalone substitution resolving to empty ($(true)) vanishes as a token in
# bash, shifting later tokens left, but leaves a PH-only token here, so every
# fixed-index read (stash args[0], the git subcommand slot) sees the wrong slot.
# Each window is also dispatched as a compacted copy with bare-PH tokens
# dropped; a deny in either copy wins ("$(which git) status" -> ["status"]).
_aug = []
for _w in windows:
    _wc = [_t for _t in _w if not (_t and all(_c == PH for _c in _t))]
    _aug.append(_w)
    if _wc != _w:
        _aug.append(_wc)
windows = _aug

def basename(p):
    return p.rsplit("/", 1)[-1]

# One-level unwrap of `bash|sh|zsh|dash|ksh -c "<body>"` and `eval <body>`: the
# quoted body is a command line, so it is re-tokenized into windows of its own,
# appended to `windows` while the main loop runs (a list picks up items appended
# mid-iteration). Called AFTER the prefix-wrapper unwrap so `sudo bash -c` opens
# too. One level only: only the original windows (index < _N_OUTER) unwrap, so a
# body that itself says `bash -c` is a documented non-goal. The outer tokenizer
# stripped the quotes but blanked substitutions only inside a DOUBLE-quoted body
# (a single-quoted one is inert to the outer shell and live to the inner), so
# the body is blanked again here and its PH tokens duplicate-classify below.
_SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
_N_OUTER = len(windows)

def _unwrap_shell(argv0, rest):
    body = None
    if argv0 in _SHELLS:
        for i in range(len(rest) - 1):
            t = rest[i].replace(PH, "")
            if t.startswith("-") and not t.startswith("--") and "c" in t:
                body = rest[i + 1]
                break
    elif argv0 == "eval" and rest:
        body = " ".join(rest)
    if not body:
        return
    if ("agent_id" in d) and _nested_spawn(body):
        deny("a subagent may not spawn a nested Claude Code session via Bash "
             "(claude -p/--print/--agent/--bg/--worktree), inside bash -c / eval either "
             "-- only the main session dispatches")
    try:
        lex = shlex.shlex(_blank_substitutions(_newlines_to_seps(body)), posix=True, punctuation_chars=True)
        lex.wordchars += PH
        lex.whitespace_split = True
        cur = []
        for tok in list(lex) + [";"]:
            if tok in OPERATORS:
                if cur:
                    windows.append(cur)
                    curc = [t for t in cur if not (t and all(c == PH for c in t))]
                    if curc != cur:
                        windows.append(curc)
                cur = []
            else:
                cur.append(tok)
    except ValueError:
        deny("could not safely tokenize the body of a bash -c / eval string - confirm with user first")
    if _DEPTH_BUDGET_BLOWN[0]:
        deny("command too long to safely tokenize (nested substitution exceeded depth-scan budget) - confirm with user first")

# Candidate names for placeholder-splice duplication: the exact argv0 basenames
# and git subcommands any check below dispatches on by exact string match.
KNOWN_DANGEROUS = ("rm", "find", "git", "dd", "mysql", "psql", "sqlite3", "mariadb")
KNOWN_GIT_SUBS = ("push", "reset", "clean", "restore", "checkout", "switch", "branch", "stash", "commit", "add")

# Duplication also fires on a token still carrying raw substitution syntax
# (belt-and-braces for any path that hands over an unblanked token). Narrow
# single-token check on purpose: a bare "$" would misfire on "$PYTHON -m pytest".
def _has_raw_subst(t):
    return "`" in t or "$(" in t or "${" in t

for _wi, w in enumerate(windows):
    if not w:
        continue
    argv0, rest = basename(w[0]), w[1:]

    # Prefix wrappers unwrap one level per iteration so "env nice rm -rf x" or
    # "sudo rm -rf x" resolve to the real command -- everyday idioms, in scope.
    # env/nice/sudo take flags+values before the wrapped command; command/nohup/
    # time only take bare flags. Every flag test strips PH first: a disguised
    # flag ("env $(true)-u FOO") no longer starts with a dash otherwise.
    # Shared with _SPAWN_ANCHOR_RE's wrapper allowance above (module-level
    # PREFIX_WRAPPERS) -- one definition, not two independently-typed lists;
    # a fix landing in one and not the other is exactly how the agent_id
    # truthiness bug went unnoticed at 3 of 5 real call sites across two
    # separate GH issues (2026-09-20 audit).
    while rest and argv0 in PREFIX_WRAPPERS:
        if argv0 == "env":
            i = 0
            while i < len(rest):
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
            while i < len(rest) and rest[i].replace(PH, "").startswith("-"):
                t = rest[i].replace(PH, "")
                i += 1
                if t == "-n" and i < len(rest):
                    i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        elif argv0 == "sudo":
            # sudo -u/-g take a value: space-joined, "="-joined, attached ("-ualice"),
            # or bundled with getopt semantics ("-nu alice": alice is the value;
            # "-un alice": "n" is the value, alice is the command). -p -C -R -T -U
            # are a non-goal.
            LONG_VALUE_FLAGS = {"--user", "--group"}
            i = 0
            while i < len(rest):
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
            while i < len(rest) and rest[i].replace(PH, "").startswith("-"):
                i += 1
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]

    if _wi < _N_OUTER:
        _unwrap_shell(argv0, rest)

    if argv0 == "xargs":
        # xargs args are never free-text prose, so scanning for a dangerous
        # basename anywhere in them is safe; "git" is included so the git
        # checks fire on the xargs-wrapped form. Full PH removal: a splice can
        # land mid-basename (xargs g$(true)it).
        for j, t in enumerate(rest):
            if basename(t).replace(PH, "") in ("rm", "find", "dd", "git"):
                argv0, rest = basename(t), rest[j + 1:]
                break
    elif argv0 == "docker" and rest and rest[0].replace(PH, "") == "exec":
        # "docker exec <flags> <container> <cmd...>" re-points argv0 to the
        # inner command so the SQL check fires on a containerized client.
        j = 1
        while j < len(rest) and rest[j].replace(PH, "").startswith("-"):
            j += 1
        if j < len(rest):
            j += 1  # skip the container name/id
        if j < len(rest):
            argv0, rest = basename(rest[j]), rest[j + 1:]

    for argv0 in (KNOWN_DANGEROUS if (PH in argv0 or _has_raw_subst(argv0)) else (argv0,)):
        if argv0 == "rm":
            # Lowercase so "rm -Rf" matches. A SHORT bundled cluster counts
            # per-character; a LONG option only on exact --recursive/--force
            # (bare letter membership across long flags false-positived on
            # "--before=1" once candidate duplication ran this on any command).
            has_r = has_f = False
            for t in rest:
                # "$(true)-rf" IS "-rf" in bash but blanks to "PH-rf", which no
                # longer starts with "-" -- strip PH, assume the dangerous
                # (empty-substitution) resolution.
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

        # Same PH-erases-flag-shape fix as the rm block ("find $(true)-exec").
        if argv0 == "find" and any(t.replace(PH, "") in ("-exec", "-execdir") for t in rest) and "rm" in [basename(t) for t in rest]:
            deny("find -exec/-execdir rm detected — destructive delete; " + delete_hint())
        if argv0 == "find" and any(t.replace(PH, "") == "-delete" for t in rest):
            deny("find -delete detected — destructive delete; " + delete_hint())

        # 2026-09-20 audit: git accepts any unambiguous prefix of a long
        # option ("--no-veri" for "--no-verify"); the exact-string checks
        # below missed it -- live-confirmed to actually execute
        # (--no-veri/--ha/--amen/--forc/--discard-ch/--del all ran for real).
        # `git push --forc` is NOT exploitable this way: git itself rejects
        # it as ambiguous with --force-with-lease/--force-if-includes, so
        # the push check below is untouched.
        def _is_flag(token, *long_forms):
            # Checked only against the SPECIFIC long form(s) given at each
            # call site below, never a global git-flag list -- so this
            # cannot itself confuse "--force" with an unrelated flag.
            # Confirmed safe against this file's own documented noisy
            # neighbors (--find-renames, --format=fuller, --force-with-lease,
            # --force-if-includes): none is a prefix of any long form checked
            # here, and a longer arg can never satisfy long_form.startswith().
            # A false-positive abbreviation only costs an extra deny/
            # confirmation -- the safe direction for this gate
            # (operating-model.md's fail-closed principle).
            #
            # compliance-audit fix-round 2, 2026-09-20: an independent
            # verifier flagged this as not "establishing unambiguity" (e.g.
            # denying `commit --no`, `branch --fo`) and claimed `--n` /
            # `--force=` slip through unguarded. Empirically re-checked
            # against real git: `--n` and every 2-3-char `=value`-suffixed
            # abbreviation tested at the time was ALWAYS rejected by git
            # itself (ambiguous, or "option takes no value") -- but that
            # check missed the shorter, plain (no `=`) 2-char-after-`--`
            # shape entirely, since the len()>3 guard below excluded it from
            # ever being checked in the first place, regardless of what git
            # would do with it.
            #
            # deep-audit fix-round 3, 2026-09-20: that gap was real and
            # live -- `git reset --h` and `git clean --f` are BOTH accepted
            # by real git as unambiguous (only one long option starts with
            # "h"/"f" for each of those subcommands) and actually executed
            # destructively, while this gate's old len()>3 guard never even
            # checked them. Fixed by lowering the guard to len()>2 (still
            # excludes a bare "--", which has no letters to be an
            # abbreviation of anything). This does NOT reintroduce the
            # already-git-rejected forms as a gap: those still fail on the
            # `long_form.startswith(token)` check itself (git's own
            # ambiguity has no bearing on that), so lowering the length
            # floor only newly catches tokens that are BOTH short and an
            # exact prefix of one specific named long form -- the same
            # narrow, call-site-scoped match this helper always made, one
            # character shorter.
            return token.startswith("--") and len(token) > 2 and any(
                lf.startswith(token) for lf in long_forms
            )

        if argv0 == "git" and rest:
            # --no-verify skips pre-commit/pre-push hooks; checked per window (a
            # global check over `tokens` only saw the last line). Git-specific
            # so `echo "--no-verify"` does not false-positive.
            if any(_is_flag(t.replace(PH, ""), "--no-verify") for t in w):
                deny("--no-verify bypasses safety hooks")
            # -c core.hooksPath=<path> (split or joined "-ccore.hooksPath=X")
            # re-points git at a different hooks dir -- same bypass as
            # --no-verify. Only a non-empty value trips it.
            # Case-insensitive key match (git config keys are case-insensitive;
            # `-c core.hookspath=` re-points hooks exactly like the canonical
            # spelling, live-confirmed) -- only the KEY is lowercased for the
            # comparison, the captured VALUE keeps its original case. The
            # sibling `config` subcommand branch two arms below already does
            # this; this arm predated it and was missed.
            hooks_path_val = None
            for idx, t in enumerate(w):
                t_pf = t.replace(PH, "")
                if t_pf == "-c" and idx + 1 < len(w):
                    nxt = w[idx + 1]
                    key, _, val = nxt.partition("=")
                    if key.lower() == "core.hookspath" and val:
                        hooks_path_val = val
                elif t_pf.startswith("-c"):
                    key, _, val = t_pf[2:].partition("=")
                    if key.lower() == "core.hookspath" and val:
                        hooks_path_val = val
            if hooks_path_val:
                deny("-c core.hooksPath=<path> re-points git at a different hooks dir — same bypass as --no-verify")
            # Walk past leading global flags so ` git -C /repo push --force`
            # (or -Cpath, --no-pager) does not set sub="-C" and bypass the gate.
            GIT_VALUE_GLOBALS = {"-C", "-c", "--git-dir", "--work-tree", "--config-env"}
            i = 0
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
            # drop the value token after a free-text flag so message content
            # (e.g. "commit -m ...rm -rf...") is never pattern-matched.
            scan, skip = [], False
            for t in args:
                if skip:
                    skip = False
                    continue
                if t.replace(PH, "") in ("-m", "--message"):
                    skip = True
                    continue
                scan.append(t)
            # "$(true)--force" IS "--force" in bash but blanks to "PH--force";
            # strip PH once here so every sub == "..." branch below sees the
            # flag shape.
            scan = [t.replace(PH, "") for t in scan]

            for sub in (KNOWN_GIT_SUBS if (PH in sub or _has_raw_subst(sub)) else (sub,)):
                if sub == "push" and any(
                    t in ("-f", "--force") or (t.startswith("--force") and not t.startswith(("--force-with-lease", "--force-if-includes")))
                    or (t.startswith("-") and not t.startswith("--") and "f" in t)
                    or t.startswith("+")  # "+refspec" force-pushes without a -f/--force flag
                    for t in scan
                ):
                    deny("git push --force overwrites remote history — needs explicit user approval (use --force-with-lease for the safe variant)")
                # `git config core.hooksPath X` / --unset disables pre-commit and
                # pre-push (same bypass class as --no-verify). The documented
                # wiring value `git-hooks` stays allowed.
                if sub == "config" and any(t.lower() == "core.hookspath" for t in scan) and "git-hooks" not in scan:
                    deny("git config core.hooksPath rewires/disables the repo git hooks — only `git config core.hooksPath git-hooks` is allowed")
                if sub == "reset" and any(_is_flag(t, "--hard") for t in scan):
                    deny("git reset --hard discards uncommitted work — confirm with user first")
                # SHORT bundled cluster counts per-character, LONG option via
                # _is_flag's prefix match (bare containment false-positived on
                # "--find-renames" / "--format=fuller" under candidate duplication --
                # _is_flag is safe against both, see its own docstring above).
                if sub == "clean" and any(
                    _is_flag(t, "--force") or (t.startswith("-") and not t.startswith("--") and "f" in t)
                    for t in scan
                ):
                    deny("git clean -f deletes untracked files — confirm with user first")
                # git restore: default mode and --worktree target the WORKTREE
                # (unrecoverable); --staged alone targets the INDEX (recoverable,
                # allowed). Unlike checkout, a restore pathspec is never a branch
                # switch, so a worktree-targeting pathspec is always destructive.
                if sub == "restore":
                    has_pathspec = ("." in scan or "--" in scan or
                                    any(not t.startswith("-") for t in scan))
                    targets_worktree = "--worktree" in scan or "--staged" not in scan
                    if has_pathspec and targets_worktree:
                        deny("git restore discards working-tree changes — confirm with user first")
                # Bundled short flags: "-qf" means -q -f. Stop scanning a cluster
                # at a value-taking letter (checkout -b/-B, switch -c/-C) so
                # "-bfoo" is not misread as -f hiding inside a branch name.
                def _bundled_force(t, stop_chars):
                    if not (t.startswith("-") and not t.startswith("--")):
                        return False
                    for ch in t[1:]:
                        if ch in stop_chars:
                            return False
                        if ch == "f":
                            return True
                    return False
                # checkout: "--"/"." = discard; 2+ nonflag = tree-ish + path
                # (`git checkout HEAD~1 file` overwrites the worktree). 1 nonflag
                # stays allowed: it may be a legit branch switch.
                # -b/-B/--orphan consume one nonflag (the new branch name), so
                # `checkout -b feat origin/develop` is a create, not tree+path.
                _co_nonflag = len([t for t in scan if not t.startswith("-")]) - (
                    1 if any(t in ("-b", "-B", "--orphan") for t in scan) else 0)
                if sub == "checkout" and ("--" in scan or "." in scan or
                                            _co_nonflag >= 2 or
                                            any(t == "-f" or _is_flag(t, "--force") or _bundled_force(t, ("b", "B")) for t in scan)):
                    deny("git checkout -- / git checkout . / git checkout -f / git checkout <tree> <file> discards working-tree changes — confirm with user first")
                if sub == "switch" and any(t == "-f" or _is_flag(t, "--force", "--discard-changes") or _bundled_force(t, ("c", "C")) for t in scan):
                    deny("git switch --force discards working-tree changes — confirm with user first")
                if sub == "branch" and (
                    any(t == "-D" or (t.startswith("-") and not t.startswith("--") and "D" in t) for t in scan)
                    or (any(_is_flag(t, "--delete") for t in scan) and any(_is_flag(t, "--force") for t in scan))
                ):
                    deny("git branch -D / --delete --force force-deletes a branch, discarding unmerged commits — confirm with user first")
                if sub == "stash" and args and args[0].replace(PH, "") in ("drop", "clear"):
                    deny("git stash drop/clear discards stashed changes — confirm with user first")
                if sub == "commit" and any(_is_flag(t, "--amend") for t in scan):
                    deny("git commit --amend rewrites history — confirm with user first")
                if sub == "add" and any(t in ("-A", ".") or _is_flag(t, "--all") for t in scan) and not _mid_merge():
                    deny("git add -A/. stages everything — stage files by name instead "
                         "(allowed only while a merge is in progress, i.e. MERGE_HEAD exists)")

        if argv0 == "dd" and any(t.replace(PH, "").startswith("of=/dev/") for t in rest):
            deny("dd writing to a raw device — irrecoverable disk-level destruction")

        if argv0 in ("mysql", "psql", "sqlite3", "mariadb"):
            # SQL genuinely lives inside -e/-c values, so DO scan them, but only
            # for known-dangerous statements. TABLE is optional in TRUNCATE
            # grammar. Full PH removal: a splice can land mid-keyword (DR$(true)OP).
            if re.search(r"DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+(TABLE\s+)?\w",
                         " ".join(rest).replace(PH, ""), re.IGNORECASE):
                deny("destructive SQL (DROP TABLE/DATABASE/SCHEMA or TRUNCATE) detected — confirm with user first")

sys.exit(0)
