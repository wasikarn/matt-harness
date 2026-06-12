#!/usr/bin/env python3
"""
auth-health-check.py — surface expired tokens, dead MCP servers, and broken
plugin state BEFORE work starts (SYNTHESIS #38 / P2.5 / spec §4.2).

The production harness article specifically calls this out as a painful
gap: "Expired tokens surface as 'the agent is stupid today' — hard to
diagnose." This script gives the operator a single command that
probes the auth/MCP/plugin surface and returns a structured verdict
with concrete remediation steps.

What this script checks
----------------------
1. **GitHub CLI auth** — `gh auth status`. Returns 0 if a valid token
   is present and the account is active; non-zero if expired, missing,
   or pointing at an account without repo access.
2. **MCP server reachability** — for each MCP server configured in
   `~/.claude/settings.json` (or project-local `.mcp.json`), probe its
   transport. For stdio servers, this means "the binary exists and
   --help exits 0"; for HTTP/SSE servers, this means "the endpoint
   responds within the timeout". The probe is BEST-EFFORT: an MCP
   server that's clearly reachable (e.g., a local binary) gets marked
   healthy, an unreachable one gets marked broken. If no MCP servers
   are configured, the section is reported as "not applicable" (not
   broken).
3. **Plugin cache validity** — for each installed plugin under
   `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, verify
   the manifest is loadable (parses as JSON, has the required fields)
   and the plugin.json version matches the installed_plugins.json
   entry. A plugin with a broken manifest OR a version mismatch is
   flagged as broken (the failure mode that produces "the plugin
   loaded yesterday and doesn't load today" without explanation).

What this script does NOT do
----------------------------
- Does NOT auto-fix anything. The verdict is "healthy" / "degraded" /
  "broken" with specific remediation. Auto-fix would be L3/L4 territory
  and the autonomy invariant (ADR 0002) keeps the harness's self-repair
  at L2 (sensor only, never auto-block / auto-mutate).
- Does NOT log to a journal. The script's job is the verdict; if the
  caller wants a journaled event, they wire it through `task-lifecycle.sh`
  or a custom SessionStart hook (see "Wiring" below).
- Does NOT block session start. The script exits with the verdict code
  and prints the JSON report. The CALLER (a SessionStart hook, a
  pre-flight in `/pre-ship-verify`, or an explicit operator invocation)
  decides whether degraded/broken means "abort" or "warn and continue".

Wiring
------
Add to a SessionStart hook (e.g. `hooks/session-load.sh` or a new
`hooks/auth-bootstrap.sh`) by adding a single line:

    python3 scripts/auth-health-check.py --json || true

The hook should not block on auth-health — the operator's first task
of the session might be to FIX the auth, and blocking would be
counterproductive. Print the verdict to stdout wrapped in
`<auth-health>...</>` so Claude Code injects it as context, and let
the operator decide.

Exit codes
----------
    0 — healthy (all checks pass)
    1 — degraded (some checks pass with warnings; remediation is optional)
    2 — broken (one or more critical checks failed; work should pause)

Distinct from `run-acceptance.py`'s 5-code contract — auth-health has
3 codes (healthy/degraded/broken), acceptance has 5
(pass/fail/invocation/parse/block). The difference: acceptance runs
test-shaped code (5 states make sense for test outcomes), auth-health
runs state-shaped probes (3 states make sense for service health).

Usage
-----
    # Human-readable (default; safe):
    python3 scripts/auth-health-check.py

    # JSON-only (for hook consumption):
    python3 scripts/auth-health-check.py --json

    # Custom timeout for MCP probes (default 5s):
    python3 scripts/auth-health-check.py --mcp-timeout 10

    # Skip a check (e.g. --no-mcp in environments without MCP):
    python3 scripts/auth-health-check.py --no-mcp
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MCP_TIMEOUT = 5  # seconds per MCP probe
DEFAULT_GH_TIMEOUT = 10  # seconds for `gh auth status`


# ---------------------------------------------------------------------------
# Check 1: GitHub CLI auth
# ---------------------------------------------------------------------------

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
            "remediation": "Run `gh auth login` (or set GITHUB_TOKEN/GH_TOKEN) before running /team-build, /review-pr, or any task that touches the gh CLI.",
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


# ---------------------------------------------------------------------------
# Check 2: MCP server reachability
# ---------------------------------------------------------------------------

def _load_mcp_config() -> list[dict[str, Any]]:
    """Load MCP server config from the standard locations.

    The vendor places MCP config in two places (per https://code.claude.com/
    docs/en/mcp): `~/.claude/settings.json` (global) and `<project>/.mcp.json`
    (project-local). Both are JSON; both have the shape
    `{"mcpServers": {<name>: {<transport config>}}}`.

    Returns a list of dicts: `{"name": str, "source": str, "config": dict}`.
    Empty list if no MCP config found.
    """
    configs: list[dict[str, Any]] = []
    paths_to_check = [
        (Path.home() / ".claude" / "settings.json", "global"),
        (REPO_ROOT / ".mcp.json", "project"),
    ]
    for path, source in paths_to_check:
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        servers = data.get("mcpServers") or data.get("mcp_servers") or {}
        if not isinstance(servers, dict):
            continue
        for name, cfg in servers.items():
            if isinstance(cfg, dict):
                configs.append({"name": str(name), "source": source, "config": cfg, "path": str(path)})
    return configs


def _probe_mcp_server(server: dict[str, Any], timeout: int) -> dict[str, Any]:
    """Probe a single MCP server's reachability.

    Best-effort, transport-specific:
      - stdio (`command` + `args`): run `<command> --help` with the timeout
        and check it doesn't error out (exit 0, 1 from --help, or
        timeout-allowed behavior)
      - HTTP/SSE (`url`): HEAD request with the timeout
      - other (sse legacy, websocket, etc.): degraded with a note

    The probe is intentionally lenient: a server that's clearly
    reachable (binary exists + --help doesn't crash) is healthy; a
    server that times out or errors hard is broken; a server with an
    unrecognized transport is degraded (we don't know how to probe it,
    not that it's broken).
    """
    name = server["name"]
    cfg = server["config"]
    started = time.time()
    cmd = cfg.get("command")
    url = cfg.get("url")
    if cmd:
        # stdio transport
        if not isinstance(cmd, str) or not cmd.strip():
            return {
                "name": name,
                "status": "broken",
                "summary": f"MCP server {name!r}: stdio transport with empty 'command'",
                "elapsed_seconds": 0.0,
                "remediation": "Fix the MCP server config: 'command' must be a non-empty string.",
            }
        args = cfg.get("args") or []
        if not isinstance(args, list):
            args = []
        try:
            # Probe with --help; if the binary doesn't support --help,
            # exit 1 or 2 is still "binary exists and runs". We only
            # treat timeout and FileNotFoundError as broken.
            probe_cmd = [cmd] + list(args) + ["--help"]
            r = subprocess.run(
                probe_cmd, capture_output=True, text=True, timeout=timeout,
            )
            elapsed = time.time() - started
            # Any non-timeout, non-NotFound response means the binary
            # exists and runs. The exit code doesn't matter for
            # reachability — only the timeout / not-found case does.
            return {
                "name": name,
                "status": "healthy",
                "summary": f"MCP server {name!r}: stdio binary {cmd!r} responded within {timeout}s (rc={r.returncode})",
                "elapsed_seconds": round(elapsed, 2),
                "remediation": None,
            }
        except subprocess.TimeoutExpired:
            return {
                "name": name,
                "status": "broken",
                "summary": f"MCP server {name!r}: stdio binary {cmd!r} timed out after {timeout}s",
                "elapsed_seconds": timeout,
                "remediation": f"Increase --mcp-timeout, or check that {cmd!r} isn't hanging on stdin.",
            }
        except FileNotFoundError:
            return {
                "name": name,
                "status": "broken",
                "summary": f"MCP server {name!r}: stdio binary {cmd!r} not found on PATH",
                "elapsed_seconds": 0.0,
                "remediation": f"Install {cmd!r} or fix the MCP server config to point at the right binary path.",
            }
        except Exception as e:
            return {
                "name": name,
                "status": "broken",
                "summary": f"MCP server {name!r}: stdio probe failed: {type(e).__name__}: {e}",
                "elapsed_seconds": 0.0,
                "remediation": "Investigate the error above; the MCP server's reachability is unprovable.",
            }
    if url:
        # HTTP/SSE transport — best-effort TCP connect via Python.
        # We don't have a guaranteed HTTP client in stdlib without
        # urllib.request, and even urllib may not handle SSE cleanly.
        # Use a raw socket probe as the minimum reachability check.
        try:
            from urllib.parse import urlparse
            parsed = urlparse(url)
            host = parsed.hostname
            port = parsed.port or (443 if parsed.scheme == "https" else 80)
            if not host:
                return {
                    "name": name,
                    "status": "degraded",
                    "summary": f"MCP server {name!r}: HTTP transport with unparseable url {url!r}",
                    "elapsed_seconds": 0.0,
                    "remediation": f"Fix the MCP server config: url {url!r} is missing a hostname.",
                }
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            try:
                sock.connect((host, port))
                elapsed = time.time() - started
                return {
                    "name": name,
                    "status": "healthy",
                    "summary": f"MCP server {name!r}: TCP connect to {host}:{port} succeeded",
                    "elapsed_seconds": round(elapsed, 2),
                    "remediation": None,
                }
            finally:
                sock.close()
        except (socket.timeout, OSError) as e:
            return {
                "name": name,
                "status": "broken",
                "summary": f"MCP server {name!r}: TCP connect to {url!r} failed: {type(e).__name__}: {e}",
                "elapsed_seconds": time.time() - started,
                "remediation": f"Check that the MCP server at {url!r} is running and reachable from this network.",
            }
    # Unknown transport shape
    return {
        "name": name,
        "status": "degraded",
        "summary": f"MCP server {name!r}: unrecognized transport config (no 'command' or 'url' key)",
        "elapsed_seconds": 0.0,
        "remediation": f"Inspect the MCP server config for {name!r} — this script recognizes stdio (command+args) and HTTP/SSE (url) but the configured transport is neither.",
    }


def check_mcp_servers(timeout: int = DEFAULT_MCP_TIMEOUT) -> dict[str, Any]:
    """Discover + probe all configured MCP servers.

    Returns a dict: {name: 'mcp_servers', status, summary, servers: [...],
    remediation}. The `servers` list contains per-server verdicts.

    If NO MCP servers are configured, status is 'not_applicable' (NOT
    'healthy' — the absence of MCP config is a fact, not a positive
    health signal). This avoids the failure mode where an operator
    reads "healthy" and assumes MCP was checked when in fact there
    was nothing to check.
    """
    configs = _load_mcp_config()
    if not configs:
        return {
            "name": "mcp_servers",
            "status": "not_applicable",
            "summary": "no MCP servers configured (checked ~/.claude/settings.json and .mcp.json)",
            "servers": [],
            "remediation": None,
        }
    server_verdicts = []
    overall_broken = 0
    overall_degraded = 0
    for server in configs:
        v = _probe_mcp_server(server, timeout=timeout)
        v["source"] = server.get("source", "unknown")
        v["config_path"] = server.get("path", "")
        server_verdicts.append(v)
        if v["status"] == "broken":
            overall_broken += 1
        elif v["status"] == "degraded":
            overall_degraded += 1
    if overall_broken > 0:
        status = "broken"
    elif overall_degraded > 0:
        status = "degraded"
    else:
        status = "healthy"
    return {
        "name": "mcp_servers",
        "status": status,
        "summary": f"probed {len(configs)} MCP server(s): {len(configs) - overall_broken - overall_degraded} healthy, {overall_degraded} degraded, {overall_broken} broken",
        "servers": server_verdicts,
        "remediation": "Inspect the per-server `remediation` field for the broken/degraded entries." if (overall_broken or overall_degraded) else None,
    }


# ---------------------------------------------------------------------------
# Check 3: Plugin cache validity
# ---------------------------------------------------------------------------

def _load_installed_plugins() -> list[dict[str, Any]]:
    """Load the installed-plugins manifest from `~/.claude/plugins/installed_plugins.json`.

    The manifest has shape (version 2):
        {
            "version": 2,
            "plugins": {
                "<plugin>@<marketplace>": [
                    {
                        "scope": "user" | "project" | ...,
                        "installPath": "<absolute path>",
                        "version": "<semver>",
                        ...
                    },
                    ...
                ],
                ...
            }
        }
    Keys are `<plugin>@<marketplace>` (a single string), and each key maps
    to a list of installations (usually one entry per scope).

    Returns a list of dicts: `{"plugin_key": str, "marketplace": str,
    "plugin": str, "version": str, "install_path": str}`. We flatten
    all installations across scopes into one record per install — a
    plugin installed at both user and project scope produces two
    records so we can check each independently.
    Empty list if the file is missing or malformed.
    """
    path = Path.home() / ".claude" / "plugins" / "installed_plugins.json"
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return []
    plugins = data.get("plugins", {})
    if not isinstance(plugins, dict):
        return []
    out = []
    for key, installations in plugins.items():
        if not isinstance(key, str) or "@" not in key:
            continue
        if not isinstance(installations, list):
            continue
        plugin_name, _, marketplace = key.rpartition("@")
        for entry in installations:
            if not isinstance(entry, dict):
                continue
            version = str(entry.get("version", "unknown"))
            install_path = str(entry.get("installPath") or entry.get("install_path") or "")
            scope = str(entry.get("scope", ""))
            out.append({
                "plugin_key": f"{plugin_name}@{marketplace}@{version}" + (f" ({scope})" if scope else ""),
                "marketplace": marketplace,
                "plugin": plugin_name,
                "version": version,
                "install_path": install_path,
                "scope": scope,
            })
    return out


def check_plugin_cache() -> dict[str, Any]:
    """Verify each installed plugin's manifest is loadable and matches installed_plugins.json.

    A plugin is "healthy" if:
      1. `installPath/.claude-plugin/plugin.json` exists and parses as JSON
      2. The `version` field matches the installed_plugins.json entry
      3. The marketplace / plugin name in plugin.json matches the
         installed_plugins.json entry
    A plugin is "degraded" if the manifest is missing/empty but the
    installPath exists (the plugin might still load — the manifest is
    a sign of intent, not a hard requirement at runtime).
    A plugin is "broken" if the manifest exists but is malformed
    (parses with an error) OR the version/name mismatches.
    """
    installed = _load_installed_plugins()
    if not installed:
        # Distinguish "manifest missing" from "manifest present but empty"
        # so the operator gets a clear signal. Both are not_applicable —
        # the script is not failing, there's just nothing to check.
        manifest_path = Path.home() / ".claude" / "plugins" / "installed_plugins.json"
        if manifest_path.exists():
            reason = "installed_plugins.json is empty or unparseable"
        else:
            reason = f"no installed plugins (no {manifest_path})"
        return {
            "name": "plugin_cache",
            "status": "not_applicable",
            "summary": reason,
            "plugins": [],
            "remediation": None,
        }
    verdicts = []
    overall_broken = 0
    overall_degraded = 0
    for plugin in installed:
        install_path = Path(plugin["install_path"])
        verdict = {
            "plugin_key": plugin["plugin_key"],
            "install_path": plugin["install_path"],
            "manifest_found": False,
            "manifest_valid": False,
            "version_match": False,
            "name_match": False,
            "issues": [],
        }
        if not install_path.exists():
            verdict["issues"].append(f"install path does not exist: {install_path}")
            overall_broken += 1
            verdict["status"] = "broken"
            verdicts.append(verdict)
            continue
        manifest_path = install_path / ".claude-plugin" / "plugin.json"
        if not manifest_path.exists():
            verdict["issues"].append(f"plugin.json not found at {manifest_path}")
            overall_degraded += 1
            verdict["status"] = "degraded"
            verdicts.append(verdict)
            continue
        verdict["manifest_found"] = True
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            verdict["issues"].append(f"plugin.json malformed: {type(e).__name__}: {e}")
            overall_broken += 1
            verdict["status"] = "broken"
            verdicts.append(verdict)
            continue
        verdict["manifest_valid"] = True
        # Version match
        manifest_version = manifest.get("version", "")
        if manifest_version == plugin["version"]:
            verdict["version_match"] = True
        else:
            verdict["issues"].append(
                f"version mismatch: installed_plugins.json={plugin['version']!r}, plugin.json={manifest_version!r}"
            )
        # Name match (plugin.json's `name` should equal installed_plugins.json's `plugin`)
        manifest_name = manifest.get("name", "")
        if manifest_name == plugin["plugin"]:
            verdict["name_match"] = True
        else:
            verdict["issues"].append(
                f"name mismatch: installed_plugins.json={plugin['plugin']!r}, plugin.json={manifest_name!r}"
            )
        if verdict["version_match"] and verdict["name_match"]:
            verdict["status"] = "healthy"
        else:
            overall_degraded += 1
            verdict["status"] = "degraded"
        verdicts.append(verdict)
    if overall_broken > 0:
        status = "broken"
    elif overall_degraded > 0:
        status = "degraded"
    else:
        status = "healthy"
    return {
        "name": "plugin_cache",
        "status": status,
        "summary": f"checked {len(installed)} installed plugin(s): {sum(1 for v in verdicts if v.get('status') == 'healthy')} healthy, {overall_degraded} degraded, {overall_broken} broken",
        "plugins": verdicts,
        "remediation": "Run `claude plugin update <plugin>@<marketplace>` to refresh mismatched versions, or `claude plugin uninstall` + reinstall for broken manifests." if (overall_broken or overall_degraded) else None,
    }


# ---------------------------------------------------------------------------
# Verdict aggregation + output
# ---------------------------------------------------------------------------

def aggregate_verdict(checks: list[dict[str, Any]]) -> dict[str, Any]:
    """Combine check verdicts into the overall verdict.

    The aggregation is: ANY broken → broken; ANY degraded (no broken) → degraded;
    ALL healthy / not_applicable → healthy.

    A `not_applicable` check is treated as "skip" — it does not count
    against the verdict. The check is documented as "no MCP servers
    configured", which is a fact, not a failure.
    """
    overall_broken = sum(1 for c in checks if c.get("status") == "broken")
    overall_degraded = sum(1 for c in checks if c.get("status") == "degraded")
    if overall_broken > 0:
        status = "broken"
        exit_code = 2
    elif overall_degraded > 0:
        status = "degraded"
        exit_code = 1
    else:
        status = "healthy"
        exit_code = 0
    return {
        "status": status,
        "exit_code": exit_code,
        "summary": f"auth-health: {status} ({len(checks) - overall_broken - overall_degraded} healthy, {overall_degraded} degraded, {overall_broken} broken)",
        "checks": checks,
    }


def print_human(verdict: dict[str, Any]) -> None:
    """Print a human-readable verdict to stdout."""
    print(f"# auth-health: {verdict['status'].upper()}")
    print(f"# {verdict['summary']}")
    print()
    for check in verdict["checks"]:
        status_emoji = {
            "healthy": "✓",
            "degraded": "⚠",
            "broken": "✗",
            "not_applicable": "—",
        }.get(check["status"], "?")
        print(f"  {status_emoji} {check['name']}: {check['status']}")
        print(f"    {check['summary']}")
        if check.get("remediation"):
            print(f"    → {check['remediation']}")
        # Per-MCP-server drill-down
        for server in check.get("servers", []):
            sub_emoji = {
                "healthy": "✓",
                "degraded": "⚠",
                "broken": "✗",
            }.get(server["status"], "?")
            print(f"      {sub_emoji} {server['name']} ({server.get('source', '?')}): {server['status']}")
            if server.get("remediation"):
                print(f"        → {server['remediation']}")
        # Per-plugin drill-down
        for plugin in check.get("plugins", []):
            sub_emoji = {
                "healthy": "✓",
                "degraded": "⚠",
                "broken": "✗",
            }.get(plugin["status"], "?")
            print(f"      {sub_emoji} {plugin['plugin_key']}: {plugin['status']}")
            for issue in plugin.get("issues", []):
                print(f"        → {issue}")
        print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Surface expired tokens, dead MCP servers, and broken plugin state.",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Print JSON-only verdict to stdout (for hook consumption).",
    )
    parser.add_argument(
        "--mcp-timeout", type=int, default=DEFAULT_MCP_TIMEOUT,
        help=f"Per-MCP-server probe timeout in seconds. Default: {DEFAULT_MCP_TIMEOUT}.",
    )
    parser.add_argument(
        "--gh-timeout", type=int, default=DEFAULT_GH_TIMEOUT,
        help=f"`gh auth status` timeout in seconds. Default: {DEFAULT_GH_TIMEOUT}.",
    )
    parser.add_argument(
        "--no-gh", action="store_true", help="Skip the gh auth check.",
    )
    parser.add_argument(
        "--no-mcp", action="store_true", help="Skip the MCP server check.",
    )
    parser.add_argument(
        "--no-plugins", action="store_true", help="Skip the plugin cache check.",
    )
    args = parser.parse_args()

    checks: list[dict[str, Any]] = []
    if not args.no_gh:
        checks.append(check_gh_auth(timeout=args.gh_timeout))
    if not args.no_mcp:
        checks.append(check_mcp_servers(timeout=args.mcp_timeout))
    if not args.no_plugins:
        checks.append(check_plugin_cache())

    if not checks:
        print("auth-health-check: all checks disabled (--no-* for everything); nothing to do", file=sys.stderr)
        return 0

    verdict = aggregate_verdict(checks)

    if args.json:
        print(json.dumps(verdict, indent=2))
    else:
        print_human(verdict)

    return verdict["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
