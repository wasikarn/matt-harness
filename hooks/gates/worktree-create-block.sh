#!/usr/bin/env bash
# Gate: enforce kbg single-branch doctrine (no new non-develop branches via worktree).
# Handles both WorktreeCreate and WorktreeRemove events. Reads the event JSON from
# stdin; exits 2 to block, 0 to allow.
#
# Why: kbg-harness branching model = "develop only, no feature branches, no worktrees"
# (user-explicit doctrine, memory branching-model.md 2026-06-11). The doctrine was
# prompt-only — proven gap: 2 orphan worktree-agent-* branches in the repo today.
# Native CC has the WorktreeCreate event; we use it to close the doctrine gap
# computationally. The check is opt-in per repo via a `/.kbg-no-worktree` sentinel —
# kbg-harness ships the sentinel, tathep/ECC/scratch repos do not, and the gate
# is a no-op everywhere except kbg-harness.
#
# Rule:
#   WorktreeCreate DENY (exit 2) iff ALL of:
#     1. Sentinel $ROOT/.kbg-no-worktree is present at the resolved repo root
#     2. tool_input.branch is set (a new branch is being created)
#     3. tool_input.branch != "develop" (the new branch is not the allowed develop branch)
#     4. NOT the review-pr allowlist shape: detach=true AND path matches review-pr-<N>
#   WorktreeCreate ALLOW otherwise (detached, existing-branch, develop, or no-sentinel).
#   WorktreeRemove ALLOW always (removal is recoverable; wired for symmetry).
#   Fail-safe = ALLOW on parse error, missing cwd, missing CLAUDE_PROJECT_DIR, no git,
#   or any other unexpected condition (matches task-complete-separation.sh precedent).
#
# Root resolution: CLAUDE_PROJECT_DIR env (Anthropic-provided project-root anchor)
# primary; walk up from cwd looking for .git OR the sentinel (bounded, max 16
# levels) as fallback. cwd may be a subdir of the repo, not the root — walking-up
# is required (Plan agent R1/R2 fix). Returns empty string on failure → fail-safe.
#
# Note on shell-quoting: the Python body lives inside a bash single-quoted
# heredoc (python3 -c '...'), so every Python string literal MUST use double
# quotes — a single quote inside the heredoc terminates the bash string early.
# All Python code below uses "..." strings exclusively.
set -uo pipefail

# shellcheck disable=SC2016  # single quotes are intentional: this is Python code, not shell
python3 -c '
import json, os, re, sys

MAX_WALK = 16

def walk_up_to_repo(start):
    """Walk up from start looking for a directory containing .git OR the
    sentinel. Bounded to MAX_WALK levels. Returns the path (string) or empty."""
    d = start or os.getcwd() or "/"
    for _ in range(MAX_WALK):
        if d in ("", "/"):
            return ""
        try:
            if os.path.isdir(os.path.join(d, ".git")) or os.path.isfile(os.path.join(d, ".kbg-no-worktree")):
                return d
        except Exception:
            pass
        parent = os.path.dirname(d)
        if parent == d:
            return ""
        d = parent
    return ""

def resolve_root(cwd):
    """Primary: CLAUDE_PROJECT_DIR env (Anthropic-provided project-root anchor).
    Fallback: walk-up from cwd. Returns empty string on failure (fail-safe allow)."""
    proj = os.environ.get("CLAUDE_PROJECT_DIR") or ""
    if proj and (os.path.isdir(os.path.join(proj, ".git")) or os.path.isfile(os.path.join(proj, ".kbg-no-worktree"))):
        return proj
    return walk_up_to_repo(cwd)

def deny(reason):
    print("[kbg:gate] BLOCKED: " + reason, file=sys.stderr)
    sys.exit(2)

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW (matches task-complete-separation.sh).
    err_msg = "unparseable stdin, allowing: %s" % e
    print("[kbg:gate] worktree-create-block: " + err_msg, file=sys.stderr)
    sys.exit(0)

tool = d.get("tool_name", "")
if tool not in ("WorktreeCreate", "WorktreeRemove"):
    sys.exit(0)  # wrong event — out of scope

cwd = d.get("cwd", "") or os.getcwd()
root = resolve_root(cwd)
if not root:
    print("[kbg:gate] worktree-create-block: could not resolve project root, allowing", file=sys.stderr)
    sys.exit(0)

sentinel = os.path.join(root, ".kbg-no-worktree")
if not os.path.isfile(sentinel):
    sys.exit(0)  # doctrine does not apply in this repo

if tool == "WorktreeRemove":
    sys.exit(0)  # symmetric observer: removal is recoverable; we do not deny.

# WorktreeCreate: parse tool_input.{path, branch, detach}.
ti = d.get("tool_input", {}) or {}
branch = ti.get("branch")
path = ti.get("path", "") or ""
detach = ti.get("detach", False)

# review-pr allowlist: detach=true AND path contains "review-pr-<N>"
# AND no new branch is being created (no -b). Verified:
# skills/review-pr/SKILL.md lines 46, 52, 156, 166, 171 use the exact
# shape `git worktree add --detach <WT> <SHA>` with no -b. A command
# that combines --detach and -b <new> is doctrine-breaking disguised
# as review-pr — deny it. macOS TMPDIR is /var/folders/.../T/...,
# Linux is /tmp — the review-pr- substring catches both.
is_review_pr = bool(detach) and bool(re.search(r"review-pr-\d+", path)) and branch is None

# Deny: new non-develop branch being created, AND not the review-pr carve-out.
if branch is not None and branch != "develop" and not is_review_pr:
    deny("kbg-harness doctrine = no new non-develop branches via worktree "
         "(single branch develop only). Use detached worktrees, develop, or "
         "an existing branch instead. Remove /.kbg-no-worktree to allow. "
         "See CLAUDE.md § Branching.")

# Defensive: when branch == "develop", confirm it is an actual branch (not a typo).
# Cheap — a single git rev-parse per WorktreeCreate event; the gate fires only
# on worktree creation, not every tool call.
if branch == "develop":
    try:
        import subprocess
        r = subprocess.run(
            ["git", "-C", root, "rev-parse", "--verify", "develop"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode != 0:
            deny("kbg-harness doctrine: branch == develop but git rev-parse --verify develop "
                 "fails (typo, renamed, or no develop branch in this repo). Use detached "
                 "worktrees or an existing branch instead.")
    except Exception as e:
        err_msg = "raised exception: %s" % e
        deny("kbg-harness doctrine: branch == develop but repo verification " + err_msg +
             ". Refusing to allow without proof. Use detached worktrees or remove /.kbg-no-worktree.")

sys.exit(0)  # allow detached, existing-branch, develop, or review-pr.
'
exit $?
