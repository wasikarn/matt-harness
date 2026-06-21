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
import sys
from pathlib import Path
from typing import Any

# Ensure the scripts/ directory is importable when invoked as a script
sys.path.insert(0, str(Path(__file__).parent))

from auth_health.gh import check_gh_auth, DEFAULT_GH_TIMEOUT
from auth_health.mcp import check_mcp_servers, inventory_mcp_servers, DEFAULT_MCP_TIMEOUT
from auth_health.plugins import check_plugin_cache


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


def print_mcp_inventory(inv: dict[str, Any]) -> None:
    """Print a human-readable read-only MCP inventory to stdout."""
    print(f"# mcp-inventory: {inv['count']} server(s) configured")
    print()
    if not inv["servers"]:
        print("  (none — checked ~/.claude/settings.json and .mcp.json)")
        print()
        return
    for s in inv["servers"]:
        loc = s.get("command") or s.get("url_host") or "?"
        print(f"  • {s['name']} [{s['transport']}] ({s['source']}) → {loc}")
        for e in s.get("env_keys", []):
            mark = "value in config" if e["value_present"] else "UNSET in config"
            print(f"      env: {e['name']} ({mark})")
        if s.get("config_path"):
            print(f"      config: {s['config_path']}")
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
    parser.add_argument(
        "--mcp", action="store_true",
        help="Print a read-only inventory of configured MCP servers (names, transport, "
             "env-key NAMES — never values) and exit 0. Does not probe or grade.",
    )
    args = parser.parse_args()

    # --mcp is an informational inventory, not a health verdict: print and exit 0.
    if args.mcp:
        inv = inventory_mcp_servers()
        if args.json:
            print(json.dumps(inv, indent=2))
        else:
            print_mcp_inventory(inv)
        return 0

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
