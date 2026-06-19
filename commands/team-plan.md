---
name: team-plan
description: "Phase 1 of the agent-teams workflow: brain-dump the feature, research codebase, ask clarifying questions, then write a structured plan to .claude/tasks/<slug>.md with team members, dependency chains, file ownership, acceptance criteria, and validation commands. Use when starting non-trivial features for multi-agent parallel implementation, or when the user says 'team plan: X', 'สร้างทีม', 'ประชุมทีม', 'จัดสรรงานทีม', 'plan ทีม', or 'แผนทีม'. Don't use for: single-file changes (use /feature-dev), trivial features (do inline), or research-only tasks (use /deep-dive)."
argument-hint: Feature description
---

# /team-plan — Multi-agent feature planning

You are planning a feature for implementation by a team of agents. This command produces a **plan artifact** at `.claude/tasks/<slug>.md`; it does NOT execute the plan. Execution is `/team-build`'s job.

This is Step 1-3 of the article `agent-teams-workflow` 7-step pipeline (Brain Dump → Research → Plan → Fresh Context → Contract Chain → Wave Execution → Validation). Steps 4-7 belong to `/team-build`.

## Core principles

- **Ask at least 10 clarifying questions.** Not 2 or 3. The article is explicit: "Not 2 or 3 questions. At least 10." If you find yourself ready to plan with fewer than 10, you haven't dug deep enough.
- **The plan file is the contract.** `.claude/tasks/<slug>.md` is what `/team-build` consumes, what a fresh session reads to resume, and what a different lead can pick up. Make it machine-parseable, not free-form prose.
- **File ownership prevents merge conflicts.** The plan MUST assign each file to exactly one team member. Cross-cutting edits are the orchestrator's job (post-wave), not the teammate's.
- **Validation commands are the gate.** Every acceptance criterion has an exact `validation_command:` that `/team-build`'s Step 7 runs. "Tests pass" is not a validation command; `npm test` is.

---

## Step 1 — Brain dump

**Goal:** capture the user's request as `## Brain dump` in the plan file. Do not over-structure.

**Actions:**
1. Initial request: `$ARGUMENTS`
2. Read `.claude/tasks/` (if exists) for prior plans the user might be amending
3. If the request is too vague to brain-dump (< 3 sentences of intent), ask one clarifying question first: "What problem are you trying to solve?" — then brain-dump based on the answer.
4. Open the plan file skeleton at `.claude/tasks/<slug>.md` with all four sections pre-populated as headers (`## Brain dump`, `## Team Members`, `## Step by Step Tasks`, `## Acceptance Criteria`, `## Validation Commands`) — empty for now.
5. Fill `## Brain dump` with the user's request verbatim + 1-2 sentences of inferred scope. **Do not invent acceptance criteria here** — that's Step 3.

**Done-when Step 1:** the plan file exists with a `## Brain dump` section.

---

## Step 2 — Research + Q&A (≥10 questions)

**Goal:** understand the codebase + surface at least 10 underspecified aspects via `AskUserQuestion`.

**Actions:**
1. Read `CLAUDE.md` and `BOUNDARY.md` (if present) for project conventions and module boundaries
2. Launch 2-3 `code-explorer` agents in parallel to map the affected area (one per cluster — schema, API surface, tests). Use the same prompt shape as `/feature-dev` Phase 2.
3. Read the files each agent flagged as essential (don't accept the agent's word; verify)
4. **Identify underspecified aspects across these dimensions:**
   - Edge cases (empty input, concurrent access, malformed data)
   - Error handling (retries, fallbacks, what gets surfaced to the user)
   - Integration points (which other modules does this touch?)
   - Scope boundaries (what's IN scope, what's explicitly OUT)
   - Design preferences (libraries, patterns, naming)
   - Backward compatibility (do existing callers/contracts break?)
   - Performance needs (latency, throughput, scale)
   - Test coverage expectations (unit / integration / e2e)
   - Migration strategy (if changing existing behavior)
   - Observability (logs, metrics, traces)
5. **Present all questions to the user in a clear, organized list.** Use `AskUserQuestion` for up to 4 at a time; for > 4, batch them across multiple `AskUserQuestion` calls. The total MUST be ≥ 10.
6. Wait for answers before Step 3.
7. Lock the acceptance contract. For non-trivial scope, invoke `kbg:accept-task` to write `.scratch/<slug>/ACCEPTANCE.md` (machine-checkable success criteria) — this is the producer that the build's acceptance-criteria check consumes.

**Anti-patterns:**

- "Whatever you think is best" → push back. The plan needs user judgment on the 10+ questions; "you decide" means the plan is built on assumptions.
- < 10 questions → the plan is incomplete. Surface the missing dimensions explicitly ("I have 7 questions but the article requires ≥ 10; here are the 3 I'd ask next…")
- Skip the agents → "I'll just read the code myself" misses cross-cutting patterns only an agent's full-corpus read catches.

**Done-when Step 2:** the plan file has a `## Q&A log` section with at least 10 answered questions (each tagged with its dimension: edge-case, error-handling, integration, scope, design, compat, perf, test, migration, observability).

---

## Step 3 — Structured plan

**Goal:** fill in the plan file's `## Team Members`, `## Step by Step Tasks`, `## Acceptance Criteria`, and `## Validation Commands` sections.

**Actions:**

### 3a. `## Team Members`

For each team member, list:

```
| Name | Role | Agent Type |
|------|------|------------|
| DB   | Schema/migration owner | backend-engineer |
| API  | Endpoint owner         | backend-engineer |
| V    | Validator              | code-reviewer (or test-engineer for test-shaped validation) |
| INT  | Integration validator  | code-explorer (traces cross-component) |
```

**Sweet spot: 3-5 teammates** (per F8 lead doctrine in `skills/orchestrate/SKILL.md`). Plans outside this range are flagged for revision here, not at `/team-build` time.

**⚠️ F8.5 — Hard cap = 5 per wave** (advisory floor 3 — F8.4; the [[bounded-agent-spawning]] contract). A prompt asking for "N items" is not a cap — the LLM overshoots (see `skills/orchestrate/SKILL.md` § Bounded fan-out for the audit-2026-06-12 overshoot). The dispatch step in `commands/team-build.md` Step 6 is the enforcement point; this planning step is responsible for **pre-trimming** any work-list >5 by deferring the tail to a `deferred-<date>.md` and queuing it as a follow-up wave. The audit fixture `eval/regressions/bounded-agent-spawning.json` locks this in code.

### 3b. `## Step by Step Tasks`

For each task:

```
| Task ID | Description                          | Depends On | Assigned To | Parallel | Files                  | Criteria                                      | Constraints              |
|---------|--------------------------------------|------------|-------------|----------|------------------------|-----------------------------------------------|--------------------------|
| DB-1    | Create `users` table + migration     | -          | DB          | yes      | migrations/002_users.sql| exports `users(id, email, created_at)`         | no destructive changes   |
| API-1   | POST /users endpoint                 | DB-1       | API         | no       | api/users.py            | returns 201 + JSON body                      | uses backend-dev skill   |
| V-1     | Lint + test pass                     | API-1      | V           | no       | (none)                  | `bash -n api/users.py` + `pytest` exit 0     | (none)                   |
| INT-1   | End-to-end trace: POST /users → DB  | V-1        | INT         | no       | (none)                  | integration test green                       | single TaskUpdate addBlockedBy=[API-1, V-1] |
```

**Wave derivation:** tasks with `Depends On == "-"` are Wave 1. Tasks whose `Depends On` are all in the same wave become Wave 2 (in parallel). Continue until all tasks are placed.

**Integration validator (D8):** for each cross-component boundary, add ONE `INT-N` task with `addBlockedBy=[all]` — single `TaskUpdate` that blocks the INT on ALL builders. Distinct from V-1's single-validator gate; INT-N verifies the seams.

### 3c. `## Acceptance Criteria`

For each task, one or more measurable criteria:

```
- [ ] DB-1: `users` table exists with `id`, `email`, `created_at` columns; migration runs forward and backward cleanly
- [ ] API-1: `POST /api/users` with `{"email": "..."}` returns 201 + `{"id": <uuid>, "email": "..."}`
- [ ] V-1: `bash -n api/users.py` exit 0, `pytest tests/test_users.py` exit 0
- [ ] INT-1: e2e test `tests/e2e/test_post_users.py` green
```

**Each criterion MUST be machine-checkable.** "Code is clean" is not a criterion; "`ruff check` exit 0" is.

### 3d. `## Validation Commands`

The exact commands `/team-build` runs in Step 7 (post-build validation):

```
## Validation Commands
- `bash -n api/users.py` (syntax)
- `ruff check api/` (lint)
- `pytest tests/test_users.py -v` (unit)
- `pytest tests/e2e/test_post_users.py -v` (e2e)
- `curl -X POST http://localhost:8000/api/users -d '{"email":"x@y.z"}'` (manual smoke)
```

**Every acceptance criterion maps to ≥ 1 validation command.** If a criterion has no command, it's not testable — revise.

---

## Step 3 done-when (final)

The plan file `.claude/tasks/<slug>.md` is complete when:

- [ ] `## Brain dump` filled (Step 1)
- [ ] `## Q&A log` has ≥ 10 answered questions (Step 2)
- [ ] `## Team Members` table filled (3-5 members, sweet spot)
- [ ] `## Step by Step Tasks` table filled with `Depends On` + `Assigned To` + `Files` + `Criteria` + `Constraints`
- [ ] Wave 1 / Wave 2 / ... ordering explicit
- [ ] `## Acceptance Criteria` filled (machine-checkable)
- [ ] `## Validation Commands` filled (one or more per criterion)
- [ ] `.scratch/<slug>/ACCEPTANCE.md` exists (machine-checkable contract, separate from this plan)

---

## What this command does NOT do

- Does NOT spawn teammates. That's `/team-build`.
- Does NOT validate the codebase. That's `/team-build` Step 7.
- Does NOT write code. Period.
- Does NOT auto-save the plan. After Step 3, the file is on disk; the user reviews before `/team-build`.

---

## Cross-references

- The plan file is the session-resettable, lead-handoffable interface (per D10 in `.scratch/article-revalidation-2026-06-12/delta-vs-REPORT-v2.md`). A fresh session, a different lead, or a partial resumption all work because the plan decouples state from session context.
- The F9 spawn-prompt template (in `skills/orchestrate/SKILL.md`) is the per-task contract format `/team-build` injects into every teammate's spawn prompt. The plan file's `## Step by Step Tasks` table is the data source; the template is the rendering.
- Validation chain (`addBlockedBy`): orchestrated by `/team-build` Step 3; the plan's `Depends On` field is the input.
- METHODOLOGY: Rule 1 (think before coding) — this whole command is the deliberate-plan gate. Rule 4 (goal-driven) — every acceptance criterion is observable. Rule 12 (fail loud) — < 10 questions is a hard stop, not a soft suggestion.
