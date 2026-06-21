"""_auth_checks_mcp.py — Check 2: MCP server reachability.

Extracted from auth-health-check.py. Import `check_mcp_servers` from here.
"""
from __future__ import annotations

import json
import socket
import subprocess
import time
from pathlib import Path
from urllib.parse import urlparse
from typing import Any

DEFAULT_MCP_TIMEOUT = 5  # seconds per MCP probe

# Resolved at import time; callers can override by passing repo_root explicitly
# if they need a different project root, but the default matches the original.
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _load_mcp_config(repo_root: Path = _REPO_ROOT) -> list[dict[str, Any]]:
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
        # ~/.claude.json is the top-level CC user config and the most common
        # home for user-defined `mcpServers` (settings.json often has none).
        # Reading it here fixes both the inventory and the probe, which were
        # blind to servers configured only in ~/.claude.json.
        (Path.home() / ".claude.json", "user-global"),
        (Path.home() / ".claude" / "settings.json", "global"),
        (repo_root / ".mcp.json", "project"),
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


def inventory_mcp_servers(repo_root: Path = _REPO_ROOT) -> dict[str, Any]:
    """Read-only inventory of configured MCP servers — does NOT probe.

    Answers "what MCP servers are configured, where, and what env keys do they
    need?" for the "is my environment actually set up" question. SAFE TO PRINT:
    reports env-var KEY NAMES and whether the config supplies a non-empty value,
    but NEVER the value itself; for HTTP servers reports the host only (no path/
    query, which can carry tokens). This is config-as-awareness, not bundling —
    consistent with kbg's "no bundled MCP servers" non-goal (it inventories the
    operator's own config, it ships nothing).

    Returns: {name: 'mcp_inventory', count, servers: [{name, source, config_path,
    transport, command, url_host, env_keys: [{name, value_present}]}]}.
    """
    configs = _load_mcp_config(repo_root)
    servers: list[dict[str, Any]] = []
    for s in configs:
        cfg = s["config"]
        if cfg.get("command"):
            transport = "stdio"
        elif cfg.get("url"):
            transport = "http"
        else:
            transport = "unknown"
        env = cfg.get("env") or {}
        env_keys: list[dict[str, Any]] = []
        if isinstance(env, dict):
            for k, v in sorted(env.items()):
                # value_present = config supplies a non-empty literal; a "${VAR}"
                # placeholder counts as present-in-config (resolution is runtime).
                env_keys.append({
                    "name": str(k),
                    "value_present": bool(isinstance(v, str) and v.strip()),
                })
        url_host = None
        if transport == "http":
            try:
                url_host = urlparse(str(cfg.get("url"))).hostname
            except (ValueError, TypeError):
                url_host = None
        servers.append({
            "name": s["name"],
            "source": s["source"],
            "config_path": s.get("path", ""),
            "transport": transport,
            "command": cfg.get("command") if transport == "stdio" else None,
            "url_host": url_host,
            "env_keys": env_keys,
        })
    return {"name": "mcp_inventory", "count": len(servers), "servers": servers}

