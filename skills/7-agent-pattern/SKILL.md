---
name: 7-agent-pattern
description: "7-agent-pattern"
---

# 7-Agent Pattern

> **Subagent self-check:** If you were dispatched as a sub-agent for a specific seat, **do not
> re-orchestrate.** Return your scoped output (a `done-when` artifact, a `Report:` block, or
> your done-criterion evidence) to the parent. The parent owns the prioritization + dispatch
> loop; you own one well-bounded deliverable.

The canonical parallel feature-build pattern from the claudefa.st agent-teams articles.
Seven specialized agents run in dependency-ordered waves so that parallel work integrates
cleanly against shared contracts instead of independently guessing data shapes.

---

## The 7 seats (canonical allocation)

| Seat | Name | Typical Agent | Owns |
|------|------|---------------|------|
| 1 | API / Middleware | `backend-engineer` or `platform-engineer` | Routes, controllers, middleware, auth guards, service-layer functions |
| 2 | Styles / Presentation | `frontend-engineer` or `i18n-specialist` | Components, pages, CSS, responsive layout, user-facing copy |
| 3 | Tests | `test-engineer` + `pr-test-analyzer` | Unit tests, integration tests, contract tests, coverage gates |
| 4 | Types / Contracts | `type-design-analyzer` | Interfaces, schemas, OpenAPI / GraphQL specs, validation rules |
| 5 | Hooks / Lifecycle | `devops-engineer` or `data-engineer` | CI/CD hooks, event pipelines, monitoring, DB migrations |
| 6 | Integration | `backend-engineer` or `platform-engineer` | Wires frontend ↔ backend, third-party APIs, auth flows, end-to-end seams |
| 7 | Remaining / Docs | `technical-writer` or `ux-reviewer` | Docs, accessibility, error messages, README updates, config files |

**Seat 4 runs first.** Shared types are dependencies; dependencies must complete before the
tasks that consume them. This is the single most common failure mode in un-coordinated
parallel builds: three agents independently decide the shape of `UserSettings`, the build
fails with 14 type errors, and nothing integrates.

---

## Wave structure for the 7 pattern

### Wave 1 — Foundation (Seats 4 → 1, sequential)

1. **Seat 4 (`type-design-analyzer`)** defines the contract: interfaces, request/response
   shapes, enums, validation schemas.
2. **Seat 1 (`backend-engineer`)** stubs routes and controllers against those types.

The output of this wave is the **schema contract** + **API contract** that every downstream
agent consumes.

### Wave 2 — Parallel build (Seats 2, 3, 5 in parallel)

- **Seat 2** builds frontend components against the type contract.
- **Seat 3** writes tests against the API contract.
- **Seat 5** adds migrations, CI hooks, and observability.

Each agent receives the exact type / schema content in its spawn prompt — not a reference
to "go read what Seat 4 did." See the **F9 spawn-prompt template** in
`skills/orchestrate/SKILL.md` for the exact shape.

### Wave 3 — Integration (Seat 6)

**Seat 6** wires all pieces together: connects the form to the API client, handles error
states, verifies auth flows, and runs the first end-to-end trace.

### Wave 4 — Polish (Seat 7)

**Seat 7** documents the API, writes user-facing error copy, updates the README, and checks
accessibility.

### Wave 5 — Validation chain

`code-reviewer` + `security-reviewer` review all files in a deterministic chain:
builder → validator → fix → re-validator. See `skills/orchestrate/SKILL.md` § "Validation
chain (builder → validator → fix → re-validator)" for the 4-step protocol and `addBlockedBy`
semantics.

---

## File ownership table (typical full-stack feature)

| File | Seat | Agent |
|------|------|-------|
| `src/api/users.ts` | 1 | `backend-engineer` |
| `src/components/UserForm.tsx` | 2 | `frontend-engineer` |
| `tests/users.test.ts` | 3 | `test-engineer` |
| `src/types/user.ts` | 4 | `type-design-analyzer` |
| `.github/workflows/ci.yml` | 5 | `devops-engineer` |
| `src/lib/api-client.ts` | 6 | `backend-engineer` |
| `docs/api/users.md` | 7 | `technical-writer` |

**Rule:** each file is owned by exactly one agent. Cross-cutting edits (barrel files,
shared config) are the orchestrator's job in post-wave consolidation, not the teammate's.

---

## When to deviate from 7

| Agents | When | Example |
|--------|------|---------|
| **< 3** | Single-file or trivial change | Use `/feature-dev` or inline — agent teams are overhead |
| **3–4** | Pure backend API or pure frontend component | Skip Seats 2, 5, 6, 7 as irrelevant |
| **5–6** | Full-stack without complex CI/CD or docs requirements | Merge Seat 5 into Seat 1, Seat 7 into Seat 3 |
| **7** | Full-stack with backend + frontend + DB + tests + docs + CI | **This pattern** |
| **8+** | Multi-service change (e.g., microservice migration) | **Split into multiple plans instead.** The 8+ case is a signal the scope is too large for one session. See `skills/task-sizing/SKILL.md` (when available) for decomposition heuristics. |

The F8 lead doctrine in `skills/orchestrate/SKILL.md` calls "3–5 teammates" the sweet spot.
The 7-agent pattern stretches to 7 because full-stack features naturally touch 7 file
boundaries; if your feature doesn't, shrink the team.

---

## Plan template (copy-pasteable)

Paste this table into your plan file (see `commands/team-plan.md` for the full plan format):

```markdown
| Task ID | Seat | Agent | Description | Files | Depends On | Criteria |
|---------|------|-------|-------------|-------|------------|----------|
| T1 | 4 | type-design-analyzer | Define UserCreateRequest/Response types | `src/types/user.ts` | — | `tsc` passes |
| T2 | 1 | backend-engineer | Implement POST /users handler | `src/api/users.ts`, `src/models/user.ts` | T1 | `pytest` passes |
| T3 | 2 | frontend-engineer | Build user registration form | `src/components/UserForm.tsx` | T1 | `jest` passes |
| T4 | 3 | test-engineer | Write integration tests for user flow | `tests/users.test.ts` | T2, T3 | coverage >80% |
| T5 | 5 | devops-engineer | Add migration + CI hook | `migrations/...`, `.github/...` | T1 | migration dry-run passes |
| T6 | 6 | backend-engineer | Wire form to API + error handling | `src/lib/api-client.ts` | T3, T2 | e2e test passes |
| T7 | 7 | technical-writer | Document API + user-facing errors | `docs/api/users.md` | T6 | no broken links |
```

**Wave derivation from `Depends On`:**
- Wave 1: T1 (no deps)
- Wave 2: T2, T3, T5 (all depend only on T1)
- Wave 3: T4 (depends on T2 + T3)
- Wave 4: T6 (depends on T3 + T2)
- Wave 5: T7 (depends on T6)
- Wave 6: validation chain (review all files)

**Contract injection per wave:**
- T2, T3, T5 prompts receive the exact output of T1 (schema + types).
- T4, T6 prompts receive the exact API signatures from T2.
- T6 also receives the frontend component props from T3.
- T7 receives the e2e trace results from T6.

---

## F8.5 bounded fan-out check

7 agents, max 3 per wave (Wave 2) = **never exceeds the 5/wave cap**. But if a wave has > 3 tasks per agent
(21 total), split into sub-waves.

The hard cap is **5 agents per wave**, enforced in code, not prose. See
`skills/orchestrate/SKILL.md` § "Bounded fan-out — hard cap (F8.5)" for the clamp
rules and the `eval/regressions/bounded-agent-spawning.json` fixture that keeps the
contract in place.

**Work-list count ≠ spawn count.** Audit + verify is a second fan-out layer. If the
work-list hits 44 and validation doubles it to 88, the cap is on **total spawned agents
across the entire plan lifetime**, not on the work-list alone.

**"7 agents" vs the F8 3-5 cap — no conflict.** The "7" is 7 **seats/tasks** spread
across 6 waves, with **peak 3 concurrent** (Wave 2: Seats 2, 3, 5). The F8 "3-5
teammates" cap counts **peak concurrent live teammates**, not total seats — so this
pattern's peak of 3 sits inside 3-5. When rendered as a `/team-build` plan, the
`## Team Members` roster is the **concurrent** set (≤5): teammates are persistent and
take multiple seats across waves (with wave-based eviction freeing slots), so the
7 seats are covered by ≤5 concurrent members. `/team-build` + `plan_linter` therefore
do **not** refuse this pattern for its seat count — they gate the concurrent roster,
which is ≤5. (If you author a `## Team Members` section listing one entry per seat,
that's the authoring mistake, not a flaw in the pattern.)

---

## Cross-references

- **Types-first discipline:** Seat 4's "run first" rule is the 7-agent specialization of
  `skills/types-first/SKILL.md` (when available). Shared interfaces are dependencies;
  dependencies run before consumers.
- **Task sizing:** Deviations from 7 agents are governed by `skills/task-sizing/SKILL.md`
  (when available). If a plan grows to 8+, split scope before dispatch.
- **Spawn-prompt template:** Every teammate prompt MUST use the F9 template from
  `skills/orchestrate/SKILL.md`. Missing What / Where / Focus / Deliverable / FILES YOU OWN
  / UPSTREAM CONTRACTS is the single most common sub-agent failure mode.
- **Plan format:** The `## Team Members`, `## Step by Step Tasks`, `## Acceptance Criteria`,
  and `## Validation Commands` sections follow `commands/team-plan.md`. The plan file is the
  session-resettable, lead-handoffable interface between planning and execution.
- **Validation chain:** Post-build review uses the builder → validator → fix → re-validator
  chain from `skills/orchestrate/SKILL.md`. Ungated for validators, gated for builders/fixers.
