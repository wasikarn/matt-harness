#!/usr/bin/env python3
"""
scripts/plan-linter.py — Pre-flight plan validator for /team-build consumption.

Validates a .claude/tasks/<slug>.md plan file against structural rules,
dependency acyclicity, file-ownership uniqueness, acceptance-criteria
coverage, and (in --strict mode) the F10 plan-approval risk filter.

Usage:
    python3 scripts/plan-linter.py .claude/tasks/health-endpoint.md [--strict] [--json]
    python3 scripts/plan-linter.py --self-test

Exit codes:
    0 — all checks pass
    1 — one or more structural checks failed
    2 — strict-mode warnings present (but structural checks pass)
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
import uuid
from collections import deque
from pathlib import Path
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
        elif stripped.startswith("|") and header_idx is None:
            # Tentative header — must be followed by separator
            header_idx = i

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


# ---------------------------------------------------------------------------
# Core linter
# ---------------------------------------------------------------------------

class PlanLinter:
    def __init__(self, content: str, strict: bool = False) -> None:
        self.content = content
        self.strict = strict
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.sections = extract_sections(content)
        self.tasks: dict[str, dict[str, Any]] = {}
        self.team_members: list[dict[str, str]] = []

    def _add_error(self, msg: str) -> None:
        self.errors.append(msg)

    def _add_warning(self, msg: str) -> None:
        if self.strict:
            self.warnings.append(msg)

    def _has_section(self, name: str) -> bool:
        return name in self.sections and self.sections[name].strip() != ""

    def lint(self) -> dict[str, Any]:
        self._check_structure()
        self._check_brain_dump()
        self._check_qa_log()
        self._check_team_members()
        self._check_tasks()
        self._check_dependencies()
        self._check_file_ownership()
        self._check_acceptance_criteria()
        self._check_validation_commands()
        if self.strict:
            self._check_f10()
        return {
            "valid": len(self.errors) == 0,
            "errors": self.errors,
            "warnings": self.warnings,
        }

    # ------------------------------------------------------------------
    # Structure
    # ------------------------------------------------------------------

    def _check_structure(self) -> None:
        for header in REQUIRED_HEADERS:
            if not self._has_section(header):
                self._add_error(f"Missing or empty required section: ## {header}")

    # ------------------------------------------------------------------
    # Brain dump
    # ------------------------------------------------------------------

    def _check_brain_dump(self) -> None:
        if "Brain dump" not in self.sections:
            return
        body = self.sections["Brain dump"].strip()
        # Remove markdown header artifacts if any leaked in
        body = re.sub(r"^#+\s*", "", body)
        if len(body) < 50:
            self._add_error(
                f"Brain dump too short ({len(body)} chars, need >= 50)"
            )

    # ------------------------------------------------------------------
    # Q&A log
    # ------------------------------------------------------------------

    def _check_qa_log(self) -> None:
        if "Q&A log" not in self.sections:
            return
        items = parse_numbered_list_items(self.sections["Q&A log"])
        if len(items) < 10:
            self._add_error(
                f"Q&A log has {len(items)} entries, need >= 10"
            )

    # ------------------------------------------------------------------
    # Team Members
    # ------------------------------------------------------------------

    def _check_team_members(self) -> None:
        if "Team Members" not in self.sections:
            return
        text = self.sections["Team Members"]
        rows = parse_markdown_table(text)
        if rows is not None:
            self.team_members = rows
        else:
            items = parse_list_items(text)
            parsed: list[dict[str, str]] = []
            for item in items:
                # Try to extract name/role/focus from list prose
                # e.g. "DB — Schema/migration owner (backend-engineer)"
                m = re.match(r"^(.+?)\s*[—-]\s*(.+?)\s*[\[(]\s*(.+?)\s*[\])]$", item)
                if m:
                    parsed.append({
                        "name": m.group(1).strip(),
                        "role": m.group(2).strip(),
                        "focus": m.group(3).strip(),
                    })
                else:
                    parts = [p.strip() for p in item.split("-", 2)]
                    if len(parts) >= 3:
                        parsed.append({
                            "name": parts[0],
                            "role": parts[1],
                            "focus": parts[2],
                        })
                    elif len(parts) == 2:
                        parsed.append({
                            "name": parts[0],
                            "role": parts[1],
                            "focus": "",
                        })
                    else:
                        parsed.append({
                            "name": item,
                            "role": "",
                            "focus": "",
                        })
            self.team_members = parsed

        count = len(self.team_members)
        if count < 3 or count > 5:
            self._add_error(
                f"Team Members count = {count}, expected 3-5"
            )

        for idx, member in enumerate(self.team_members):
            name = member.get("name", "").strip()
            role = member.get("role", "").strip()
            focus = (
                member.get("focus", "").strip()
                or member.get("agent type", "").strip()
            )
            if not name:
                self._add_error(f"Team member #{idx + 1} missing name")
            if not role:
                self._add_error(f"Team member #{idx + 1} missing role")
            if not focus:
                self._add_error(
                    f"Team member #{idx + 1} missing focus / agent type"
                )

    # ------------------------------------------------------------------
    # Step by Step Tasks
    # ------------------------------------------------------------------

    def _check_tasks(self) -> None:
        if "Step by Step Tasks" not in self.sections:
            return
        rows = parse_markdown_table(self.sections["Step by Step Tasks"])
        if rows is None:
            self._add_error("Step by Step Tasks section has no parseable table")
            return

        required_cols = {"task id", "description", "depends on", "files", "criteria", "constraints"}
        present = {k.lower() for k in rows[0].keys() if k.strip()}
        missing = required_cols - present
        if missing:
            self._add_error(
                f"Step by Step Tasks table missing columns: {', '.join(sorted(missing))}"
            )

        for idx, row in enumerate(rows):
            tid = row.get("task id", "").strip()
            desc = row.get("description", "").strip()
            if not tid:
                self._add_error(f"Task row #{idx + 1} missing Task ID")
            if not desc:
                self._add_error(f"Task row #{idx + 1} missing Description")
            if tid:
                depends_raw = row.get("depends on", "-").strip()
                depends = [d.strip() for d in depends_raw.split(",") if d.strip() and d.strip() != "-"]
                files_raw = row.get("files", "").strip()
                files = [f.strip() for f in files_raw.split(",") if f.strip() and f.strip().lower() != "(none)"]
                self.tasks[tid] = {
                    "id": tid,
                    "description": desc,
                    "depends_on": depends,
                    "files": files,
                    "criteria": row.get("criteria", "").strip(),
                    "constraints": row.get("constraints", "").strip(),
                }

    # ------------------------------------------------------------------
    # Dependencies (acyclicity)
    # ------------------------------------------------------------------

    def _check_dependencies(self) -> None:
        if not self.tasks:
            return
        # Check dangling deps
        all_ids = set(self.tasks)
        for tid, task in self.tasks.items():
            for dep in task["depends_on"]:
                if dep not in all_ids:
                    self._add_error(
                        f"Task '{tid}' depends on unknown task '{dep}'"
                    )
        cycle = detect_cycle(self.tasks)
        if cycle:
            self._add_error(
                f"Cyclic dependency detected: {' -> '.join(cycle)}"
            )

    # ------------------------------------------------------------------
    # File ownership unique
    # ------------------------------------------------------------------

    def _check_file_ownership(self) -> None:
        file_to_tasks: dict[str, list[str]] = {}
        for tid, task in self.tasks.items():
            for f in task["files"]:
                if f:
                    file_to_tasks.setdefault(f, []).append(tid)
        for f, tids in file_to_tasks.items():
            if len(tids) > 1:
                self._add_error(
                    f"File '{f}' owned by multiple tasks: {', '.join(tids)}"
                )

    # ------------------------------------------------------------------
    # Acceptance Criteria
    # ------------------------------------------------------------------

    def _check_acceptance_criteria(self) -> None:
        if "Acceptance Criteria" not in self.sections:
            return
        text = self.sections["Acceptance Criteria"]
        items = parse_list_items(text)
        if len(items) < 3:
            self._add_error(
                f"Acceptance Criteria has {len(items)} items, need >= 3"
            )
        for idx, item in enumerate(items):
            if "validation_command:" not in item.lower():
                self._add_error(
                    f"Acceptance criterion #{idx + 1} missing validation_command:"
                )

    # ------------------------------------------------------------------
    # Validation Commands
    # ------------------------------------------------------------------

    def _check_validation_commands(self) -> None:
        if "Validation Commands" not in self.sections:
            return
        text = self.sections["Validation Commands"]
        items = parse_list_items(text)
        if len(items) < 3:
            self._add_error(
                f"Validation Commands has {len(items)} items, need >= 3"
            )
        for idx, item in enumerate(items):
            if not looks_like_shell_command(item):
                self._add_error(
                    f"Validation command #{idx + 1} does not look like a runnable shell command: {item[:80]}"
                )

    # ------------------------------------------------------------------
    # F10 strict checks
    # ------------------------------------------------------------------

    def _check_f10(self) -> None:
        # 1. Auth/secrets without security-reviewer
        has_security_reviewer = any(
            "security" in (m.get("role", "") + m.get("focus", "")).lower()
            for m in self.team_members
        )
        if not has_security_reviewer:
            for tid, task in self.tasks.items():
                combined = (
                    task["description"] + " " + task["criteria"]
                    + " " + " ".join(task["files"])
                ).lower()
                if any(kw in combined for kw in AUTH_SECRET_KEYWORDS):
                    self._add_warning(
                        f"F10: Task '{tid}' touches auth/secrets but team has no security-reviewer"
                    )
                    break  # one warning is enough

        # 2. Schema changes without migration task
        has_migration_task = any(
            any(kw in (task["description"] + " " + task["criteria"]).lower()
                for kw in MIGRATION_TASK_KEYWORDS)
            and any(f.endswith(".sql") or "migration" in f.lower()
                    for f in task["files"])
            for task in self.tasks.values()
        ) if self.tasks else False

        schema_tasks = []
        for tid, task in self.tasks.items():
            combined = (task["description"] + " " + task["criteria"]).lower()
            if any(kw in combined for kw in SCHEMA_CHANGE_KEYWORDS):
                schema_tasks.append(tid)
        if schema_tasks and not has_migration_task:
            self._add_warning(
                f"F10: Schema change tasks {schema_tasks} but no dedicated migration task found"
            )

        # 3. No integration validator for cross-component boundaries
        has_integration_validator = any(
            tid.lower().startswith("int-")
            or "integration" in task["description"].lower()
            or "integration" in (task.get("assigned role", "") or "").lower()
            for tid, task in self.tasks.items()
        ) if self.tasks else False

        # Heuristic: cross-component = any task depends on a task with different assigned role
        # We don't have assigned_role in tasks here because we only parsed the task table
        # Let's re-read the rows for assigned_to / assigned role
        if "Step by Step Tasks" in self.sections:
            rows = parse_markdown_table(self.sections["Step by Step Tasks"])
            if rows:
                assignees: dict[str, str] = {}
                for row in rows:
                    tid = row.get("task id", "").strip()
                    assigned = row.get("assigned to", "").strip()
                    if tid and assigned:
                        assignees[tid] = assigned
                cross_component = False
                for tid, task in self.tasks.items():
                    for dep in task["depends_on"]:
                        if dep in assignees and tid in assignees:
                            if assignees[dep] != assignees[tid]:
                                cross_component = True
                                break
                    if cross_component:
                        break
                if cross_component and not has_integration_validator:
                    self._add_warning(
                        "F10: Cross-component dependencies detected but no integration validator (INT-*) task found"
                    )

        # 4. Overlapping file paths — directory-level overlap (strict nuance)
        # We already check exact duplicates in non-strict; here flag same-directory
        # ownership of many files as a merge-conflict risk.
        dirs: dict[str, list[str]] = {}
        for tid, task in self.tasks.items():
            for f in task["files"]:
                dir_part = str(Path(f).parent)
                if dir_part == ".":
                    continue
                dirs.setdefault(dir_part, []).append(tid)
        for d, tids in dirs.items():
            unique = set(tids)
            if len(unique) > 1 and len(tids) >= 3:
                self._add_warning(
                    f"F10: Directory '{d}' touched by multiple tasks ({', '.join(sorted(unique))}) — merge conflict risk"
                )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def run_linter(plan_path: str, strict: bool = False, json_mode: bool = False) -> int:
    p = Path(plan_path)
    if not p.exists():
        msg = f"Plan file not found: {plan_path}"
        if json_mode:
            print(json.dumps({"valid": False, "errors": [msg], "warnings": []}))
        else:
            print(msg, file=sys.stderr)
        return 1

    content = p.read_text(encoding="utf-8")
    linter = PlanLinter(content, strict=strict)
    result = linter.lint()

    if json_mode:
        print(json.dumps(result))
    else:
        if result["errors"]:
            print("Plan has errors")
            for e in result["errors"]:
                print(f"  - {e}")
        elif result["warnings"]:
            print("Plan is structurally valid but has F10 risks")
            for w in result["warnings"]:
                print(f"  - {w}")
        else:
            print("Plan is flight-ready")
            # Summary stats
            sections = linter.sections
            tasks = linter.tasks
            print(f"  Sections: {len(sections)}")
            print(f"  Tasks: {len(tasks)}")
            print(f"  Team members: {len(linter.team_members)}")
            ac_items = parse_list_items(sections.get("Acceptance Criteria", ""))
            vc_items = parse_list_items(sections.get("Validation Commands", ""))
            print(f"  Acceptance criteria: {len(ac_items)}")
            print(f"  Validation commands: {len(vc_items)}")

    if result["errors"]:
        return 1
    if result["warnings"]:
        return 2
    return 0


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _self_test() -> None:
    tmp_base = Path(tempfile.gettempdir()) / f"kbg_linter_test_{uuid.uuid4().hex}"
    tmp_base.mkdir(parents=True)

    try:
        # ------------------------------------------------------------------
        # Good plan
        # ------------------------------------------------------------------
        good_plan = tmp_base / "good.md"
        good_plan.write_text(
            "# Good Plan\n\n"
            "## Brain dump\n"
            "This is a detailed brain dump that explains the feature we want to build. "
            "It covers the user story, the endpoints, and the database changes needed.\n\n"
            "## Q&A log\n"
            "1. What is the expected throughput? A: 1000 RPS.\n"
            "2. Do we need caching? A: Yes, Redis.\n"
            "3. What auth mechanism? A: OAuth2.\n"
            "4. Backwards compat? A: Yes, v1 stays.\n"
            "5. Test strategy? A: Unit + e2e.\n"
            "6. Rollback plan? A: Blue/green.\n"
            "7. Observability? A: Prometheus metrics.\n"
            "8. Error handling? A: Retry with backoff.\n"
            "9. Rate limiting? A: Token bucket.\n"
            "10. Data retention? A: 30 days.\n\n"
            "## Team Members\n"
            "| Name | Role | Agent Type |\n"
            "|------|------|------------|\n"
            "| DB   | Schema/migration owner | backend-engineer |\n"
            "| API  | Endpoint owner         | backend-engineer |\n"
            "| V    | Validator              | code-reviewer    |\n"
            "| INT  | Integration validator  | code-explorer    |\n\n"
            "## Step by Step Tasks\n"
            "| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |\n"
            "|---------|-------------|------------|-------------|-------|----------|-------------|\n"
            "| DB-1    | Create users table | - | DB | migrations/001.sql | schema ok | none |\n"
            "| API-1   | POST /users endpoint | DB-1 | API | api/users.py | returns 201 | - |\n"
            "| V-1     | Lint + test | API-1 | V | (none) | pytest green | - |\n"
            "| INT-1   | End-to-end trace | V-1 | INT | (none) | integration green | - |\n\n"
            "## Acceptance Criteria\n"
            "- [ ] DB-1: users table exists validation_command: bash scripts/check_db.sh\n"
            "- [ ] API-1: POST /users returns 201 validation_command: pytest tests/test_api.py\n"
            "- [ ] V-1: tests pass validation_command: pytest tests/ -v\n"
            "- [ ] INT-1: e2e green validation_command: pytest tests/e2e/ -v\n\n"
            "## Validation Commands\n"
            "- `bash -n api/users.py`\n"
            "- `pytest tests/test_api.py -v`\n"
            "- `pytest tests/e2e/ -v`\n"
            "- `curl -X POST http://localhost:8000/api/users -d '{\"email\":\"x@y.z\"}'`\n\n",
            encoding="utf-8",
        )

        code = run_linter(str(good_plan), strict=False, json_mode=False)
        assert code == 0, f"Good plan should pass, got exit {code}"

        # Strict mode should also pass for good plan (has security? no, but also no auth tasks)
        code = run_linter(str(good_plan), strict=True, json_mode=False)
        assert code == 0, f"Good plan strict should pass, got exit {code}"

        # JSON mode
        import io
        old_stdout = sys.stdout
        sys.stdout = io.StringIO()
        code = run_linter(str(good_plan), strict=False, json_mode=True)
        json_out = sys.stdout.getvalue()
        sys.stdout = old_stdout
        assert code == 0
        parsed = json.loads(json_out)
        assert parsed["valid"] is True
        assert parsed["errors"] == []

        # ------------------------------------------------------------------
        # Bad plan — missing sections
        # ------------------------------------------------------------------
        bad_plan = tmp_base / "bad.md"
        bad_plan.write_text(
            "# Bad Plan\n\n"
            "## Brain dump\n"
            "Short.\n\n"
            "## Team Members\n"
            "| Name | Role | Agent Type |\n"
            "|------|------|------------|\n"
            "| A    | Dev  | backend-engineer |\n\n"
            "## Step by Step Tasks\n"
            "| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |\n"
            "|---------|-------------|------------|-------------|-------|----------|-------------|\n"
            "| T-1    | Do thing | T-2 | A | file.py | ok | - |\n"
            "| T-2    | Do other | T-1 | A | file.py | ok | - |\n\n"
            "## Acceptance Criteria\n"
            "- [ ] One criterion without validation command\n\n"
            "## Validation Commands\n"
            "- this is prose, not a command\n",
            encoding="utf-8",
        )

        sys.stdout = io.StringIO()
        code = run_linter(str(bad_plan), strict=False, json_mode=False)
        out = sys.stdout.getvalue()
        sys.stdout = old_stdout
        assert code == 1, f"Bad plan should fail with 1, got {code}"
        assert "Brain dump too short" in out
        assert "Cyclic dependency" in out
        assert "File 'file.py' owned by multiple tasks" in out
        assert "missing validation_command:" in out
        assert "does not look like a runnable shell command" in out
        assert "Acceptance Criteria has 1 items, need >= 3" in out
        assert "Validation Commands has 1 items, need >= 3" in out
        assert "Team Members count = 1, expected 3-5" in out

        # ------------------------------------------------------------------
        # Strict warnings plan
        # ------------------------------------------------------------------
        warn_plan = tmp_base / "warn.md"
        warn_plan.write_text(
            "# Warn Plan\n\n"
            "## Brain dump\n"
            "This is a detailed brain dump that explains the feature we want to build. "
            "It covers the user story, the endpoints, and the database changes needed.\n\n"
            "## Q&A log\n"
            "1. Q1? A: A1.\n"
            "2. Q2? A: A2.\n"
            "3. Q3? A: A3.\n"
            "4. Q4? A: A4.\n"
            "5. Q5? A: A5.\n"
            "6. Q6? A: A6.\n"
            "7. Q7? A: A7.\n"
            "8. Q8? A: A8.\n"
            "9. Q9? A: A9.\n"
            "10. Q10? A: A10.\n\n"
            "## Team Members\n"
            "| Name | Role | Agent Type |\n"
            "|------|------|------------|\n"
            "| DB   | Schema owner | backend-engineer |\n"
            "| API  | Endpoint owner | backend-engineer |\n"
            "| V    | Validator | code-reviewer |\n\n"
            "## Step by Step Tasks\n"
            "| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |\n"
            "|---------|-------------|------------|-------------|-------|----------|-------------|\n"
            "| DB-1    | Add users table | - | DB | db/users.py | exports users(id) | none |\n"
            "| API-1   | POST /users with password hashing | DB-1 | API | api/users.py | returns 201 | uses auth |\n"
            "| V-1     | Lint + test | API-1 | V | (none) | pytest green | - |\n\n"
            "## Acceptance Criteria\n"
            "- [ ] DB-1: table exists validation_command: bash scripts/check_db.sh\n"
            "- [ ] API-1: POST returns 201 validation_command: pytest tests/test_api.py\n"
            "- [ ] V-1: tests pass validation_command: pytest tests/ -v\n\n"
            "## Validation Commands\n"
            "- `bash -n api/users.py`\n"
            "- `pytest tests/test_api.py -v`\n"
            "- `pytest tests/ -v`\n\n",
            encoding="utf-8",
        )

        sys.stdout = io.StringIO()
        code = run_linter(str(warn_plan), strict=True, json_mode=False)
        out = sys.stdout.getvalue()
        sys.stdout = old_stdout
        assert code == 2, f"Warn plan strict should exit 2, got {code}"
        assert "F10: Task 'API-1' touches auth/secrets" in out
        assert "F10: Schema change tasks" in out
        assert "F10: Cross-component dependencies" in out

        # Non-strict should pass for warn_plan (structurally valid)
        code = run_linter(str(warn_plan), strict=False, json_mode=False)
        assert code == 0, f"Warn plan non-strict should pass, got {code}"

        # ------------------------------------------------------------------
        # JSON strict warnings
        # ------------------------------------------------------------------
        sys.stdout = io.StringIO()
        code = run_linter(str(warn_plan), strict=True, json_mode=True)
        json_out = sys.stdout.getvalue()
        sys.stdout = old_stdout
        assert code == 2
        parsed = json.loads(json_out)
        assert parsed["valid"] is True  # structurally valid even with warnings
        assert len(parsed["warnings"]) > 0

        print("OK — all linter assertions passed")
    finally:
        shutil.rmtree(tmp_base, ignore_errors=True)


# ---------------------------------------------------------------------------
# Auto-fix
# ---------------------------------------------------------------------------

def auto_fix(content: str) -> tuple[str, list[str]]:
    """Apply trivial automatic fixes to a plan markdown.

    Returns (fixed_content, list_of_fix_descriptions).
    """
    fixes: list[str] = []
    lines = content.splitlines()
    out_lines: list[str] = []
    in_ac = False
    in_table_section = False
    table_has_separator = False
    table_section_headers = {"team members", "step by step tasks"}

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # Detect section transitions
        if stripped.startswith("## "):
            section_name = stripped[3:].strip().lower()
            in_ac = section_name == "acceptance criteria"
            in_table_section = section_name in table_section_headers
            table_has_separator = False
            out_lines.append(line)
            i += 1
            continue

        # Fix 1: Missing validation_command: in Acceptance Criteria
        if in_ac and (re.match(r"^[-*]\s+\[?\s*\]?", stripped) or re.match(r"^\d+\.\s+", stripped)):
            if "validation_command:" not in stripped.lower():
                # Append placeholder before any trailing double-space or period
                if stripped.endswith(".") and len(stripped) > 2:
                    line = line.rstrip()[:-1] + " validation_command: TBD_FIXME."
                else:
                    line = line.rstrip() + " validation_command: TBD_FIXME"
                fixes.append("Added missing validation_command: placeholder to acceptance criterion")
            out_lines.append(line)
            i += 1
            continue

        # Fix 2: Missing table separator row (only inject once per table, after header)
        if in_table_section and stripped.startswith("|") and "---" not in stripped:
            if not table_has_separator:
                if i + 1 < len(lines):
                    next_line = lines[i + 1].strip()
                    if next_line.startswith("|") and "---" in next_line:
                        table_has_separator = True
                    else:
                        # This line looks like a header row; inject separator after it
                        cells = [c.strip() for c in stripped.split("|")]
                        while cells and cells[0] == "":
                            cells.pop(0)
                        while cells and cells[-1] == "":
                            cells.pop()
                        if cells:
                            sep = "|" + "|".join([" --- " for _ in cells]) + "|"
                            out_lines.append(line)
                            out_lines.append(sep)
                            fixes.append("Inserted missing table separator row")
                            table_has_separator = True
                            i += 1
                            continue
            out_lines.append(line)
            i += 1
            continue

        if in_table_section and stripped.startswith("|") and "---" in stripped:
            table_has_separator = True
            out_lines.append(line)
            i += 1
            continue

        out_lines.append(line)
        i += 1

    # Fix 3: Ensure all required headers exist (append placeholders at end)
    existing_sections = extract_sections("\n".join(out_lines))
    for header in REQUIRED_HEADERS:
        if header not in existing_sections or existing_sections[header].strip() == "":
            out_lines.append("")
            out_lines.append(f"## {header}")
            out_lines.append("*(Auto-added placeholder — fill in before build)*")
            fixes.append(f"Added missing section: ## {header}")

    return "\n".join(out_lines), fixes


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Pre-flight plan validator")
    parser.add_argument("plan_file", nargs="?", help="Path to plan markdown file")
    parser.add_argument("--strict", action="store_true", help="Enable F10 plan-approval risk checks")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    parser.add_argument("--fix", action="store_true", help="Apply trivial auto-fixes and re-lint")
    parser.add_argument("--self-test", action="store_true", help="Run built-in self-test")
    args = parser.parse_args(argv)

    if args.self_test:
        _self_test()
        return 0

    if not args.plan_file:
        parser.error("plan_file is required (unless --self-test)")

    plan_path = Path(args.plan_file)
    if not plan_path.exists():
        msg = f"Plan file not found: {args.plan_file}"
        if args.json:
            print(json.dumps({"valid": False, "errors": [msg], "warnings": []}))
        else:
            print(msg, file=sys.stderr)
        return 1

    # Apply fixes if requested
    if args.fix:
        content = plan_path.read_text(encoding="utf-8")
        fixed_content, fix_descriptions = auto_fix(content)
        if fix_descriptions:
            plan_path.write_text(fixed_content, encoding="utf-8")
            if not args.json:
                print("Applied auto-fixes:")
                for desc in fix_descriptions:
                    print(f"  - {desc}")
                print("")
        # Re-run linter after fixes (non-strict first, strict if originally requested)
        code = run_linter(str(plan_path), strict=False, json_mode=args.json)
        if code == 0 and args.strict:
            code = run_linter(str(plan_path), strict=True, json_mode=args.json)
        return code

    return run_linter(args.plan_file, strict=args.strict, json_mode=args.json)


if __name__ == "__main__":
    sys.exit(main())
