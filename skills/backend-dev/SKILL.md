---
name: backend-dev
description: "Backend implementation skill for API endpoints, DB migrations, webhooks, background jobs, rate limiters, error middleware, and schema design. Runs TDD + terminal-ops + architecture + diagnose. Use when the user asks for FastAPI/Flask/Django endpoints, SQL migrations, or Redis services. Don't use for: frontend UI/CSS, security-only audits (kbg:security-auditor), research (kbg:research-brief), infra deployment (devops-engineer), or frontend tests."
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
