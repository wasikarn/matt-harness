#!/usr/bin/env bash
# Gate: prompt the human to approve any Write/Edit/MultiEdit — OR a Bash-mediated
# write (redirect, tee, sed -i, perl -i, cp, mv, rm, trash) — to the verifier
# surfaces: hooks/gates/**, hooks/advisory/**, hooks/hooks.json, the
# PreToolUse dispatcher's own routing (hooks/pretooluse-table.json,
# hooks/dispatch-pretooluse.py/.sh), AND the non-model audit verifier
# (skills/meta/harness-audit/scripts/audit.sh + checks/**) — so the model cannot
# neuter the deny-gates, silently turn an advisory sensor into something
# that emits permissionDecision, repoint or delete a gate's table entry, OR
# weaken the audit checks that judge it without an in-session human
# approval (the tamper-resistance principle: the agent cannot edit the code
# that judges it). hooks/advisory/** added 2026-08-06: previously
# unprotected, meaning a sensor could be edited into a real gate with zero
# prompt (found by a blind-spot sweep). hooks/pretooluse-table.json +
# dispatch-pretooluse.* added 2026-08-25: T12 moved gate routing OUT of the
# already-protected hooks/hooks.json into these three new files, which
# inherited none of that protection (found by an independent adversarial
# audit of #91, same day). A gate/check the model can silently disable is
# not a computational deny — and a half-protected perimeter is worse than
# none, so ALL FOUR deterministic verifier classes (gates, advisory
# sensors, the dispatcher's own routing, and audit) are guarded.
#
# Bash mode (tool_name == Bash): the Write/Edit matchers above do not see Bash,
# so `echo x > hooks/gates/irrecoverable.sh`, `sed -i …`, `tee`, `cp`/`mv` could
# edit a verifier surface with zero prompt (found 2026-07-03). This gate scans
# the Bash command for redirect targets and write-command file args that resolve
# into the protected set. Bounded idiom set — a habit-guard, not an adversarial
# sandbox; revisit if the threat model demands full Bash analysis.
#
# Emits a PreToolUse `permissionDecision: ask` JSON (exit 0) so Claude Code
# surfaces a live Approve/Deny prompt to the operator — no env-var bypass, no
# restart. The maker still cannot self-approve; the human decides each edit.
#
# Reads the PreToolUse JSON payload from stdin. Exit 0 + ask JSON on hit
# (JSON honored); exit 0 + no output on miss (clean allow); exit 0 + ask JSON
# on internal error too (fail-safe: an unparseable payload must never resolve
# to a silent allow on a tamper-resistance gate). One deliberate carve-out
# (#93): a machine with no python3 at all allows with a stderr note instead —
# announced fail-open, not silent (doctrine-bootstrap.sh also names it at
# SessionStart), because the classifier below cannot run at all there.
#
# Path matching is case-INsensitive: macOS/APFS is case-insensitive but
# case-preserving, and os.path.realpath() does not correct a path's casing to
# match the on-disk directory-entry casing — so a case-sensitive substring
# check can be bypassed by writing to a differently-cased path (e.g.
# "hooks/Gates/x.sh") that the filesystem still resolves into the real
# protected directory. Lowercasing both sides only widens the match (more
# prompts, never fewer) so it is safe on case-sensitive filesystems too.
#
# Folded path-hardcode deny (2026-07-03): the former gate:write:path-hardcode
# hook (a separate parallel PreToolUse hook) is folded into this gate's Write
# branch. It blocks a hardcoded /Users/<name> path written into a .sh/.py/.js
# file (case-insensitive endswith; scans content/new_string and MultiEdit
# edits[]) by exiting 2 BEFORE the verifier ask — a block wins over an ask,
# matching the prior parallel behavior where path-hardcode denied while this
# gate asked. Folding removes one python3 spawn per Write/Edit (a CPU win,
# not a felt-latency win: this gate's own python cold-start remains the
# Write-matcher floor). path-hardcode.sh and its hooks.json entry are deleted.
set -uo pipefail

# --- Fast path (Bash matcher only): skip the python3 cold-start on Bash
# commands that cannot write to a verifier surface. Write|Edit|NotebookEdit
# calls always reach python (the gate's primary purpose). For a Bash call, a
# write to a verifier surface needs EITHER the verifier path spelled out in the
# command (redirects, tee/cp/mv/sed/perl/rsync/dd/rm/trash targets are argv) OR
# a diff/archive carrier (git apply/am, patch, tar -x) whose real target lives
# inside a diff file or resolves to cwd -- invisible to a command-string
# substring match, so those carriers fall through to python unconditionally
# (plan-review 2026-08-14: git apply/am + patch + tar-cwd would otherwise fail
# open -- `git apply /tmp/x.diff` with `+++ b/hooks/gates/...` rewrites a gate
# with no prompt) OR an unquoted $VAR/~ target that python expands
# (os.path.expandvars/expanduser, line ~427) into a verifier path invisible to
# the raw command string (found by tests/hooks/test-verifier-protect.sh's
# existing $TARGETDIR/~ battery cases -- both fell open on the first version of
# this fast-path). False positives (digit/start/dispatch) just spawn python.
# Out of threat model (this gate is not an adversarial sandbox, line ~210): a
# pre-existing symlink whose realpath resolves into a verifier surface, and
# \u JSON escapes (the CC serializer emits ASCII alphanumerics literally).
# sync-seam: the stdin-capture + whitespace-normalize prefix (this line +
# the next) is hand-duplicated in irrecoverable.sh's own fast-path -- not
# extracted to a shared sourced helper because these gates govern their own
# edits (a shared-helper bug would break both simultaneously; editing this
# exact fast-path cost 2 self-inflicted lockouts before it landed clean,
# 2026-08-14). If either file's normalize step changes, check the other.
_input="$(cat)"
_ws="$(printf '%s' "$_input" | sed 's/\\[nt]/ /g' | tr -s '[:space:]' ' ')"
_run=1
# GH #125: the sed step above matches only the LAST backslash immediately
# before a JSON-encoded "\n", so a real 1-backslash bash line-continuation
# (which fully vanishes in real bash, gluing e.g. "hoo" + continuation +
# "ks/gates/x.sh" into "hooks/gates/x.sh") survives normalization as a
# residual space instead ("hoo ks/gates/x.sh") -- breaking the contiguous
# substring match below and letting a real verifier-surface write fall
# through as a fast-path allow. Rather than reimplement bash own
# parity-sensitive continuation rule (odd backslash-run = continuation, even
# = a real escaped backslash + ordinary newline) in sed/bash -- this exact
# fast-path region has already cost 2 self-inflicted lockouts, and python own
# _newlines_to_seps below already gets this parity rule right -- any raw
# backslash anywhere in the input disables the whole fast-allow
# classification below and defers to python unconditionally. Same "false
# positives just spawn python" direction as every other coarse check here.
_has_bs=0
case "$_input" in *\\*) _has_bs=1 ;; esac
# GH #128/#130: a backtick or $(...) command substitution (also ${x} with x
# unset, $'...' ANSI-C quoting, and $@/$* with zero positional parameters --
# each found and fixed one spelling at a time, 2026-09-03) vanishes in real
# bash but survives here as literal characters, splicing either check below
# apart -- a protected path (`echo x > hoo`true`ks/gates/probe.sh`, GH #128)
# or a write-command NAME (`c$(true)p evil.sh hooks/gates/x.sh`, GH #130) --
# so the contiguous substring match neither case-statement below performs can
# catch it. Enumerating specific spellings kept finding gaps (4 rounds), so
# this is the general form instead: ANY bare `$` or backtick anywhere in the
# raw input refuses the whole fast-path classification below (one guard on
# the outer `if`, since both case-statements live inside it) -- a strict
# superset of every enumerated marker, since each one itself contains a `$`
# or a backtick. Same conservative-deferral direction as the _has_bs guard
# above and the sibling fix in irrecoverable.sh: detect the PRESENCE of the
# marker on the RAW input rather than resolving the substitution here.
_has_subst=0
case "$_input" in *'`'*|*'$'*) _has_subst=1 ;; esac
# Match the quoted tool_name value precisely (the "Bash" is the JSON value, not
# a substring of a longer word) so a Write to a file_path that happens to
# contain "Bash" is not mis-routed through the Bash fast-path (which could exit
# 0 and skip the gate's primary Write-path protection). [[ =~ ]] is used
# because a `case` pattern cannot contain literal double-quotes cleanly (the
# syntax-error lockout on the first attempt). The regex tolerates the optional
# space after the colon in both JSON serializations.
if [ "$_has_bs" -eq 0 ] && [ "$_has_subst" -eq 0 ] && [[ $_ws =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"Bash\" ]]; then
  # GH #127: lowercase before matching. macOS/APFS is case-insensitive but
  # case-preserving (header comment above), so a case-sensitive substring
  # check can be bypassed by a differently-cased path spelling
  # (hooks/GATES/x.sh) that the filesystem still resolves into the same real
  # protected directory. Lowercasing only widens the match (more python
  # spawns, never fewer allows), matching the python-side is_gate_path()
  # behavior this file's header already promises.
  _norm="$(printf '%s' "$_ws" | tr -d "\"'\\" | tr '[:upper:]' '[:lower:]')"
  case "$_norm" in
    *git*|*patch*|*tar*) : ;;  # diff/archive carrier -> target may be in a file/cwd -> python
    *tee*|*sed*|*perl*|*cp*|*mv*|*install*|*rsync*|*dd*|*rm*|*trash*|*">"*)
      case "$_norm" in
        *hooks/gates*|*hooks/advisory*|*hooks/hooks.json*|*hooks/pretooluse-table.json*|*hooks/dispatch-pretooluse*|*skills/harness-audit*|*skills/*/harness-audit*|*'~'*) : ;;  # write + verifier path (or an expandable ~ target) -> python (a $ target is already caught by the outer _has_subst guard above)
        *) _run=0 ;;  # write to a non-verifier, non-expandable surface -> allow fast
      esac
      ;;
    *) _run=0 ;;  # no write/redirect token -> allow fast
  esac
fi
[ "$_run" -eq 0 ] && exit 0

# Portability guard (#93): announced fail-open — without python3 this gate
# cannot classify the call at all; doctrine-bootstrap.sh names the missing
# dep once at SessionStart.
if ! command -v python3 >/dev/null 2>&1; then
  echo "[mh:gate] python3 not found — verifier-protect gate cannot run; allowing (install python3 to restore verifier-surface protection)" >&2
  exit 0
fi

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
printf '%s' "$_input" | python3 -c '
import sys, json, os, shlex, re

# lib_dir is argv[1] -- $(dirname "$0")/lib, appended below where this
# python3 -c block is invoked. $0-based resolution because
# CLAUDE_PLUGIN_ROOT can be empty in some invocation contexts; $0
# cannot, since bash sets it from the literal command that ran this file.
sys.path.insert(0, sys.argv[1])
from _hook_output import emit_ask
from _protected_paths import is_gate_path

PROTECTED_REASON = (
    "Editing a verifier surface — the deny-gates or audit checks that "
    "judge the model live here. Tamper-resistance: the model cannot edit "
    "the code that judges it without your approval."
)

# No literal single-quote character appears anywhere below (the whole script
# body is wrapped in a bash single-quoted string, which cannot contain one at
# all). SQ builds one at runtime wherever a regex or replacement needs to
# match or emit a quote character.
SQ = chr(39)
DQ = chr(34)
# Command-substitution blanking placeholder (GH #129, ported from
# irrecoverable.sh -- see _blank_substitutions below).
PH = "\x01"

# Ported from worktree-guard.py 2026-08-04, after a subagent_type
# mh:silent-failure-hunter re-verification dispatch confirmed this generator
# — despite the header comment above claiming a straight port in the other
# direction — never received three fixes worktree-guard.py needed across two
# earlier rounds the same day: heredoc-body mistokenization, ANSI-C quote
# mistokenization, and newline-as-statement-separator blindness. Confirmed
# exploitable here too by direct reproduction before porting, not assumed
# from the code shape alone. Delimiter is any run of non-whitespace,
# non-quote characters — bash allows hyphens/dots/etc (e.g. <<MY-EOF), not
# just word characters.
_HEREDOC_RE = re.compile(r"<<(-)?\s*([" + SQ + r"\"]?)([^\s" + SQ + r"\"]+)\2")
_ANSI_C_QUOTE_RE = re.compile(r"\$" + SQ + r"((?:[^" + SQ + r"\\]|\\.)*)" + SQ)
# A heredoc feeding an interpreter (bash <<EOF, python3 <<EOF, ...) is
# executable code, not inert data -- stripping it would let a write inside
# the body silently skip bash_write_targets below. Checked against the
# segment of the line before "<<", i.e. the command the heredoc is stdin
# for. Confirmed exploitable 2026-08-06: "bash <<EOF\necho x > <verifier
# path>\nEOF" reached this gate as a clean allow before this check existed.
_INTERPRETER_RE = re.compile(r"\b(bash|sh|zsh|dash|ksh|python3?|python2|perl|ruby|node|nodejs|osascript)\b")


def _strip_heredocs(cmd):
    # shlex has no concept of heredoc syntax and mis-tokenizes on any quote
    # character inside body text — heredoc bodies are literal data until the
    # closing delimiter line, not shell syntax subject to quoting rules --
    # UNLESS the heredoc feeds an interpreter, see _INTERPRETER_RE above.
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
    # argv0 like $SQ\x70SQ (SQ = single quote) never reassembles into the
    # decoded character it resolves to in real bash.
    #
    # This file own dispatch logic below compares argv0 by EXACT STRING
    # (argv0 == "tee", argv0 in ("rm", ...)) -- a boundary-only rewrite
    # ($SQ...SQ becomes a plain SQ...SQ token, escapes left raw) is
    # insufficient here: re-wrapping "$SQ\x70SQ" as "SQ\x70SQ" still yields
    # the literal token "c\x70" once glued to a preceding "c", which can
    # never equal "cp". Proven exploitable live 2026-09-03: "c$SQ\x70SQ
    # evil.sh hooks/gates/x.sh" (bash-equivalent to "cp evil.sh
    # hooks/gates/x.sh") reached bash_write_targets() with zero candidates --
    # this version diverges from the boundary-only approach on purpose,
    # actually RESOLVING the escape rather than just re-quoting it. Ported
    # verbatim from the irrecoverable.sh sibling fix for the identical root
    # cause (fixed there first the same session) -- the decode logic itself
    # needs no changes to fit here, only the surrounding names.
    #
    # Bounded escape set, matching what a cp/rm/git/dd/... argv0 or write-
    # target splice realistically needs: \xHH (hex), \nnn (1-3 octal
    # digits), and the standard single-char escapes \n \t \r \\ \SQ \DQ.
    # Anything else (\a \b \e \cX \uHHHH, ...) falls through as its raw two
    # literal characters, same as before -- a full ANSI-C decoder is out of
    # scope; those spellings are not realistic splice vectors and an
    # unhandled one just stays a literal (non-matching, safe-direction)
    # token.
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
    # statement separator and split one command window into two.
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


def _newlines_to_seps(cmd):
    # A bare newline separates Bash statements exactly like semicolon does,
    # but shlex treats \n as ordinary whitespace, so a write-only statement
    # on any line but the first is invisible to every argv0-dispatch branch
    # below. Insert a separator AFTER each real newline (never in place of
    # it) -- keeping the real newline matters because the default comment
    # handling stops consuming at (and consumes) the next literal newline;
    # replacing every newline outright would leave no newline anywhere, so a
    # single # anywhere in the command would swallow the rest of it as one
    # comment (confirmed exploitable 2026-08-04, shipped in v0.68.172). A
    # backslash immediately before the newline is a real bash line
    # continuation OUTSIDE a comment or single-quoted string (same logical
    # statement, not a separator) -- bash removes BOTH characters entirely,
    # joining the two physical lines with nothing between them, so this does
    # the same (full removal).
    #
    # A REGEX substitution over the raw string cannot make that call
    # correctly, because it has no notion of quote or comment state: a bash
    # hash comment always ends at the very next literal newline no matter
    # what precedes it (comments get zero escape processing at all --
    # backslash count is irrelevant there), so a backslash right before that
    # newline has NO continuation effect inside a comment, and single-quoted
    # content must pass through completely untouched (no continuation
    # stripping at all -- bash treats every character between quotes as
    # literal, backslash included). A prior version of this function used
    # exactly such a context-blind regex substitution and, after the GH #124
    # full-removal fix, erased a backslash-newline pair sitting inside a hash
    # comment too -- deleting the only newline that would have terminated the
    # comment for the downstream shlex reader, and swallowing the write
    # statement that followed into the same comment window (confirmed live
    # 2026-09-03, a fresh-context review of the #124 fix: a comment ending in
    # a trailing backslash right before its terminating newline, followed by
    # a real write on the next line, silently yielded zero write targets --
    # worse than pre-#124, which at least preserved the newline and asked).
    # The same context-blindness also already mishandled a backslash-newline
    # pair preceded by ANOTHER backslash (e.g. two backslashes right before a
    # comment-terminating newline) even before GH #124 existed, since the
    # regex matches only the last backslash + newline as one continuation
    # pair and does not know it is inside a comment either.
    #
    # Ported char-by-char, quote-and-comment-aware from irrecoverable.sh
    # function of the same name (GH #122/#123 fix for the identical shape at
    # that file own top-level flag checks) -- this generator needed the same
    # scan, one level deeper inside its own idiom dispatch (sed/perl -i
    # detection, dd of= prefix matching, even an argv0 split across a
    # continuation) -- all still closed by full removal here, same as the
    # regex version own GH #124 fix. Double-quoted content still gets the
    # same full-removal continuation treatment bash itself applies there, but
    # a hash inside double quotes is never a comment marker.
    out = []
    in_squote = in_dquote = in_comment = False
    i, n = 0, len(cmd)
    while i < n:
        c = cmd[i]
        if in_comment:
            if c == "\n":
                # comment ends at the literal newline, same as bash -- emit
                # the same separator a normal newline gets so the window
                # that follows still splits off correctly.
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


# GH #139: work budget for the depth-counting closer-search inside
# _blank_substitutions below, charged per character the search itself
# walks -- ported from irrecoverable.sh own identical fix. Without it, an
# adversarial run of unclosed "$(" starts costs O(remaining length) EACH,
# for O(length) starts -- O(n^2) total. Once spent, the while loop exits
# with depth still non-zero, the same fallback-to-literal path an
# already-unbalanced span already takes.
#
# GH #139 follow-up: that fallback-to-literal path is NOT safe on its own
# when budget exhaustion (not a genuinely unbalanced span) is why it was
# taken -- an un-blanked span is exactly the bypass shape this issue closed,
# so an adversary could pad a real dangerous command with just enough
# leading "$(" flood to burn the budget and hide the payload again. This
# module-level flag (mutated in place, never rebound, so no "global" needed)
# records that a search stopped BECAUSE the budget ran out -- checked once
# right after _blank_substitutions runs below, before any token reaches
# dispatch.
_DEPTH_BUDGET_BLOWN = [False]
_DEPTH_SCAN_BUDGET = 2_000_000


def _blank_substitutions(cmd):
    # Command-substitution placeholder pass (GH #129, ported from
    # irrecoverable.sh -- see that file for the full rationale). A
    # backtick/$(...)/${...} span vanishes in real bash once its (possibly
    # empty) output splices into the surrounding text -- "c$(true)p" IS "cp"
    # once bash evaluates it -- but shlex has no concept of this and treats
    # the punctuation as literal characters, so a spliced argv0 or write-
    # target survives tokenization as its own garbled token and evades every
    # exact-match dispatch below (argv0 == "cp", argv0 in ("rm", "trash"),
    # is_gate_path(target), ...). This blanks the whole span to one
    # placeholder byte (PH), which is added to shlex wordchars at the call
    # site so it fuses into the surrounding literal text as ONE token
    # instead of splitting it; any dispatch or target token that still
    # contains PH after tokenization is treated as unknowable rather than
    # trusted literally (duplicated across every known write-verb, or
    # treated as a possible protected path).
    #
    # Real shell-quote-state tracking (a left-to-right character scan, same
    # mechanism as _newlines_to_seps above), not a naive regex pairing of
    # single-quote bytes -- an ordinary English contraction inside
    # a double-quoted string must not be mistaken for a quote boundary in
    # either direction (irrecoverable.sh own history: a flat regex version
    # of this pass both let a real splice through past an unrelated
    # contraction and, separately, mis-collected real single-quoted prose as
    # a live command because of one). $(...)/`...`/${...} are only ever live
    # when unquoted or inside double quotes, never inside a genuine single-
    # quoted span. Fixed-point iterated (capped at 5 passes) to handle
    # nesting. ${...} bodies are never re-collected as a statement (a
    # parameter expansion is a variable reference, not a command); backtick/
    # $(...) bodies are, so a real command hidden inside one still gets
    # scanned by the window loop below.
    #
    # GH #139 fix (2026-09-04): a prior version of this comment named a
    # paren nested inside a $(...) span (e.g. $(f() { :; }; f)) as a
    # deliberately-out-of-scope residual that could defeat the fixed-point
    # scan -- the closer-search used to stop at the FIRST "(" or ")" byte
    # instead of the matching one, so a paren belonging to a subshell or
    # function definition inside the span left its true end un-blanked.
    # That claim is now wrong: the closer-search depth-counts same-type
    # brackets (same technique main-exec-guard.sh own _inner_cmds already
    # uses), so that example is caught. (A prior note here also claimed a
    # placeholder landing mid-flag stays recognizable as a flag --
    # factually wrong, a splice can land mid-flag same as mid-keyword;
    # removed 2026-09-04, see the full PH-removal fix in bash_write_targets
    # below.)
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
                # A hash outside any quote starts a real bash comment,
                # checked with priority ABOVE the quote-state checks below
                # (same priority order this file own sibling
                # _newlines_to_seps already uses) -- comment text is inert
                # in real bash, so a $(...)/backtick/${...} shape sitting
                # inside one must never be matched as a live substitution
                # (found: a substitution-shaped string inside a real comment
                # was still collected as a real command body, raising a
                # false ask on an innocent command).
                out.append(c)
                if c == "\n":
                    in_comment = False
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
        new = _scan_once(cmd)
        if new == cmd:
            break
        cmd = new
    if bodies:
        # Comment-truncation fix: appending with a plain " ; " separator lets
        # any `#` earlier in `cmd` (including one embedded inside an EARLIER
        # recovered body already joined here) start a shlex comment that
        # silently swallows everything appended after it -- "echo $(cp
        # evil.sh hooks/gates/x.sh)  # copy" recovers "cp evil.sh
        # hooks/gates/x.sh" as a body, but appending it after the trailing
        # "# copy" buried the whole write inside that same still-open
        # comment, with no separator to end it (shlex default comment
        # handling stops only at a literal newline, never at " ; "). A real
        # "\n" before each appended body ends any open comment the same way
        # a genuine bash newline would, then "; " starts a fresh statement --
        # same idiom this file own _newlines_to_seps already uses for real
        # newlines.
        cmd = cmd + "\n; " + "\n; ".join(bodies)
    return cmd


def _diff_targets(path):
    # Read a diff/patch file and yield the real write targets named in its
    # +++ b/<path> headers -- a patch/git-apply/am command argv never names
    # the file it actually writes; that lives inside the diff content.
    # Best-effort: an unreadable path (nonexistent, a stray redirect-operator
    # token, a binary diff) is silently skipped.
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

def _verifier_reason(fp, reason=None):
    return reason or (PROTECTED_REASON + " (" + fp + ")")

# is_gate_path -- imported above from _protected_paths (2026-08-15
# extraction; was is_verifier_path, defined inline here). Was also used by
# risk-check/SKILL.md own embedded classifier (narrower copy, missing
# hooks/advisory/ coverage) before that skill was deleted 2026-09-01,
# sweep #3 (zero lifetime dispatches).

def _has_raw_subst(tok):
    # Reviewer follow-up (2026-09-04): the Finding-4 ValueError fallback in
    # bash_write_targets below tokenizes the ORIGINAL, never-blanked command
    # string -- a spliced dispatch token reaching that path still carries
    # its literal substitution syntax (e.g. "c$(true)p"), never the PH
    # placeholder byte _blank_substitutions would have left behind. The GH
    # #129 splice-duplication trigger a few lines below is gated purely on
    # "PH in argv0", so it never fires on this path and a spliced argv0
    # sails through unrecognized (confirmed live: a quote-crossing span that
    # forces the fallback, followed by "c$(true)p evil.sh hooks/gates/x.sh",
    # was a silent allow). This is a narrow, ONE-TOKEN check for literal
    # substitution syntax still sitting in a token -- deliberately NOT a
    # bare "$" check (that would misfire on every ordinary $VAR-shaped token,
    # e.g. "$PYTHON" in "$PYTHON -m pytest", and cause a false ask where none
    # should happen).
    return "`" in tok or "$(" in tok or "${" in tok

_CMD_LEN_CAP = 150_000
# GH #140: the shlex.shlex(..., punctuation_chars=True) call below (and its
# shlex.split() ValueError fallback) has no length cap of its own, and its
# cost is superlinear in the length of a single long token -- not merely
# proportional to total input length. Measured fresh against this exact
# file, single token appended ahead of a real redirect into hooks/gates/,
# python3 cold-start included: 100,000 chars ~0.23s, 150,000 ~0.37s,
# 200,000 ~0.55s, 250,000 ~0.71s, 300,000 ~0.92s -- a 700,000-char payload
# blows straight past a 2s timeout. Checked separately: many SHORT tokens
# summing to the same total length stay fast (roughly linear) -- the
# blowup tracks the longest SINGLE token, not raw input length. A
# total-length cap still bounds the worst case either way, since no single
# token can exceed the total, even though it is more conservative than
# strictly necessary for the many-short-tokens shape. 150,000 was picked to
# keep worst-case added latency comfortably under half a second while
# being enormously generous relative to a real single-line Bash command
# (essentially never anywhere near this size -- a few hundred characters is
# already a very long one, and even an extreme case rarely reaches a few
# thousand). Checked here against the RAW cmd this function receives
# (before _strip_heredocs/_normalize_ansi_c_quotes/_blank_substitutions run
# on it below) -- irrecoverable.sh and merge-door.sh check their own cmd
# after that preprocessing already ran at module scope, so the exact string
# measured differs slightly by file; all four still bound the same
# downstream shlex cost, which is what matters. This gate own primary
# mechanism is emit_ask (see module docstring) -- fail toward ASKING, not a
# silent allow, matching every other ambiguous-input path here. Raising
# lets the existing top-level except Exception: emit_ask(...) handle it,
# the same route line ~695 own ValueError re-raise already uses for a
# genuinely malformed command.
def bash_write_targets(cmd):
    """Yield candidate file paths the Bash command writes to or deletes.
    Bounded idiom set: redirects, tee, rm, trash, sed -i, perl -i,
    cp/mv/install, dd, rsync, tar -x, patch, git apply/am. Not an
    adversarial sandbox."""
    if len(cmd) > _CMD_LEN_CAP:
        raise ValueError("command too long to safely tokenize (%d chars, cap %d)" % (len(cmd), _CMD_LEN_CAP))
    orig_cmd = cmd
    cmd = _blank_substitutions(_newlines_to_seps(_normalize_ansi_c_quotes(_strip_heredocs(cmd))))
    # GH #139 follow-up: see _DEPTH_BUDGET_BLOWN above -- a scan that could
    # not finish leaves a span un-blanked, the same bypass shape this issue
    # closed. Raising here (before shlex ever sees the possibly-corrupted
    # string) routes to this file own existing top-level except Exception:
    # emit_ask(...) the same way every other ambiguous-input path in this
    # function already does.
    if _DEPTH_BUDGET_BLOWN[0]:
        raise ValueError("command too long to safely tokenize -- nested substitution exceeded depth-scan budget")
    # No except ValueError / cmd.split() fallback on the BLANKED string on
    # purpose (GH #129, same bypass shape already fixed in irrecoverable.sh):
    # tokenizing the raw pre-blanking string on a shlex failure re-exposes
    # every splice _blank_substitutions just neutralized -- PH was never in
    # that raw string, so a spliced argv0 built this way can never match a
    # known write-verb and the whole mechanism goes inert (silent allow).
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        # $ is not in shlex default wordchars, so an unquoted redirect target
        # like $HOME/foo splits into two tokens ($ and HOME/foo) instead of
        # one. PH (GH #129) needs the same treatment so a blanked splice fuses
        # into its surrounding literal text as one token instead of splitting it.
        lex.wordchars += "$" + PH
        tokens = list(lex)
    except ValueError:
        # The ${...}/$(...)/backtick closer-search in _blank_substitutions
        # own _scan_once is not quote-boundary-aware: it scans forward for
        # the terminating char without tracking quote state for characters
        # it skips over. When that span crosses a real quote delimiter
        # (common in ordinary Python/JSON/heredoc content -- reachable here
        # because an interpreter heredoc is never stripped, see
        # _strip_heredocs above), the quote toggle is silently lost and the
        # blanked string can come out quote-unbalanced even though the
        # ORIGINAL command was not -- shlex.shlex(...) above then raises
        # ValueError on a benign command, turning it into a hard ask.
        # Distinguish self-inflicted corruption from a genuinely malformed
        # command by re-parsing the ORIGINAL, pre-blanking string as a pure
        # predicate -- if it parses cleanly, fall back to a coarser split of
        # the ORIGINAL (never the blanked string, which would re-expose the
        # exact splice the comment above warns about) instead of
        # hard-failing a benign command.
        try:
            shlex.split(orig_cmd)
        except ValueError:
            # The original was already unbalanced before blanking -- a
            # genuinely malformed command, not our own corruption. Fail
            # toward asking, never toward a silent allow: propagate to this
            # file own top-level `except Exception: emit_ask(...)` below.
            raise
        # A plain whitespace .split() glues a compound command into one
        # token stream with no separator awareness, so a dangerous command
        # placed AFTER a ;/&&/||/&, glued tight against it with no
        # surrounding whitespace, would never surface as its own window
        # below and its argv0 would never get checked at all -- a silent
        # allow strictly worse than the ask this whole branch exists to
        # give instead (found by an independent reviewer: "echo ${y:-"a}b"}"
        # corrupts the primary shlex path exactly as described above, and
        # ";cp evil.sh hooks/gates/x.sh" glued right after it, with zero
        # fallback separator-awareness, evaded the window split entirely).
        # Split on the same separators the window-builder below already
        # recognizes, keeping each one as its own token regardless of
        # adjacent whitespace (unlike .split()), then naive-word-split every
        # plain segment in between -- this feeds the window-builder the same
        # SHAPE of tokens list the primary shlex path would, just coarser.
        # "(" ")" "{" "}" deliberately excluded from this split (unlike the
        # SEPS set below) -- they show up far more often as literal
        # characters inside a corrupted ${...} span than as real grouping
        # operators, and this fallback only ever runs once the primary path
        # has already failed to make sense of the input.
        tokens = []
        for piece in re.split(r"(&&|\|\||;|\||&)", orig_cmd):
            if piece in ("&&", "||", ";", "|", "&"):
                tokens.append(piece)
            else:
                tokens.extend(piece.split())
    # Split into windows on command separators so per-command argv0 logic works.
    # ( ) { } added (2026-09-03): shlex with punctuation_chars=True already
    # tokenizes a bare ( ) as its own token (confirmed by direct testing --
    # part of shlexs default punctuation_chars string) and { } as single-char
    # tokens too (posix-mode non-wordchar splitting), but without them here
    # a grouped/braced command left the literal "(" or "{" as argv0 instead
    # of the real command inside it -- e.g. "(cp evil.sh hooks/gates/x.sh)"
    # never dispatched to the cp branch below, silently allowing the write.
    # Matches the already-shipped OPERATORS set in the sibling gates
    # irrecoverable.sh (line ~276) and merge-door.sh (line ~129). A literal
    # ( inside a QUOTED argument (e.g. a commit message "fix(gates): ...")
    # stays inside that one token and is unaffected -- shlex only emits a
    # standalone ( / ) / { / } token for an unquoted one.
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

    # GH #129 Layer 3 (2026-09-03, ported from irrecoverable.sh, same root
    # cause): a standalone vanish shifts every later token left by one
    # position in real bash, but _blank_substitutions above leaves a
    # PH-only token in its place, so the git apply/am fixed-index reads
    # below (rest[0]=="-C", rest[sub_idx]) trust the wrong position.
    # Confirmed live: "git $(true) -C <dir> apply <diff>" silently allowed
    # -- the branch is skipped entirely, not just the wrong directory. Same
    # fix as the sibling file: append a compacted copy of any window
    # carrying a bare-PH-only token, run BEFORE the KNOWN_WRITE_VERBS
    # duplication below so a compacted window whose argv0 comes out clean
    # goes through the ordinary dispatch path (duplicating it too would
    # misalign rest a second, different way).
    _aug = []
    for _w in windows:
        _wc = [_t for _t in _w if not (_t and all(_c == PH for _c in _t))]
        _aug.append(_w)
        if _wc != _w:
            _aug.append(_wc)
    windows = _aug

    KNOWN_WRITE_VERBS = ("tee", "rm", "trash", "sed", "perl", "cp", "mv",
                         "install", "rsync", "tar", "patch", "git", "dd")
    dup = []
    for w in windows:
        _argv0_tok = w[0].rsplit("/", 1)[-1] if w else ""
        # PH catches a splice the primary path blanked; _has_raw_subst
        # catches one that reached this point via the Finding-4 fallback
        # above, which tokenizes the ORIGINAL command and so never contains
        # PH at all -- see _has_raw_subst own comment for the confirmed
        # live bypass this closes.
        if w and (PH in _argv0_tok or _has_raw_subst(_argv0_tok)):
            for cand in KNOWN_WRITE_VERBS:
                dup.append([cand] + w[1:])
        else:
            dup.append(w)
    windows = dup
    for w in windows:
        if not w:
            continue
        argv0 = w[0].rsplit("/", 1)[-1]
        rest = w[1:]
        i = 0
        # redirects inside this command window: >, >>, &>, >&  [target is next token]
        while i < len(rest):
            t = rest[i]
            if t in (">", ">>", "&>", ">&"):
                if i + 1 < len(rest):
                    yield rest[i + 1]
                i += 2
                continue
            if t.startswith(">"):
                yield t.lstrip(">")
                i += 1
                continue
            i += 1
        # write-command idioms
        nonflag = [t for t in rest if not t.startswith("-")]
        # Splice-uncertainty safety net (2026-09-04 sweep): a raw, never-
        # blanked substitution token reaching here via the Finding-4
        # ValueError fallback (orig_cmd is never run through
        # _blank_substitutions, so it never carries a PH placeholder) can
        # defeat every .lstrip(PH) flag check below the same way it defeats
        # the argv0-duplication trigger above and the final target-path
        # check below -- confirmed live, independently, for sed/perl -i,
        # cp/mv/install -t, tar -C, git -C/apply-am gating, and dd of=: each
        # exact-match flag test silently fails against raw substitution
        # syntax (lstrip(PH) is a no-op on it), so the branch either yields
        # nothing at all or falls through to the wrong candidate. Rather
        # than widen each of those 5 sites with its own bespoke candidate-
        # guessing logic, yield any token that still carries raw
        # substitution syntax as its own candidate here. Gated on argv0 in
        # KNOWN_WRITE_VERBS (the same list the duplication step above
        # expands a disguised argv0 into, so a spliced verb is still
        # covered) -- an earlier ungated version fired on every window
        # regardless of verb, and a benign interpreter heredoc body (for
        # example a python3 script with literal ${ text in a data
        # structure, no shell substitution involved at all) tripped a false
        # ask purely from unrelated data sitting in that window own rest.
        # The downstream expand+check a few lines down (PH in expanded or
        # _has_raw_subst(expanded) or is_gate_path(expanded)) that closes
        # the target-path gap already asks on whatever this yields.
        if argv0 in KNOWN_WRITE_VERBS:
            for _t in rest:
                if _has_raw_subst(_t):
                    yield _t
        if argv0 == "tee":
            for t in nonflag:
                yield t
        elif argv0 in ("rm", "trash"):
            # Deleting a verifier surface neuters it as completely as
            # editing it, and a plain `rm <file>` on a regular file needs
            # neither -r nor -f -- irrecoverable.sh only denies rm when
            # BOTH flags are present, so a bare rm never reaches that
            # check at all. trash is a common local alias for rm (this
            # very repo has one) and had zero coverage anywhere (found
            # 2026-08-06).
            for t in nonflag:
                yield t
        elif argv0 in ("sed", "perl"):
            # Full PH removal (2026-09-04, cross-file review): a splice can
            # land MID-flag too (-$(true)i -> -PHi), not just leading --
            # lstrip only strips the left edge, so a mid-flag splice left
            # this whole outer gate False and the branch yielded nothing at
            # all, a total silent bypass, not just one missed check.
            # Confirmed live: sed -$(true)i -e s/x/y/ hooks/gates/z.sh ->
            # rc=0, silent allow (in-place edit to a gate file). .replace
            # removes PH from anywhere in the token, same treatment
            # irrecoverable.sh already uses for its SQL-keyword scan.
            # _has_raw_subst(t) covers the fallback path the same way
            # Finding A widened the final check -- a flag token that still
            # carries raw substitution syntax (never blanked, so .replace
            # finds no PH to remove) counts as unknowable, ask on it rather
            # than silently trust it is not -i.
            if any(t.replace(PH, "") in ("-i", "--in-place") or _has_raw_subst(t) for t in rest) or \
               any(t.replace(PH, "").startswith("-i") and t.replace(PH, "") != "-i" for t in rest):
                # skip -e/-i values; remaining nonflag args are the files
                skipnext = False
                for t in rest:
                    if skipnext:
                        skipnext = False
                        continue
                    if t.replace(PH, "") in ("-e", "--expression"):
                        skipnext = True
                        continue
                    if not t.replace(PH, "").startswith("-") and t not in ("-", ""):
                        yield t
        elif argv0 in ("cp", "mv", "install"):
            # -t / --target-directory= sets the destination explicitly and the
            # remaining nonflag args become SOURCES, so nonflag[-1] would yield
            # a source and the real destination is lost (found v0.36.0 audit:
            # `cp -t hooks/gates/ evil.sh` silently allowed evil.sh into the
            # verifier dir). When -t is present, yield its value instead.
            # GNU coreutils also accepts -t joined to its value (-thooks/gates/)
            # and bundled with other short flags (-rthooks/gates/) -- the exact
            # form matched above misses both (found in the v0.36.0-fix follow-up
            # audit, still lands as a source via nonflag[-1]). A short-flag token
            # containing a literal t with trailing chars covers both joined and
            # bundled forms; this is a habit-guard heuristic (widens the match,
            # never narrows it), not full getopt parsing.
            # Full PH removal (2026-09-04, cross-file review): a splice can
            # land mid-flag too (-$(true)t -> -PHt), not just leading --
            # .replace strips PH from anywhere, same treatment
            # irrecoverable.sh already uses for its SQL-keyword scan.
            # Confirmed live: cp -$(true)t hooks/gates/ evil.sh -> rc=0,
            # silent allow (real destination hooks/gates/ never recognized,
            # nonflag[-1]="evil.sh" checked instead). A token still carrying
            # raw substitution syntax (fallback path, .replace finds no PH
            # to remove) is treated the same as a real -t match below --
            # unknowable, ask rather than silently trust it is not -t.
            tgt = None
            for j, t in enumerate(rest):
                dt = t.replace(PH, "")
                if _has_raw_subst(t):
                    tgt = t
                    break
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
                    # bundle ending in t with no joined value (-rt DIR): the
                    # next token is the target dir, same idiom as -t DIR above,
                    # just bundled with other short flags first (found in the
                    # compliance-audit adversarial pass: -tDIR and -rtDIR were
                    # closed but -rt DIR space-separated was not)
                    tgt = rest[j + 1]
                    break
            if tgt is not None:
                yield tgt
            elif nonflag:
                yield nonflag[-1]  # no -t → last nonflag is the destination
        elif argv0 == "rsync":
            # No -t/--target-directory idiom to worry about; the destination is
            # always the last nonflag arg.
            if nonflag:
                yield nonflag[-1]
        elif argv0 == "tar":
            # Extract mode writes files into -C/--directory when present. When
            # absent (tar xf a.tar, the common case -- writes into cwd), yield
            # cwd itself via ".". Known residual gap even with this fallback:
            # is_verifier_path checks a substring/endswith pattern against
            # the resolved path, and "." rarely spells out a protected
            # pattern on its own -- closing that fully would need a
            # different check shape, tracked separately, not attempted here
            # (confirmed 2026-08-04, silent-failure-hunter round 4).
            # Full PH removal (2026-09-04, cross-file review, parity with
            # the cp/mv/install -t and sed/perl -i fix above): a splice can
            # land mid-flag or mid-mode-string too, not just leading --
            # .replace strips PH from anywhere, same treatment
            # irrecoverable.sh already uses for its SQL-keyword scan.
            mode_str = rest[0].replace(PH, "") if rest and not rest[0].replace(PH, "").startswith("--") else ""
            has_extract = ("x" in mode_str.lstrip("-")) or any(t.replace(PH, "") == "--extract" for t in rest)
            if has_extract:
                yielded_dir = False
                # A -C/--directory flag that still carries raw substitution
                # syntax (fallback path, .replace finds no PH to remove) is
                # unknowable -- same Finding-A-style widening as cp/mv/
                # install -t above -- yield it directly instead of falling
                # through to the "." fallback and losing the real target.
                for j, t in enumerate(rest):
                    dt = t.replace(PH, "")
                    if _has_raw_subst(t):
                        yield t
                        yielded_dir = True
                        break
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
        elif argv0 == "patch":
            # patch <file> < diff rewrites <file> in place -- already handled
            # by the plain nonflag yield below. The common multi-file form
            # (patch -pN < diff.patch, or a patch-file arg instead of stdin)
            # names its real targets inside the diff +++ b/<path> headers,
            # never in argv -- confirmed exploitable 2026-08-04 (silent-
            # failure-hunter round 4): a diff-content scan on every nonflag
            # token closes it, the same technique already used below for git
            # apply/am. -d/--directory relocates where a relative in-diff
            # target actually resolves; without folding it in, this
            # generator would check the wrong path when patch does not run
            # from the guarded repo own root (ported from worktree-guard.py,
            # which already carries this fix).
            # Full PH removal (2026-09-04, cross-file review): the -o/-d
            # separate-token forms below used a bare exact match with no PH
            # handling at all -- worse than leading-only, since a splice
            # ANYWHERE in -o/-d (not just mid-flag) skipped these checks. A
            # disguised -d in particular left directory=None, so a diff
            # relying on -d to relocate an otherwise-unrecognizable target
            # (same shape as Finding 10, fixed only for --directory= before)
            # was silently unrelocated. .replace strips PH from anywhere;
            # _has_raw_subst(t) covers the fallback path the same way
            # Finding A widened the final check.
            directory = None
            for j, t in enumerate(rest):
                if (t.replace(PH, "") in ("-o", "--output") or _has_raw_subst(t)) and j + 1 < len(rest):
                    yield rest[j + 1]
                if (t.replace(PH, "") in ("-d", "--directory") or _has_raw_subst(t)) and j + 1 < len(rest):
                    directory = rest[j + 1]
                dt = t.replace(PH, "")
                if dt.startswith("--directory="):
                    directory = dt[len("--directory="):]
            for t in nonflag:
                yield t
                for target in _diff_targets(t):
                    yield os.path.join(directory, target) if directory else target
        elif argv0 == "git":
            # The real target of git apply or git am lives inside the diff
            # +++ b/path lines, not argv -- the natural way to silently rewrite
            # a gate file in one command (found in the v0.36.0-fix follow-up
            # audit: zero coverage). Habit-guard: yield the diff-file arg
            # itself (harmless if it does not match a verifier path) and, when
            # readable, scan it for the paths it actually touches. A diff piped
            # via stdin (git apply < x.diff) or an obfuscated target inside the
            # diff is outside this bounded idiom set -- not an adversarial
            # sandbox. git -C <dir> apply/am puts the real subcommand one slot
            # later than a bare "git apply" -- missing this dispatch left the
            # whole -C form invisible to this generator (confirmed 2026-08-04,
            # silent-failure-hunter round 4, folded into the same fix pass
            # since it is the identical apply/am gap one token over). -C also
            # relocates where a relative in-diff target resolves, same as
            # patch -d/--directory above -- found the hard way: an earlier
            # version of this fix dispatched into the branch correctly but
            # still resolved the diff relative path against the cwd the hook
            # runs in, missing the actual -C directory entirely.
            # Full PH removal (2026-09-04, cross-file review): a splice
            # landing mid-flag (-$(true)C) or mid-subcommand (a$(true)pply)
            # made BOTH outer checks below false, skipping this whole
            # branch entirely -- a total silent bypass, not just one missed
            # check. .replace strips PH from anywhere; _has_raw_subst(t)
            # covers the fallback path the same way Finding A widened the
            # final check -- an unknowable -C or subcommand token is
            # treated as if it matched, fail-safe.
            sub_idx, directory = 0, None
            if len(rest) > 1 and (rest[0].replace(PH, "") == "-C" or _has_raw_subst(rest[0])):
                sub_idx, directory = 2, rest[1]
            if len(rest) > sub_idx and (rest[sub_idx].replace(PH, "") in ("apply", "am") or _has_raw_subst(rest[sub_idx])):
                diff_args = [t for t in rest[sub_idx + 1:] if not t.startswith("-")]
                for t in diff_args:
                    yield t
                    for target in _diff_targets(t):
                        yield os.path.join(directory, target) if directory else target
        elif argv0 == "dd":
            # dd of=<path> writes to <path>. /dev/ raw-device writes are
            # denied by irrecoverable.sh; here we surface non-/dev of= targets
            # so writing a verifier-surface file (a gate, hooks.json, an audit
            # check) triggers the recoverable ASK (found v0.36.0 audit: dd had
            # no verifier-protect coverage at all).
            # Full PH removal (2026-09-04, cross-file review), same pattern
            # as cp/mv/install -t above: a splice can land mid-flag
            # (o$(true)f=...), not just leading. .replace strips PH from
            # anywhere; _has_raw_subst(t) covers the fallback path the same
            # way Finding A widened the final check.
            for t in rest:
                dt = t.replace(PH, "")
                if _has_raw_subst(t):
                    yield t
                    continue
                if dt.startswith("of=") and not dt.startswith("of=/dev/"):
                    yield dt[len("of="):]

try:
    d = json.load(sys.stdin)
    tool = d.get("tool_name", "")
    ti = d.get("tool_input")
    if not isinstance(ti, dict):
        # A present-but-non-dict tool_input (e.g. JSON null) previously
        # collapsed via "or {}" into a clean allow, silently defeating the
        # never-resolve-to-a-silent-allow invariant documented above
        # (found 2026-08-06).
        emit_ask(_verifier_reason("<missing/malformed tool_input>", (
            "verifier-protect received a PreToolUse payload with no usable "
            "tool_input and cannot confirm this write is safe. Fail-safe: "
            "approve manually or deny."
        )))
        sys.exit(0)

    if tool == "Bash":
        cmd = ti.get("command", "") or ""
        for p in bash_write_targets(cmd):
            # A candidate can still carry a literal ~ or $VAR here —
            # tokenization alone does not expand it, and is_verifier_path
            # never did either. Expand both, or a target that really
            # resolves into a protected path never matches.
            expanded = os.path.expandvars(os.path.expanduser(p))
            # Finding A (2026-09-04 sweep, confirmed live): a raw substitution
            # that reached here via the Finding-4 fallback never carries PH
            # (orig_cmd is never blanked) and its literal text does not
            # contain a contiguous protected-path substring either -- e.g.
            # "hoo$(true)ks/gates/x.sh" matches neither PH-in-expanded nor
            # is_gate_path. Widened the same way as the argv0-duplication
            # trigger and the flag-detection safety net above: treat any
            # candidate still carrying raw substitution syntax as unknowable
            # and ask on it rather than silently trust it.
            if PH in expanded or _has_raw_subst(expanded) or is_gate_path(expanded):
                emit_ask(_verifier_reason(expanded, "Bash write to a verifier surface (" + expanded + ") — " + PROTECTED_REASON))
                break
        sys.exit(0)

    fp = ti.get("file_path", "") or ti.get("notebook_path", "") or ""

    # path-hardcode deny (folded 2026-07-03): block /Users/[a-zA-Z] in
    # .sh/.py/.js before the ask (a block exit 2 wins over an ask). Preserves
    # the case-insensitive endswith gate, the content/new_string scan, and
    # the MultiEdit edits[] accumulation. .js added 2026-08-24 (#93): shipped
    # workflow runners under scripts/workflows/ are .js and were the one
    # scripted-surface class this deny did not cover.
    if fp and fp.lower().endswith((".sh", ".py", ".js")):
        content = ti.get("content") or ti.get("new_string") or ""
        for edit in ti.get("edits") or []:
            content += "\n" + (edit.get("new_string") or "")
        if re.search(r"/Users/[a-zA-Z]", content):
            print("[mh:gate] BLOCKED: hardcoded /Users/ path in " + fp +
                  " — use $HOME or ~ instead", file=sys.stderr)
            sys.exit(2)

    if is_gate_path(fp):
        emit_ask(_verifier_reason(fp))
except Exception:
    # Cannot confirm this write is safe — fail toward asking, never toward a
    # silent allow.
    emit_ask(_verifier_reason("<unparsed tool input>", (
        "verifier-protect could not parse this tool call and cannot confirm "
        "it is safe. Fail-safe: approve manually or deny."
    )))
' "$(dirname "$0")/lib"
