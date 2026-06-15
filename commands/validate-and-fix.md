---
name: validate-and-fix
type: command
description: "Run the builder-validator-fix-revalidator quality chain on a single completed task. Use after a teammate claims a task is done but you want independent validation before merging. Don't use for: pre-execution plan validation (use /team-build's F10 gate), post-build whole-project validation (use /pre-ship-verify), or tasks without a plan file (use /feature-dev for single-file work)."
argument-hint: "Task ID (e.g. API-1) and optional plan slug"
disable-model-invocation: true
---

# /validate-and-fix — Builder-validator chain for a single task

You are running the per-task quality pipeline `B → V1 → F → V2` (builder → validator → fix → re-validator) from `skills/orchestrate/SKILL.md` § Validation chain, applied to **one** task that a builder agent has already claimed complete. This is the manual invocation of the F7 TaskCompleted gate at single-task granularity — distinct from `/team-build`'s wave-level F7 gate and from `/pre-ship-verify`'s project-wide acceptance contract.

The command takes a task ID and an optional plan slug. If the plan slug is omitted, search `.claude/tasks/*/board.json` for the task ID. If exactly one match exists, use it; if zero or multiple, refuse and ask the user to provide the plan slug.

---

## Step 1 — Read the task from the board

**Goal:** locate the task, verify it's in a validateable state, and gather the artifacts the reviewer needs.

**Actions:**
1. **Resolve `plan_dir`:**
   - If `plan-slug` provided: `plan_dir = .claude/tasks/<plan-slug>/`
   - Else: scan `.claude/tasks/*/board.json` for `tasks[<task-id>]`. If exactly one board contains the task, use its directory. Otherwise refuse: `"Task <task-id> found in N plans; pass plan-slug to disambiguate."`
2. **Acquire lock:**
   ```python
   from scripts.task_board_lib import lock_acquire, board_read
   lock_acquire(plan_dir, timeout=10)
   ```
   If lock fails, refuse — another process is mutating the board.
3. **Read board:** `board = board_read(plan_dir)`
4. **Verify task exists:** `task = board["tasks"].get(<task-id>)`. If missing, release lock and refuse.
5. **Verify task status** is `completed` or `in_progress`. If `pending` or `blocked`, release lock and refuse: `"Task <task-id> is <status>; validation requires completed or in_progress."`
   - If status is `in_progress`, warn: `"Task is still in_progress; validating incomplete work may yield false rejects."` but continue.
6. **Read `task["files"]`**. If empty, warn: `"Task has no files field — reviewer will have no ownership boundary."`
7. **Read the plan file** (`board["plan_file"]`) to extract:
   - The task's acceptance criteria (from `task["criteria"]` — already on the board)
   - The task's `validation_command` from the plan's `## Validation Commands` section if the plan maps commands to task IDs; otherwise use `task["criteria"]` as the observable check.
8. **Do NOT release the lock yet** — board mutations happen in Steps 2, 3, and 4. Use try/finally to ensure release on all exit paths.

---

## Step 2 — Primary validation (V1, ungated)

**Goal:** independent review of the builder's output. The reviewer is read-only (`code-reviewer`); no `AskUserQuestion` gate required.

**Actions:**
1. Build the F9 spawn prompt for `code-reviewer`:

   ```
   # Task: Validate <task-id> implementation

   ## What
   Review the files modified by task <task-id> for correctness, criterion satisfaction, and minimal blast radius.

   ## Where
   <absolute paths from task["files"]>

   ## Focus
   Correctness over speed. Flag any behavior that violates the acceptance criteria or introduces regressions.

   ## Deliverable
   A structured verdict report with:
   - verdict: one of {pass, minor, reject}
   - findings: list of file:line citations with severity (P0/P1/P2) and explanation
   - criteria_check: whether each acceptance criterion is satisfied

   ## FILES YOU OWN (read-only)
   - <absolute path 1>
   - <absolute path 2>
   (Only these files. Do not review out-of-scope files.)

   ## UPSTREAM CONTRACTS
   (Empty — this is a single-task validation.)

   ## Files + Criteria + Constraints
   | File                  | Criterion                                     | Constraint                |
   |-----------------------|-----------------------------------------------|---------------------------|
   | <path>                | <task["criteria"]>                            | <task["constraints"]>     |

   ## Done-when
   - [ ] Verdict is exactly one of: pass, minor, reject
   - [ ] Every finding includes a file:line citation
   - [ ] criteria_check references the specific criterion text from the plan
   ```

2. Spawn `code-reviewer` with `model: "sonnet"` (review is read-only; Opus is unnecessary).
3. Wait for completion. Parse the verdict from the reviewer's output.
4. If the reviewer returns an **unparseable verdict** (missing verdict field, or value not in {pass, minor, reject}), treat as `reject` and include the raw output in `findings`.

**Verdict handling + board update:**
- **`pass`**: update `task["status"] = "completed"`, write `validation_results = {"V1": {"verdict":"pass", "agent_id":"...", "completed_at":"...", "findings":[]}}`, write board, release lock, DONE.
- **`minor`**: update `task["status"] = "completed"`, write `validation_results = {"V1": {"verdict":"minor", "agent_id":"...", "completed_at":"...", "findings":[...]}}`, write board, release lock, log warnings to user, DONE.
- **`reject`**: update `task["status"] = "in_review"`, write `validation_results = {"V1": {"verdict":"reject", "agent_id":"...", "completed_at":"...", "findings":[...]}}`, write board (keep lock held), proceed to Step 3.

---

## Step 3 — Fix (F, gated)

**Goal:** present V1's findings to the user and get explicit direction.

**Actions:**
1. Summarize V1 findings by severity (P0 = load-bearing doctrine / public API; P1 = internal API; P2 = internal-only), with file:line citations.
2. Surface `AskUserQuestion`:

   - `Spawn fixer agent to address findings (Recommended)` — a write-capable agent will apply fixes
   - `Skip fix and mark as completed anyway` — accept the risk; override the reject
   - `Reject — discard the implementation and restart` — task goes back to builder pool

3. **If user chooses "Spawn fixer":**
   - Determine fixer role: use `task["assigned_role"]` if present (e.g. `backend-engineer`, `frontend-engineer`, `technical-writer`); default to `backend-engineer`.
   - Determine fixer model: `sonnet` by default; upgrade to `opus` only if the task touches auth/secrets/crypto or the findings include security-critical issues.
   - Update board:
     - `task["status"] = "in_progress"`
     - Append a sub-task record to `task["sub_tasks"]` (create the list if absent):
       ```json
       {
         "id": "<task-id>-fix-1",
         "type": "fix",
         "agent_id": "<fixer-agent-id>",
         "spawned_at": "<ISO-8601>",
         "status": "in_progress",
         "trigger": "V1 reject",
         "findings_count": N
       }
       ```
   - Build the F9 spawn prompt for the fixer:

     ```
     # Task: Fix <task-id> validation findings

     ## What
     Apply the exact fixes requested by the V1 code-reviewer for task <task-id>.

     ## Where
     <absolute paths from task["files"]>

     ## Focus
     Minimal blast radius — only change what the reviewer flagged. Do not refactor unrelated code.

     ## Deliverable
     The modified files pass the original acceptance criteria and the V1 reviewer's findings are resolved.

     ## FILES YOU OWN
     - <absolute path 1>
     - <absolute path 2>
     (Only files in this list. Anything else is out of scope — defer to the orchestrator.)

     ## UPSTREAM CONTRACTS
     - From V1 review: <list of findings verbatim> — each must be addressed or explicitly declined with reason

     ## Files + Criteria + Constraints
     | File                  | Criterion                                     | Constraint                |
     |-----------------------|-----------------------------------------------|---------------------------|
     | <path>                | <task["criteria"]>                            | <task["constraints"]>     |

     ## Done-when
     - [ ] Every V1 finding is either (a) fixed with file:line evidence, or (b) declined with documented reason
     - [ ] The task's validation command (if any) exits 0
     - [ ] No edit outside FILES YOU OWN
     ```

   - Spawn the fixer. Wait for completion.
   - Update the sub-task record: `status = "completed"`, `completed_at = <now>`.
   - Write board (keep lock held). Proceed to Step 4.

4. **If user chooses "Skip fix":**
   - Update board: `task["status"] = "completed"`, append `{"override": true, "reason": "user skipped V1 reject"}` to `validation_results`.
   - Write board, release lock, DONE.

5. **If user chooses "Reject":**
   - Update board: `task["status"] = "pending"`, `task["claimed_by"] = None`, `task["claimed_at"] = None`, `task["completed_at"] = None`, clear `validation_results`, clear `sub_tasks`.
   - Write board, release lock, report: `"Task <task-id> reset to pending. Re-dispatch with /team-build or /feature-dev."`

---

## Step 4 — Re-validation (V2, ungated)

**Goal:** verify the fixer's changes resolved the V1 findings and introduced no new issues.

**Actions:**
1. **Determine reviewer type:**
   - If any file in `task["files"]` matches auth/secrets/crypto patterns (heuristic: path contains `auth`, `secret`, `token`, `password`, `crypto`, `acl`, `rbac`, `oauth`, `jwt`, `mfa`, `credential`, `vault`, `kms`): spawn `security-reviewer`.
   - Else: spawn `code-reviewer`.

2. Build the F9 spawn prompt for V2:

   ```
   # Task: Re-validate <task-id> after fix

   ## What
   Review the post-fix state of task <task-id>. Confirm the V1 findings are resolved and no new issues were introduced.

   ## Where
   <absolute paths from task["files"]>

   ## Focus
   Regression prevention — the fix must resolve the findings without side effects.

   ## Deliverable
   A structured verdict report with:
   - verdict: one of {pass, minor, reject}
   - v1_findings_status: for each V1 finding, "resolved" or "still_open" with file:line
   - new_issues: list of any new file:line citations (empty if none)

   ## FILES YOU OWN (read-only)
   - <absolute path 1>
   - <absolute path 2>

   ## UPSTREAM CONTRACTS
   - From V1 review: <original findings>
   - From fixer <task-id>-fix-1: <summary of changes applied>

   ## Files + Criteria + Constraints
   | File                  | Criterion                                     | Constraint                |
   |-----------------------|-----------------------------------------------|---------------------------|
   | <path>                | <task["criteria"]>                            | <task["constraints"]>     |

   ## Done-when
   - [ ] Verdict is exactly one of: pass, minor, reject
   - [ ] v1_findings_status accounts for every original V1 finding
   - [ ] No new P0 issues introduced
   ```

3. Spawn reviewer with `model: "sonnet"`.
4. Wait for completion. Parse verdict. Unparseable verdicts are treated as `reject`.

**Verdict handling + board update:**
- **`pass`**: update `task["status"] = "completed"`, merge V2 results into `validation_results` (`{"V2": {"verdict":"pass", "agent_id":"...", "completed_at":"...", "findings":[], "v1_findings_status":[...]}}`), write board, release lock, DONE.
- **`minor`**: update `task["status"] = "completed"`, merge V2 results, write board, release lock, log warnings, DONE.
- **`reject`**: update `task["status"] = "rejected"`, merge V2 results into `validation_results`, write board, release lock. Present to user:

   `AskUserQuestion`:
   - `Loop — spawn another fixer and re-validate (Recommended)`
   - `Accept risk — mark completed despite V2 reject`
   - `Abort — reset task to pending`

   - **"Loop"**: return to Step 3 with V2 findings as the new input (bump fix sub-task counter to `<task-id>-fix-2`, etc.).
   - **"Accept risk"**: mark `task["status"] = "completed"`, append `{"override": true, "reason": "user accepted V2 reject"}` to `validation_results`, write board, release lock, DONE.
   - **"Abort"**: reset to `pending` as in Step 3 option 3.

---

## Board update semantics

The board is the single source of truth. Mutations are atomic via `board_write`. Locking prevents races with `/team-build` or other `/validate-and-fix` invocations.

| Step | `task["status"]` | `task["validation_results"]` | Lock |
|------|------------------|------------------------------|------|
| After Step 1 (load) | unchanged | unchanged | held |
| After Step 2 (V1 pass) | `completed` | `{"V1": {"verdict":"pass",...}}` | released |
| After Step 2 (V1 minor) | `completed` | `{"V1": {"verdict":"minor",...}}` | released |
| After Step 2 (V1 reject) | `in_review` | `{"V1": {"verdict":"reject",...}}` | held → Step 3 |
| After Step 3 (fixer spawned) | `in_progress` | V1 results + fix sub-task record | held → Step 4 |
| After Step 3 (skip) | `completed` | V1 results + `{"override":true}` | released |
| After Step 3 (abort) | `pending` | cleared | released |
| After Step 4 (V2 pass) | `completed` | merged V1 + V2 | released |
| After Step 4 (V2 minor) | `completed` | merged V1 + V2 | released |
| After Step 4 (V2 reject → loop) | `rejected` | merged V1 + V2 | released; user must re-invoke |

**Sub-task record shape** (stored in `task["sub_tasks"]`):
```json
{
  "id": "<task-id>-fix-1",
  "type": "fix",
  "agent_id": "<fixer-agent-id>",
  "spawned_at": "2026-06-12T10:00:00Z",
  "completed_at": "2026-06-12T10:15:00Z",
  "status": "completed",
  "trigger": "V1 reject",
  "findings_count": 3
}
```

---

## F8.5 bounded fan-out

This command processes **one task at a time**. If the user passes multiple task IDs (e.g., `/validate-and-fix API-1 API-2`), process them **sequentially**, not in parallel. Each task's Step 3 (Fix) may require user interaction, and Step 4 depends on Step 3's output. The validation chain is inherently sequential.

The hard cap of 16 agents per wave from `skills/orchestrate/SKILL.md` does not apply directly because this command spawns at most 2 reviewers + 1 fixer per task. Still, do not spawn the V1 reviews for multiple tasks simultaneously; finish one chain before starting the next.

---

## Done-when

The `/validate-and-fix` invocation is complete when:

- [ ] Task located and board lock acquired
- [ ] V1 reviewer spawned, completed, and verdict parsed
- [ ] Board updated after V1 (pass, minor, or in_review)
- [ ] If V1 rejected: user direction obtained (fix / skip / abort)
- [ ] If fixer spawned: fixer completed, board updated to `in_progress`, sub-task recorded
- [ ] V2 reviewer spawned, completed, and verdict parsed
- [ ] Board updated after V2 with final `validation_results`
- [ ] Lock released in **all** code paths (including errors and refusals)
- [ ] User informed of final status with file:line evidence

---

## What this command does NOT do

- Does NOT plan or build. The task must already be implemented by a builder agent.
- Does NOT skip the user gate on `reject`. A reject without user direction is a hard stop.
- Does NOT silently override a reject. The user must explicitly choose "Skip fix" or "Accept risk".
- Does NOT validate the whole plan. Use `/pre-ship-verify` for project-wide acceptance contracts.
- Does NOT validate pre-execution plan quality. Use `/team-build`'s F10 gate for that.
- Does NOT auto-merge or ship. This is a quality gate, not a ship gate.

---

## Cross-references

- **Validation chain `B → V1 → F → V2`** — `skills/orchestrate/SKILL.md` § Validation chain. The DAG pattern, `addBlockedBy` ordering, and 4-step merge after parallel fan-in.
- **F9 spawn-prompt template** — `skills/orchestrate/SKILL.md` § Spawn-prompt template. Used verbatim for V1, fixer, and V2 prompts.
- **F8 lead doctrine** — `skills/orchestrate/SKILL.md` § Lead-coordinator doctrine. The lead dispatches reviewers; teammates do the reviewing.
- **F8.5 bounded fan-out** — `skills/orchestrate/SKILL.md` § Bounded fan-out. This command's sequential nature is the single-task version of that cap.
- **F7 TaskCompleted gate** — `hooks/task-lifecycle.sh` and `/team-build` Step 7. `/validate-and-fix` is the per-task manual invocation of the same quality gate.
- **Task board I/O** — `scripts/task_board_lib.py`. `board_read`, `board_write`, `lock_acquire`, `lock_release`.
- **METHODOLOGY:** Rule 4 (goal-driven) — every reviewer gets exact criteria, not a topic. Rule 12 (fail loud) — reject stops and asks; no silent override. Rule 13 (orchestrate) — the chain is `addBlockedBy` in the runtime, not advisory.
