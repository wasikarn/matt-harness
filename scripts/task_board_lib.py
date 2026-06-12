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
"""

from __future__ import annotations

import json
import os
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
CURRENT_SCHEMA_VERSION = 1
BOARD_FILENAME = "board.json"
LOCK_DIRNAME = ".lock"
HEARTBEAT_DIRNAME = "heartbeat"


# ---------------------------------------------------------------------------
# Board I/O
# ---------------------------------------------------------------------------

def board_init(plan_file: str) -> dict:
    """Parse a markdown plan file and create a fresh board.json payload.

    Parameters
    ----------
    plan_file: Path to .claude/tasks/<slug>.md

    Returns
    -------
    dict: board payload (not yet written to disk)
    """
    plan_path = Path(plan_file).resolve()
    if not plan_path.exists():
        raise FileNotFoundError(f"Plan file not found: {plan_file}")

    slug = plan_path.stem
    content = plan_path.read_text(encoding="utf-8")

    # Extract tasks table from ## Step by Step Tasks section
    tasks, waves = _parse_plan_table(content)

    now = _utcnow_iso()
    board = {
        "schema_version": CURRENT_SCHEMA_VERSION,
        "plan_slug": slug,
        "plan_file": str(plan_path.relative_to(Path.cwd())) if _is_under_cwd(plan_path) else str(plan_path),
        "created_at": now,
        "updated_at": now,
        "status": "pending",
        "current_wave": 1,
        "tasks": tasks,
        "waves": waves,
        "agents": {},
    }

    # Initial blocked recomputation
    board = recompute_blocked(board)
    return board


def board_read(plan_dir: str) -> dict:
    """Read and validate board.json from plan_dir.

    Parameters
    ----------
    plan_dir: Directory containing board.json (e.g. .claude/tasks/<slug>/)

    Returns
    -------
    dict: Parsed board payload

    Raises
    ------
    FileNotFoundError: board.json does not exist
    ValueError: schema_version mismatch or malformed JSON
    """
    board_file = Path(plan_dir) / BOARD_FILENAME
    if not board_file.exists():
        raise FileNotFoundError(f"Board file not found: {board_file}")

    raw = board_file.read_text(encoding="utf-8")
    try:
        payload: dict[str, Any] = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {board_file}: {exc}") from exc

    version = payload.get("schema_version")
    if version != CURRENT_SCHEMA_VERSION:
        raise ValueError(
            f"Unsupported schema_version: {version} (expected {CURRENT_SCHEMA_VERSION})"
        )

    if "tasks" not in payload or not isinstance(payload["tasks"], dict):
        raise ValueError(f"Malformed board: missing 'tasks' dict in {board_file}")

    return payload


def board_write(plan_dir: str, payload: dict) -> None:
    """Atomically write board.json using tempfile + os.rename.

    Parameters
    ----------
    plan_dir: Target directory
    payload:  Board dict to serialize
    """
    board_file = Path(plan_dir) / BOARD_FILENAME
    # Ensure directory exists
    board_file.parent.mkdir(parents=True, exist_ok=True)

    payload["updated_at"] = _utcnow_iso()
    tmp = board_file.with_suffix(f".tmp.{os.getpid()}")
    try:
        with tmp.open("w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.rename(str(tmp), str(board_file))
    except Exception:
        if tmp.exists():
            os.unlink(str(tmp))
        raise


# ---------------------------------------------------------------------------
# Locking (mkdir protocol — portable POSIX)
# ---------------------------------------------------------------------------

def lock_acquire(plan_dir: str, timeout: int = 10) -> bool:
    """Acquire a mkdir-based lock on plan_dir/.lock

    Parameters
    ----------
    plan_dir: Directory to lock under
    timeout:  Seconds to wait before giving up

    Returns
    -------
    bool: True if lock acquired, False on timeout
    """
    lock_dir = Path(plan_dir) / LOCK_DIRNAME
    waited = 0
    # Each iteration sleeps 0.1s, so timeout*10 iterations ~= timeout seconds
    while True:
        try:
            lock_dir.mkdir(parents=False, exist_ok=False)
            return True
        except FileExistsError:
            time.sleep(0.1)
            waited += 1
            if waited >= timeout * 10:
                return False


def lock_release(plan_dir: str) -> None:
    """Release the mkdir-based lock.

    Parameters
    ----------
    plan_dir: Directory whose .lock should be removed
    """
    lock_dir = Path(plan_dir) / LOCK_DIRNAME
    if lock_dir.exists():
        lock_dir.rmdir()


# ---------------------------------------------------------------------------
# Dependency recomputation
# ---------------------------------------------------------------------------

def recompute_blocked(board: dict) -> dict:
    """Update blocked_by and status from depends_on + completed status.

    A task is blocked if any of its depends_on tasks are not completed.
    Status transitions:
      - completed → stays completed
      - blocked   → pending if no remaining blockers
      - pending   → blocked if blockers appear (should not happen in normal flow)

    Parameters
    ----------
    board: Board dict (mutated in place and returned)

    Returns
    -------
    dict: The mutated board dict
    """
    tasks = board.get("tasks", {})
    completed = {
        tid for tid, task in tasks.items()
        if task.get("status") == "completed"
    }

    for tid, task in tasks.items():
        if task.get("status") == "completed":
            task["blocked_by"] = []
            continue

        deps = task.get("depends_on", []) or []
        remaining = [d for d in deps if d not in completed]
        task["blocked_by"] = remaining

        if remaining:
            if task.get("status") not in ("in_progress", "completed"):
                task["status"] = "blocked"
        else:
            if task.get("status") == "blocked":
                task["status"] = "pending"

    # Derive plan-level status
    all_statuses = {t.get("status") for t in tasks.values()}
    if all_statuses == {"completed"}:
        board["status"] = "completed"
    elif "in_progress" in all_statuses:
        board["status"] = "in_progress"
    elif "blocked" in all_statuses or "pending" in all_statuses:
        board["status"] = "pending" if "pending" in all_statuses else "in_progress"
    else:
        board["status"] = "in_progress"

    # Derive current_wave from unblocked / in-progress tasks
    current_wave = None
    for tid, task in sorted(tasks.items()):
        status = task.get("status")
        if status in ("pending", "in_progress"):
            wave = task.get("wave")
            if wave is not None and (current_wave is None or wave < current_wave):
                current_wave = wave
    board["current_wave"] = current_wave if current_wave is not None else 1

    return board


# ---------------------------------------------------------------------------
# Heartbeat I/O
# ---------------------------------------------------------------------------

def heartbeat_write(plan_dir: str, agent_id: str, task_id: str, status: str, note: str) -> None:
    """Write a per-agent heartbeat JSON. No lock required.

    Parameters
    ----------
    plan_dir: Plan directory
    agent_id: Agent/session identifier
    task_id:  Current task being worked on
    status:   Task status string
    note:     Human-readable progress note
    """
    hb_dir = Path(plan_dir) / HEARTBEAT_DIRNAME
    hb_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "agent_id": agent_id,
        "current_task": task_id,
        "task_status": status,
        "last_heartbeat": _utcnow_iso(),
        "progress_note": note,
    }

    hb_file = hb_dir / f"{agent_id}.json"
    tmp = hb_file.with_suffix(f".tmp.{os.getpid()}")
    try:
        with tmp.open("w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.rename(str(tmp), str(hb_file))
    except Exception:
        if tmp.exists():
            os.unlink(str(tmp))
        raise


def heartbeat_read_all(plan_dir: str) -> list:
    """Scan heartbeat/*.json and return list of heartbeat dicts.

    Parameters
    ----------
    plan_dir: Plan directory containing heartbeat/ subdirectory

    Returns
    -------
    list: Parsed heartbeat JSON objects
    """
    hb_dir = Path(plan_dir) / HEARTBEAT_DIRNAME
    if not hb_dir.exists():
        return []

    results = []
    for fpath in sorted(hb_dir.glob("*.json")):
        try:
            raw = fpath.read_text(encoding="utf-8")
            data = json.loads(raw)
            data.setdefault("_file", str(fpath.name))
            results.append(data)
        except (json.JSONDecodeError, OSError):
            # Skip corrupted heartbeat files silently — they are ephemeral
            continue
    return results


# ---------------------------------------------------------------------------
# Claim protocol
# ---------------------------------------------------------------------------

def claim_task(board: dict, task_id: str, agent_id: str) -> dict | None:
    """Attempt to claim a task. Mutates board in place if successful.

    Eligibility:
      - task.status == "pending"
      - len(task.blocked_by) == 0
      - task.claimed_by is None

    On success, sets status="in_progress", claimed_by=agent_id, claimed_at=now.

    Parameters
    ----------
    board:    Board dict
    task_id:  Task to claim
    agent_id: Agent claiming the task

    Returns
    -------
    dict: Mutated board on success, None on failure
    """
    tasks = board.get("tasks", {})
    task = tasks.get(task_id)
    if task is None:
        return None

    if task.get("status") != "pending":
        return None
    if task.get("claimed_by") is not None:
        return None
    blocked_by = task.get("blocked_by", []) or []
    if blocked_by:
        return None

    task["status"] = "in_progress"
    task["claimed_by"] = agent_id
    task["claimed_at"] = _utcnow_iso()
    board["updated_at"] = _utcnow_iso()

    # Ensure agent entry exists
    agents = board.setdefault("agents", {})
    if agent_id not in agents:
        agents[agent_id] = {
            "id": agent_id,
            "spawned_at": _utcnow_iso(),
            "last_heartbeat_file": str(Path(HEARTBEAT_DIRNAME) / f"{agent_id}.json"),
        }

    return board


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _is_under_cwd(p: Path) -> bool:
    try:
        p.relative_to(Path.cwd())
        return True
    except ValueError:
        return False


def _parse_plan_table(content: str) -> tuple[dict, dict]:
    """Naive markdown table parser for ## Step by Step Tasks.

    Expected table columns (order-insensitive header matching):
      Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints

    Returns (tasks dict, waves dict).
    """
    lines = content.splitlines()
    in_section = False
    header_line_idx = None
    separator_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("## Step by Step Tasks"):
            in_section = True
            continue
        if in_section and line.strip().startswith("## "):
            break
        if in_section and "|" in line and "Task ID" in line:
            header_line_idx = i
            continue
        if in_section and header_line_idx is not None and separator_idx is None and "|---" in line:
            separator_idx = i
            break

    if header_line_idx is None or separator_idx is None:
        raise ValueError("Could not find Step by Step Tasks table in plan file")

    headers = [h.strip().lower() for h in lines[header_line_idx].split("|")]
    col_map = {}
    for idx, h in enumerate(headers):
        if "task id" in h:
            col_map["id"] = idx
        elif "description" in h:
            col_map["description"] = idx
        elif "depends on" in h:
            col_map["depends_on"] = idx
        elif "assigned to" in h or "assigned" in h:
            col_map["assigned_to"] = idx
        elif "files" in h:
            col_map["files"] = idx
        elif "criteria" in h:
            col_map["criteria"] = idx
        elif "constraints" in h:
            col_map["constraints"] = idx

    if "id" not in col_map or "description" not in col_map:
        raise ValueError("Step by Step Tasks table missing required columns (Task ID, Description)")

    tasks: dict[str, dict] = {}
    for line in lines[separator_idx + 1 :]:
        stripped = line.strip()
        if not stripped or not stripped.startswith("|"):
            continue
        if stripped.startswith("## "):
            break
        cells = [c.strip() for c in stripped.split("|")]
        if len(cells) < max(col_map.values()) + 1:
            continue

        task_id = cells[col_map["id"]]
        if not task_id or task_id.lower() == "task id":
            continue

        desc = cells[col_map.get("description", 1)] if "description" in col_map else ""
        depends_raw = cells[col_map.get("depends_on", 2)] if "depends_on" in col_map else ""
        depends_on = [d.strip() for d in depends_raw.split(",") if d.strip() and d.strip() != "-"]
        assigned = cells[col_map.get("assigned_to", 3)] if "assigned_to" in col_map else ""
        files_raw = cells[col_map.get("files", 5)] if "files" in col_map else ""
        files = [f.strip() for f in files_raw.split(",") if f.strip() and f.strip() != "(none)"]
        criteria = cells[col_map.get("criteria", 6)] if "criteria" in col_map else ""
        constraints = cells[col_map.get("constraints", 7)] if "constraints" in col_map else None
        if constraints in ("", "(none)", "-"):
            constraints = None

        tasks[task_id] = {
            "id": task_id,
            "description": desc,
            "status": "pending",
            "assigned_role": assigned,
            "claimed_by": None,
            "claimed_at": None,
            "completed_at": None,
            "depends_on": depends_on,
            "blocked_by": [],
            "files": files,
            "criteria": criteria,
            "constraints": constraints,
            "wave": None,
            "notes": "",
        }

    waves = _derive_waves(tasks)
    for tid, task in tasks.items():
        task["wave"] = waves.get(tid)

    # Convert waves mapping to wave-number -> list-of-task-ids
    wave_groups: dict[str, list] = {}
    for tid, wave in waves.items():
        wave_groups.setdefault(str(wave), []).append(tid)
    return tasks, wave_groups


def _derive_waves(tasks: dict) -> dict[str, int]:
    """Topological wave assignment from depends_on.

    Wave 1 = no dependencies.
    Wave N = max(wave of all deps) + 1.
    """
    waves: dict[str, int] = {}

    def wave_of(tid: str) -> int:
        if tid in waves:
            return waves[tid]
        task = tasks.get(tid)
        if task is None:
            return 0
        deps = task.get("depends_on", []) or []
        if not deps:
            waves[tid] = 1
            return 1
        max_dep = max(wave_of(d) for d in deps)
        waves[tid] = max_dep + 1
        return waves[tid]

    for tid in tasks:
        wave_of(tid)
    return waves


# ---------------------------------------------------------------------------
# Self-test (TDD tracer bullet)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import shutil
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
