---
name: backend-patterns
description: Backend architecture, API design, and DB optimization for Node.js/Next.js. Use when building a Node/TS backend. Don't use for Python/Go/Rust backends, or the client half (kbg:frontend-patterns).
metadata:
  origin: ECC
---

# Backend Development Patterns

Backend architecture patterns and best practices for scalable server-side applications.
Full code for every pattern below lives in `reference.md` — this file carries the trigger
conditions and the gotchas that aren't obvious from the code alone.

## When to Activate

- Designing REST API endpoints
- Implementing repository, service, or controller layers
- Optimizing database queries (N+1, indexing, connection pooling)
- Adding caching (Redis, in-memory, HTTP cache headers)
- Setting up background jobs or async processing
- Structuring error handling and validation for APIs
- Building middleware (auth, logging, rate limiting)

## API Design Patterns

- **RESTful API structure** — resource-based URLs, HTTP verbs mapped to CRUD, query
  params for filter/sort/pagination. `reference.md#restful-api-structure`.
- **Repository pattern** — abstract data access behind an interface so the service layer
  never talks to the database driver directly. `reference.md#repository-pattern`.
- **Service layer pattern** — business logic separated from data access.
  `reference.md#service-layer-pattern`.
- **Middleware pattern** — an App Router route handler wrapper for auth, logging, or rate
  limiting. `reference.md#middleware-pattern`.

**Don't let a middleware's try/catch mask the handler's own bugs.** A `withAuth`-style
wrapper's catch should only cover the token-verification call it's wrapping — an async
handler's own errors are separate promise rejections a plain try/catch around the whole
call can't see without an explicit `await`, and adding that `await` just to catch more
would relabel the handler's real bugs as "Invalid token", hiding them behind a fake auth
failure. Keep the try scoped to verification only; let handler errors propagate to the
route's own error handling.

## Database Patterns

- **Query optimization** — select only the columns you need, not `select('*')`.
  `reference.md#query-optimization`.
- **N+1 prevention** — batch-fetch related rows instead of querying per item in a loop.
  `reference.md#n1-query-prevention`.
- **Transaction pattern** — wrap a multi-table write in a Postgres function via RPC.
  `reference.md#transaction-pattern`.

**Indexing & pool sizing:** for multi-column filters, one composite index beats two
single-columns — Postgres bitmap-scan across two indexes is slower than one composite
read. Order the composite equality-first, then range/sort, and carry the `SELECT`
columns via an `INCLUDE` covering index to skip the heap fetch. For pool sizing on
Supabase/Postgres, the aggregate `pool.max × instances` (node-postgres's `Pool` option,
or `connection_limit` in a Prisma connection string) must stay under the server
`max_connections` cap with ~20% headroom for replicas and migrations — sizing
per-instance in isolation exhausts connections under multi-pod fan-out.

**Don't let the exception handler swallow the failure.** In the transaction pattern's SQL
function, an `EXCEPTION WHEN OTHERS` block that `RETURN`s a `success: false` payload
completes the function *normally* from Postgres's point of view — no error propagates.
`supabase.rpc()` then comes back with `error: null` and `data: { success: false, ... }`,
so the TypeScript wrapper's `if (error) throw new Error(...)` never fires on the exact
failure this SQL was written to catch, and `return data` hands the caller a payload that
looks like success unless it separately checks `data.success`. Bare `RAISE;` inside the
handler re-throws the original error so it actually reaches the caller's `error` field
instead.

## Caching Strategies

- **Redis caching layer** — wrap a repository with a cache-check-then-fetch decorator.
  `reference.md#redis-caching-layer`.
- **Cache-aside pattern** — the same shape as a standalone function.
  `reference.md#cache-aside-pattern`.

**Stampede guard:** both examples above are textbook get-then-set with no protection on a
miss — for a hot key, every concurrent request fires the DB fetch simultaneously on each
TTL expiry (thundering herd). Guard the re-warm with a `SETNX` single-flight mutex (one
request rebuilds, the rest wait or serve stale) or probabilistic early refresh (XFetch);
without it the cache that should relieve the DB becomes the spike that kills it.

## Error Handling Patterns

- **Centralized error handler** — a typed `ApiError` class plus one handler function that
  maps error types to HTTP status codes. `reference.md#centralized-error-handler`.
- **Retry with exponential backoff** — retry a failing async call with a growing delay.
  `reference.md#retry-with-exponential-backoff`.

**Two fixes before shipping the retry snippet:** (1) add jitter —
`Math.pow(2, i) * 1000 + Math.random() * 1000` — so N replicas retrying in lockstep (1s,
2s at the default `maxRetries = 3`) don't form a synchronized retry storm that re-kills
the recovering dependency; (2) gate retry on idempotency — the snippet retries `fn`
unconditionally, so a POST/create that failed after the write succeeded produces a
duplicate. For non-idempotent verbs require an `Idempotency-Key` header or a dedupe row
before retrying.

## Authentication & Authorization

- **JWT token validation** — verify a bearer token and extract the payload.
  `reference.md#jwt-token-validation`.
- **Role-based access control** — a permission table keyed by role, plus a
  `requirePermission` HOF. `reference.md#role-based-access-control`.

## Rate Limiting

Rate limiting must use a shared store such as Redis, a gateway, or the
platform's native limiter. Do not use per-process in-memory counters for
production APIs: they reset on deploy, split across replicas, and fail open in
serverless or multi-instance environments.

Decide what happens when the shared store itself goes down — don't inherit
whatever the client library defaults to silently. If the store is shared with
other traffic-critical paths (e.g. the same Redis also backs your cache), a
store outage already exposes the backend through those paths, so failing the
limiter open too compounds the exposure — fail closed (`503` + a short
`Retry-After`) instead. If rate limiting is pure defense-in-depth on an
isolated store, failing open avoids turning a store blip into a full outage.
Either is legitimate; leaving it undecided is not — most client libraries fail
open by default without saying so.

Derive the store key from the caller's credential (hash it) rather than using
the raw API key or token as the literal key name — a raw key otherwise
surfaces in the store's own dashboard, logs, and debugging tools in plaintext.
`reference.md#rate-limiting-key-hashing`.

Keep the backend layer responsible for choosing the integration point, the HTTP
contract, and the error shape; use `kbg:security-auditor` for abuse case review.

## Background Jobs & Queues

- **Simple queue pattern** — an in-process array queue with a `process()` loop.
  `reference.md#simple-queue-pattern`.

**That in-process shape is unbounded and per-process** — no depth cap, no backpressure,
and every job in memory is lost on a pod recycle or invisible to the other replicas. For
a multi-replica service, treat Redis/BullMQ as the default, not a fallback: it persists
jobs across crashes and lets any replica claim the next one, so it doesn't have the
heap-growth risk just described at all. Only an in-process queue (single instance, jobs
cheap to lose) needs a depth-cap fix: reject above a high-water mark with `503` +
`Retry-After` instead of pushing forever. Don't bolt that 503 control onto a Redis/BullMQ
queue — it guards against a different failure mode (heap OOM) than the one an external
queue actually has (rising latency as depth grows, not process death); alert on queue
depth instead (e.g. BullMQ's `getWaitingCount()`).

A serverless deployment (a common target for a Next.js route) makes the in-process shape
worse: the function can freeze or tear down the instant the handler returns. `add()`
doesn't await `process()`, so a job already dequeued can be frozen mid-execution —
started but not guaranteed to finish. Worse, a job added while the queue is already busy
(e.g. a second request landing on the same warm instance before the first drains) sits
untouched in the array until the loop reaches it — if the environment tears down first,
that job can fail to ever start. Either way, that's a stronger reason to reach for
Redis/BullMQ here than heap growth alone.

## Logging & Monitoring

- **Structured logging** — a small `Logger` class emitting JSON log lines with request
  context. `reference.md#structured-logging`.

**Remember**: Backend patterns enable scalable, maintainable server-side applications.
Choose patterns that fit your complexity level.

## Related

- Agent: `performance-optimizer` - once a bottleneck beyond N+1/indexing/pool-sizing is
  confirmed, for the deeper algorithmic fix (heap, sliding window, binary search) around it

## Verify before use

1. Before adopting any pattern, verify it against your system's real load and failure modes.
   Patterns drift from your constraints; if a pattern's stated trade-off fails under your load, avoid it — never adopt a pattern unverified against the failure mode it claims to solve.
