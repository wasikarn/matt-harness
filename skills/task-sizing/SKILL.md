---
name: task-sizing
description: "Right-size /team-plan tasks before /team-build: the 5-6-tasks-per-agent rule, wave balancing, splitting oversized tasks, merging undersized ones — so a team finishes faster with fewer merge conflicts. Use when reviewing a plan's task granularity, or the user asks how big a task or wave should be. Also fires on Thai sizing requests like 'task sizing', 'แบ่ง task', 'ขนาด task', 'ย่อย task'. Don't use for: authoring the plan (use /team-plan), runtime dispatch (use kbg:orchestrate), or single-agent work (use /feature-dev)."
---

# Task Sizing

> **Subagent self-check:** If you were dispatched as a sub-agent for a specific task, **do not re-orchestrate.** Return your scoped output (a `done-when` artifact, a `Report:` block, or your done-criterion evidence) to the parent. The parent owns the prioritization + dispatch loop; you own one well-bounded deliverable.

Size and shape tasks so that a team of agents finishes faster, with fewer merge conflicts and less wasted context. This skill is the planning-phase counterpart to `orchestrate` (runtime dispatch) and `team-plan` (plan authoring).

## Input Contract

- **Needs:** a `/team-plan` artifact (`.claude/tasks/<slug>.md`) or a user request to size a proposed plan. The skill operates on the `## Step by Step Tasks` table.
- **When the plan is missing:** ask the user to run `/team-plan` first, or provide the task list directly.
- **Defaults:** assume the plan uses the standard table columns (`Task ID`, `Description`, `Depends On`, `Assigned To`, `Files`, `Criteria`).

## The 5-6 rule

Per article `agent-teams-best-practices`, **5-6 tasks per agent is the sweet spot.**

- **< 3 tasks** = under-utilization. The agent burns context-setup tokens for marginal work. Merge the crumbs into one coherent task or assign the agent additional scope.
- **> 8 tasks** = context thrashing. The agent switches too often, loses track of file state, and reports progress in low-value increments.
- **The rule is per-agent, not per-plan.** A plan with 4 agents and 24 tasks is fine (6 each). A plan with 2 agents and 20 tasks is not (10 each — split into two waves or add agents).

## Task size heuristics

| Dimension | Too small | Too big | Just right |
|-----------|-----------|---------|------------|
| **Description** | < 30 chars, or "just run X" (use a command instead) | Vague novel ("implement auth system") | 1 concrete sentence: "Add POST /users with email validation" |
| **Files touched** | No files assigned (pure coordination / pure research) | > 3 files owned by one task | 1-2 files, clearly named |
| **Acceptance criteria** | None listed | > 2 criteria (creeping scope) | 1-2 criteria, each machine-checkable |
| **Dependencies** | 0 (island task — merge with a sibling) | > 2 upstream tasks (serial bottleneck) | 1 dependency max |
| **Time estimate** | < 15 min (use inline or a command) | > 4 hours (no natural check-in) | 2-4 hours |

**Anti-patterns:**
- "Update docs after X" as a standalone task → merge into X.
- "Fix lint" as a standalone task → merge into the task that introduced the lint.
- A task with no files and no criteria → drop or merge; it is not verifiable.

## Splitting oversized tasks

When a task violates the "too big" column above, split it before `/team-build`. Three proven patterns:

1. **Interface-first split.** Extract the API contract, type definition, or database schema as its own task. This becomes Wave 1; implementation tasks depend on it. This prevents the "types agent and API agent disagree on `UserSettings` shape" failure from article `task-distribution`.
2. **Layer split.** Decompose backend → frontend → integration → tests. Each layer is one task. The backend task exports the contract; the frontend task consumes it via `UPSTREAM CONTRACTS` (F9 template in `skills/orchestrate/SKILL.md`).
3. **File split.** When files are independent (e.g., `src/api/users.py` and `src/api/billing.py`), assign one file per task. Never split a single file across two agents — that causes silent overwrites.

## Merging undersized tasks

1. **Same file + same owner.** If two tasks touch `src/components/Dashboard.tsx` and both are assigned to `frontend-engineer`, merge them into one task with combined criteria.
2. **Update docs after X.** Documentation that depends on X's deliverable belongs in X's task. The acceptance criterion becomes: "Feature works AND `README.md` section Y is updated."
3. **No files + no criteria.** Drop the task. If it is pure coordination ("tell the API agent to start"), that is the lead's job, not a task board entry.

## Wave balancing

A `/team-build` plan is executed in waves: all Wave 1 tasks run in parallel, then Wave 2, etc.

| Wave | Purpose | Task count |
|------|---------|------------|
| **Wave 1** | Foundational setup — schemas, types, contracts, migrations | 3-5 tasks |
| **Wave 2+** | Implementation layers that consume Wave 1 contracts | 2-4 tasks each |
| **Final wave** | Integration validators + end-to-end checks (INT-N) | 1-3 tasks |

**Total waves for a feature: 3-5.** More than 5 waves means the plan is too coarse-grained; merge waves or enlarge task scope. Fewer than 3 waves means the feature is small enough for `/feature-dev` (single-agent).

**Wave bands vs. the F8 min-3 floor (different axes — they do not conflict).** The task counts above are the width of an *auto-resolved* wave: a property of the dependency graph, which legitimately narrows as a feature integrates (the 7-agent pattern's later waves are often a single task — that is correct, not under-parallelized). The F8 "min 3 / max 5" band is a *different* axis — how many teammates a lead *chooses* to fan out into one explicit `type: parallel` stage. A later wave with 2 ready tasks is the DAG narrowing, never flagged. The dispatcher's F8.4 advisory fires only on an explicit `parallel` agent fan-out below 3 (`scripts/orchestrate/planner.py` `f8_4_under_warnings`), never on auto-resolved wave width; a fixed diverse-lens panel (e.g. code-review + security-review = 2 by design) opts out with `panel: true`.

**F8.5 hard cap:** If any wave has >5 tasks, split the wave or merge tasks. A prompt asking for "N items" is not a cap — the LLM overshoots; clamp in code, not in prose. See `skills/orchestrate/SKILL.md` § Bounded fan-out (audit-2026-06-12 overshoot anecdote there).

## Output Format

This skill produces **revised task tables** (or a verbal sizing verdict) and optionally emits the embedded self-check script's report. The output is planning guidance, not code.

- **Verbal verdict:** "Split task API-1 into API-1a (contract) and API-1b (implementation). Merge V-1 and INT-1."
- **Self-check report:** a terminal table of stats + wave counts + agent load + flag count.
- **Revised plan file:** the updated `## Step by Step Tasks` table, rewritten to disk only if the user confirms.

## Self-check script

Run the bundled self-check against a plan file to catch sizing violations before `/team-build`:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/task_size_check.py" .claude/tasks/<slug>.md
```

Exit codes: `0` = all tasks within bounds · `1` = plan file malformed or missing the `## Step by Step Tasks` table · `2` = one or more sizing flags found. The script prints per-wave counts, per-agent load, and a flagged-task list; thresholds mirror the heuristics above (see `scripts/task_size_check.py`).

## Failure Modes to Avoid

1. **Splitting by function instead of by file.** "Agent A writes the first half of `src/api/users.py`, agent B writes the second half" → silent overwrite. The boundary is file-level, never function-level.
2. **Forgetting the interface-first task.** If Wave 1 has no contract/schema task, parallel agents in Wave 2 will invent incompatible shapes. Always extract the shared interface as Wave 1.
3. **Treating "validation" as a single task.** One validator per component is the minimum. For cross-component features, add an integration validator (INT-N) that blocks on ALL builders.
4. **Ignoring the F8.5 hard cap at planning time.** A prompt asking for "20-35 items" is not a cap. If the plan has >5 tasks in any wave, split the wave or merge tasks before `/team-build` dispatches.
5. **Verbal estimates without observable done-whens.** "Make the code work" is not a criterion. Every task must have an observable check a reviewer can run.

## Cross-references

- `skills/orchestrate/SKILL.md` § F8.5 (bounded fan-out hard cap) and F9 spawn-prompt template (file ownership + upstream contracts).
- `commands/team-plan.md` — plan artifact format with `## Step by Step Tasks` table that the self-check script consumes.
- `commands/team-build.md` — wave execution and validation chain.
- Article `agent-teams-best-practices` (claudefa.st) — empirical 5-6 tasks/agent sweet spot.
- Article `task-distribution` (claudefa.st) — 7-agent feature pattern, validation chains, and cross-domain coordination.
