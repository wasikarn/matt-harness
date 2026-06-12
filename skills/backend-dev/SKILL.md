---
name: backend-dev
description: "Use this skill whenever the user asks for backend implementation work — API endpoints, database migrations, service logic, backend refactors, webhook handlers, background jobs, rate limiters, error-handling middleware, or database schema design. Runs a backend workflow with TDD + terminal-ops + architecture + diagnose preloaded. Always trigger for FastAPI/Flask/Django endpoints, SQL migrations, Redis-based services, or normalization tasks. Don't use for: frontend UI components, CSS, security-only audits (use kbg:security-auditor), pure research (use kbg:research-brief), infrastructure deployment (use /devops-engineer), or writing tests for existing frontend code."
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
