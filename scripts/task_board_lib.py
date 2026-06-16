#!/usr/bin/env python3
"""
scripts/task_board_lib.py — Shared library for the file-based task board polyfill.

Sandbox constraint: Sub-agent Write/Edit tool operations may be silently discarded
by Claude Code (GitHub #9458). Therefore, the lead (parent session) is the SOLE
writer of board.json. This library supports BOTH paths:
  - Lead write path: board_write(), lock_acquire(), lock_release()
  - Sub-agent read path: board_read(), heartbeat_write(), heartbeat_read_all()

All board mutations go through atomic write (tempfile + os.rename) and mkdir-based
locking. Recomputation of blocked_by is deterministic from depends_on + completed set.

Implementation is split across three private modules:
  _task_board_io   — constants, board_init / board_read / board_write + helpers
  _task_board_lock — lock_acquire / lock_release
  _task_board_ops  — recompute_blocked / heartbeat_* / claim_task

This file is the public API facade: import from here, not from the private modules.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Ensure private sibling modules are importable when this file is on sys.path
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

# ---------------------------------------------------------------------------
# Re-exports — public API
# ---------------------------------------------------------------------------

from task_board.io import (  # noqa: E402
    BOARD_FILENAME,
    CURRENT_SCHEMA_VERSION,
    HEARTBEAT_DIRNAME,
    LOCK_DIRNAME,
    _derive_waves,
    _is_under_cwd,
    _parse_plan_table,
    _utcnow_iso,
    board_init,
    board_read,
    board_write,
)

from task_board.lock import (  # noqa: E402
    lock_acquire,
    lock_release,
)

from task_board.ops import (  # noqa: E402
    claim_task,
    heartbeat_read_all,
    heartbeat_write,
    recompute_blocked,
)

__all__ = [
    # Constants
    "BOARD_FILENAME",
    "CURRENT_SCHEMA_VERSION",
    "HEARTBEAT_DIRNAME",
    "LOCK_DIRNAME",
    # Board I/O
    "board_init",
    "board_read",
    "board_write",
    # Locking
    "lock_acquire",
    "lock_release",
    # Operations
    "recompute_blocked",
    "heartbeat_write",
    "heartbeat_read_all",
    "claim_task",
    # Internal helpers (re-exported for backward compat)
    "_utcnow_iso",
    "_is_under_cwd",
    "_parse_plan_table",
    "_derive_waves",
]


# ---------------------------------------------------------------------------
# Self-test (TDD tracer bullet)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import shutil
    import tempfile
    import uuid

    tmp_base = Path(tempfile.gettempdir()) / f"kbg_test_{uuid.uuid4().hex}"
    plan_dir = tmp_base / "plan"
    plan_dir.mkdir(parents=True)

    try:
        # 1. Build a synthetic board directly
        board = {
            "schema_version": CURRENT_SCHEMA_VERSION,
            "plan_slug": "test",
            "plan_file": "test.md",
            "created_at": _utcnow_iso(),
            "updated_at": _utcnow_iso(),
            "status": "pending",
            "current_wave": 1,
            "tasks": {
                "A": {
                    "id": "A",
                    "description": "Task A",
                    "status": "pending",
                    "assigned_role": "backend-engineer",
                    "claimed_by": None,
                    "claimed_at": None,
                    "completed_at": None,
                    "depends_on": [],
                    "blocked_by": [],
                    "files": [],
                    "criteria": "A works",
                    "constraints": None,
                    "wave": 1,
                    "notes": "",
                },
                "B": {
                    "id": "B",
                    "description": "Task B",
                    "status": "pending",
                    "assigned_role": "backend-engineer",
                    "claimed_by": None,
                    "claimed_at": None,
                    "completed_at": None,
                    "depends_on": ["A"],
                    "blocked_by": [],
                    "files": [],
                    "criteria": "B works",
                    "constraints": None,
                    "wave": 2,
                    "notes": "",
                },
            },
            "waves": {"1": ["A"], "2": ["B"]},
            "agents": {},
        }

        # 2. Atomic write + read round-trip
        board_write(str(plan_dir), board)
        read_back = board_read(str(plan_dir))
        assert read_back["plan_slug"] == "test"
        assert read_back["schema_version"] == CURRENT_SCHEMA_VERSION
        assert "tasks" in read_back

        # 3. Lock acquire / release
        assert lock_acquire(str(plan_dir), timeout=5) is True
        assert (plan_dir / LOCK_DIRNAME).exists()
        lock_release(str(plan_dir))
        assert not (plan_dir / LOCK_DIRNAME).exists()

        # 4. Lock timeout (try to double-acquire should fail after short timeout)
        assert lock_acquire(str(plan_dir), timeout=1) is True
        second = lock_acquire(str(plan_dir), timeout=1)
        assert second is False, "Double lock should timeout"
        lock_release(str(plan_dir))

        # 5. Recompute blocked
        board = read_back
        board = recompute_blocked(board)
        assert board["tasks"]["A"]["status"] == "pending"
        assert board["tasks"]["B"]["status"] == "blocked"
        assert board["tasks"]["B"]["blocked_by"] == ["A"]

        # 6. Claim task
        result = claim_task(board, "A", "agent-1")
        assert result is not None
        assert result["tasks"]["A"]["status"] == "in_progress"
        assert result["tasks"]["A"]["claimed_by"] == "agent-1"
        assert result["agents"]["agent-1"]["id"] == "agent-1"

        # Cannot claim already-claimed task
        assert claim_task(result, "A", "agent-2") is None

        # Cannot claim blocked task
        assert claim_task(result, "B", "agent-2") is None

        # 7. Heartbeat write / read
        heartbeat_write(str(plan_dir), "agent-1", "A", "in_progress", "working on it")
        hbs = heartbeat_read_all(str(plan_dir))
        assert len(hbs) == 1
        assert hbs[0]["agent_id"] == "agent-1"
        assert hbs[0]["current_task"] == "A"

        # 8. Heartbeat corruption resilience
        bad_file = plan_dir / HEARTBEAT_DIRNAME / "bad.json"
        bad_file.write_text("not json", encoding="utf-8")
        hbs = heartbeat_read_all(str(plan_dir))
        assert len(hbs) == 1, "Corrupt heartbeat should be skipped"

        # 9. board_init from synthetic markdown
        md_path = tmp_base / "tasks" / "demo.md"
        md_path.parent.mkdir(parents=True)
        md_path.write_text(
            "## Step by Step Tasks\n"
            "| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |\n"
            "|---------|-------------|------------|-------------|-------|----------|-------------|\n"
            "| DB-1    | Create table| -          | DB          | migrations/001.sql | schema ok | none |\n"
            "| API-1   | Endpoint    | DB-1       | API         | api/users.py | 201 ok | - |\n",
            encoding="utf-8",
        )
        init_board = board_init(str(md_path))
        assert init_board["plan_slug"] == "demo"
        assert "DB-1" in init_board["tasks"]
        assert "API-1" in init_board["tasks"]
        assert init_board["tasks"]["DB-1"]["wave"] == 1
        assert init_board["tasks"]["API-1"]["wave"] == 2
        assert init_board["tasks"]["API-1"]["depends_on"] == ["DB-1"]

        print("OK — all assertions passed")
    finally:
        shutil.rmtree(tmp_base, ignore_errors=True)
