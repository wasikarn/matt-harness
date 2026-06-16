# _plan_linter_parsers.py — Parsing utilities for plan-linter.
#
# Pure library module — no shebang, no __main__ block.
# Imported by _plan_linter_core.py and plan-linter.py.

from __future__ import annotations

import re
from collections import deque
from typing import Any


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REQUIRED_HEADERS = [
    "Brain dump",
    "Team Members",
    "Step by Step Tasks",
    "Acceptance Criteria",
    "Validation Commands",
]

SHELL_KEYWORDS = {
    "bash", "sh", "pytest", "python", "python3", "npm", "yarn", "pnpm",
    "curl", "wget", "ruff", "black", "mypy", "tsc", "cargo", "go",
    "make", "cmake", "docker", "kubectl", "helm", "git", "grep", "find",
    "cat", "echo", "test", "[" , "]", "mkdir", "touch", "rm", "cp", "mv",
    "ls", "cd", "pwd", "sort", "uniq", "wc", "diff", "head", "tail",
    "awk", "sed", "jq", "xargs", "terraform", "pulumi", "gcloud", "aws",
}

AUTH_SECRET_KEYWORDS = {
    "auth", "secret", "password", "token", "credential", "oauth",
    "jwt", "session", "login", "logout", "permission", "rbac", "acl",
    "encrypt", "decrypt", "hash", "salt", "api_key", "apikey",
}

SCHEMA_CHANGE_KEYWORDS = {
    "schema", "migration", "migrate", "table", "column", "database",
    "db", "sql", "index", "foreign key", "constraint", "alter",
}

MIGRATION_TASK_KEYWORDS = {
    "migration", "migrate", "schema", "sql", "ddl", "alter table",
}


# ---------------------------------------------------------------------------
# Section extraction
# ---------------------------------------------------------------------------

def extract_sections(content: str) -> dict[str, str]:
    """Split markdown into sections keyed by ## header text (without #)."""
    sections: dict[str, str] = {}
    current_header: str | None = None
    current_lines: list[str] = []

    for line in content.splitlines():
        m = re.match(r"^##\s+(.+)$", line.strip())
        if m:
            if current_header is not None:
                sections[current_header] = "\n".join(current_lines).strip()
            current_header = m.group(1).strip()
            current_lines = []
        else:
            current_lines.append(line)

    if current_header is not None:
        sections[current_header] = "\n".join(current_lines).strip()

    return sections


# ---------------------------------------------------------------------------
# Table parser
# ---------------------------------------------------------------------------

def parse_markdown_table(text: str) -> list[dict[str, str]] | None:
    """Parse a markdown table into a list of row dicts.

    Returns None if no valid table found.
    """
    lines = text.splitlines()
    header_idx: int | None = None
    sep_idx: int | None = None

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("|") and "---" in stripped:
            if header_idx is not None and i == header_idx + 1:
                sep_idx = i
                break
            # Separator without a matching header candidate — reset
            header_idx = None
        elif stripped.startswith("|") and header_idx is None:
            # Tentative header — must be followed by separator
            header_idx = i
            if i + 1 < len(lines) and lines[i + 1].strip().startswith("|") and "---" in lines[i + 1]:
                sep_idx = i + 1
                break
            # Next line is not a separator — not a real table header
            header_idx = None

    if header_idx is None or sep_idx is None:
        return None

    headers = [h.strip().lower() for h in lines[header_idx].split("|")]
    # Remove empty strings caused by leading/trailing pipes
    headers = [h for h in headers if h]

    rows: list[dict[str, str]] = []
    for line in lines[sep_idx + 1 :]:
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.split("|")]
        # Remove empty strings caused by leading/trailing pipes only
        while cells and cells[0] == "":
            cells.pop(0)
        while cells and cells[-1] == "":
            cells.pop()
        # Pad or truncate to match header count
        while len(cells) < len(headers):
            cells.append("")
        cells = cells[: len(headers)]
        row = {headers[j]: cells[j] for j in range(len(headers))}
        rows.append(row)

    return rows if rows else None


# ---------------------------------------------------------------------------
# List parser
# ---------------------------------------------------------------------------

def parse_list_items(text: str) -> list[str]:
    """Extract top-level list items from markdown text.

    Supports '- ', '* ', and 'N. '.
    """
    items: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if re.match(r"^[-*]\s+", stripped):
            items.append(re.sub(r"^[-*]\s+", "", stripped))
        elif re.match(r"^\d+\.\s+", stripped):
            items.append(re.sub(r"^\d+\.\s+", "", stripped))
    return items


def parse_numbered_list_items(text: str) -> list[str]:
    """Extract numbered list items only."""
    items: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if re.match(r"^\d+\.\s+", stripped):
            items.append(re.sub(r"^\d+\.\s+", "", stripped))
    return items


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

def looks_like_shell_command(text: str) -> bool:
    """Heuristic: does this look like a runnable shell command vs prose?"""
    t = text.strip()
    if not t:
        return False

    # Prose heuristics
    # Ends with a period (sentences)
    if t.endswith(".") and not t.endswith(".."):
        return False

    # Long sentences with many spaces and common prose words
    word_count = len(t.split())
    if word_count > 15:
        # Very long — probably prose unless it has backticks
        if "`" not in t:
            return False

    # Check for backtick-wrapped command
    backtick_cmds = re.findall(r"`([^`]+)`", t)
    for cmd in backtick_cmds:
        first_word = cmd.split()[0] if cmd.split() else ""
        if first_word in SHELL_KEYWORDS or any(
            kw in cmd for kw in SHELL_KEYWORDS
        ):
            return True

    # If the entire text is wrapped in backticks, check inside
    if t.startswith("`") and t.endswith("`"):
        inner = t[1:-1].strip()
        first = inner.split()[0] if inner.split() else ""
        if first in SHELL_KEYWORDS:
            return True

    # Check first word against shell keywords
    first = t.split()[0] if t.split() else ""
    if first in SHELL_KEYWORDS:
        return True

    # Contains common shell operators/patterns
    if any(op in t for op in ("|", "&&", "||", ";", ">", "<", "$(", "`", "#!/")):
        return True

    # Contains a known executable path pattern
    if re.search(r"\b(bin/|scripts/|\.py|\.sh|\.js|\.ts)\b", t):
        return True

    return False


def detect_cycle(tasks: dict[str, dict[str, Any]]) -> list[str] | None:
    """Return a cycle path if the dependency graph has a cycle, else None.

    Uses Kahn's algorithm for topological sort.
    """
    in_degree: dict[str, int] = {tid: 0 for tid in tasks}
    adj: dict[str, list[str]] = {tid: [] for tid in tasks}

    for tid, task in tasks.items():
        for dep in task.get("depends_on", []):
            if dep in tasks:
                adj[dep].append(tid)
                in_degree[tid] += 1
            else:
                # dangling dependency counts as a structural error elsewhere,
                # but we still treat it as an edge here to avoid false negatives
                in_degree[tid] += 1

    queue = deque([tid for tid, d in in_degree.items() if d == 0])
    visited_count = 0
    topo: list[str] = []

    while queue:
        node = queue.popleft()
        topo.append(node)
        visited_count += 1
        for neighbor in adj[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)

    if visited_count == len(tasks):
        return None

    # Find a node that wasn't visited and trace back a cycle
    remaining = {tid for tid in tasks if tid not in topo}
    for start in remaining:
        path: list[str] = []
        seen: set[str] = set()
        node = start
        while node in tasks:
            if node in seen:
                cycle_start = path.index(node)
                return path[cycle_start:] + [node]
            seen.add(node)
            path.append(node)
            deps = [d for d in tasks[node].get("depends_on", []) if d in tasks and d not in topo]
            if not deps:
                break
            node = deps[0]
    return None
