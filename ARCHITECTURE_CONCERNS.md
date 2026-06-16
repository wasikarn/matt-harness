# Architecture Concerns — Task Board Integration (hooks/task-lifecycle.sh)

Scope: backend-side data-integrity and contract stability for the new task-board
runtime layer (`.claude/tasks/<slug>/board.json` + `heartbeat/` + `.lock/`).

## 1. Atomicity & Locking

- **Mechanism**: `mkdir`-based directory lock (atomic on Linux/macOS/WSL).  
- **Trap hazard**: `trap 'rmdir "$lock_dir" ...' EXIT` in a `local`-scoped variable
  causes unbound-variable failure under `set -u` when the trap fires after the
  function returns.  
  → **Fix applied**: expand the path at trap-set time via `printf '%q'` and embed
  the escaped literal into the trap string.
- **Timeout**: default 10 s; overridable by callers.  Long-running board ops must
  stay under this threshold or the lock is lost and concurrent writes race.
- **Write atomicity**: `tmp.$$` + `mv`.  Crash after `printf` but before `mv` leaves
  a temp file; it is harmless and idempotent on retry.

## 2. Board Schema Contract & Backward Compatibility

- **Embedding convention**: `plan_slug:` and `task_id:` are parsed from the task
  description text (same style as `validation_command:`).  Missing fields mean
  *no board update* — the hook falls back to plain logging.  This preserves all
  204 pre-existing tests that know nothing about the board.
- **Status transitions**:
  - `TaskCreated`  → `in_progress` (only from `pending`; idempotent if already claimed)
  - `TaskCompleted` → `completed` + `completed_at` + recompute `blocked_by`
- **Idempotency**: repeated `TaskCreated` with the same `task_id` does not
  overwrite `claimed_at` or reset status; it is a no-op.
- **Schema version**: `board.json` carries `"schema_version": 1`.  Future schema
  bumps must gate reads/writes by version or migrate atomically under lock.

## 3. `blocked_by` Recomputation (TaskCompleted)

- `kbg_recompute_blocked` is called *after* the task is marked completed.  It scans
  every non-completed task’s `depends_on` array and rebuilds `blocked_by` from the
  set of tasks whose status is **not** `"completed"`.
- **Race window**: if two tasks complete concurrently, both recompute passes may
  write the same result, but because the board is updated under lock the second
  write is serialised and safe.
- **Performance**: O(n) over the task map; acceptable until the board holds
  hundreds of tasks.  If boards grow larger, switch to incremental recomputation
  or move `blocked_by` derivation into read-time.

## 4. Heartbeat Staleness (TeammateIdle)

- **Trigger**: stale heartbeat (> 5 min old) AND at least one pending unblocked task.
- **Time source**: `datetime.fromisoformat` via a Python one-liner.  This handles
  ISO-8601 with or without trailing `Z` (the Python helper normalises `+00:00` to
  `Z`).
- **Backward compat**: if neither `plan_slug` nor `cwd` is present in the event,
  the handler exits 0 immediately.  No false positives for legacy environments.
- **Filesystem scan**: `ls .claude/tasks/*/heartbeat/*.json`.  Empty heartbeat
  dirs or missing dirs are skipped silently.

## 5. Lock Release & Auto-Cleanup

- `scripts/locks/lock-release.sh` is called from `TaskCompleted` only when the task has
  a non-empty `files` array.  It brute-force `rmdir`s the `.lock` directory.
- **Why not `trap` alone?** `trap EXIT` already auto-releases the lock when the
  hook process exits, but the hook is a *separate* process from the task runner.
  If the runner itself crashed while holding the lock, `lock-release.sh` is the
  manual (or cron-driven) cleanup path.

## 6. JSON Parsing Failures (Silent Skips)

- `jq` is used for all board reads.  If `board.json` is corrupted, `kbg_board_read`
  prints to stderr and returns 1; the caller skips the update.  This is
  intentional — a corrupt board must not block the hook’s primary duty
  (event logging).
- **Test pitfall**: `printf '...\n...'` without a `%s` format causes `printf` to
  interpret `\n` as real newlines, producing *invalid JSON* that `jq` rejects.
  All board-integration tests were fixed to use `printf '%s' '...'`.

## 7. Rollback Considerations

- The integration is additive: no old columns/files are removed.
- To disable board integration temporarily, remove `task_board_lib.sh` or break
  the `PLAN_DIR` path.  The hook degrades to plain logging without crashing.
- No database migration is involved; the board is a JSON file in the workspace.

---
*Evidence: 209 tests pass (204 pre-existing + 5 board-integration), `bash -n` clean.*
