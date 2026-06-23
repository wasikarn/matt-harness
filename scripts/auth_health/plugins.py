"""_auth_checks_plugins.py — Check 3: Plugin cache validity.

Extracted from auth-health-check.py. Import `check_plugin_cache` from here.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


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
            # Some plugins ship without a plugin.json: skill-only plugins
            # (a `skills/` dir, no manifest), marketplace.json-based plugins
            # (qmd), or LSP connectors (a near-empty stub). If the install
            # path exposes a discoverable plugin surface (agents/skills/
            # commands/hooks/output-styles/themes, or an alt
            # .claude-plugin/marketplace.json), the plugin loads without a
            # manifest — treat as healthy. A stub with no surface stays
            # degraded: we can't confirm it delivers anything.
            surface_dirs = ("agents", "skills", "commands", "hooks", "output-styles", "themes")
            has_surface = any((install_path / sd).is_dir() for sd in surface_dirs) \
                or (install_path / ".claude-plugin" / "marketplace.json").exists()
            if has_surface:
                verdict["status"] = "healthy"
            else:
                verdict["issues"].append(
                    f"plugin.json not found at {manifest_path} and no discoverable plugin surface (agents/skills/commands/hooks/output-styles/themes or marketplace.json) — unverified stub"
                )
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
        # Version match. The rule's purpose is to catch real drift (both
        # versions non-empty and different). Many official/marketplace
        # plugins ship an unversioned manifest (version="") while
        # installed_plugins.json records "unknown" or a marketplace commit
        # hash — the manifest is valid and the name matches, so the plugin
        # loads. Accept an unversioned manifest as a match rather than
        # crying "degraded" on every healthy official plugin.
        manifest_version = manifest.get("version", "")
        if manifest_version == plugin["version"]:
            verdict["version_match"] = True
        elif manifest_version == "":
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
