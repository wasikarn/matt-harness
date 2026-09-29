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
# Wrappers whose own flags may take a space-separated value before the wrapped
# command (an attached value, "-c3" / "-oL" / "--signal=KILL", is one token and
# needs no case). timeout/gtimeout also take one DURATION positional; that is
# handled where the wrapper is unwrapped. exec/setsid take bare flags only.
# Open-ended by nature: a wrapper missing here (watch, flock, strace, ...) still
# hides its command, the list covers the ones an everyday one-liner uses.
FLAG_VALUE_WRAPPERS = {
    "nice": ("-n",),
    "ionice": ("-c", "-n"),
    "stdbuf": ("-i", "-o", "-e"),
    "timeout": ("-s", "-k", "--signal"),
    "gtimeout": ("-s", "-k", "--signal"),
}
PREFIX_WRAPPERS = ("env", "command", "nohup", "time", "sudo", "exec", "setsid") + tuple(FLAG_VALUE_WRAPPERS)
# Reserved words that open a command position inside a compound statement
# ("for x in a; do rm -rf y; done": the segment after ";" starts with "do"), so
# the real argv0 comes right after them. Stripped at segment start only, never
# scanned for inside arguments, so `echo do rm -rf x` stays an echo. The same
# statement split over lines was already denied, only the ";" spelling leaked.
# Shared by the token windows (below) and the spawn anchor.
SHELL_KEYWORDS = ("!", "if", "elif", "then", "else", "do", "while", "until", "coproc")
# A wrapper word must be followed by whitespace, in the lookahead too: with a bare
# \b a token that only STARTS with one ("timeout=30", "exec-bot") is neither a
# wrapper nor an ordinary token, the regex dead-ends and the anchor never fires.
_WRAPPER_ALT = r"(?:" + "|".join(PREFIX_WRAPPERS) + r")(?=\s)"
_WRAPPER_PREFIX = r"(?:" + _WRAPPER_ALT + r"\s+(?:(?!" + _WRAPPER_ALT + r")\S+\s+)*)*"
_KEYWORD_PREFIX = r"(?:(?:" + "|".join(re.escape(k) for k in SHELL_KEYWORDS) + r")\s+)*"
_SPAWN_ANCHOR_RE = re.compile(
    r"(?:^|[|;&(]|&&|\|\|)\s*" + _KEYWORD_PREFIX + r"(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*" + _WRAPPER_PREFIX +
    r"\\?(?:\S*/)?claude(?![-\w./])",
    re.MULTILINE,
)
_SPAWN_FLAG_RE = re.compile(r"-p\b|--print\b|--agent\b|--bg\b|--worktree\b")
# GH #157: an ODD backslash run directly before a quote escapes that quote
# in real bash (`claude \" ; othertool -p x` -- the `"` is a literal argument
# character, not a string opener), so it is captured as one literal token
# here, ahead of the quoted-span alternatives that would otherwise start a
# span at that quote and swallow the real ";" after it. An even run
# (`\\"a ; b"`) leaves the quote live, falls through to the run + span
# alternatives below, and still swallows the ";" -- the deny direction.
_SPAWN_TOKEN_RE = re.compile(
    "\\\\(?:\\\\\\\\)*[\"" + SQ + "]|"
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

def ask(reason):
    # Unlike deny(), doesn't exit immediately -- a later, more severe check in
    # the same run can still escalate to deny() (which does exit right away),
    # same "ask now, a worse finding can still override" shape config-write-guard.py
    # and codex-setup-guard.py's own emit_ask() already use.
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "ask",
                                             "permissionDecisionReason": reason}}))
    journal(GATE_ID, d.get("tool_name"), "ask", d.get("session_id"))

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
    # An escaped separator ("\ ", "\;", "\|", ...) is still a LITERAL character
    # in bash, not a real word break, so a "#" right after it is mid-word, not
    # a comment start -- out[-1] alone can't tell the two apart (both leave the
    # same separator byte in out). This tracks whether the last APPENDED char
    # came from an escaped pair, so the "#" boundary check can discount it.
    last_escaped = False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_comment:
            if c == "\n":
                out.append(c); out.append(";"); out.append(" ")
                in_comment = False
            else:
                out.append(c)
            last_escaped = False
            i += 1
            continue
        if in_squote:
            out.append(c)
            if c == SQ:
                in_squote = False
            last_escaped = False
            i += 1
            continue
        if in_dquote:
            if c == "\\" and i + 1 < n and s[i + 1] == "\n":
                # continuation inside double quotes: bash strips both chars
                i += 2
                continue
            if c == "\\" and i + 1 < n and s[i + 1] in (DQ, "\\", "$", "`"):
                out.append(c); out.append(s[i + 1])
                last_escaped = False
                i += 2
                continue
            out.append(c)
            if c == DQ:
                in_dquote = False
            last_escaped = False
            i += 1
            continue
        # unquoted, not in a comment
        if c == SQ:
            in_squote = True
            out.append(c); i += 1
            last_escaped = False
        elif c == DQ:
            in_dquote = True
            out.append(c); i += 1
            last_escaped = False
        elif c == "\\" and i + 1 < n and s[i + 1] == "\n":
            # real line continuation: both chars removed, nothing appended
            i += 2
        elif c == "\\" and i + 1 < n:
            # any other escaped pair is consumed together so the escaped char
            # is never re-examined as a hash/quote marker
            out.append(c); out.append(s[i + 1])
            i += 2
            last_escaped = True
        elif c == "#" and not last_escaped and (not out or out[-1] in _REDIRECT_TARGET_STOP):
            in_comment = True
            out.append(c); i += 1
            last_escaped = False
        elif c == "#":
            out.append(HASH_LIT); i += 1
            last_escaped = False
        elif c == "\n":
            out.append(c); out.append(";"); out.append(" ")
            i += 1
            last_escaped = False
        else:
            out.append(c)
            i += 1
            last_escaped = False
    return "".join(out)

# Command-substitution placeholder pass. A backtick/$(...)/${...}/<(...)/>(...)
# span vanishes in real bash once its output splices in ("gi`true`t" IS "git"),
# but shlex keeps the punctuation literal, so a spliced argv0 evades exact-match
# dispatch. Resolving the substitution would mean running a subshell, so instead
# the span is blanked to one placeholder byte (PH): PH is a shlex wordchar so it
# fuses into the surrounding text as ONE token, and any argv0/subcommand token
# still containing PH is duplicate-classified across every KNOWN_DANGEROUS /
# KNOWN_GIT_SUBS candidate downstream.
# Closer-search depth-counts same-type brackets so nested spans ("$(echo
# $(date))", "$(f() { :; }; f)") resolve in one pass; the fixed-point loop stays
# as defense-in-depth. Out of scope: a bracket hidden behind a quote/escape
# boundary INSIDE the span (quotes tracked at top level only).
# Each downstream flag comparison strips PH itself (full .replace, not a
# leading-only strip: a mid-flag PH like --for<PH>ce is an exact-match bypass).
# Blanking must not DISCARD the body ("$ (git push --force)" is a real deny), so
# every backtick/$(...)/<(...)/>(...) body is re-appended as its own statement;
# ${...} bodies are not (parameter expansion, not a command). Single-quoted
# spans are never blanked; double-quoted $(...) IS live in bash -- telling them
# apart needs the real quote-state scan below, not a regex. A span inside a "#"
# comment passes through unchanged. <(...)/>(...) (GH #181) is never a real
# "<"/">" redirect -- a redirect target can't start with an unescaped "(" -- so
# blanking it here, before _blank_redirections runs, also stops that "<"/">"
# from being misread as a redirect operator downstream.
PH = "\x01"
# shlex.shlex's own `commenters` (never overridden, stays its default "#") skips
# to the next real "\n" the moment it sees an unquoted "#" ANYWHERE in a token,
# mid-word or not -- it has no word-position awareness, so a literal "foo#bar"
# fed to it unchanged still loses everything from "#" onward, regardless of the
# in_comment tracking below (that tracking only keeps quote-state correct while
# copying comment text through -- see "A span inside a "#" comment passes
# through unchanged" above -- it does not change what shlex itself treats as a
# comment start). A mid-word "#" is swapped for this placeholder before shlex
# ever sees it (a genuine word-boundary "#" is left alone, so shlex's own
# comment-stripping still runs for a real comment); HASH_LIT is added to
# lex.wordchars at both call sites. No downstream restore to "#" is needed: no
# dangerous argv0/flag/subcommand this file matches on contains "#", so a
# placeholder byte counts as one nonflag token exactly like a real "#" would.
HASH_LIT = "\x02"
# A process-substitution span ("<(cmd)"/">(cmd)", GH #181) blanks to ITS OWN
# placeholder, never bare PH: unlike "$(...)"/backtick, whose expanded value
# IS attacker-controlled to be an arbitrary string (so PH must be fully
# .replace()d back out before any exact flag/subcommand match, everywhere PH
# already is), a process substitution ALWAYS expands to a bash-synthesized
# "/dev/fd/<n>" path -- it can never literally become "-f"/"--force"/"rm"/etc,
# so PSUB never needs that same defensive stripping. The one place PSUB DOES
# matter: a PURE PSUB token (`git checkout main <(true)`) is a real nonflag
# argument to checkout, but not a real worktree pathspec checkout could
# overwrite (a "/dev/fd/<n>" target), so it is excluded from checkout's
# nonflag-arg count (see the "_co_nonflag" line) -- caught by an adversarial
# pass as an over-deny regression on the naive "any extra nonflag arg denies"
# version of this fix.
PSUB = "\x03"
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
    # `depth_work_used`/`_depth`: only the <(...)/>(...) branch (GH #181)
    # passes these, to recursively re-scan ITS OWN extracted body for a
    # nested different-type substitution before splicing it back in verbatim
    # (a backtick nested inside "<(...)" was found live/unscanned by an
    # adversarial pass -- see the GH #181 comment on that branch). The
    # top-level fixed-point loop below never passes them, so its own budget
    # and depth are unchanged from before. Sharing one `depth_work_used`
    # list across the whole recursion (never a fresh one per call) keeps the
    # total work bounded by one _DEPTH_SCAN_BUDGET regardless of nesting
    # depth; `_depth` caps the recursion itself, since a budget check alone
    # does not stop Python's own RecursionError on ~1000 properly-closed,
    # budget-cheap nested spans.
    def _scan_once(s, depth_work_used=None, _depth=0):
        if depth_work_used is None:
            depth_work_used = [0]
        out = []
        in_squote = in_dquote = in_comment = False
        # See _newlines_to_seps's own comment: an escaped separator is still a
        # literal char in bash, not a real word break, so a "#" right after it
        # is mid-word -- out[-1] alone can't tell the two apart.
        last_escaped = False
        i, n = 0, len(s)
        while i < n:
            c = s[i]
            if in_comment:
                if c == "\n":
                    in_comment = False
                out.append(c)
                last_escaped = False
                i += 1
                continue
            if in_squote:
                out.append(c)
                if c == SQ:
                    in_squote = False
                last_escaped = False
                i += 1
                continue
            if in_dquote:
                if c == "\\" and i + 1 < n and s[i + 1] in (DQ, "\\", "$", "`"):
                    out.append(c); out.append(s[i + 1])
                    last_escaped = False
                    i += 2
                    continue
                if c == DQ:
                    out.append(c)
                    in_dquote = False
                    last_escaped = False
                    i += 1
                    continue
                # else: fall through -- substitutions ARE live inside double quotes
            else:
                if c == SQ:
                    in_squote = True
                    out.append(c); i += 1
                    last_escaped = False
                    continue
                if c == DQ:
                    in_dquote = True
                    out.append(c); i += 1
                    last_escaped = False
                    continue
                if c == "\\" and i + 1 < n:
                    out.append(c); out.append(s[i + 1])
                    i += 2
                    last_escaped = True
                    continue
                if c == "#" and not last_escaped and (not out or out[-1] in _REDIRECT_TARGET_STOP):
                    in_comment = True
                    out.append(c); i += 1
                    last_escaped = False
                    continue
                if c == "#":
                    out.append(HASH_LIT); i += 1
                    last_escaped = False
                    continue
            if c == "`":
                j = s.find("`", i + 1)
                if j != -1:
                    bodies.append(s[i + 1:j])
                    out.append(PH)
                    i = j + 1
                    last_escaped = False
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
                    last_escaped = False
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
                    last_escaped = False
                    continue
            elif c in ("<", ">") and not in_dquote and s[i + 1:i + 2] == "(":
                # Process substitution (GH #181): "<(cmd)"/">(cmd)" is a WORD,
                # never a real redirect (a real "<"/">" redirect target can't
                # start with "(" unescaped), so it must be blanked here, the
                # same as "$(...)", BEFORE _blank_redirections ever sees the
                # "<"/">" -- otherwise that bare "<"/">" is misread as an input/
                # output redirect operator, and the body's own closing ")"
                # (never a real word boundary here) reaches the "#"-boundary
                # check as a bare character.
                # "not in_dquote": unlike "$(...)"/backtick (live inside double
                # quotes in real bash, correctly recognized either way by the
                # sibling branches above), "<(...)"/">(...)" is INERT text
                # inside double quotes -- "echo \"<(rm -rf x)\"" must stay a
                # harmless literal string, not get its quoted body extracted
                # and re-scanned as a real command (an adversarial pass caught
                # this as an over-deny regression).
                # Quote-aware, unlike the sibling "$(...)"/"${...}" closer-
                # searches above: a ")" inside a quoted string in the body
                # ("<(echo \")\"; rm -rf x)") is not a real closer, and the
                # naive count-every-paren approach those siblings use closes
                # the span early on it, leaving the real dangerous tail as
                # unblanked literal text (a real regression, caught by an
                # adversarial pass; the identical gap in "$(...)" itself is
                # pre-existing and unrelated -- filed as GH #184, not fixed
                # here).
                depth, j = 1, i + 2
                tsq = tdq = False
                while j < n and depth and depth_work_used[0] <= _DEPTH_SCAN_BUDGET:
                    depth_work_used[0] += 1
                    tc = s[j]
                    if tsq:
                        if tc == SQ:
                            tsq = False
                        j += 1
                        continue
                    if tdq:
                        if tc == "\\" and j + 1 < n and s[j + 1] in (DQ, "\\", "$", "`"):
                            j += 2
                            continue
                        if tc == DQ:
                            tdq = False
                        j += 1
                        continue
                    if tc == SQ:
                        tsq = True; j += 1; continue
                    if tc == DQ:
                        tdq = True; j += 1; continue
                    if tc == "\\" and j + 1 < n:
                        j += 2
                        continue
                    if tc == "(":
                        depth += 1
                    elif tc == ")":
                        depth -= 1
                    j += 1
                if depth and depth_work_used[0] > _DEPTH_SCAN_BUDGET:
                    _DEPTH_BUDGET_BLOWN[0] = True
                if not depth:
                    # The extracted body is spliced back as its own top-level
                    # statement ("\n; " + body) only once, after this whole
                    # function returns -- never re-examined by this scan loop
                    # again. A DIFFERENT-type substitution nested inside it
                    # (a backtick inside "<(...)") would otherwise survive
                    # unblanked all the way to shlex, still glued to its
                    # neighbor characters and evading exact-match dispatch
                    # (an adversarial pass caught this live: "<(echo `rm -rf
                    # x`)" reached shlex as "`rm", never matching "rm").
                    # Recursively re-scanning it here (this branch only --
                    # the sibling "$(...)"/"${...}" branches above share the
                    # identical gap, confirmed pre-existing, filed as GH
                    # #185, not fixed here) closes that while a shared
                    # depth_work_used bounds the total work across every
                    # recursion level to one budget; _depth caps the
                    # recursion itself, since a budget check alone doesn't
                    # stop Python's own RecursionError on a deep chain of
                    # cheap, properly-closed spans.
                    body = s[i + 2:j - 1]
                    if _depth < 50:
                        body = _scan_once(body, depth_work_used, _depth + 1)
                    else:
                        _DEPTH_BUDGET_BLOWN[0] = True
                    bodies.append(body)
                    out.append(PSUB)
                    i = j
                    last_escaped = False
                    continue
            out.append(c)
            i += 1
            last_escaped = False
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

# A real shell redirection ([n]<word / [n]>[>]word / [n]<&word / [n]>&word /
# [n]<<<word / &>word / &>>word) is consumed entirely by bash before the
# target program's own argv is built -- it never reaches git, so a downstream
# nonflag-arg count or exact-token check (e.g. checkout's "1 nonflag = branch
# switch, 2+ = tree-ish+path") must not see it. A prior attempt fixed this by
# stripping matching tokens AFTER shlex(posix=True) tokenized the command --
# rejected (2026-09-29, found by an adversarial Codex pass, see
# security-gate-token-strip-needs-quote-state memory): posix=True dequotes, so
# a LITERAL quoted ">" and a real unquoted > redirect become the identical
# token string, and stripping "a bare digit immediately before an operator
# token" can't tell a real fd-prefix ("2>&1", no space) from a real positional
# arg that happens to be a digit followed by a separately-spaced redirect
# ("checkout HEAD 2 >out" -- shlex has already discarded whether that space
# existed). Both are only resolvable from the RAW string, where quoting and
# spacing are both still intact -- so this runs BEFORE shlex, on the raw
# command text, with real quote/comment state tracked char-by-char exactly
# like _newlines_to_seps above (same escape-pair and quote-toggle rules), never
# treating a quoted or backslash-escaped character as a real operator. Matched
# spans are DELETED outright, not blanked to PH: PH would make a token vanish
# from the "compacted" window copy below but still count in the RAW copy (PH
# is a wordchar, so it's still one non-flag token there) -- and "a deny in
# either copy wins" means the raw copy's inflated nonflag count would still
# false-deny, exactly the bug this exists to fix. A redirect target is never
# itself a command to re-scan for danger (unlike a $(...) body), so nothing
# needs to survive at that position the way a substitution's body does.
# Runs AFTER _blank_substitutions so a redirect character inside a $(...) body
# that gets re-appended as its own statement is still correctly re-scanned
# (it's real command text by then), and one already blanked to PH is not
# double-processed (PH itself never matches the redirect-operator regex).
# "#" is NOT in this set: bash only treats "#" as a comment-starter at the
# START of a word, not glued mid-word ("out#suffix" is one literal filename) --
# handled as a special case in the target loop below (round 2, found by an
# adversarial Codex pass: `git checkout HEAD >out#suffix <realfile>` let the
# target-consumption stop at "#", silently dropping <realfile> from the scan
# entirely; that exact payload correctly denies on the unmodified gate).
# "{"/"}" are ALSO not in this set, for the same reason, found the same way
# (round 3): unlike "(" and ")" -- real, always-special shell operators, a bare
# unquoted "{"/"}" mid-word is just a literal character in bash (verified live:
# `bash -n -c 'echo out{suffix'` is a syntax error for "(" but NOT for "{" --
# only paired, comma/range-shaped brace expansion is special, and only at a
# word boundary). `git checkout HEAD >out{suffix <realfile>` bypassed the same
# way the "#" case did before this line excluded them too.
# GH #188: bash 4+'s named-fd form "{var}>file" is a redirect too. Its "{var}"
# prefix used to survive as text: the outer tokenizer split it into "{" "var"
# "}" (window breaks), cutting `checkout HEAD {fd}>/dev/null <path>` off before
# <path> (fail-open), and the bash -c/eval tokenizer (whitespace_split) kept
# "{fd}" as one nonflag arg (over-deny on a plain branch switch). Only matched
# at a word start (checked at the call site): "x{fd}>f" is the literal word
# "x{fd}" followed by a plain ">f" redirect. Like an fd number, "{var}" never
# prefixes "&>"/"&>>" ("{fd}&>x" is the word "{fd}" plus a redirect). ">|"
# (noclobber) and "<>" are operators too: without ">|", "{fd}>|x <path>" left
# "|x <path>" as a pipe that cut the window before <path> (#208 validator).
_REDIRECT_OP_RE = re.compile(
    r"\{[A-Za-z_][A-Za-z0-9_]*\}(?:>>|<<<|<<|>&|<&|>\||<>|>|<)"
    r"|\d{0,2}(?:>>|<<<|<<|>&|<&|&>>|&>|>\||<>|>|<)")
_REDIRECT_TARGET_STOP = set(" \t\n;|&()")
def _blank_redirections(s):
    out = []
    in_squote = in_dquote = in_comment = False
    # See _newlines_to_seps's own comment: an escaped separator is still a
    # literal char in bash, not a real word break, so a "#" right after it
    # is mid-word -- out[-1] alone can't tell the two apart.
    last_escaped = False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_comment:
            out.append(c)
            if c == "\n":
                in_comment = False
            last_escaped = False
            i += 1
            continue
        if in_squote:
            out.append(c)
            if c == SQ:
                in_squote = False
            last_escaped = False
            i += 1
            continue
        if in_dquote:
            if c == "\\" and i + 1 < n and s[i + 1] in (DQ, "\\", "$", "`"):
                out.append(c); out.append(s[i + 1])
                last_escaped = False
                i += 2
                continue
            out.append(c)
            if c == DQ:
                in_dquote = False
            last_escaped = False
            i += 1
            continue
        # unquoted, not in a comment
        if c == SQ:
            in_squote = True
            out.append(c); i += 1
            last_escaped = False
            continue
        if c == DQ:
            in_dquote = True
            out.append(c); i += 1
            last_escaped = False
            continue
        if c == "\\" and i + 1 < n:
            # an escaped char (including an escaped ">"/"<") is never a real
            # operator -- consumed together so it is not re-examined below.
            out.append(c); out.append(s[i + 1])
            i += 2
            last_escaped = True
            continue
        if c == "#" and not last_escaped and (not out or out[-1] in _REDIRECT_TARGET_STOP):
            in_comment = True
            out.append(c); i += 1
            last_escaped = False
            continue
        if c == "#":
            out.append(HASH_LIT); i += 1
            last_escaped = False
            continue
        m = _REDIRECT_OP_RE.match(s, i)
        # mid-word "{": literal text, not a named fd (GH #188). After an
        # escaped char ("x\ {fd}>f") it is still read as a redirect: keeping
        # "{" as text lets the outer tokenizer break the window at "{".
        if m and c == "{" and out and out[-1] not in _REDIRECT_TARGET_STOP:
            m = None
        if m:
            j = m.end()
            while j < n and s[j] in " \t":
                j += 1
            # Consume the operator's target word, itself quote/escape-aware
            # (a quoted or spaced redirect target, "> \"my file\"", is one word).
            k, tsq, tdq = j, False, False
            while k < n:
                tc = s[k]
                if tsq:
                    if tc == SQ:
                        tsq = False
                    k += 1
                    continue
                if tdq:
                    if tc == "\\" and k + 1 < n and s[k + 1] in (DQ, "\\", "$", "`"):
                        k += 2
                        continue
                    if tc == DQ:
                        tdq = False
                    k += 1
                    continue
                if tc == SQ:
                    tsq = True; k += 1; continue
                if tc == DQ:
                    tdq = True; k += 1; continue
                if tc == "\\" and k + 1 < n:
                    k += 2
                    continue
                if tc == "#" and k == j:
                    # "#" as the very first target char IS a real word-start,
                    # i.e. a genuine comment ("> #comment") -- leave it for the
                    # outer dispatcher's own "#" branch to enter comment state
                    # correctly, rather than swallowing it here.
                    break
                if tc in _REDIRECT_TARGET_STOP:
                    break
                k += 1
            # Leave a space where the redirect was: deleting it outright can
            # glue the punctuation on either side into one shlex token (")"
            # + ";" -> ");", not in OPERATORS), hiding the window break before
            # a dangerous tail (found by the GH #188 differential fuzz).
            out.append(" ")
            i = k
            last_escaped = False
            continue
        out.append(c)
        i += 1
        last_escaped = False
    return "".join(out)

# shlex.split() only recognizes ;/&&/||/|/& as separators when whitespace
# surrounds them ("echo hi;rm -rf x" glued "hi;rm"); punctuation_chars=True
# splits them out as their own tokens while respecting quotes. ( ) { } get the
# same treatment so "(rm -rf x)" / "{ rm -rf x; }" do not leave "(" as argv0.
OPERATORS = {";", "&&", "||", "|", "&", "(", ")", "{", "}"}
_OPS_LONGEST_FIRST = sorted(OPERATORS, key=len, reverse=True)

# shlex fuses a run of punctuation into ONE token: ");", "&&(", ")|", ")|&", ";;".
# None of those is in OPERATORS, so the window never split and the next command
# stayed an argument of the previous one. A token made only of operators is cut
# back into them; anything with another character (a redirection) is left alone.
# shlex has already dropped the quotes, so a QUOTED argument of that shape
# (echo ');' rm -rf x) is split too: an over-deny, the safe direction, and the
# same limit a quoted ";" always had here.
def _split_ops(tok):
    if tok in OPERATORS:
        return [tok]
    out, i = [], 0
    while i < len(tok):
        for op in _OPS_LONGEST_FIRST:
            if tok.startswith(op, i):
                out.append(op)
                i += len(op)
                break
        else:
            return [tok]
    return out

# shlex cost is superlinear in the longest SINGLE token (700k chars blows a 2s
# timeout), so an oversized command denies on length ALONE before shlex runs.
_CMD_LEN_CAP = 150_000
if len(cmd) > _CMD_LEN_CAP:
    deny("command too long to safely tokenize (" + str(len(cmd)) + " chars, cap " + str(_CMD_LEN_CAP) + ") - confirm with user first")

try:
    lex = shlex.shlex(_blank_redirections(_blank_substitutions(_newlines_to_seps(_normalize_ansi_c_quotes(cmd)))), posix=True, punctuation_chars=True)
    lex.wordchars += PH + HASH_LIT + PSUB
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
        _fallback_src = _blank_redirections(_blank_substitutions(_newlines_to_seps(_normalize_ansi_c_quotes(cmd))))
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
for tok in [p for t in tokens for p in _split_ops(t)]:
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
        lex = shlex.shlex(_blank_redirections(_blank_substitutions(_newlines_to_seps(body))), posix=True, punctuation_chars=True)
        lex.wordchars += PH + HASH_LIT + PSUB
        lex.whitespace_split = True
        cur = []
        for tok in [p for t in list(lex) for p in _split_ops(t)] + [";"]:
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
KNOWN_DANGEROUS = ("rm", "find", "git", "gh", "dd", "mysql", "psql", "sqlite3", "mariadb")
KNOWN_GIT_SUBS = ("push", "reset", "clean", "restore", "checkout", "switch", "branch", "stash", "commit", "add")

# Duplication also fires on a token still carrying raw substitution syntax
# (belt-and-braces for any path that hands over an unblanked token). Narrow
# single-token check on purpose: a bare "$" would misfire on "$PYTHON -m pytest".
def _has_raw_subst(t):
    return "`" in t or "$(" in t or "${" in t

# 2026-09-21 deep-audit: a bare `NAME=value` prefix (`FOO=bar rm -rf x`) made
# argv0 "FOO=bar", so every token-dispatched deny below fell through. Returns
# the assignment's (key, value) or None; the same env-var hook bypass the -c
# branch denies is checked here too (GIT_CONFIG_PARAMETERS / GIT_CONFIG_KEY_n
# carrying core.hooksPath is exactly `-c core.hooksPath=`, via the
# environment) -- one helper for the bare prefix and the `env` wrapper below.
def _assignment(t):
    key, eq, val = t.replace(PH, "").partition("=")
    if not eq or not key.isidentifier():
        return None
    if (key == "GIT_CONFIG_PARAMETERS" or key.startswith("GIT_CONFIG_KEY_")) \
            and "core.hookspath" in val.lower():
        deny("-c core.hooksPath=<path> re-points git at a different hooks dir — same bypass as --no-verify")
    return key, val

for _wi, w in enumerate(windows):
    while w and (w[0] in SHELL_KEYWORDS or _assignment(w[0])):
        w = w[1:]
    if not w:
        continue
    argv0, rest = basename(w[0]), w[1:]

    # Prefix wrappers unwrap one level per iteration so "env nice rm -rf x" or
    # "sudo rm -rf x" resolve to the real command -- everyday idioms, in scope.
    # env/sudo and FLAG_VALUE_WRAPPERS take flags+values before the wrapped
    # command; command/nohup/time/exec/setsid only take bare flags. Every flag
    # test strips PH first: a disguised
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
                elif _assignment(rest[i]):
                    i += 1
                else:
                    break
            if i >= len(rest):
                break
            argv0, rest = basename(rest[i]), rest[i + 1:]
        elif argv0 in FLAG_VALUE_WRAPPERS:
            i = 0
            while i < len(rest) and rest[i].replace(PH, "").startswith("-"):
                t = rest[i].replace(PH, "")
                i += 1
                if t in FLAG_VALUE_WRAPPERS[argv0] and i < len(rest):
                    i += 1
            if argv0 in ("timeout", "gtimeout"):
                i += 1  # the DURATION positional
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
        else:  # command, nohup, time, exec, setsid — bare flags then the wrapped command
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
                # --config-env=KEY=VAR / --config-env KEY=VAR: git reads the
                # value from env var VAR, same effect as -c (2026-09-21 audit).
                elif t_pf == "--config-env" and idx + 1 < len(w):
                    key, _, val = w[idx + 1].partition("=")
                    if key.lower() == "core.hookspath" and val:
                        hooks_path_val = val
                elif t_pf.startswith("--config-env="):
                    key, _, val = t_pf[len("--config-env="):].partition("=")
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
            scan_raw, skip = [], False
            for t in args:
                if skip:
                    skip = False
                    continue
                if t.replace(PH, "") in ("-m", "--message"):
                    skip = True
                    continue
                scan_raw.append(t)
            # "$(true)--force" IS "--force" in bash but blanks to "PH--force";
            # strip PH once here so every sub == "..." branch below sees the
            # flag shape. scan_raw (pre-strip) is kept index-aligned alongside
            # for the PSUB-identity checks below: a glued "$(...)<(...)" token
            # (no space between them -- one shlex token, "PH_char+PSUB_char")
            # collapses to a value textually identical to a lone PSUB once PH
            # is stripped out, wrongly inheriting PSUB's "safe to exclude"
            # treatment even though the $(...) half is attacker-controlled.
            # Checking the RAW (pre-strip) token for exact PSUB identity
            # instead of the stripped one closes that (deep-audit, 2026-09-29).
            scan = [t.replace(PH, "") for t in scan_raw]

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
                    # A PURE PSUB token is a real nonflag argument but never a
                    # real worktree pathspec restore could discard (its
                    # expanded value is always a synthesized "/dev/fd/<n>"
                    # path) -- same reasoning as checkout's _co_nonflag
                    # exclusion above; missed here on the first pass, found
                    # by a deep-audit pass (2026-09-29). Checked against
                    # scan_raw (pre-PH-strip), not scan, so a glued
                    # "$(...)<(...)" token that only LOOKS like a lone PSUB
                    # after stripping still counts (see scan_raw's own
                    # comment above).
                    # --pathspec-from-file's VALUE is read by git as a list of
                    # real pathspecs, so the flag alone means path mode
                    # regardless of what its argument token looks like --
                    # excluding a bare PSUB from the nonflag count is wrong
                    # for THIS flag specifically, since the process
                    # substitution's OUTPUT, not the token itself, is the
                    # actual pathspec source (also closes the same gap for
                    # --pathspec-from-file=<file>/- with no substitution at
                    # all, GH #189).
                    has_pathspec = ("." in scan or "--" in scan or
                                    any(_is_flag(t.split("=", 1)[0], "--pathspec-from-file") for t in scan) or
                                    any(not t.startswith("-") and traw != PSUB
                                        for t, traw in zip(scan, scan_raw)))
                    # GH #189: -W (bundled too) and any --worktree
                    # abbreviation ("--work") count; a short cluster stops at
                    # "s" (-s takes a value: "-sW" is source "W"). After "--"
                    # every token is a pathspec ("-- -Wfile").
                    _opts = scan[:scan.index("--")] if "--" in scan else scan
                    targets_worktree = "--staged" not in _opts or any(
                        _is_flag(t, "--worktree")
                        or (t.startswith("-") and not t.startswith("--") and "W" in t.split("s", 1)[0])
                        for t in _opts)
                    if has_pathspec and targets_worktree:
                        deny("git restore discards working-tree changes — confirm with user first")
                # Bundled short flags: "-qf" means -q -f. Stop scanning a cluster
                # at a value-taking letter (checkout -b/-B, switch -c/-C) so
                # "-bfoo" is not misread as -f hiding inside a branch name.
                # `flag` is the letter looked for (default -f; commit -n, branch
                # -d, add -A use the same scan).
                def _bundled_flag(t, stop_chars, flag="f"):
                    if not (t.startswith("-") and not t.startswith("--")):
                        return False
                    for ch in t[1:]:
                        if ch in stop_chars:
                            return False
                        if ch == flag:
                            return True
                    return False
                # checkout: "--"/"." = discard; 2+ nonflag = tree-ish + path
                # (`git checkout HEAD~1 file` overwrites the worktree). 1 nonflag
                # stays allowed: it may be a legit branch switch.
                # -b/-B/--orphan consume one nonflag (the new branch name), so
                # `checkout -b feat origin/develop` is a create, not tree+path.
                # A PURE PSUB token (GH #181: `checkout main <(true)`) is a real
                # nonflag arg but never a real worktree pathspec (its expanded
                # value is always a synthesized "/dev/fd/<n>" path, not
                # attacker-controlled the way "$(...)" is), so it's excluded
                # here rather than counted toward the tree-ish+path deny.
                # Checked against scan_raw (pre-PH-strip), not scan -- see
                # scan_raw's own comment above; a glued "$(...)<(...)" token
                # only LOOKS like a lone PSUB after PH-stripping.
                # --pathspec-from-file is checked separately, unconditionally
                # of _co_nonflag: its VALUE is read by git as a list of real
                # pathspecs regardless of how many other nonflag args are
                # present (deep-audit, 2026-09-29; same reasoning as
                # restore's identical check above).
                _co_nonflag = len([t for t, traw in zip(scan, scan_raw) if not t.startswith("-") and traw != PSUB]) - (
                    1 if any(t in ("-b", "-B", "--orphan") for t in scan) else 0)
                if sub == "checkout" and ("--" in scan or "." in scan or
                                            _co_nonflag >= 2 or
                                            any(_is_flag(t.split("=", 1)[0], "--pathspec-from-file") for t in scan) or
                                            any(t == "-f" or _is_flag(t, "--force") or _bundled_flag(t, ("b", "B")) for t in scan)):
                    deny("git checkout -- / git checkout . / git checkout -f / git checkout <tree> <file> discards working-tree changes — confirm with user first")
                if sub == "switch" and any(t == "-f" or _is_flag(t, "--force", "--discard-changes") or _bundled_flag(t, ("c", "C")) for t in scan):
                    deny("git switch --force discards working-tree changes — confirm with user first")
                if sub == "branch" and (
                    any(t == "-D" or (t.startswith("-") and not t.startswith("--") and "D" in t) for t in scan)
                    # -d -f, -df, -fd, -d --force and --delete -f are -D by another spelling.
                    or (any(_is_flag(t, "--delete") or _bundled_flag(t, "", "d") for t in scan)
                        and any(_is_flag(t, "--force") or _bundled_flag(t, "", "f") for t in scan))
                ):
                    deny("git branch -D / --delete --force force-deletes a branch, discarding unmerged commits — confirm with user first")
                if sub == "stash" and args and args[0].replace(PH, "") in ("drop", "clear"):
                    deny("git stash drop/clear discards stashed changes — confirm with user first")
                if sub == "commit" and any(_is_flag(t, "--amend") for t in scan):
                    deny("git commit --amend rewrites history — confirm with user first")
                # `commit -n` is --no-verify (push -n is --dry-run, merge -n --no-stat, so
                # commit only). Cluster stops at a value-taking letter: -mnew is a message,
                # -Fnotes.txt a file, -tnotes a template, -uno the untracked-files mode.
                if sub == "commit" and any(_bundled_flag(t, "mFtu", "n") for t in scan):
                    deny("git commit -n is --no-verify, it bypasses safety hooks")
                # -A also arrives bundled (-Af, -fA, -vA); add has no value-taking short flag.
                if sub == "add" and any(t == "." or _bundled_flag(t, "", "A") or _is_flag(t, "--all") for t in scan) and not _mid_merge():
                    deny("git add -A/. stages everything — stage files by name instead "
                         "(allowed only while a merge is in progress, i.e. MERGE_HEAD exists)")

        # Phase B (2026-09-28): local, interactive-session-only defense-in-depth
        # for this repo's PR-review flow -- ask, never deny, since a merge can be
        # a legitimate operator-approved action. Does NOT constrain a GitHub
        # credential used outside a Claude Code session with mh loaded (a cloud
        # Routine, the web UI, a raw API call) -- see docs/adr/0004-* for that
        # threat model; branch protection (B5) is the real enforcement there.
        if argv0 == "gh" and rest:
            gh_scan = [t.replace(PH, "") for t in rest]
            if gh_scan[0] == "pr" and "merge" in gh_scan[1:]:
                ask("gh pr merge would merge a pull request into this repo — the PR-review "
                    "flow (docs/reference/branching-model.md) expects a human to do this. "
                    "Confirm this is intentional.")
            if gh_scan[0] == "api" and any("/merge" in t for t in gh_scan[1:]):
                ask("gh api .../merge calls the GitHub merge endpoint directly — the "
                    "PR-review flow (docs/reference/branching-model.md) expects a human to "
                    "do this. Confirm this is intentional.")

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
