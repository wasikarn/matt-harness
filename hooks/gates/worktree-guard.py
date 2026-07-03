#!/usr/bin/env python3
# ponytail: tathep worktree guard (moved from dotfiles 2026-07-02). Redirects Edit/Write on
# a SUB-repo's main checkout so parallel terminals can't clobber one shared working tree.
# Branch alone can't fix this — one repo dir = one working tree regardless of branch; the
# worktree is the isolation. Auto-creates a session-scoped worktree under WT_ROOT and
# transparently redirects the edit there via PreToolUse updatedInput.
# ponytail: branch name is `wip/<session-id>` — session_id is the only stable identifier
# this hook has. Rename the branch to TP-XXX before opening a PR.
# Base selection: TATHEP_BASE=<branch> fetches origin/<branch> and bases the auto-worktree
# there (hotfix sessions: TATHEP_BASE=main — see tathep CLAUDE.md § Branching). Unset =
# current HEAD of the main checkout, which can lag origin; prefer an explicit worktree for
# hotfix work. Fetch failure falls back to HEAD — never blocks editing on network.
# Exempt: workspace-root repo (docs/standups/plans) and anything outside the tathep
# workspace — this gate is a NO-OP for every other project the plugin loads in.
# Fails OPEN on any error. Escape: TATHEP_ALLOW_MAIN_EDIT=1.
# Test seams: TATHEP_WORKSPACE / TATHEP_WT_ROOT override the default roots.
import json, os, subprocess, sys

WORKSPACE = os.path.expanduser(os.environ.get("TATHEP_WORKSPACE", "~/Codes/Works/tathep"))
WT_ROOT = os.path.expanduser(os.environ.get("TATHEP_WT_ROOT", "~/.worktrees"))
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


def deny(repo, top, why):
    print(
        f"⛔ {repo}: editing on {why}. Parallel terminals here clobber one working tree.\n"
        f"Create a worktree first (all tathep worktrees live under {WT_ROOT}/):\n"
        f"  git -C {top} worktree add {WT_ROOT}/{repo}-TP-XXX -b feature/TP-XXX-slug\n"
        f"  cd {WT_ROOT}/{repo}-TP-XXX\n"
        f"then re-run the edit there. One-off override: TATHEP_ALLOW_MAIN_EDIT=1",
        file=sys.stderr,
    )
    return 2


def main():
    if os.environ.get("TATHEP_ALLOW_MAIN_EDIT") == "1":
        return 0
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    ti = data.get("tool_input", {}) or {}
    field = "file_path" if "file_path" in ti else ("notebook_path" if "notebook_path" in ti else None)
    fp = ti.get(field) if field else None
    if not fp:
        return 0
    fp = os.path.abspath(fp)
    if not under(fp, WORKSPACE):
        return 0  # other projects untouched

    cwd = nearest_dir(fp)
    top = git(["rev-parse", "--show-toplevel"], cwd)
    if not top:
        return 0  # not a git repo
    if os.path.realpath(top) == os.path.realpath(WORKSPACE):
        return 0  # workspace-root docs repo

    gd = git(["rev-parse", "--absolute-git-dir"], cwd)
    common = git(["rev-parse", "--git-common-dir"], cwd)
    if common and not os.path.isabs(common):
        common = os.path.join(cwd, common)
    in_worktree = bool(gd) and bool(common) and os.path.realpath(gd) != os.path.realpath(common)
    branch = git(["rev-parse", "--abbrev-ref", "HEAD"], cwd)
    repo = os.path.basename(top)

    if in_worktree and branch not in PROTECTED:
        return 0

    why = "main checkout" if not in_worktree else f"protected branch '{branch}'"

    session = data.get("session_id", "")
    if not session:
        return deny(repo, top, why)  # no session id to key a scratch worktree off — ask a human

    slug = session[:8]
    wt_dir = os.path.join(WT_ROOT, f"{repo}-wip-{slug}")
    branch_name = f"wip/{slug}"
    base = os.environ.get("TATHEP_BASE", "").strip()
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
            f"production branch — set TATHEP_BASE=main (or create the hotfix worktree explicitly). "
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
    print("selftest ok")


if "--selftest" in sys.argv:
    _selftest()
    sys.exit(0)

sys.exit(main())
