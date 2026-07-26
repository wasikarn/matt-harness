---
name: backend-patterns
description: Backend architecture, API design, and DB optimization for Node.js/Next.js — the kept TS/backend base. Use when building a Node/TS backend. Don't use for Python/Go/Rust backends.
metadata:
  origin: ECC
---

# Backend Development Patterns

Backend architecture patterns and best practices for scalable server-side applications.

## When to Activate

- Designing REST API endpoints
- Implementing repository, service, or controller layers
- Optimizing database queries (N+1, indexing, connection pooling)
- Adding caching (Redis, in-memory, HTTP cache headers)
- Setting up background jobs or async processing
- Structuring error handling and validation for APIs
- Building middleware (auth, logging, rate limiting)

## API Design Patterns

### RESTful API Structure

```typescript
// PASS: Resource-based URLs
GET    /api/markets                 # List resources
GET    /api/markets/:id             # Get single resource
POST   /api/markets                 # Create resource
PUT    /api/markets/:id             # Replace resource
PATCH  /api/markets/:id             # Update resource
DELETE /api/markets/:id             # Delete resource

// PASS: Query parameters for filtering, sorting, pagination
GET /api/markets?status=active&sort=volume&limit=20&offset=0
```

### Repository Pattern

```typescript
// Abstract data access logic
interface MarketRepository {
  findAll(filters?: MarketFilters): Promise<Market[]>
  findById(id: string): Promise<Market | null>
  findByIds(ids: string[]): Promise<Market[]>
  create(data: CreateMarketDto): Promise<Market>
  update(id: string, data: UpdateMarketDto): Promise<Market>
  delete(id: string): Promise<void>
}

class SupabaseMarketRepository implements MarketRepository {
  async findAll(filters?: MarketFilters): Promise<Market[]> {
    let query = supabase.from('markets').select('*')

    if (filters?.status) {
      query = query.eq('status', filters.status)
    }

    if (filters?.limit) {
      query = query.limit(filters.limit)
    }

    const { data, error } = await query

    if (error) throw new Error(error.message)
    return data
  }

  // Other methods...
}
```

### Service Layer Pattern

```typescript
// Business logic separated from data access
class MarketService {
  constructor(private marketRepo: MarketRepository) {}

  async searchMarkets(query: string, limit: number = 10): Promise<Market[]> {
    // Business logic
    const embedding = await generateEmbedding(query)
    const results = await this.vectorSearch(embedding, limit)

    // Fetch full data
    const markets = await this.marketRepo.findByIds(results.map(r => r.id))

    // Sort by similarity, highest score first — scoreB - scoreA, not the
    // other way round, or unmatched markets (defaulted to 0) sort to the front
    return markets.sort((a, b) => {
      const scoreA = results.find(r => r.id === a.id)?.score || 0
      const scoreB = results.find(r => r.id === b.id)?.score || 0
      return scoreB - scoreA
    })
  }

  private async vectorSearch(
    embedding: number[],
    limit: number
  ): Promise<Array<{ id: string; score: number }>> {
    // Vector search implementation
    return []
  }
}
```

### Middleware Pattern

```typescript
// Request/response processing pipeline — App Router route handler wrapper.
// (A Pages Router API middleware wraps (req, res) instead of returning a
// Response; every other example in this file is App Router, so this one
// matches rather than mixing conventions.)
export function withAuth(
  handler: (req: Request, user: JWTPayload) => Promise<Response>
) {
  return async (req: Request): Promise<Response> => {
    const token = req.headers.get('authorization')?.replace('Bearer ', '')

    if (!token) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    // handler is async, so an error it throws surfaces as a promise
    // rejection, not a synchronous throw — `return handler(...)` without
    // await lets that rejection escape this try/catch uncaught. verifyToken
    // and handler need separate error handling for the catch below to mean
    // anything.
    let user: JWTPayload
    try {
      user = verifyToken(token)
    } catch (error) {
      return NextResponse.json({ error: 'Invalid token' }, { status: 401 })
    }

    return handler(req, user)
  }
}

// Usage
export const GET = withAuth(async (req, user) => {
  // Handler receives the authenticated user
  return NextResponse.json({ success: true })
})
```

## Database Patterns

### Query Optimization

```typescript
// PASS: GOOD: Select only needed columns
const { data } = await supabase
  .from('markets')
  .select('id, name, status, volume')
  .eq('status', 'active')
  .order('volume', { ascending: false })
  .limit(10)

// FAIL: BAD: Select everything
const { data } = await supabase
  .from('markets')
  .select('*')
```

### N+1 Query Prevention

```typescript
// FAIL: BAD: N+1 query problem
const markets = await getMarkets()
for (const market of markets) {
  market.creator = await getUser(market.creator_id)  // N queries
}

// PASS: GOOD: Batch fetch
const markets = await getMarkets()
const creatorIds = markets.map(m => m.creator_id)
const creators = await getUsers(creatorIds)  // 1 query
const creatorMap = new Map(creators.map(c => [c.id, c]))

markets.forEach(market => {
  market.creator = creatorMap.get(market.creator_id)
})
```

### Indexing & Pool Sizing

For multi-column filters, one composite index beats two single-columns — Postgres bitmap-scan across two indexes is slower than one composite read. Order the composite equality-first, then range/sort, and carry the `SELECT` columns via an `INCLUDE` covering index to skip the heap fetch. For pool sizing on Supabase/Postgres, the aggregate `pool.max × instances` (node-postgres's `Pool` option, or `connection_limit` in a Prisma connection string) must stay under the server `max_connections` cap with ~20% headroom for replicas and migrations — sizing per-instance in isolation exhausts connections under multi-pod fan-out.

### Transaction Pattern

```typescript
async function createMarketWithPosition(
  marketData: CreateMarketDto,
  positionData: CreatePositionDto
) {
  // Use Supabase transaction
  const { data, error } = await supabase.rpc('create_market_with_position', {
    market_data: marketData,
    position_data: positionData
  })

  if (error) throw new Error('Transaction failed')
  return data
}

// SQL function in Supabase
CREATE OR REPLACE FUNCTION create_market_with_position(
  market_data jsonb,
  position_data jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_market_id int;
BEGIN
  -- Start transaction automatically; list columns explicitly (serial id not in payload)
  INSERT INTO markets (creator_id, question, closes_at)
    SELECT creator_id, question, closes_at FROM jsonb_populate_record(NULL::markets, market_data)
    RETURNING id INTO v_market_id;
  -- Use the id just generated, not position_data's own market_id field — the
  -- client can't know the new market's id yet, so trusting a client-supplied
  -- value here either fails a not-null/FK constraint or silently attaches
  -- the position to the wrong (pre-existing) market.
  INSERT INTO positions (market_id, user_id, side, size)
    SELECT v_market_id, user_id, side, size FROM jsonb_populate_record(NULL::positions, position_data);
  RETURN jsonb_build_object('success', true);
EXCEPTION
  WHEN OTHERS THEN
    -- Rollback happens automatically. Re-raise instead of returning a
    -- failure payload — see the note below the block.
    RAISE;
END;
$$;
```

**Don't let the exception handler swallow the failure:** an `EXCEPTION WHEN OTHERS` block that `RETURN`s a `success: false` payload completes the function *normally* from Postgres's point of view — no error propagates. `supabase.rpc()` then comes back with `error: null` and `data: { success: false, ... }`, so the TypeScript wrapper's `if (error) throw new Error(...)` never fires on the exact failure this SQL was written to catch, and `return data` hands the caller a payload that looks like success unless it separately checks `data.success`. Bare `RAISE;` inside the handler re-throws the original error so it actually reaches the caller's `error` field instead.

## Caching Strategies

### Redis Caching Layer

```typescript
class CachedMarketRepository implements MarketRepository {
  constructor(
    private baseRepo: MarketRepository,
    private redis: RedisClient
  ) {}

  async findById(id: string): Promise<Market | null> {
    // Check cache first
    const cached = await this.redis.get(`market:${id}`)

    if (cached) {
      return JSON.parse(cached)
    }

    // Cache miss - fetch from database
    const market = await this.baseRepo.findById(id)

    if (market) {
      // Cache for 5 minutes
      await this.redis.setex(`market:${id}`, 300, JSON.stringify(market))
    }

    return market
  }

  async invalidateCache(id: string): Promise<void> {
    await this.redis.del(`market:${id}`)
  }

  // Other MarketRepository methods delegate straight to baseRepo, omitted for brevity
}
```

### Cache-Aside Pattern

```typescript
async function getMarketWithCache(id: string): Promise<Market> {
  const cacheKey = `market:${id}`

  // Try cache
  const cached = await redis.get(cacheKey)
  if (cached) return JSON.parse(cached)

  // Cache miss - fetch from DB
  const market = await db.markets.findUnique({ where: { id } })

  if (!market) throw new Error('Market not found')

  // Update cache
  await redis.setex(cacheKey, 300, JSON.stringify(market))

  return market
}
```

**Stampede guard:** the snippet is textbook get-then-set with no protection on a miss — for a hot key, every concurrent request fires the DB fetch simultaneously on each TTL expiry (thundering herd). Guard the re-warm with a `SETNX` single-flight mutex (one request rebuilds, the rest wait or serve stale) or probabilistic early refresh (XFetch); without it the cache that should relieve the DB becomes the spike that kills it.

## Error Handling Patterns

### Centralized Error Handler

```typescript
class ApiError extends Error {
  constructor(
    public statusCode: number,
    public message: string,
    public isOperational = true
  ) {
    super(message)
    Object.setPrototypeOf(this, ApiError.prototype)
  }
}

export function errorHandler(error: unknown, req: Request): Response {
  if (error instanceof ApiError) {
    return NextResponse.json({
      success: false,
      error: error.message
    }, { status: error.statusCode })
  }

  if (error instanceof z.ZodError) {
    return NextResponse.json({
      success: false,
      error: 'Validation failed',
      details: error.issues  // .errors was a v3 alias, removed in Zod v4
    }, { status: 400 })
  }

  // Log unexpected errors
  console.error('Unexpected error:', error)

  return NextResponse.json({
    success: false,
    error: 'Internal server error'
  }, { status: 500 })
}

// Usage
export async function GET(request: Request) {
  try {
    const data = await fetchData()
    return NextResponse.json({ success: true, data })
  } catch (error) {
    return errorHandler(error, request)
  }
}
```

### Retry with Exponential Backoff

```typescript
async function fetchWithRetry<T>(
  fn: () => Promise<T>,
  maxRetries = 3
): Promise<T> {
  let lastError: Error

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn()
    } catch (error) {
      lastError = error as Error

      if (i < maxRetries - 1) {
        // Exponential backoff: 2^i seconds (1s, 2s, ... — attempt count bounded by maxRetries, no delay ceiling)
        const delay = Math.pow(2, i) * 1000
        await new Promise(resolve => setTimeout(resolve, delay))
      }
    }
  }

  throw lastError!
}

// Usage
const data = await fetchWithRetry(() => fetchFromAPI())
```

**Two fixes before shipping the above:** (1) add jitter — `Math.pow(2, i) * 1000 + Math.random() * 1000` — so N replicas retrying in lockstep (1s, 2s at the default `maxRetries = 3`) don't form a synchronized retry storm that re-kills the recovering dependency; (2) gate retry on idempotency — `fn` is retried unconditionally, so a POST/create that failed after the write succeeded produces a duplicate. For non-idempotent verbs require an `Idempotency-Key` header or a dedupe row before retrying.

## Authentication & Authorization

### JWT Token Validation

```typescript
import jwt from 'jsonwebtoken'

interface JWTPayload {
  userId: string
  email: string
  role: 'admin' | 'moderator' | 'user'
}

export function verifyToken(token: string): JWTPayload {
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!) as JWTPayload
    return payload
  } catch (error) {
    throw new ApiError(401, 'Invalid token')
  }
}

export async function requireAuth(request: Request) {
  const token = request.headers.get('authorization')?.replace('Bearer ', '')

  if (!token) {
    throw new ApiError(401, 'Missing authorization token')
  }

  return verifyToken(token)
}

// Usage in API route
export async function GET(request: Request) {
  const user = await requireAuth(request)

  const data = await getDataForUser(user.userId)

  return NextResponse.json({ success: true, data })
}
```

### Role-Based Access Control

```typescript
type Permission = 'read' | 'write' | 'delete' | 'admin'

// requireAuth() above returns JWTPayload — reuse it here instead of a
// separately-shaped User, or hasPermission()/requirePermission() declare an
// argument type requireAuth() can never actually produce.
type User = JWTPayload

const rolePermissions: Record<User['role'], Permission[]> = {
  admin: ['read', 'write', 'delete', 'admin'],
  moderator: ['read', 'write', 'delete'],
  user: ['read', 'write']
}

export function hasPermission(user: User, permission: Permission): boolean {
  return rolePermissions[user.role].includes(permission)
}

export function requirePermission(permission: Permission) {
  return (handler: (request: Request, user: User) => Promise<Response>) => {
    return async (request: Request) => {
      const user = await requireAuth(request)

      if (!hasPermission(user, permission)) {
        throw new ApiError(403, 'Insufficient permissions')
      }

      return handler(request, user)
    }
  }
}

// Usage - HOF wraps the handler
export const DELETE = requirePermission('delete')(
  async (request: Request, user: User) => {
    // Handler receives authenticated user with verified permission
    return new Response('Deleted', { status: 200 })
  }
)
```

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

Keep the backend layer responsible for choosing the integration point, the HTTP
contract, and the error shape; use `kbg:security-auditor` for abuse case review.

## Background Jobs & Queues

### Simple Queue Pattern

```typescript
class JobQueue<T> {
  private queue: T[] = []
  private processing = false

  async add(job: T): Promise<void> {
    this.queue.push(job)

    if (!this.processing) {
      this.process()
    }
  }

  private async process(): Promise<void> {
    this.processing = true

    while (this.queue.length > 0) {
      const job = this.queue.shift()!

      try {
        await this.execute(job)
      } catch (error) {
        console.error('Job failed:', error)
      }
    }

    this.processing = false
  }

  private async execute(job: T): Promise<void> {
    // Job execution logic
  }
}

// Usage for indexing markets
interface IndexJob {
  marketId: string
}

const indexQueue = new JobQueue<IndexJob>()

export async function POST(request: Request) {
  const { marketId } = await request.json()

  // Add to queue instead of blocking
  await indexQueue.add({ marketId })

  return NextResponse.json({ success: true, message: 'Job queued' })
}
```

**The `JobQueue` above is unbounded and per-process — no depth cap, no backpressure, and every job in memory is lost on a pod recycle or invisible to the other replicas.** For a multi-replica service, treat Redis/BullMQ as the default, not a fallback: it persists jobs across crashes and lets any replica claim the next one, so it doesn't have the heap-growth risk just described at all. Only an in-process queue (single instance, jobs cheap to lose) needs the depth-cap fix: reject above a high-water mark with `503` + `Retry-After` instead of pushing forever. Don't bolt that 503 control onto a Redis/BullMQ queue — it guards against a different failure mode (heap OOM) than the one an external queue actually has (rising latency as depth grows, not process death); alert on queue depth instead (e.g. BullMQ's `getWaitingCount()`). The `POST` handler above is a case in point: on a serverless deployment (a common target for a Next.js route like this one), the function can freeze or tear down the instant the handler returns. `add()` doesn't await `process()`, so a job already dequeued can be frozen mid-execution — started but not guaranteed to finish. Worse, a job added while the queue is already busy (e.g. a second request landing on the same warm instance before the first drains) sits untouched in the array until the loop reaches it — if the environment tears down first, that job can fail to ever start. Either way, that's a stronger reason to reach for Redis/BullMQ here than heap growth alone.

## Logging & Monitoring

### Structured Logging

```typescript
interface LogContext {
  userId?: string
  requestId?: string
  method?: string
  path?: string
  [key: string]: unknown
}

class Logger {
  log(level: 'info' | 'warn' | 'error', message: string, context?: LogContext) {
    const entry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      ...context
    }

    console.log(JSON.stringify(entry))
  }

  info(message: string, context?: LogContext) {
    this.log('info', message, context)
  }

  warn(message: string, context?: LogContext) {
    this.log('warn', message, context)
  }

  error(message: string, error: Error, context?: LogContext) {
    this.log('error', message, {
      ...context,
      error: error.message,
      stack: error.stack
    })
  }
}

const logger = new Logger()

// Usage
export async function GET(request: Request) {
  const requestId = crypto.randomUUID()

  logger.info('Fetching markets', {
    requestId,
    method: 'GET',
    path: '/api/markets'
  })

  try {
    const markets = await fetchMarkets()
    return NextResponse.json({ success: true, data: markets })
  } catch (error) {
    logger.error('Failed to fetch markets', error as Error, { requestId })
    return NextResponse.json({ error: 'Internal error' }, { status: 500 })
  }
}
```

**Remember**: Backend patterns enable scalable, maintainable server-side applications. Choose patterns that fit your complexity level.

## Verify before use

1. Before adopting any pattern, verify it against your system's real load and failure modes.
   Patterns drift from your constraints; if a pattern's stated trade-off fails under your load, avoid it — never adopt a pattern unverified against the failure mode it claims to solve.
