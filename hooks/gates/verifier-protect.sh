#!/usr/bin/env bash
# Gate: prompt the human to approve any Write/Edit/MultiEdit — OR a Bash-mediated
# write (redirect, tee, sed -i, perl -i, cp, mv, rm, trash) — to the verifier
# surfaces: hooks/gates/**, hooks/advisory/**, hooks/hooks.json, the
# PreToolUse dispatcher's own routing (hooks/pretooluse-table.json,
# hooks/dispatch-pretooluse.py/.sh), AND the non-model audit verifier
# (skills/harness-audit/scripts/audit.sh + checks/**) — so the model cannot
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
# Match the quoted tool_name value precisely (the "Bash" is the JSON value, not
# a substring of a longer word) so a Write to a file_path that happens to
# contain "Bash" is not mis-routed through the Bash fast-path (which could exit
# 0 and skip the gate's primary Write-path protection). [[ =~ ]] is used
# because a `case` pattern cannot contain literal double-quotes cleanly (the
# syntax-error lockout on the first attempt). The regex tolerates the optional
# space after the colon in both JSON serializations.
if [[ $_ws =~ \"tool_name\"[[:space:]]*:[[:space:]]*\"Bash\" ]]; then
  _norm="$(printf '%s' "$_ws" | tr -d "\"'\\")"
  case "$_norm" in
    *git*|*patch*|*tar*) : ;;  # diff/archive carrier -> target may be in a file/cwd -> python
    *tee*|*sed*|*perl*|*cp*|*mv*|*install*|*rsync*|*dd*|*rm*|*trash*|*">"*)
      case "$_norm" in
        *hooks/gates*|*hooks/advisory*|*hooks/hooks.json*|*hooks/pretooluse-table.json*|*hooks/dispatch-pretooluse*|*skills/harness-audit*|*'$'*|*'~'*) : ;;  # write + verifier path (or an expandable target) -> python
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
_LINE_CONT_RE = re.compile(r"\\\n")
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
    # shlex does not understand ANSI-C quoting ($SQ...SQ) — it splits on the
    # bare $ instead of treating the whole span as one token. Rewriting to a
    # plain quoted token fixes token BOUNDARIES, which is all this generator
    # needs (not a full backslash-escape reimplementation).
    return _ANSI_C_QUOTE_RE.sub(lambda m: SQ + m.group(1) + SQ, cmd)


def _newlines_to_seps(cmd):
    # A bare newline separates Bash statements exactly like semicolon does,
    # but shlex treats \n as ordinary whitespace, so a write-only statement
    # on any line but the first is invisible to every argv0-dispatch branch
    # below. Insert a separator AFTER each non-continuation newline (never in
    # place of it) — keeping the real newline matters because the default
    # comment handling stops consuming at the next literal newline; replacing
    # every newline outright would let a single # anywhere swallow the rest
    # of the command as one comment.
    placeholder = "\x00"
    cmd = _LINE_CONT_RE.sub(placeholder, cmd)
    cmd = cmd.replace("\n", "\n; ")
    return cmd.replace(placeholder, "\\\n")


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
# extraction; was is_verifier_path, defined inline here). Also used by
# the embedded classifier in skills/risk-check/SKILL.md, which previously had its own
# narrower copy missing hooks/advisory/ coverage.

def bash_write_targets(cmd):
    """Yield candidate file paths the Bash command writes to or deletes.
    Bounded idiom set: redirects, tee, rm, trash, sed -i, perl -i,
    cp/mv/install, dd, rsync, tar -x, patch, git apply/am. Not an
    adversarial sandbox."""
    cmd = _newlines_to_seps(_normalize_ansi_c_quotes(_strip_heredocs(cmd)))
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        # $ is not in shlex default wordchars, so an unquoted redirect target
        # like $HOME/foo splits into two tokens ($ and HOME/foo) instead of
        # one.
        lex.wordchars += "$"
        tokens = list(lex)
    except ValueError:
        tokens = cmd.split()
    # Split into windows on command separators so per-command argv0 logic works.
    SEPS = {";", "&&", "||", "|", "&"}
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
            if any(t in ("-i", "--in-place") or t == "-i" for t in rest) or \
               any(t.startswith("-i") and t != "-i" for t in rest):
                # skip -e/-i values; remaining nonflag args are the files
                skipnext = False
                for t in rest:
                    if skipnext:
                        skipnext = False
                        continue
                    if t in ("-e", "--expression"):
                        skipnext = True
                        continue
                    if not t.startswith("-") and t not in ("-", ""):
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
            tgt = None
            for j, t in enumerate(rest):
                if t in ("-t", "--target-directory") and j + 1 < len(rest):
                    tgt = rest[j + 1]
                    break
                if t.startswith("--target-directory="):
                    tgt = t[len("--target-directory="):]
                    break
                if t.startswith("-") and not t.startswith("--") and len(t) > 2:
                    m = re.match(r"^-[a-zA-Z]*t(.+)$", t)
                    if m:
                        tgt = m.group(1)
                        break
                if t.startswith("-") and not t.startswith("--") and \
                   re.match(r"^-[a-zA-Z]*t$", t) and j + 1 < len(rest):
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
            mode_str = rest[0] if rest and not rest[0].startswith("--") else ""
            has_extract = ("x" in mode_str.lstrip("-")) or ("--extract" in rest)
            if has_extract:
                yielded_dir = False
                for j, t in enumerate(rest):
                    if t in ("-C", "--directory") and j + 1 < len(rest):
                        yield rest[j + 1]
                        yielded_dir = True
                        break
                    if t.startswith("--directory="):
                        yield t[len("--directory="):]
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
            # apply/am.
            for j, t in enumerate(rest):
                if t in ("-o", "--output") and j + 1 < len(rest):
                    yield rest[j + 1]
            for t in nonflag:
                yield t
                yield from _diff_targets(t)
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
            sub_idx, directory = 0, None
            if len(rest) > 1 and rest[0] == "-C":
                sub_idx, directory = 2, rest[1]
            if len(rest) > sub_idx and rest[sub_idx] in ("apply", "am"):
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
            for t in rest:
                if t.startswith("of=") and not t.startswith("of=/dev/"):
                    yield t[len("of="):]

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
            if is_gate_path(expanded):
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
