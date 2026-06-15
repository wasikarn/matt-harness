---
name: types-first
description: "types-first"
---

# types-first

> **Subagent self-check:** If you were dispatched to define types or contracts, **do not re-orchestrate.** Return the contract artifact (the type file, schema snippet, or OpenAPI spec) to the parent. The parent owns the wave dispatch; you own one well-bounded deliverable.

## Core rule

From article `task-distribution`:

> **Interfaces are dependencies.** If Task B depends on Task A's output, Task A must produce a machine-verifiable contract before Task B starts.

A "machine-verifiable contract" means:

- **Type definitions** — TypeScript interfaces, Python dataclasses, Rust structs, Protobuf schemas
- **API contracts** — OpenAPI spec, GraphQL schema, REST endpoint signatures (paths, methods, request/response shapes, status codes)
- **DB schemas** — Migration files, ORM models, Prisma schema, SQL `CREATE TABLE` statements
- **Event schemas** — Kafka/Redis topic shapes, webhook payload definitions, message queue envelope formats

Without this rule, parallel agents invent their own shapes. The build fails with type errors that no single agent can fix, because each agent believed its own shape was correct.

## The types-first wave order

Contract definition must complete before implementation fans out. This is a 4-wave pipeline:

| Wave | Agents | Purpose | Output |
|------|--------|---------|--------|
| **Wave 1 — Contract definition** | `type-design-analyzer` + `backend-engineer` | Define the interface | Type file, schema, or OpenAPI snippet |
| **Wave 2 — Implementation (parallel)** | `backend-engineer` (server) + `frontend-engineer` (client) | Build against the contract | Server handlers, client forms, both using the same types |
| **Wave 3 — Integration** | `backend-engineer` or `platform-engineer` | Wire both sides | Validation middleware, DB persistence, event publishing |
| **Wave 4 — Validation** | `test-engineer` + `code-reviewer` | Verify the contract is honored | Contract tests, type-check pass, lint clean |

**Why 4 waves, not 2:** Wave 1 produces the contract. Wave 2 is parallel but only starts after Wave 1 completes. Wave 3 needs the outputs from *both* Wave 2 branches, so it is a merge point. Wave 4 validates the merged result. Skipping Wave 3 and jumping from Wave 2 to Wave 4 leaves the integration seam (middleware, DB wiring, event bridge) untested.

## Contract verification tools

The contract produced in Wave 1 must be checkable by a deterministic command before any Wave 2 agent starts:

| Stack | Tool | Command |
|-------|------|---------|
| TypeScript | `tsc` | `tsc --noEmit` (compile-time check) |
| Python | `mypy` / `pydantic` | `mypy src/types/` or `python -c "from models import UserRequest; ..."` |
| Rust | `cargo check` | `cargo check --lib` |
| OpenAPI | `redocly lint` / `swagger-codegen validate` | `redocly lint openapi.yaml` |
| DB | `sqlc generate` / schema diff | `sqlc generate --file sqlc.yaml` or `pg_dump --schema-only` diff |
| Custom | JSON Schema | `ajv validate -s schema.json -d sample.json` or `jsonschema -i sample.json schema.json` |

**Rule:** The Wave 1 agent's `Done-when` must include at least one of these commands exiting 0. If the contract is not machine-verifiable, it is not a contract — it is a suggestion.

## Anti-patterns

| Anti-pattern | Why it fails | What to do instead |
|--------------|--------------|--------------------|
| "We'll agree on the shape later" | Guaranteed merge conflict. Two agents finish successfully; the build fails with type errors. | Make shape agreement Wave 1, enforced by `depends_on`. |
| "The backend team will figure it out" | Frontend blocked, context wasted. The frontend agent invents a shape, then reworks it. | Both sides build against the same contract; neither is upstream of the other. |
| "Types are overhead" | Type errors become runtime errors in production. The cost of a missing field at 2 AM is higher than the cost of defining it upfront. | Include `tsc --noEmit` or `mypy` in CI and in the Wave 1 done-when. |
| "One agent does everything" | Violates the 7-agent pattern; context saturates. A single agent cannot hold the frontend component tree, the backend route table, the DB schema, and the test matrix in one context window. | Split at contract boundaries; the contract is the shared context. |

## Worked example: `POST /users`

The user says: "Add user signup to the app."

### Plan excerpt (from `/team-plan`)

```
| Task ID | Description                          | Depends On | Assigned To | Parallel | Files                  |
|---------|--------------------------------------|------------|-------------|----------|------------------------|
| T1      | Define CreateUserRequest / UserResponse types + OpenAPI spec | -          | type-design-analyzer | no | src/types/user.ts, openapi/users.yaml |
| T2      | Implement POST /users handler        | T1         | backend-engineer | yes | src/api/users.py       |
| T3      | Implement signup form component      | T1         | frontend-engineer | yes | src/components/SignupForm.tsx |
| T4      | Wire validation + DB persistence     | T2, T3     | backend-engineer | no  | src/middleware/validate_user.py, migrations/003_user.sql |
| T5      | Write contract tests against OpenAPI   | T4         | test-engineer    | no  | tests/contract/test_users.openapi.py |
```

**Wave derivation:**
- Wave 1: T1 (`Depends On: -`)
- Wave 2: T2 + T3 (both `Depends On: T1`, so they unblock together when T1 completes)
- Wave 3: T4 (`Depends On: T2, T3` — merge point)
- Wave 4: T5 (`Depends On: T4` — validation)

### Task 1 (Wave 1) — F9 spawn prompt

```
# Task: Define user types and OpenAPI contract

## What
Produce TypeScript interfaces `CreateUserRequest` and `UserResponse`, plus an OpenAPI 3.0 snippet for `POST /users`.

## Where
`src/types/user.ts` and `openapi/users.yaml`

## Focus
Correctness over speed — every field must have a documented purpose.

## Deliverable
`src/types/user.ts` exports `CreateUserRequest` and `UserResponse`; `openapi/users.yaml` validates with `redocly lint`.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/types/user.ts
- /Users/kobig/Codes/Personals/kbg-harness/openapi/users.yaml

## UPSTREAM CONTRACTS
(Empty list — first task in chain.)

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/types/user.ts | exports `CreateUserRequest` and `UserResponse` | no runtime code, only types |
| openapi/users.yaml | `redocly lint` exits 0 | references `src/types/user.ts` fields |

## Done-when
- [ ] `src/types/user.ts` exports both interfaces with JSDoc on every field
- [ ] `redocly lint openapi/users.yaml` exits 0
- [ ] No edit to files outside FILES YOU OWN
```

Spawn with `AskUserQuestion` (gated — type-design-analyzer holds Edit/Write).

### Task 2 (Wave 2a) — F9 spawn prompt

```
# Task: Implement POST /users handler

## What
Implement the `POST /users` endpoint that accepts `CreateUserRequest` and returns `UserResponse`.

## Where
`src/api/users.py`

## Focus
API stability — the contract is fixed; the implementation must match it exactly.

## Deliverable
`src/api/users.py` exports a `POST /users` handler that returns HTTP 201 + `UserResponse` JSON.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/api/users.py

## UPSTREAM CONTRACTS
- From task T1: `src/types/user.ts` — `CreateUserRequest` has fields `email: string`, `password: string`; `UserResponse` has `id: UUID`, `email: string`, `created_at: ISO8601`.
- From task T1: `openapi/users.yaml` — `POST /users` request body schema and 201 response schema.

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/api/users.py | `POST /users` returns 201 + `UserResponse` shape | uses T1 types, no new fields invented |

## Done-when
- [ ] `POST /users` with valid `CreateUserRequest` returns 201 + `UserResponse`
- [ ] `bash -n src/api/users.py` exits 0
- [ ] No edit to files outside FILES YOU OWN
```

Spawn with `AskUserQuestion` (gated — backend-engineer holds Edit/Write/Bash).

### Task 3 (Wave 2b) — F9 spawn prompt

```
# Task: Implement signup form component

## What
Build a `SignupForm` React component that submits `CreateUserRequest` and renders the returned `UserResponse`.

## Where
`src/components/SignupForm.tsx`

## Focus
Type safety over styling — the form must compile against the exact T1 interfaces.

## Deliverable
`src/components/SignupForm.tsx` exports `SignupForm` and compiles with `tsc --noEmit`.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/components/SignupForm.tsx

## UPSTREAM CONTRACTS
- From task T1: `src/types/user.ts` — `CreateUserRequest` has fields `email: string`, `password: string`; `UserResponse` has `id: UUID`, `email: string`, `created_at: ISO8601`.

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/components/SignupForm.tsx | exports `SignupForm` | imports from `src/types/user.ts`, no local re-definition of request/response shapes |

## Done-when
- [ ] `tsc --noEmit` passes with `SignupForm` importing `CreateUserRequest` and `UserResponse`
- [ ] Form submits `POST /users` with the correct JSON shape
- [ ] No edit to files outside FILES YOU OWN
```

Spawn with `AskUserQuestion` (gated — frontend-engineer holds Edit/Write/Bash).

### Task 4 (Wave 3) — F9 spawn prompt

```
# Task: Wire validation + DB persistence

## What
Add request validation middleware and a DB migration so the handler persists users.

## Where
`src/middleware/validate_user.py` and `migrations/003_user.sql`

## Focus
Data integrity — idempotency, FK constraints, no data loss on retry.

## Deliverable
Validation middleware enforces `CreateUserRequest` schema; migration creates `users` table matching `UserResponse` fields.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/middleware/validate_user.py
- /Users/kobig/Codes/Personals/kbg-harness/migrations/003_user.sql

## UPSTREAM CONTRACTS
- From task T2: `src/api/users.py` — the handler signature and current implementation.
- From task T3: `src/components/SignupForm.tsx` — the form's submit shape (must match T1, but verify).
- From task T1: `src/types/user.ts` — the canonical shape both sides agreed on.

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/middleware/validate_user.py | rejects payloads missing required T1 fields | no new validation rules beyond T1 spec |
| migrations/003_user.sql | `users` table columns match `UserResponse` fields | reversible migration (`down` script provided) |

## Done-when
- [ ] Migration runs forward and backward cleanly
- [ ] `POST /users` with invalid payload returns 400 before touching DB
- [ ] `POST /users` with duplicate email is handled idempotently
- [ ] No edit to files outside FILES YOU OWN
```

Spawn with `AskUserQuestion` (gated — backend-engineer holds Edit/Write/Bash).

### Task 5 (Wave 4) — F9 spawn prompt

```
# Task: Write contract tests against OpenAPI

## What
Generate or write contract tests that assert the running `POST /users` endpoint matches the OpenAPI spec from T1.

## Where
`tests/contract/test_users.openapi.py`

## Focus
Contract fidelity — the implementation must not drift from the spec.

## Deliverable
Contract test file that fails if the API response shape diverges from `openapi/users.yaml`.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/tests/contract/test_users.openapi.py

## UPSTREAM CONTRACTS
- From task T1: `openapi/users.yaml` — the canonical spec.
- From task T4: `src/middleware/validate_user.py` + `migrations/003_user.sql` — the final implementation.

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| tests/contract/test_users.openapi.py | every `POST /users` response matches OpenAPI schema | uses `schemathesis` or `dredd`; no mocked server |

## Done-when
- [ ] Contract test passes against the running dev server
- [ ] Test fails if a field is added to the response without updating `openapi/users.yaml`
- [ ] No edit to files outside FILES YOU OWN
```

Spawn **ungated** — test-engineer is read-only for test execution, but if it holds Edit/Write to create the test file, it is gated. Check the agent's actual `tools:` grant.

## Integration with task board

The contract task (Wave 1) must be observable as `completed` before any dependent task is spawned.

### `depends_on` enforcement

In the plan file (`.claude/tasks/<slug>.md`):

```
| Task ID | Description | Depends On |
|---------|-------------|------------|
| T1      | Define types + OpenAPI | -          |
| T2      | Implement handler      | T1         |
| T3      | Implement form         | T1         |
| T4      | Wire persistence       | T2, T3     |
| T5      | Contract tests         | T4         |
```

### Task board state machine

Use `scripts/task_board_lib.sh` (see `skills/orchestrate/SKILL.md` § "Task board integration"):

1. **Spawn T1:** create with `status = "pending"`, `depends_on = []`. Claim → `in_progress`.
2. **After T1 completes:** set `status = "completed"`, run `kbg_recompute_blocked`.
3. **Check T2 and T3:** `kbg_board_read "$PLAN_DIR" | jq '.tasks["T2"].status'` should now be `"pending"` (unblocked). Spawn both in parallel.
4. **After T2 and T3 complete:** set both `completed`, run `kbg_recompute_blocked`. T4 unblocks.
5. **After T4 completes:** set `completed`, run `kbg_recompute_blocked`. T5 unblocks.
6. **After T5 completes:** the whole chain is `completed`; update plan-level `status`.

### `blocked_by` field

`kbg_recompute_blocked` derives `blocked_by` from `depends_on`. If T2 has `depends_on: ["T1"]` and T1 is not `completed`, T2's `blocked_by` will contain `"T1"`. The lead MUST NOT spawn T2 while `blocked_by` is non-empty.

**The contract task's `files` field:** When T1 completes, the lead populates `tasks["T1"].files` with the absolute paths of the contract files (`src/types/user.ts`, `openapi/users.yaml`). T2 and T3 read these paths from the board; they do not guess.

## Cross-references

- **Orchestration:** `skills/orchestrate/SKILL.md` — the F9 spawn-prompt template, validation chain (`addBlockedBy`), bounded fan-out cap (F8.5), and lead-coordinator doctrine (F8) that this skill's wave execution follows.
- **Task sizing:** `skills/task-sizing/SKILL.md` — how to decide whether a contract is "one task" or "multiple tasks" (e.g., types + OpenAPI + DB schema might be three micro-tasks or one macro-task depending on complexity).
- **Planning:** `commands/team-plan.md` — the plan file format (`## Step by Step Tasks` table with `Depends On`, `Files`, `Criteria`, `Constraints`) that feeds into this skill's wave derivation.
- **Validation chain:** `skills/orchestrate/SKILL.md` § "Validation chain (TaskCreate + addBlockedBy)" — the builder → validator → fix → re-validator pattern that Wave 4 uses.
- **Contract chain analysis:** Article `agent-teams-workflow` Step 5 — the conceptual source of the 4-wave pipeline.

## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
