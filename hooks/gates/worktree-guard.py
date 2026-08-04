#!/usr/bin/env python3
# ponytail: generic worktree guard (moved from dotfiles 2026-07-02). Redirects Edit/Write on
# a SUB-repo's main checkout so parallel terminals can't clobber one shared working tree.
# Branch alone can't fix this — one repo dir = one working tree regardless of branch; the
# worktree is the isolation. Auto-creates a session-scoped worktree under WT_ROOT and
# transparently redirects the edit there via PreToolUse updatedInput.
# ponytail: branch name is `wip/<session-id>` — session_id is the only stable identifier
# this hook has. Rename the branch to your ticket key before opening a PR.
# Base selection: KBG_WORKTREE_BASE=<branch> fetches origin/<branch> and bases the
# auto-worktree there (hotfix sessions: KBG_WORKTREE_BASE=main). Unset = current HEAD of
# the main checkout, which can lag origin; prefer an explicit worktree for hotfix work.
# Fetch failure falls back to HEAD — never blocks editing on network.
# Guarded workspace is opt-in and unset by default: KBG_GUARDED_WORKSPACE has NO default,
# so this gate is a total NO-OP for every project unless the operator sets it (this is a
# public plugin — no client/workspace path ships in this file). Exempt even when set: the
# workspace-root repo itself (docs/standups/plans).
# Fails OPEN on any error. Escape: KBG_ALLOW_MAIN_EDIT=1.
# Test seams: KBG_GUARDED_WORKSPACE / KBG_WORKTREE_ROOT override the default roots.
# Bash coverage (2026-07-16): the Write/Edit/NotebookEdit matcher never sees a
# Bash-mediated write (echo >>, sed -i, tee, cp/mv) to a protected checkout —
# the same blind spot verifier-protect.sh closed for the verifier surfaces on
# 2026-07-03. bash_write_targets() below is a straight port of that gate's
# generator. Unlike the Write/Edit path, a raw shell command's target can't be
# transparently rewritten via updatedInput, so the Bash branch denies (exit 2)
# instead of auto-redirecting — this must not be weaker than the Write path's
# unconditional redirect, or the gap this fix closes reopens on the Bash side.
import json, os, re, shlex, subprocess, sys

WORKSPACE = os.path.expanduser(os.environ.get("KBG_GUARDED_WORKSPACE", ""))
WT_ROOT = os.path.expanduser(os.environ.get("KBG_WORKTREE_ROOT", "~/.worktrees"))
PROTECTED = {"main", "master", "develop"}


def git(args, cwd):
    try:
        return subprocess.run(["git", "-C", cwd, *args],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


def git_ok(args, cwd):
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


_LINE_CONT_RE = re.compile(r"\\\n")


def _newlines_to_seps(cmd):
    """A bare newline separates Bash statements exactly like ';' does, but
    shlex's whitespace set includes \\n, so it's swallowed as ordinary
    inter-token whitespace and never lands in SEPS below -- a write-only
    statement on any line but the first is invisible to every argv0-dispatch
    branch. Convert non-continuation newlines to ';' before tokenizing. A
    backslash immediately before the newline is a real bash line continuation
    (same logical statement, not a separator) -- left alone for shlex's own
    (slightly quirky but harmless for target-detection purposes) handling.
    Confirmed exploitable (2026-08-04): a write statement on a later line of a
    multi-statement command bypassed this gate silently (exit 0)."""
    placeholder = "\x00"
    cmd = _LINE_CONT_RE.sub(placeholder, cmd)
    cmd = cmd.replace("\n", " ; ")
    return cmd.replace(placeholder, "\\\n")


def _normalize_ansi_c_quotes(cmd):
    """shlex doesn't understand bash's ANSI-C quoting ($'...') -- it splits on
    the bare `$` instead of treating the whole span as one token, so a target
    like $'weird\\tname.txt' yields the literal string '$' as the "target"
    instead of the real filename. Rewriting $'...' to a plain '...' token fixes
    token BOUNDARIES (what this gate needs) even though it doesn't reproduce
    bash's own backslash-escape interpretation inside the quotes (out of scope
    -- this generator is explicitly "not an adversarial sandbox")."""
    return _ANSI_C_QUOTE_RE.sub(lambda m: "'" + m.group(1) + "'", cmd)


def bash_write_targets(cmd):
    """Yield candidate file paths a Bash command writes to. Ported from
    verifier-protect.sh's generator of the same name (bounded idiom set:
    redirects, tee, sed -i, cp/mv/install, rsync, tar -x, patch, git apply/am,
    dd of=; not an adversarial sandbox)."""
    cmd = _newlines_to_seps(_normalize_ansi_c_quotes(_strip_heredocs(cmd)))
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
        tokens = list(lex)
    except ValueError:
        tokens = cmd.split()
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
        if argv0 == "tee":
            for t in nonflag:
                yield t
        elif argv0 in ("sed", "perl"):
            if any(t in ("-i", "--in-place") or t == "-i" for t in rest) or \
               any(t.startswith("-i") and t != "-i" for t in rest):
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
            for j, t in enumerate(rest):
                if t in ("-o", "--output") and j + 1 < len(rest):
                    yield rest[j + 1]
            for t in nonflag:
                yield t
        elif argv0 == "git" and rest and rest[0] in ("apply", "am"):
            diff_args = [t for t in rest[1:] if not t.startswith("-")]
            for t in diff_args:
                yield t
        elif argv0 == "dd":
            for t in rest:
                if t.startswith("of=") and not t.startswith("of=/dev/"):
                    yield t[len("of="):]


def classify(fp):
    """fp is an already-abspath'd candidate file path. Returns
    (repo, top, why, branch) if it sits on a protected main checkout
    or protected branch inside the configured guarded workspace, else None
    (out of scope or already safe — a real worktree on a non-protected
    branch). Shared by both the Write/Edit path and the Bash path so they
    can't drift into two different definitions of "protected"."""
    if not WORKSPACE or not os.path.isabs(WORKSPACE):
        return None  # unset/relative KBG_GUARDED_WORKSPACE -> gate is off, not "guard cwd"
    if not under(fp, WORKSPACE):
        return None  # other projects untouched
    cwd = nearest_dir(fp)
    top = git(["rev-parse", "--show-toplevel"], cwd)
    if not top:
        return None  # not a git repo
    if os.path.realpath(top) == os.path.realpath(WORKSPACE):
        return None  # workspace-root docs repo
    gd = git(["rev-parse", "--absolute-git-dir"], cwd)
    common = git(["rev-parse", "--git-common-dir"], cwd)
    if common and not os.path.isabs(common):
        common = os.path.join(cwd, common)
    in_worktree = bool(gd) and bool(common) and os.path.realpath(gd) != os.path.realpath(common)
    branch = git(["rev-parse", "--abbrev-ref", "HEAD"], cwd)
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
        f"then re-run the edit there. One-off override: KBG_ALLOW_MAIN_EDIT=1",
        file=sys.stderr,
    )
    return 2


def main():
    if os.environ.get("KBG_ALLOW_MAIN_EDIT") == "1":
        return 0
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}

    if tool == "Bash":
        cmd = ti.get("command", "") or ""
        for p in bash_write_targets(cmd):
            if not p:
                continue
            result = classify(os.path.abspath(p))
            if result is not None:
                repo, top, why, _branch = result
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
    base = os.environ.get("KBG_WORKTREE_BASE", "").strip()
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
            f"production branch — set KBG_WORKTREE_BASE=main (or create the hotfix worktree explicitly). "
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
