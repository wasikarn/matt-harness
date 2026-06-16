# _plan_linter_core.py — PlanLinter class for plan-linter.
#
# Pure library module — no shebang, no __main__ block.
# Imported by plan-linter.py.

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .parsers import (
    AUTH_SECRET_KEYWORDS,
    MIGRATION_TASK_KEYWORDS,
    REQUIRED_HEADERS,
    SCHEMA_CHANGE_KEYWORDS,
    detect_cycle,
    extract_sections,
    looks_like_shell_command,
    parse_list_items,
    parse_markdown_table,
    parse_numbered_list_items,
)


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
