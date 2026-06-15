---
name: backend-dev
description: "Use when the user asks for backend implementation — API endpoints, DB migrations, webhook handlers, background jobs, rate limiters, error-handling middleware, or schema design. Runs a TDD + terminal-ops + architecture + diagnose workflow. Always for FastAPI/Flask/Django endpoints, SQL migrations, or Redis services. Don't use for: frontend UI/CSS, security-only audits (kbg:security-auditor), research (kbg:research-brief), infra deployment (/devops-engineer), or frontend tests."
context: fork
agent: backend-engineer
---

Implement the backend task described by the user.

## Workflow

1. **Write tests first** — create a failing test before any implementation. Verify it fails (Red).
2. **Minimal implementation** — write the smallest code that makes the test pass (Green).
3. **Verify with real execution** — run the test suite, linter, and type checker. Fix errors immediately.
4. **Flag architecture concerns** — document at least 1–3 architecture concerns in an `ARCHITECTURE_CONCERNS.md` file. Focus on: production readiness (logging structure, error handling, monitoring), data integrity (idempotency, historical immutability, FK constraints), and performance (Redis TTL, middleware overhead, index usage).
5. **Refactor** — clean up duplication, improve naming, extract helpers. Re-run tests after each change.

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
