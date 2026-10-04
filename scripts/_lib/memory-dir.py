#!/usr/bin/env python3
"""Shared memory-store directory resolver -- the ONE place this logic lives.

Consumers: skills/meta/memory-lint/scripts/memory-lint.py (imports this file
directly via importlib), hooks/stop/memory-audit-commit.sh and
hooks/session/memory-health-nudge.sh (invoke this file as a subprocess).

Precedence, unchanged from memory-lint.py's original memory_dir() except for
step 3: (1) autoMemoryDirectory setting; (2) CLAUDE_CONFIG_DIR +
CLAUDE_CODE_PROJECT_DIR_NAME together (no git call at all in this branch --
Claude Code "ignores this variable when CLAUDE_CONFIG_DIR is unset",
env-vars.md:326); (3) git-derived -- now via --git-common-dir's parent
instead of --show-toplevel, so a linked worktree resolves to the SAME shared
store as the main checkout (worktree-per-session support, 2026-09-28) instead
of a separate, worktree-local one that was never actually created; (4)
non-git fallback to raw cwd, unchanged.

Usage: python3 memory-dir.py          -> prints the resolved memory dir path
       python3 memory-dir.py --enc    -> prints only the <enc> path segment
"""
import json
import os
import re
import subprocess
import sys


def _slug(path):
    # Claude Code's own rule (its binary: replace(/[^a-zA-Z0-9]/g,"-")):
    # every non-alphanumeric char becomes "-", not just "/" (GH #423).
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def _auto_memory_directory_setting():
    # memory.md:362 -- autoMemoryDirectory in settings.json overrides the
    # whole storage location. Read from any scope; project scope wins over
    # user scope, matching Claude Code's own most-specific-wins precedence.
    for path in (
        os.path.join(".claude", "settings.local.json"),
        os.path.join(".claude", "settings.json"),
        os.path.expanduser("~/.claude/settings.json"),
    ):
        try:
            with open(path) as f:
                value = json.load(f).get("autoMemoryDirectory")
        except (OSError, json.JSONDecodeError):
            continue
        if value:
            return value
    return None


def _git_derived_root():
    # --git-common-dir is the SAME path across every worktree of one repo
    # (unlike --show-toplevel, which returns each worktree's own directory).
    # Take its parent when it ends in ".git" to recover the repo-root path a
    # plain checkout would report; fall back to the common-dir itself for
    # the rare bare-repo case where it has no ".git" suffix at all.
    try:
        common_dir = subprocess.run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return os.getcwd()
    if os.path.basename(common_dir) == ".git":
        return os.path.dirname(common_dir)
    return common_dir


def resolve_enc():
    """Return just the <enc> path segment (used by bash consumers for
    marker/lock file naming, which key off <enc> rather than the full
    memory dir path)."""
    auto_dir = _auto_memory_directory_setting()
    if auto_dir:
        # A configured autoMemoryDirectory has no separate <enc> concept --
        # callers that need marker/lock naming fall back to encoding the
        # resolved directory itself in that case.
        return _slug(os.path.expanduser(auto_dir))
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    project_dir_name = os.environ.get("CLAUDE_CODE_PROJECT_DIR_NAME")
    if config_dir and project_dir_name:
        return project_dir_name
    return _slug(_git_derived_root())


def resolve_memory_dir():
    auto_dir = _auto_memory_directory_setting()
    if auto_dir:
        return os.path.expanduser(auto_dir)
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    projects_root = os.path.expanduser(config_dir) if config_dir else os.path.expanduser("~/.claude")
    projects_root = os.path.join(projects_root, "projects")
    project_dir_name = os.environ.get("CLAUDE_CODE_PROJECT_DIR_NAME")
    if config_dir and project_dir_name:
        enc = project_dir_name
    else:
        enc = _slug(_git_derived_root())
    return os.path.join(projects_root, enc, "memory")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--enc":
        print(resolve_enc())
    else:
        print(resolve_memory_dir())
