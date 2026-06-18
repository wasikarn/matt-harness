#!/usr/bin/env python3
"""nav.py — smart L3 capability miner for kbg-harness.

Scans skill, command, agent, and hook surfaces by description/frontmatter,
ranks matches by keyword overlap, and emits a concise candidate list.

Usage:
    python3 skills/harness-nav/scripts/nav.py <keyword-or-phrase>
    python3 skills/harness-nav/scripts/nav.py --json <keyword-or-phrase>

Exit codes:
    0 — matches found (or query is empty and usage printed)
    1 — no matches found
"""

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def tokenize(text: str) -> set[str]:
    """Lowercase word tokens, drop punctuation."""
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def score(query_tokens: set[str], text: str) -> float:
    """Simple overlap score: matched tokens / query tokens."""
    if not query_tokens:
        return 0.0
    text_tokens = tokenize(text)
    matched = query_tokens & text_tokens
    return len(matched) / len(query_tokens)


def read_frontmatter(path: Path, key: str) -> str:
    """Read a single-line frontmatter value from `key: value`."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if line.strip().startswith("---"):
                    continue
                m = re.match(rf"^{re.escape(key)}:\s*(.*?)\s*$", line)
                if m:
                    return m.group(1).strip().strip('"')
    except OSError:
        pass
    return ""


def read_first_comment(path: Path) -> str:
    """First non-shebang comment line of a shell/python hook."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("#!/") or not stripped:
                    continue
                if stripped.startswith("#"):
                    return stripped.lstrip("#").strip()
                break
    except OSError:
        pass
    return ""


def read_first_heading(path: Path) -> str:
    """First markdown H1 heading line, stripped of '#'."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("# "):
                    return stripped.lstrip("# ").strip()
    except OSError:
        pass
    return ""


def scan_skills() -> list[dict]:
    results = []
    skills_dir = ROOT / "skills"
    if not skills_dir.is_dir():
        return results
    for d in skills_dir.iterdir():
        skill_file = d / "SKILL.md"
        if not skill_file.is_file():
            continue
        name = d.name
        desc = read_frontmatter(skill_file, "description")
        if not desc:
            continue
        results.append({
            "kind": "skill",
            "name": name,
            "description": desc,
            "path": str(skill_file.relative_to(ROOT)),
        })
    return results


def scan_commands() -> list[dict]:
    results = []
    cmd_dir = ROOT / "commands"
    if not cmd_dir.is_dir():
        return results
    for f in cmd_dir.glob("*.md"):
        name = f.stem
        desc = read_frontmatter(f, "description")
        if not desc:
            continue
        results.append({
            "kind": "command",
            "name": name,
            "description": desc,
            "path": str(f.relative_to(ROOT)),
        })
    return results


def scan_agents() -> list[dict]:
    results = []
    agents_dir = ROOT / "agents"
    if not agents_dir.is_dir():
        return results
    for f in agents_dir.glob("*.md"):
        name = f.stem
        desc = read_frontmatter(f, "description")
        if not desc:
            continue
        results.append({
            "kind": "agent",
            "name": name,
            "description": desc,
            "path": str(f.relative_to(ROOT)),
        })
    return results


def scan_hooks() -> list[dict]:
    results = []
    hooks_dir = ROOT / "hooks"
    if not hooks_dir.is_dir():
        return results
    # Hooks are nested in subdirs now; skip _lib.sh and hooks.json.
    for f in hooks_dir.rglob("*.sh"):
        if f.name.startswith("_") or f.name == "hooks.json":
            continue
        name = f.stem
        desc = read_first_comment(f)
        results.append({
            "kind": "hook",
            "name": name,
            "description": desc,
            "path": str(f.relative_to(ROOT)),
        })
    return results


def scan_reference() -> list[dict]:
    """Index read-only reference docs under docs/reference/ (not invokable skills)."""
    results = []
    ref_dir = ROOT / "docs" / "reference"
    if not ref_dir.is_dir():
        return results
    # Top-level reference pages and one-level nested READMEs/indexes only.
    # Nested subdirs expose their README/index entry point; extra files like
    # UPSTREAM-README.md are reachable from that entry point and don't need
    # their own nav row.
    candidates = (
        sorted(ref_dir.glob("*.md"))
        + sorted(ref_dir.glob("*/README.md"))
        + sorted(ref_dir.glob("*/index.md"))
    )
    for f in candidates:
        heading = read_first_heading(f)
        if not heading:
            continue
        # For nested README/index files, surface the directory name (e.g.
        # docs/reference/thinking-skills/README.md -> "thinking-skills").
        name = f.stem
        if f.parent != ref_dir:
            name = f.parent.name
        results.append({
            "kind": "reference",
            "name": name,
            "description": heading,
            "path": str(f.relative_to(ROOT)),
        })
    return results


def main() -> int:
    args = sys.argv[1:]
    as_json = False
    if args and args[0] == "--json":
        as_json = True
        args = args[1:]

    if not args:
        print(__doc__)
        return 0

    query = " ".join(args)
    query_tokens = tokenize(query)
    synonyms = {
        "test": ["testing", "tests"],
        "review": ["reviewer", "reviews"],
        "deploy": ["ship", "release"],
        "security": ["safe", "unsafe", "dangerous"],
        "audit": ["auditor", "auditing"],
        "memory": ["trim", "lint"],
        "team": ["teammate", "agents"],
        "mental": ["reasoning", "thinking"],
        "model": ["models"],
        "models": ["model"],
        "reference": ["docs"],
    }
    for word, alts in synonyms.items():
        if word in query_tokens:
            query_tokens.update(alts)

    all_items = scan_skills() + scan_commands() + scan_agents() + scan_hooks() + scan_reference()
    scored = []
    for item in all_items:
        text = f"{item['name']} {item['description']}"
        s = score(query_tokens, text)
        if s > 0:
            scored.append((s, item))

    scored.sort(key=lambda x: (-x[0], x[1]["kind"], x[1]["name"]))
    top = scored[:8]

    if as_json:
        print(json.dumps({"query": query, "matches": [m for _, m in top]}, indent=2))
    else:
        if not top:
            print(f"No L3 matches for: {query}")
            return 1
        print(f"# L3 matches for: {query}")
        print("")
        print("| Kind | Name | Description |")
        print("|---|---|---|")
        for s, item in top:
            print(f"| {item['kind']} | `{item['name']}` | {item['description']} |")
        print("")
        print("Next step: read the matching SKILL.md / command / agent spec, then invoke directly.")

    return 0 if top else 1


if __name__ == "__main__":
    sys.exit(main())
