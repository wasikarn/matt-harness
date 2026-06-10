# Architecture Concerns Template

After implementing the task and verifying tests pass, write an `ARCHITECTURE_CONCERNS.md` file with at least 1–3 concerns from the categories below.

## Categories

### Production Readiness
- Logging structure: Are IDs searchable fields (`extra={"error_id": ...}`) or interpolated strings?
- Error handling: Does the middleware swallow intentional HTTPExceptions?
- Monitoring: Are there hooks for metrics/tracing? Silent failures?
- Configuration: Are timeouts, retries, pool sizes hardcoded?

### Data Integrity
- Idempotency: Can the operation run twice safely?
- Historical immutability: Does updating a reference table retroactively change historical records?
- FK constraints: Are orphans prevented at the DB level?
- Transaction boundaries: Are multi-table writes atomic?

### Performance
- Redis TTL: Is expiry computed from capacity/refill_rate, or hardcoded?
- Middleware overhead: Does BaseHTTPMiddleware allocate a Request object per call?
- Index usage: Are queries hitting indexes or scanning?
- Connection pooling: Is the pool size bounded?

### API Contract
- Response models: Are Pydantic models explicit or inferred?
- Status codes: Are they explicit or relying on framework defaults?
- Router separation: Will the app scale past a single file?

For full REST API design guidance (URI design, HTTP methods, status codes, HATEOAS, versioning, multitenancy, tracing), see `references/rest-api-design.md`.

## Format

Use this structure for each concern:

```markdown
## 1. [Short name]

**Concern:** [What is the risk?]
**Impact:** [When does it matter?]
**Mitigation:** [What would fix it?]
```
