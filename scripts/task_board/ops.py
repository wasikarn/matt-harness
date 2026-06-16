"""
scripts/_task_board_ops.py — Board operations (private module).

Owns: recompute_blocked, heartbeat_write, heartbeat_read_all, claim_task.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from .io import HEARTBEAT_DIRNAME, _utcnow_iso


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
        t for t, task in tasks.items()
        if task.get("status") == "completed"
    }

    for _, task in tasks.items():
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
    if any(t.get("status") == "in_progress" for t in tasks.values()):
        board["status"] = "in_progress"
    elif any(t.get("status") in ("pending", "blocked") for t in tasks.values()):
        board["status"] = "pending"
    else:
        board["status"] = "completed"

    # Derive current_wave from unblocked / in-progress tasks
    current_wave = None
    for _, task in sorted(tasks.items()):
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
