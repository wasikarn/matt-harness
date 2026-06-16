"""
scripts/_task_board_io.py — Board I/O primitives (private module).

Owns: constants, _utcnow_iso, _is_under_cwd, _parse_plan_table,
      _derive_waves, board_init, board_read, board_write.
"""

from __future__ import annotations

import json
import os
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
        if in_section and line.strip().startswith("|") and "Task ID" in line:
            if i + 1 < len(lines) and "|---" in lines[i + 1]:
                header_line_idx = i
                separator_idx = i + 1
                break
            continue

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

        if task_id in tasks:
            raise ValueError(f"Duplicate task ID in plan: {task_id}")
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
    # Import here to avoid circular import (_task_board_ops imports from here)
    from .ops import recompute_blocked

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
