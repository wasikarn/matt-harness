# CLAUDE.md — <SERVICE_NAME> (TaThep Platform service)

> Starter. Copy to a tathep service repo as its `CLAUDE.md`, fill every `<PLACEHOLDER>`, delete this note.
> Keep it short — CLAUDE.md is read every session; bloat costs context.

## What this is

<SERVICE_NAME> — <one line: what it does, who consumes it>.
Stack: `<LANGUAGE/FRAMEWORK>`, `<DATASTORE>`, `<RUNTIME>`.

## Conventions (TaThep)

- **Tickets:** `TP-*` (Jira project `TP`). Reference the ticket in branch, PR, and commit.
- **Acceptance criteria:** Thai, PO/QA-readable — plain checklist by default; Given/When/Then only for complex flows.
- **Plan files:** multi-repo work → `<workspace>/docs/plans/`; single-repo → `<repo>/docs/plans/`.
- **Branching:** `<BRANCH_MODEL>`.

## Build / test / run

- Install: `<INSTALL_CMD>`
- Test: `<TEST_CMD>` — run before every PR
- Lint/format: `<LINT_CMD>`
- Run locally: `<RUN_CMD>`

## Architecture notes (fill as the service grows)

- Entry point: `<PATH>`
- Data model / migrations: `<PATH>`
- Contracts this service owns with consumers: `<LIST>`

## Don't

- `<SERVICE-SPECIFIC GUARDRAIL, e.g. "never write to the legacy orders_v1 table">`
