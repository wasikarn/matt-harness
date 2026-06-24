---
name: team-cleanup
description: "Clean up stale agent-team artifacts: old locks, dead heartbeats, orphaned board entries, archived completed plans. Use after a /team-build finishes, when the user says 'clean up the team', 'remove old plans', 'ล้างทีม', 'เคลียร์ทีม', 'ลบแผนทีม', or 'ทำความสะอาดทีม'. or when the user says 'ล้างทีม', 'เคลียร์ทีม', 'ลบแผนทีม'. Don't use for: active builds (use /wave-status first to verify completion), or plans you intend to resume (the archive is reversible for 30 days)."
argument-hint: Plan slug or --all
disable-model-invocation: true
disable-model-invocation-reason: destructive — deletes stale team locks/heartbeats/artifacts
---

# /team-cleanup — Clean up stale agent-team artifacts

You are a maintenance agent for the agent-teams workflow. This command reaps stale locks, heartbeats, orphaned board entries, archives completed plans, and removes empty plan directories. It operates on the file-based task board at `.claude/tasks/<slug>/`.

## Core principles

- **Dry-run first.** Unless the user explicitly omitted `--dry-run`, preview every cleanup action before executing it.
- **Never reap running work.** A heartbeat younger than 1 hour means the task is actively being worked on. Skip it.
- **Governance logs are evidence.** Every destructive action is journaled via `journal_append` (`hooks/_lib.sh`). A cleanup without a log entry is an invisible change.
- **Archive, don't delete.** Completed plans are moved to `.claude/tasks/archive/` with a date-stamped filename, not erased. The user can restore them for 30 days.

---

## Step 1 — Resolve scope

**Goal:** determine which plan(s) to clean.

**Arguments from `$ARGUMENTS`:**
- Positional argument: plan slug (e.g. `health-endpoint`)
- `--all`: clean every plan directory found in `.claude/tasks/`
- `--dry-run`: preview only; do not delete, move, or modify anything
- `--force`: required to delete the active plan `.md` file when archiving (without `--force`, the plan file is preserved even after board archival)

**Actions:**
1. Parse `$ARGUMENTS` into `TARGET_SLUG`, `ALL_MODE`, `DRY_RUN`, `FORCE`.
2. If `--all`:
   - Enumerate every directory in `~/.claude/tasks/` that contains a `board.json` or a `.md` plan file.
   - Build `PLAN_LIST` = all discovered slugs.
3. If a positional slug is provided:
   - Verify `~/.claude/tasks/<slug>/` exists (or `~/.claude/tasks/<slug>.md` exists).
   - If missing, fail loud: "Plan `<slug>` not found in `.claude/tasks/`."
   - Build `PLAN_LIST` = `[slug]`.
4. If no arguments provided (default):
   - List all plan directories in `~/.claude/tasks/` with their last-modified time.
   - If only one plan exists, auto-select it with an info message.
   - If multiple plans exist, present them to the user via `AskUserQuestion` single-select, OR auto-select the most recently modified plan and announce the choice.
5. **Dry-run notice:** If `DRY_RUN` is true, prefix every subsequent action with `[DRY-RUN]` and only simulate changes.

**Done-when Step 1:** `PLAN_LIST` contains one or more valid slugs to clean.

---

## Step 2 — Reap stale locks

**Goal:** remove expired mkdir-based locks for each target plan.

**Actions (per plan in `PLAN_LIST`):**
1. Run `bash "${KBG_PLUGIN_ROOT}/scripts/locks/lock-reap.sh" --team=<slug> [--dry-run]`.
   - If `DRY_RUN` is true, append `--dry-run` to the invocation.
   - Capture stdout (list of broken locks or "No stale locks found").
2. Log the result via `journal_append`:
   - Hook id: `team-cleanup`
   - Event: `lock_reap`
   - Fields: `{"slug":"<slug>","dry_run":<bool>,"reaped":<count>,"details":"<stdout>"}`
3. Record the count in a running summary table under the `Locks` column.

**Done-when Step 2:** all stale locks for the scoped plans have been reported and reaped (or previewed).

---

## Step 3 — Reap stale heartbeats

**Goal:** delete heartbeat files that are older than 24 hours or belong to already-completed tasks.

**Actions (per plan):**
1. Read `~/.claude/tasks/<slug>/heartbeat/*.json`.
   - If no heartbeat directory exists, record `0` and skip.
2. For each heartbeat file:
   - Parse `last_heartbeat` ISO timestamp.
   - Read the corresponding `board.json` to check the task's `status` for `current_task`.
   - **Delete condition:** heartbeat is older than 24 hours, OR the referenced task's `status == "completed"`.
   - **Skip condition:** heartbeat is younger than 1 hour AND the task is not completed (active work).
3. If `DRY_RUN` is true, list what would be deleted; do not remove files.
4. Log each batch via `journal_append`:
   - Event: `heartbeat_reap`
   - Fields: `{"slug":"<slug>","dry_run":<bool>,"reaped":<count>,"reason":"age_or_completed"}`
5. Record the count in the summary table under `Heartbeats`.

**Safety:** Never delete a heartbeat file younger than 1 hour unless its task is `completed`. This protects running agents.

**Done-when Step 3:** only fresh, in-progress heartbeats remain.

---

## Step 4 — Reset orphaned board entries

**Goal:** detect tasks stuck in `in_progress` with no recent heartbeat and reset them to `pending` so another agent can claim them.

**Actions (per plan):**
1. Acquire the board lock via `task_board_lib.py` (or `${KBG_PLUGIN_ROOT}/scripts/locks/lock-claim.sh` on the plan directory), or use atomic read/write discipline.
   - On lock failure, log a warning and skip this plan.
2. Read `board.json`.
3. For each task with `status == "in_progress"`:
   - Look for a heartbeat in `heartbeat/` whose `agent_id == task.claimed_by` and `current_task == task.id`.
   - Compute heartbeat age from `last_heartbeat`.
   - If the heartbeat is missing OR older than 1 hour:
     - Set `task["status"] = "pending"`.
     - Set `task["claimed_by"] = None`.
     - Set `task["claimed_at"] = None`.
     - Count this as one orphaned reset.
4. If any tasks were reset, write the updated `board.json` atomically (tempfile + rename).
   - If `DRY_RUN` is true, do not write; only list the tasks that would be reset.
5. Release the board lock if acquired.
6. Log via `journal_append`:
   - Event: `orphan_reset`
   - Fields: `{"slug":"<slug>","dry_run":<bool>,"reset_count":<count>,"task_ids":["..."]}`
7. Record the count in the summary table under `Orphaned`.

**Safety:** A missing heartbeat directory is treated as "no heartbeats" — all in-progress tasks without other evidence of life are orphaned.

**Done-when Step 4:** every in-progress task has a heartbeat younger than 1 hour, or has been reset to pending.

---

## Step 5 — Archive completed plans

**Goal:** move fully-completed `board.json` snapshots to the archive directory if completion is older than 7 days.

**Actions (per plan):**
1. Read `board.json`.
2. Check if ALL tasks have `status == "completed"`.
   - If not, skip to the next plan.
3. Find the most recent `completed_at` among all tasks.
   - If any task lacks `completed_at`, use `board["updated_at"]` as a fallback.
   - If the newest completion is younger than 7 days, skip.
4. If archival conditions are met:
   - Ensure `~/.claude/tasks/archive/` exists.
   - Construct archive filename: `<slug>-<YYYY-MM-DD>.json` (use current UTC date).
   - If `DRY_RUN` is true, preview the move; do not write.
   - Else, atomically move `board.json` to the archive path.
5. **Plan file deletion (only with `--force`):**
   - If `FORCE` is true AND the board was successfully archived, delete `~/.claude/tasks/<slug>.md`.
   - If `FORCE` is false, preserve the plan `.md` file even after board archival.
   - Log the decision: event `plan_file_kept` or `plan_file_deleted`.
6. Log via `journal_append`:
   - Event: `plan_archived`
   - Fields: `{"slug":"<slug>","dry_run":<bool>,"archive_path":"...","completed_at":"...","plan_file_deleted":<bool>}`
7. Record `Archived` in the summary table (count = 1 if archived, 0 if not).

**Done-when Step 5:** all fully-completed plans older than 7 days are archived, and the plan `.md` file is preserved unless `--force` was passed.

---

## Step 6 — Remove empty plan directories

**Goal:** delete directories in `~/.claude/tasks/` that have no `board.json` and no `.md` plan file.

**Actions:**
1. Enumerate every subdirectory in `~/.claude/tasks/` (excluding `archive/`).
2. For each directory `<slug>/`:
   - If `board.json` does not exist AND `<slug>.md` does not exist in the parent `tasks/` dir:
     - If the directory contains heartbeat files or lock artifacts, log them.
     - If `DRY_RUN` is true, preview removal.
     - Else, remove the directory recursively.
     - Count as one empty-dir removal.
3. Log via `journal_append`:
   - Event: `empty_dir_removed`
   - Fields: `{"slug":"<slug>","dry_run":<bool>,"removed":<bool>}`
4. Record the count in the summary table under `EmptyDirs`.

**Safety:** Never remove a directory that still contains a `board.json` or is paired with a `.md` plan file in the parent directory.

**Done-when Step 6:** only directories with plan artifacts remain.

---

## Step 7 — Confirmation gate (destructive mode only)

**Goal:** get explicit user approval before executing any destructive action when not in dry-run.

**Actions:**
1. If `DRY_RUN` is true, skip this step. Present the summary table from Step 8 and exit.
2. If `DRY_RUN` is false AND any destructive action is queued (locks to break, heartbeats to delete, orphans to reset, boards to archive, empty dirs to remove):
   - Present the summary table from Step 8.
   - Invoke `AskUserQuestion` single-select:
     - `Proceed with cleanup` — execute all queued actions
     - `Cancel` — abort without modifying anything; log event `cleanup_cancelled`
3. If the user selects `Cancel`, log via `journal_append`:
   - Event: `cleanup_cancelled`
   - Fields: `{"slugs":[...],"reason":"user_cancelled"}`
   - Print "Cleanup cancelled by user. No changes were made."
   - Exit.

**Done-when Step 7:** user has explicitly approved destructive actions, or dry-run preview is complete.

---

## Step 8 — Report summary

**Goal:** present a concise, machine-readable summary of everything that happened (or would happen).

**Actions:**
1. Build a markdown table:

   | Plan Slug | Locks Reaped | Heartbeats Reaped | Orphans Reset | Archived | Empty Dirs |
   |-----------|-------------:|------------------:|--------------:|---------:|-----------:|
   | `<slug>`  | 2            | 5                 | 1             | 0        | 0          |

2. Append a second table for archive details (if any):

   | Plan Slug | Archive Path | Plan File Kept |
   |-----------|--------------|----------------|
   | `<slug>`  | `...`        | Yes            |

3. If `DRY_RUN` is true, prefix the report header with `## [DRY-RUN] Preview`.
4. If any action failed (lock timeout, board read error, etc.), list failures in a separate `### Errors` section with the plan slug and error message.

**Done-when Step 8:** user has a complete, auditable summary of the cleanup run.

---

## Step 9 — Execute destructive actions (non-dry-run only)

**Goal:** perform the actual cleanup after user confirmation.

**Actions:**
1. If `DRY_RUN` is true, this step is already complete (preview only).
2. Replay Steps 2-6 with `DRY_RUN = false`, using the already-computed lists.
   - Re-run `lock-reap.sh` without `--dry-run`.
   - Delete the heartbeats identified in Step 3.
   - Write the orphaned resets from Step 4.
   - Move the archives from Step 5.
   - Remove empty directories from Step 6.
3. After execution, re-run Step 8 to present the final summary.
4. Log a final completion event via `journal_append`:
   - Event: `cleanup_complete`
   - Fields: `{"slugs":[...],"actions_total":<sum of all counts>}`

**Done-when Step 9:** all queued cleanup actions have been executed and the final summary is displayed.

---

## What this command does NOT do

- Does NOT stop running agents. If a task has a heartbeat younger than 1 hour, it is considered active and is never reset or deleted. **Graceful end-of-build teardown is `/team-build` Step 8's job, not cleanup's** — that step stops teammates once the build's done-when is met. Cleanup only reaps *stale artifacts* (expired locks, dead heartbeats, orphaned board entries) left behind after agents are already gone.
- Does NOT automatically delete plan `.md` files. The plan file is preserved after board archival unless `--force` is passed.
- Does NOT resume archived plans. To resume, move the archive JSON back to the plan directory and rename it to `board.json`.
- Does NOT clean the global `~/.claude/locks/` tree outside the scoped team. Only the plan's team context is touched.
- Does NOT modify the plan file content. It only moves or deletes the board JSON and the plan file as whole files.

---

## Cross-references

- **Task board library** — `${KBG_PLUGIN_ROOT}/scripts/task_board_lib.py` provides `board_read()`, `board_write()`, `heartbeat_read_all()`, `lock_acquire()`, `lock_release()`, and `recompute_blocked()`. Use it for atomic board mutations.
- **Lock reaper** — `"${KBG_PLUGIN_ROOT}/scripts/locks/lock-reap.sh"` breaks expired locks and logs via `journal_append`.
- **Governance journal** — `hooks/_lib.sh:journal_append` (and `hooks/_lib.py`) is the single emission point. Every destructive action in this command MUST log through it.
- **METHODOLOGY:** Rule 12 (fail loud) — missing plan, missing board, or lock timeout are surfaced as errors in the summary, not silently ignored. Rule 2 (simplicity first) — this command is a linear pipeline (2-6) with a single dry-run fork; no speculative abstraction layers.
