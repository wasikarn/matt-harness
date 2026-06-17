#!/usr/bin/env python3
"""
scripts/utils/migrate-plan-to-board.py — Migrate .claude/tasks/<slug>.md plan(s)
into .claude/tasks/<slug>/board.json runtime boards. Sole producer of board.json.

  --plan PATH : migrate that one plan.
  (no args)   : migrate every plan under .claude/tasks/.

Idempotent: skips boards that already exist unless --force is passed.

Uses the shared task_board_lib for board construction and atomic write.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from pathlib import Path

# Ensure we can import the sibling library (task_board_lib.py lives at scripts/ root)
_SCRIPT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_SCRIPT_DIR))

try:
    import task_board_lib as tbl
except ImportError as exc:
    print(f"[migrate] ERROR: cannot import task_board_lib: {exc}", file=sys.stderr)
    sys.exit(1)


def migrate(plan_file: str, force: bool = False) -> Path:
    """Migrate a single plan file to its board directory.

    Parameters
    ----------
    plan_file: Path to .claude/tasks/<slug>.md
    force:     Overwrite existing board.json if True

    Returns
    -------
    Path: Path to the emitted board.json
    """
    plan_path = Path(plan_file).resolve()
    if not plan_path.exists():
        raise FileNotFoundError(f"Plan file not found: {plan_file}")

    slug = plan_path.stem
    # Target directory: same parent as the plan file, subdirectory named by slug
    plan_dir = plan_path.parent / slug
    board_file = plan_dir / tbl.BOARD_FILENAME

    if board_file.exists() and not force:
        print(f"[migrate] SKIP: board already exists at {board_file} (use --force to overwrite)")
        return board_file

    board = tbl.board_init(str(plan_path))
    tbl.board_write(str(plan_dir), board)
    print(f"[migrate] OK: {board_file}")
    return board_file


def migrate_all(tasks_dir: str = ".claude/tasks", force: bool = False) -> int:
    """Migrate every <slug>.md directly under tasks_dir. Returns plans processed.

    Idempotent via migrate() — boards that already exist print SKIP and are
    left untouched, so re-running is safe.
    """
    plans = sorted(Path(tasks_dir).glob("*.md"))
    for plan in plans:
        migrate(str(plan), force=force)
    return len(plans)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Migrate plan markdown to board.json")
    parser.add_argument("--plan", help="One .claude/tasks/<slug>.md (default: every plan under .claude/tasks/)")
    parser.add_argument("--force", action="store_true", help="Overwrite existing board.json")
    args = parser.parse_args(argv)

    try:
        if args.plan:
            migrate(args.plan, force=args.force)
        elif migrate_all(force=args.force) == 0:
            print("[migrate] no plan files found under .claude/tasks/")
        return 0
    except Exception as exc:
        print(f"[migrate] ERROR: {exc}", file=sys.stderr)
        return 1


# ---------------------------------------------------------------------------
# Self-test (TDD tracer bullet)
# ---------------------------------------------------------------------------

def _self_test() -> None:
    import uuid as uuid_mod

    tmp_base = Path(tempfile.gettempdir()) / f"kbg_migrate_test_{uuid_mod.uuid4().hex}"
    tasks_dir = tmp_base / ".claude" / "tasks"
    tasks_dir.mkdir(parents=True)

    try:
        # 1. Write a sample plan markdown
        plan_path = tasks_dir / "health-endpoint.md"
        plan_path.write_text(
            "# Health Endpoint Plan\n\n"
            "## Step by Step Tasks\n"
            "| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |\n"
            "|---------|-------------|------------|-------------|-------|----------|-------------|\n"
            "| DB-1    | Create users table | - | DB | migrations/002_users.sql | exports users(id, email) | no destructive changes |\n"
            "| API-1   | POST /users endpoint | DB-1 | API | api/users.py | returns 201 + JSON body | uses backend-dev skill |\n"
            "| V-1     | Lint + test pass | API-1 | V | (none) | bash -n + pytest exit 0 | (none) |\n"
            "| INT-1   | End-to-end trace | V-1 | INT | (none) | integration test green | single TaskUpdate |\n",
            encoding="utf-8",
        )

        # 2. Migrate
        board_file = migrate(str(plan_path))
        assert board_file.exists()

        # 3. Validate emitted board
        board = tbl.board_read(str(board_file.parent))
        assert board["plan_slug"] == "health-endpoint"
        assert board["schema_version"] == tbl.CURRENT_SCHEMA_VERSION
        assert "DB-1" in board["tasks"]
        assert "API-1" in board["tasks"]
        assert "V-1" in board["tasks"]
        assert "INT-1" in board["tasks"]

        # Wave checks
        assert board["tasks"]["DB-1"]["wave"] == 1
        assert board["tasks"]["API-1"]["wave"] == 2
        assert board["tasks"]["V-1"]["wave"] == 3
        assert board["tasks"]["INT-1"]["wave"] == 4

        # Initial blocked state
        assert board["tasks"]["DB-1"]["status"] == "pending"
        assert board["tasks"]["DB-1"]["blocked_by"] == []
        assert board["tasks"]["API-1"]["status"] == "blocked"
        assert board["tasks"]["API-1"]["blocked_by"] == ["DB-1"]
        assert board["tasks"]["V-1"]["status"] == "blocked"
        assert board["tasks"]["V-1"]["blocked_by"] == ["API-1"]

        # Waves mapping
        assert board["waves"]["1"] == ["DB-1"]
        assert board["waves"]["2"] == ["API-1"]
        assert board["waves"]["3"] == ["V-1"]
        assert board["waves"]["4"] == ["INT-1"]

        # 4. Idempotency — second run should skip
        import io
        old_stdout = sys.stdout
        sys.stdout = io.StringIO()
        board_file2 = migrate(str(plan_path))
        stdout_val = sys.stdout.getvalue()
        sys.stdout = old_stdout
        assert "SKIP" in stdout_val, f"Expected SKIP in output, got: {stdout_val}"
        assert board_file2 == board_file

        # 5. Force overwrite
        board_file3 = migrate(str(plan_path), force=True)
        assert board_file3 == board_file
        board_forced = tbl.board_read(str(board_file3.parent))
        assert board_forced["plan_slug"] == "health-endpoint"

        # 5b. Bulk mode — migrate_all sweeps every *.md under tasks_dir (idempotent)
        (tasks_dir / "second-plan.md").write_text(
            "# Second\n\n## Step by Step Tasks\n"
            "| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |\n"
            "|---------|-------------|------------|-------------|-------|----------|-------------|\n"
            "| X-1     | only task | - | DB | a.sql | exports x | (none) |\n",
            encoding="utf-8",
        )
        assert migrate_all(str(tasks_dir)) == 2  # health-endpoint skips, second-plan new
        assert (tasks_dir / "second-plan" / tbl.BOARD_FILENAME).exists()

        # 6. Missing plan file should raise
        try:
            migrate(str(tasks_dir / "nonexistent.md"))
            raise AssertionError("Expected FileNotFoundError")
        except FileNotFoundError:
            pass

        print("OK — all migration assertions passed")
    finally:
        shutil.rmtree(tmp_base, ignore_errors=True)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        _self_test()
    else:
        sys.exit(main())
