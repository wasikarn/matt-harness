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
from pathlib import Path

# Ensure the scripts/ directory is importable when invoked as a script
sys.path.insert(0, str(Path(__file__).parent))

from plan_linter.parsers import (
    REQUIRED_HEADERS,
    extract_sections,
    parse_list_items,
)
from plan_linter.core import PlanLinter


# ---------------------------------------------------------------------------
# CLI runner
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

    content = p.read_text(encoding="utf-8", errors="replace")
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
        content = plan_path.read_text(encoding="utf-8", errors="replace")
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
