---
name: backend-dev
description: "Backend implementation skill for API endpoints, DB migrations, webhooks, background jobs, rate limiters, error middleware, and schema design. Runs TDD, verifies with real execution, and flags architecture concerns. Use when the user asks for FastAPI/Flask/Django endpoints, SQL migrations, or Redis services. Thai: 'เขียน API', 'ทำ migration', 'เพิ่ม webhook', 'สร้าง background job', 'ทำ rate limiter'. Don't use for: frontend UI/CSS, security-only audits (kbg:security-auditor), research (/deep-dive), infra deployment (devops-engineer), or frontend tests."
---

Implement the backend task described by the user.

## Workflow

1. **Write tests first** — create a failing test before any implementation. Verify it fails (Red). For REST endpoint/contract work, consult `references/rest-api-design.md` before settling the API surface.
2. **Minimal implementation** — write the smallest code that makes the test pass (Green).
3. **Verify with real execution** — run the test suite, linter, and type checker. Fix errors immediately.
4. **Flag architecture concerns** — document at least 1–3 architecture concerns in an `ARCHITECTURE_CONCERNS.md` file (template: `references/architecture-concerns-template.md`). Focus on: production readiness (logging structure, error handling, monitoring), data integrity (idempotency, historical immutability, FK constraints), and performance (Redis TTL, middleware overhead, index usage).
5. **Refactor** — clean up duplication, improve naming, extract helpers. Re-run tests after each change.
