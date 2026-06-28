---
name: hono-patterns
description: Hono web framework patterns: typed routing, Zod validation, middleware, RPC client, context variables, and Bun/Node runtime adapters.
metadata:
  origin: kbg
  tathep_projects:
    - tathep-video-processing
---

# Hono Patterns

## App Setup and Routing

```typescript
import { Hono } from 'hono'

// Type the context variables for type-safe c.var access
type Variables = {
  userId: string
  db: Database
}

const app = new Hono<{ Variables: Variables }>()

// Basic routes
app.get('/health', (c) => c.json({ status: 'ok' }))
app.post('/users', async (c) => {
  const body = await c.req.json()
  return c.json({ created: body }, 201)
})

// Path params
app.get('/users/:id', (c) => {
  const id = c.req.param('id')
  return c.json({ id })
})

// Route groups
const usersRouter = new Hono<{ Variables: Variables }>()
usersRouter.get('/', listUsers)
usersRouter.post('/', createUser)
usersRouter.get('/:id', getUser)

app.route('/users', usersRouter)
```

## Validation with Zod

```typescript
import { zValidator } from '@hono/zod-validator'
import { z } from 'zod'

const createUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(2).max(100),
  role: z.enum(['admin', 'user']),
})

app.post('/users',
  zValidator('json', createUserSchema),
  async (c) => {
    const data = c.req.valid('json')  // type-safe, validated
    const user = await createUser(data)
    return c.json(user, 201)
  }
)

// Validate query params
const querySchema = z.object({
  page: z.coerce.number().default(1),
  limit: z.coerce.number().max(100).default(20),
  status: z.enum(['active', 'inactive']).optional(),
})

app.get('/users', zValidator('query', querySchema), async (c) => {
  const { page, limit, status } = c.req.valid('query')
  return c.json(await listUsers({ page, limit, status }))
})
```

## Middleware

Middleware runs in registration order. Use `app.use()` for global, or inline for route-specific:

```typescript
import { logger } from 'hono/logger'
import { cors } from 'hono/cors'
import { bearerAuth } from 'hono/bearer-auth'

// Global middleware
app.use('*', logger())
app.use('*', cors({ origin: process.env.ALLOWED_ORIGIN }))

// Auth middleware — injects userId into context
app.use('/api/*', async (c, next) => {
  const token = c.req.header('Authorization')?.replace('Bearer ', '')
  if (!token) return c.json({ error: 'Unauthorized' }, 401)
  const userId = await verifyToken(token)
  c.set('userId', userId)   // now available as c.var.userId in handlers
  await next()
})

// Route-specific
app.post('/admin/actions',
  bearerAuth({ token: process.env.ADMIN_TOKEN! }),
  adminHandler
)
```

## Context Variables Pattern

Inject services once in middleware, access anywhere:

```typescript
// Inject DB in middleware
app.use('*', async (c, next) => {
  c.set('db', db)  // set typed variable
  await next()
})

// Use in handler — fully typed
app.get('/users/:id', async (c) => {
  const db = c.var.db        // type-safe: Database
  const userId = c.var.userId
  const user = await db.users.findById(c.req.param('id'))
  return user ? c.json(user) : c.json({ error: 'Not found' }, 404)
})
```

## RPC Client

Hono's RPC generates a fully typed client from route definitions — no schema duplication:

```typescript
// server: routes/users.ts
import { Hono } from 'hono'
const users = new Hono()
  .get('/:id', async (c) => {
    return c.json({ id: c.req.param('id'), name: 'Alice' })
  })
  .post('/', zValidator('json', createUserSchema), async (c) => {
    const data = c.req.valid('json')
    return c.json({ ...data, id: 'new-id' }, 201)
  })

export type UsersRoutes = typeof users
export default users

// client: anywhere in frontend or another service
import { hc } from 'hono/client'
import type { UsersRoutes } from '../server/routes/users'

const client = hc<UsersRoutes>('http://localhost:3000')

const response = await client.users[':id'].$get({ param: { id: '123' } })
const user = await response.json()  // fully typed
```

## Error Handling

```typescript
app.onError((err, c) => {
  if (err instanceof ValidationError) {
    return c.json({ error: err.message, details: err.issues }, 400)
  }
  if (err instanceof NotFoundError) {
    return c.json({ error: 'Not found' }, 404)
  }
  console.error(err)
  return c.json({ error: 'Internal server error' }, 500)
})

app.notFound((c) => c.json({ error: `Route ${c.req.path} not found` }, 404))
```

## Runtime Adapters

```typescript
// Bun (direct — no adapter needed)
export default app   // Bun uses the default export directly
// bun run server.ts — Bun detects Hono's fetch handler

// Node.js
import { serve } from '@hono/node-server'
serve({ fetch: app.fetch, port: 3000 })

// With graceful shutdown (Bun)
const server = Bun.serve({ port: 3000, fetch: app.fetch })
process.on('SIGTERM', () => server.stop())
```

## Testing

```typescript
import { testClient } from 'hono/testing'

const client = testClient(app)

// Type-safe test calls without running a server
const res = await client.users.$get()
expect(res.status).toBe(200)
const body = await res.json()
expect(body).toMatchObject({ users: expect.any(Array) })
```

## Common Pitfalls

- **`c.req.json()` vs `c.req.valid('json')`** — `json()` is raw (unvalidated), `valid()` returns the Zod-parsed output. Always use `valid()` in validated routes.
- **Middleware order** — `app.use()` runs in registration order. Auth middleware must be registered before the routes it protects.
- **`c.set()` type inference** — the `Variables` generic on `new Hono<{ Variables: ... }>()` must be consistent across the app and sub-routers. A sub-router without the generic loses type safety on `c.var`.
- **RPC export type** — the RPC client type is `typeof router`, NOT the Hono instance type. Export `type AppType = typeof app` from the entry file.
- **`app.route()` strips base path** — when a sub-router is mounted at `/users`, the sub-router's handlers receive paths relative to `/users` (e.g., `/:id` not `/users/:id`).
