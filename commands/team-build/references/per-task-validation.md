# Per-task validation chain (B → V1 → F → V2)

This is the detailed reference for the per-task quality pipeline that `/team-build` runs after each task in a wave completes. It was formerly the standalone `/validate-and-fix` command; it is now embedded as Step 6b of `/team-build`.

## When this runs

`/team-build` Step 6 spawns builder agents in waves. After each task claims `completed`, the lead immediately runs the chain below **before starting the next wave**. If a task fails V2, the lead does NOT start downstream tasks that depend on it.

## Roles

- **B** — builder (already spawned in Step 6).
- **V1** — `code-reviewer` (read-only; ungated).
- **F** — fixer agent, write-capable (gated by user approval when V1 rejects).
- **V2** — `code-reviewer` or `security-reviewer` (read-only; ungated).

## Step-by-step

### V1 — Primary validation

Spawn `code-reviewer` with the F9 prompt:

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

**Verdict handling:**
- `pass`: task stays `completed`; record V1 result; continue.
- `minor`: task stays `completed`; record V1 result; log warnings; continue.
- `reject`: task moves to `in_review`; record V1 result; proceed to Fix.

Unparseable verdicts are treated as `reject`.

### F — Fix (user-gated)

If V1 rejects, the lead surfaces `AskUserQuestion`:

- `Spawn fixer agent to address findings (Recommended)`
- `Skip fix and mark as completed anyway`
- `Reject — discard the implementation and restart`

**Spawn fixer:**
- Role = `task["assigned_role"]` or `backend-engineer`.
- Model = `sonnet`; upgrade to `opus` only for auth/secrets/crypto findings.
- Sub-task record: `{"id":"<task-id>-fix-1","type":"fix","status":"in_progress","trigger":"V1 reject","findings_count":N}` appended to `task["sub_tasks"]`.
- F9 prompt:

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
- From V1 review: <list of findings verbatim>

## Files + Criteria + Constraints
| File                  | Criterion                                     | Constraint                |
|-----------------------|-----------------------------------------------|---------------------------|
| <path>                | <task["criteria"]>                            | <task["constraints"]>     |

## Done-when
- [ ] Every V1 finding is either (a) fixed with file:line evidence, or (b) declined with documented reason
- [ ] The task's validation command (if any) exits 0
- [ ] No edit outside FILES YOU OWN
```

**Skip fix:** mark `completed` with override reason; continue.

**Reject:** reset task to `pending`, clear `claimed_by`, `claimed_at`, `completed_at`, `validation_results`, `sub_tasks`; do not continue downstream dependents until the wave is re-run.

### V2 — Re-validation

Reviewer selection:
- If any file matches auth/secrets/crypto patterns: `security-reviewer`.
- Else: `code-reviewer`.

F9 prompt:

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

**Verdict handling:**
- `pass` / `minor`: task `completed`; merge V2 into `validation_results`; continue.
- `reject`: task `rejected`; merge V2 results; surface `AskUserQuestion`:
  - `Loop — spawn another fixer and re-validate (Recommended)`
  - `Accept risk — mark completed despite V2 reject`
  - `Abort — reset task to pending`

## Board locking

All board reads/writes use `${KBG_PLUGIN_ROOT}/scripts/task_board_lib.py` (`lock_acquire`, `board_read`, `board_write`, `lock_release`). The lock is held from V1 through the end of the chain; released on all paths via `try/finally`.

## Sub-task record shape

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

## What this chain does NOT do

- It does NOT replace the wave-level or project-level validation in `/team-build` Step 7.
- It does NOT auto-merge or ship.
- It does NOT silently override a reject; user direction is required.
