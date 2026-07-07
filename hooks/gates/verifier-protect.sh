#!/usr/bin/env bash
# Gate: prompt the human to approve any Write/Edit/MultiEdit — OR a Bash-mediated
# write (redirect, tee, sed -i, perl -i, cp, mv) — to the verifier surfaces:
# hooks/gates/**, hooks/hooks.json, AND the non-model audit verifier
# (skills/harness-audit/scripts/audit.sh + checks/**) — so the model cannot
# neuter the deny-gates OR weaken the audit checks that judge it without an
# in-session human approval (the tamper-resistance principle: the agent cannot
# edit the code that judges it). A gate/check the model can silently disable is
# not a computational deny — and a half-protected perimeter is worse than none,
# so BOTH deterministic verifiers (the gates AND the audit) are guarded.
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
# to a silent allow on a tamper-resistance gate).
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
# branch. It blocks a hardcoded /Users/<name> path written into a .sh or .py
# file (case-insensitive endswith; scans content/new_string and MultiEdit
# edits[]) by exiting 2 BEFORE the verifier ask — a block wins over an ask,
# matching the prior parallel behavior where path-hardcode denied while this
# gate asked. Folding removes one python3 spawn per Write/Edit (a CPU win,
# not a felt-latency win: this gate's own python cold-start remains the
# Write-matcher floor). path-hardcode.sh and its hooks.json entry are deleted.
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import sys, json, os, shlex, re

PROTECTED_REASON = (
    "Editing a verifier surface — the deny-gates or audit checks that "
    "judge the model live here. Tamper-resistance: the model cannot edit "
    "the code that judges it without your approval."
)

def emit_ask(fp, reason=None):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason or (PROTECTED_REASON + " (" + fp + ")"),
        }
    }))

def is_verifier_path(fp):
    if not fp:
        return False
    norm = fp.lstrip()
    if norm.startswith("./"):
        norm = norm[2:]
    try:
        norm = os.path.realpath(norm)
    except Exception:
        pass
    nl = norm.lower()
    rel = fp.lstrip()
    if rel.startswith("./"):
        rel = rel[2:]
    rl = rel.lower()
    if "/hooks/gates/" in nl or nl.endswith("/hooks/gates"):
        return True
    if nl.endswith("/hooks/hooks.json"):
        return True
    if nl.endswith("/skills/harness-audit/scripts/audit.sh"):
        return True
    if "/skills/harness-audit/scripts/checks/" in nl or \
       nl.endswith("/skills/harness-audit/scripts/checks"):
        return True
    if rl == "hooks/hooks.json" or rl.startswith("hooks/gates/"):
        return True
    if rl == "skills/harness-audit/scripts/audit.sh" or \
       rl.startswith("skills/harness-audit/scripts/checks/") or \
       rl == "skills/harness-audit/scripts/checks":
        return True
    return False

def bash_write_targets(cmd):
    """Yield candidate file paths the Bash command writes to. Bounded idiom
    set: redirects, tee, sed -i, perl -i, cp/mv/install, dd, rsync, tar -x,
    patch, git apply/am. Not an adversarial sandbox."""
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
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
            # Extract mode writes files into -C/--directory (or CWD, already
            # covered by the is_verifier_path relative-path handling). Old-style
            # bare mode clusters (tar xf a.tar) and dash-prefixed ones (-xf)
            # both put the mode letters in the first arg after argv0.
            mode_str = rest[0] if rest and not rest[0].startswith("--") else ""
            has_extract = ("x" in mode_str.lstrip("-")) or ("--extract" in rest)
            if has_extract:
                for j, t in enumerate(rest):
                    if t in ("-C", "--directory") and j + 1 < len(rest):
                        yield rest[j + 1]
                        break
                    if t.startswith("--directory="):
                        yield t[len("--directory="):]
                        break
        elif argv0 == "patch":
            # patch <file> < diff rewrites <file> in place; -o/--output
            # redirects elsewhere. Target is a plain nonflag arg either way.
            for j, t in enumerate(rest):
                if t in ("-o", "--output") and j + 1 < len(rest):
                    yield rest[j + 1]
            for t in nonflag:
                yield t
        elif argv0 == "git" and rest and rest[0] in ("apply", "am"):
            # The real target of git apply or git am lives inside the diff
            # +++ b/path lines, not argv -- the natural way to silently rewrite
            # a gate file in one command (found in the v0.36.0-fix follow-up
            # audit: zero coverage). Habit-guard: yield the diff-file arg
            # itself (harmless if it does not match a verifier path) and, when
            # readable, scan it for the paths it actually touches. A diff piped
            # via stdin (git apply < x.diff) or an obfuscated target inside the
            # diff is outside this bounded idiom set -- not an adversarial
            # sandbox.
            diff_args = [t for t in rest[1:] if not t.startswith("-")]
            for t in diff_args:
                yield t
                try:
                    with open(t, "r", errors="ignore") as f:
                        for line in f:
                            if line.startswith("+++ "):
                                p = line[4:].strip()
                                if p.startswith("b/"):
                                    p = p[2:]
                                if p != "/dev/null":
                                    yield p
                except OSError:
                    pass
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
    ti = d.get("tool_input", {}) or {}

    if tool == "Bash":
        cmd = ti.get("command", "") or ""
        for p in bash_write_targets(cmd):
            if is_verifier_path(p):
                emit_ask(p, "Bash write to a verifier surface (" + p + ") — " + PROTECTED_REASON)
                break
        sys.exit(0)

    fp = ti.get("file_path", "") or ti.get("notebook_path", "") or ""

    # path-hardcode deny (folded 2026-07-03): block /Users/[a-zA-Z] in .sh/.py
    # before the ask (a block exit 2 wins over an ask). Preserves the
    # case-insensitive .sh/.py endswith gate, the content/new_string scan, and
    # the MultiEdit edits[] accumulation.
    if fp and fp.lower().endswith((".sh", ".py")):
        content = ti.get("content") or ti.get("new_string") or ""
        for edit in ti.get("edits") or []:
            content += "\n" + (edit.get("new_string") or "")
        if re.search(r"/Users/[a-zA-Z]", content):
            print("[kbg:gate] BLOCKED: hardcoded /Users/ path in " + fp +
                  " — use $HOME or ~ instead", file=sys.stderr)
            sys.exit(2)

    if is_verifier_path(fp):
        emit_ask(fp)
except Exception:
    # Cannot confirm this write is safe — fail toward asking, never toward a
    # silent allow.
    emit_ask("<unparsed tool input>", (
        "verifier-protect could not parse this tool call and cannot confirm "
        "it is safe. Fail-safe: approve manually or deny."
    ))
'