"""_auth_checks_gh.py — Check 1: GitHub CLI auth.

Extracted from auth-health-check.py. Import `check_gh_auth` from here.
"""
from __future__ import annotations

import os
import subprocess
import time
from typing import Any

DEFAULT_GH_TIMEOUT = 10  # seconds for `gh auth status`


def check_gh_auth(timeout: int = DEFAULT_GH_TIMEOUT) -> dict[str, Any]:
    """Run `gh auth status` and return a verdict dict.

    Healthy: `gh auth status` exits 0 (token present, account active).
    Degraded: `gh auth status` exits non-zero BUT a token IS set in env
              (`GITHUB_TOKEN` / `GH_TOKEN` / `GH_CONFIG_DIR`); the token
              may be stale but is recoverable.
    Broken: `gh auth status` exits non-zero AND no token is set; the
            operator must `gh auth login` before any work that touches
            the gh CLI.

    We deliberately call `gh auth status` even when no env token is set
    — `gh` can read its own keyring-backed credential, so the env check
    is a heuristic for the "keyring dropped" failure mode, not a
    substitute for the actual probe.
    """
    started = time.time()
    try:
        r = subprocess.run(
            ["gh", "auth", "status"],
            capture_output=True, text=True, timeout=timeout,
        )
        elapsed = time.time() - started
        stdout = r.stdout.strip()
        stderr = r.stderr.strip()
        # `gh auth status` returns 0 when logged in, 1 when not, 4 on
        # internal error. Treat any rc != 0 as "not logged in" and let
        # the env-token heuristic disambiguate degraded vs broken.
        token_env_set = bool(
            os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        )
        if r.returncode == 0:
            return {
                "name": "gh_auth",
                "status": "healthy",
                "summary": "gh auth status: active account",
                "details": stdout.splitlines() if stdout else [],
                "elapsed_seconds": round(elapsed, 2),
                "remediation": None,
            }
        if token_env_set:
            return {
                "name": "gh_auth",
                "status": "degraded",
                "summary": "gh auth status: non-zero, but GITHUB_TOKEN/GH_TOKEN env var is set; the keyring credential may be stale",
                "details": (stdout + stderr).splitlines() if (stdout or stderr) else [],
                "elapsed_seconds": round(elapsed, 2),
                "remediation": "Run `gh auth status` interactively to see which account/token is failing. If the env token is stale, refresh it; if `gh` should use keyring, run `gh auth login`.",
            }
        return {
            "name": "gh_auth",
            "status": "broken",
            "summary": "gh auth status: non-zero, no GITHUB_TOKEN/GH_TOKEN env var; gh CLI is not authenticated",
            "details": (stdout + stderr).splitlines() if (stdout or stderr) else [],
            "elapsed_seconds": round(elapsed, 2),
            "remediation": "Run `gh auth login` (or set GITHUB_TOKEN/GH_TOKEN) before running kbg:orchestrate, kbg:review-pr, or any task that touches the gh CLI.",
        }
    except subprocess.TimeoutExpired:
        return {
            "name": "gh_auth",
            "status": "broken",
            "summary": f"gh auth status: timed out after {timeout}s",
            "details": [],
            "elapsed_seconds": timeout,
            "remediation": "Check if `gh` is hanging on a network call. Run `gh auth status` interactively to see the error.",
        }
    except FileNotFoundError:
        return {
            "name": "gh_auth",
            "status": "broken",
            "summary": "gh CLI not found on PATH",
            "details": [],
            "elapsed_seconds": 0.0,
            "remediation": "Install the GitHub CLI: https://cli.github.com/ — or skip this check via --no-gh if the task doesn't need gh.",
        }
    except Exception as e:
        return {
            "name": "gh_auth",
            "status": "broken",
            "summary": f"gh auth status: unexpected error: {type(e).__name__}: {e}",
            "details": [],
            "elapsed_seconds": 0.0,
            "remediation": "Investigate the error above; the gh auth state is unprovable.",
        }
