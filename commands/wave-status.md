---
name: wave-status
description: "Report real-time status of a multi-agent build: current wave, task progress, stale heartbeats, active locks, and ETA. Use during /team-build execution to check progress, or when the user asks 'where are we', 'status of the build', 'is the team done'. Don't use for: single-file work (use /status-update), or before a plan exists (use /team-plan first)."
argument-hint: "Plan slug (e.g. health-endpoint) or path to board.json"
---

# /wave-status — Multi-agent build status report

Read the task board for a plan and report real-time execution status: current wave, task progress, stale heartbeats, active locks, and ETA.

---

## Step 1 — Resolve plan directory / board.json

1. Parse `$ARGUMENTS`:
   - Extract the first positional argument as `target`
   - Detect `--json` flag anywhere in `$ARGUMENTS`
   - Detect `--watch` flag anywhere in `$ARGUMENTS`
2. Resolve the board path:
   - If `target` ends with `.json`: use it directly as `board_path`
   - Else if `target` is a directory containing `board.json`: use that `board.json`
   - Else if `target` is a slug: look for `~/.claude/tasks/<target>/board.json`
3. If no `target` was provided:
   - Scan `~/.claude/tasks/` for subdirectories containing `board.json`
   - If none found: tell the user "No active boards found in ~/.claude/tasks/. Run /team-plan then /team-build first."
   - Pick the plan directory with the most recent `mtime` on the directory itself
   - Tell the user: "No plan slug provided. Using <slug> (most recently modified). Pass a slug or path explicitly to override."
   - Set `board_path` accordingly
4. Verify `board_path` exists. If not, report the resolved path and stop.

---

## Step 2 — Read the board

Run a Python one-liner with `PYTHONPATH="${CLAUDE_PLUGIN_ROOT}"` to import `scripts.task_board_lib` and call `board_read(plan_dir)` where `plan_dir` is the directory containing `board.json`.

If `board_read` raises `FileNotFoundError` or `ValueError`, report the error verbatim and stop.

---

## Step 3 — Compute status report

Run the following analysis against the board payload. Write a small Python helper script under `.scratch/wave-status.py` (create `.scratch/` if needed) and execute it with `PYTHONPATH="${CLAUDE_PLUGIN_ROOT}"`. The script imports `scripts.task_board_lib` from the plugin root.

### 3a. Wave breakdown

```python
import json, os, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

# Add plugin root to path so task_board_lib can be imported
sys.path.insert(0, os.environ["CLAUDE_PLUGIN_ROOT"])
from scripts.task_board_lib import board_read, heartbeat_read_all

plan_dir = sys.argv[1]
board = board_read(plan_dir)

tasks = board.get("tasks", {})
waves = board.get("waves", {})

wave_stats = {}
for wave_num, task_ids in waves.items():
    wave_tasks = [tasks[tid] for tid in task_ids if tid in tasks]
    total = len(wave_tasks)
    completed = sum(1 for t in wave_tasks if t.get("status") == "completed")
    in_progress = sum(1 for t in wave_tasks if t.get("status") == "in_progress")
    blocked = [t for t in wave_tasks if t.get("status") == "blocked"]
    pending = sum(1 for t in wave_tasks if t.get("status") == "pending")
    blocked_reasons = []
    for t in blocked:
        reasons = t.get("blocked_by", [])
        if reasons:
            blocked_reasons.append(f"{t['id']}: blocked by {', '.join(reasons)}")
    wave_stats[wave_num] = {
        "total": total,
        "completed": completed,
        "in_progress": in_progress,
        "blocked_count": len(blocked),
        "blocked_reasons": blocked_reasons,
        "pending": pending,
    }
```

### 3b. Current wave

```python
current_wave = None
for wave_num in sorted(wave_stats.keys(), key=int):
    stats = wave_stats[wave_num]
    if stats["in_progress"] > 0:
        current_wave = wave_num
        break
    if stats["pending"] > 0:
        current_wave = wave_num
        break
if current_wave is None:
    current_wave = "Complete"
```

### 3c. ETA estimate

```python
total_tasks = len(tasks)
completed_tasks = [t for t in tasks.values() if t.get("status") == "completed"]
completed_count = len(completed_tasks)

avg_duration_seconds = None
if completed_count > 0:
    durations = []
    for t in completed_tasks:
        claimed = t.get("claimed_at")
        completed_at = t.get("completed_at")
        if claimed and completed_at:
            try:
                c_ts = datetime.fromisoformat(claimed.replace("Z", "+00:00"))
                d_ts = datetime.fromisoformat(completed_at.replace("Z", "+00:00"))
                durations.append((d_ts - c_ts).total_seconds())
            except (ValueError, TypeError):
                pass
    if durations:
        avg_duration_seconds = sum(durations) / len(durations)

remaining = total_tasks - completed_count
if avg_duration_seconds and remaining > 0:
    eta_seconds = int(remaining * avg_duration_seconds)
    eta_str = f"{eta_seconds // 3600}h{(eta_seconds % 3600) // 60}m"
elif remaining == 0:
    eta_str = "Done"
else:
    eta_str = "Unknown (no completed tasks with timestamps yet)"
```

### 3d. Stale heartbeats

```python
hbs = heartbeat_read_all(plan_dir)
stale = []
for hb in hbs:
    last = hb.get("last_heartbeat")
    if last:
        try:
            ts = datetime.fromisoformat(last.replace("Z", "+00:00"))
            if (datetime.now(timezone.utc) - ts) > timedelta(minutes=5):
                stale.append(hb)
        except (ValueError, TypeError):
            pass
```

### 3e. Active locks

```python
locks = []
locks_base = Path.home() / ".claude" / "locks"
if locks_base.exists():
    for lock_file in locks_base.rglob("lock.json"):
        try:
            data = json.loads(lock_file.read_text(encoding="utf-8"))
            # Include lock if its team directory matches plan slug or its resource_id matches a task ID
            team_dir = lock_file.parent.parent.name
            resource_id = data.get("resource_id", "")
            if team_dir == board.get("plan_slug") or resource_id in tasks:
                locks.append(data)
        except (json.JSONDecodeError, OSError):
            continue
```

### 3f. Validation results (optional)

```python
validation_results = board.get("validation_results")
validation_summary = None
if validation_results:
    if isinstance(validation_results, dict):
        passed = sum(1 for v in validation_results.values() if v.get("passed"))
        total_val = len(validation_results)
        validation_summary = f"{passed}/{total_val} passed"
    else:
        validation_summary = str(validation_results)
```

---

## Step 4 — Render output

### If `--json` was passed

Print the raw board JSON (from `board_read`) directly. Do not render the formatted report.

### Formatted report (default)

Print in this exact shape:

```
Plan: <plan_slug>
Current wave: <current_wave>

Wave breakdown:
  Wave <N>:
    Total: <total>
    Completed: <completed>
    In progress: <in_progress>
    Blocked: <blocked_count>
    Pending: <pending>
    <blocked_reasons, one per line, indented 4 spaces>

Stale heartbeats: <count>
  <agent_id> (<current_task>) — last heartbeat <age>

Active locks: <count>
  <resource_id> — owner: <owner>, reason: <reason>

ETA: <eta_str> (<completed_count>/<total_tasks> done)
```

If `validation_summary` is present, append:

```
Validation: <validation_summary>
```

If a section has zero items (e.g., no stale heartbeats, no active locks), print the header with `(none)` rather than omitting it entirely.

---

## Step 5 — Watch mode (`--watch`)

If `--watch` is passed:

1. Write the status-report script so it re-runs itself in a loop.
2. The loop must:
   - Print a clear separator (`--- refresh at <timestamp> ---`)
   - Re-read the board via `board_read`
   - Recompute and re-print the formatted report
   - Sleep 30 seconds
   - Repeat until interrupted
3. Wrap the loop in a `try/except KeyboardInterrupt` so Ctrl+C prints "Watch stopped." and exits 0.
4. Run the script with `PYTHONPATH="${CLAUDE_PLUGIN_ROOT}" python3 .scratch/wave-status.py <plan_dir>`.
5. If the runtime environment blocks `time.sleep`, print the report once and tell the user: "Watch mode unavailable in this runtime; re-run /wave-status manually for updates."

---

## Done-when

The command is complete when:

- [ ] Plan directory / `board.json` is resolved
- [ ] Board is read successfully via `task_board_lib.board_read`
- [ ] Formatted report (or raw JSON) is printed to the user
- [ ] Stale heartbeats older than 5 minutes are flagged
- [ ] Active locks are listed (or `(none)` if empty)
- [ ] ETA is computed from completed-task timestamps when data exists
- [ ] `validation_results` summary is included if present
- [ ] `--json` bypasses formatting and prints raw board JSON
- [ ] `--watch` refreshes every 30 seconds until interrupted

---

## Example output

```
Plan: health-endpoint
Current wave: 2

Wave breakdown:
  Wave 1:
    Total: 3
    Completed: 3 ✅
    In progress: 0
    Blocked: 0
    Pending: 0
  Wave 2:
    Total: 2
    Completed: 0
    In progress: 1 🔄
    Blocked: 1 ⏳
    Pending: 0
    API-1: blocked by DB-1
  Wave 3:
    Total: 1
    Completed: 0
    In progress: 0
    Blocked: 0
    Pending: 1

Stale heartbeats: 1
  agent-7 (API-1) — last heartbeat 8m12s

Active locks: 1
  DB-1 — owner: agent-3, reason: migration in progress

ETA: 42m (3/6 done)
```

---

## What this command does NOT do

- Does NOT modify the board, tasks, or locks. This is strictly read-only.
- Does NOT spawn agents or execute plan steps. That's `/team-build`.
- Does NOT validate the build or run acceptance criteria. That's `/team-build` Step 7.
- Does NOT create a plan. That's `/team-plan`.
- Does NOT fix stale heartbeats or release locks. It only reports them.

---

## Cross-references

- `${CLAUDE_PLUGIN_ROOT}/scripts/task_board_lib.py` — `board_read()`, `heartbeat_read_all()`, board schema
- `commands/team-build.md` — writes the board and heartbeats this command reads
- `commands/team-plan.md` — produces the plan file that seeds the board
- `${CLAUDE_PLUGIN_ROOT}/scripts/locks/lock-query.sh` — per-resource lock query (used here for broad scan fallback)
