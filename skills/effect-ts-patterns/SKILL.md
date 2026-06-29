---
name: effect-ts-patterns
description: "Effect-ts patterns: Effect<A,E,R> type, Effect.gen, Layer DI, Schema validation, fiber concurrency, and @effect/platform HTTP. For typed-effect-system codebases. Use when building or maintaining Effect-ts applications in TypeScript. Don't use for vanilla Promise/async codebases without Effect."
metadata:
  origin: kbg
  tathep_projects:
    - tathep-platform-api
    - tathep-video-processing
---

# Effect-ts Patterns

## The Core Type

`Effect<A, E, R>` — three type parameters:

- **A** — success value type
- **E** — expected/typed errors (recoverable)
- **R** — requirements (services the effect needs from its environment)

`Effect<User, UserNotFound, Database>` means: produces a `User`, may fail with `UserNotFound`, requires a `Database` service.

Never conflate E (typed errors) with defects (unexpected exceptions — those are `Cause<E>`).

## Effect.gen — Imperative Style

Use `Effect.gen` for sequential logic. It's like `async/await` but with typed errors:

```typescript
import { Effect } from 'effect'

const getUser = (id: string) =>
  Effect.gen(function* () {
    const db = yield* Database     // acquire service from context
    const user = yield* db.find(id)  // yield* unwraps Effect<User, NotFound, never>
    if (!user) return yield* Effect.fail(new UserNotFound({ id }))
    return user
  })
```

For pipeline style, use `pipe`:

```typescript
const result = pipe(
  Effect.succeed(42),
  Effect.map(n => n * 2),
  Effect.flatMap(n => Effect.succeed(`result: ${n}`))
)
```

## Error Handling

Errors are values in the `E` channel. Tag them with `Data.TaggedError`:

```typescript
import { Data } from 'effect'

class UserNotFound extends Data.TaggedError('UserNotFound')<{ id: string }> {}
class DatabaseError extends Data.TaggedError('DatabaseError')<{ cause: unknown }> {}

// Recover from specific error type
const safe = pipe(
  getUser('123'),
  Effect.catchTag('UserNotFound', (e) => Effect.succeed(null)),
  // DatabaseError still propagates
)

// Recover from all errors
const withFallback = Effect.orElse(getUser('123'), () => Effect.succeed(defaultUser))
```

## Layer — Dependency Injection

`Layer` constructs services and wires their dependencies. Never pass services as function arguments — inject via Layer:

```typescript
import { Effect, Layer, Context } from 'effect'

// Define service interface
class Database extends Context.Tag('Database')<Database, {
  find: (id: string) => Effect.Effect<User | null, DatabaseError>
  save: (user: User) => Effect.Effect<void, DatabaseError>
}>() {}

// Implement
const DatabaseLive = Layer.effect(
  Database,
  Effect.gen(function* () {
    const config = yield* DatabaseConfig
    const pool = yield* Effect.tryPromise(() => createPool(config.url))
    return {
      find: (id) => Effect.tryPromise({ try: () => pool.query(...), catch: (e) => new DatabaseError({ cause: e }) }),
      save: (user) => Effect.tryPromise({ try: () => pool.save(user), catch: (e) => new DatabaseError({ cause: e }) }),
    }
  })
)

// Compose layers
const AppLayer = Layer.provide(DatabaseLive, DatabaseConfigLive)

// Run with layers
Effect.runPromise(pipe(myEffect, Effect.provide(AppLayer)))
```

## Schema — Runtime Validation

`Schema` is NOT just types — it validates and parses at runtime:

```typescript
import { Schema } from 'effect'

const UserSchema = Schema.Struct({
  id: Schema.UUID,
  email: Schema.String.pipe(Schema.pattern(/^[^@]+@[^@]+$/)),
  age: Schema.Int.pipe(Schema.between(0, 150)),
  role: Schema.Literal('admin', 'user'),
})

type User = Schema.Schema.Type<typeof UserSchema>

// Parse (throws ParseError in E channel on failure)
const parseUser = Schema.decodeUnknown(UserSchema)
// Encode back to plain object
const encodeUser = Schema.encodeUnknown(UserSchema)

// In an Effect.gen context:
const user = yield* parseUser(rawInput)
```

## Fiber Concurrency

```typescript
import { Effect, Fiber } from 'effect'

// Run concurrently, wait for both
const [a, b] = yield* Effect.all([fetchA, fetchB], { concurrency: 'unbounded' })

// Race — first to succeed wins, other is interrupted
const result = yield* Effect.race(fetchFromCacheEffect, fetchFromDbEffect)

// Fork and forget (background)
const fiber = yield* Effect.fork(backgroundTask)
// Later: yield* Fiber.await(fiber) or yield* Fiber.interrupt(fiber)

// Parallel with controlled concurrency
const results = yield* Effect.forEach(ids, fetchUser, { concurrency: 5 })
```

## @effect/platform — HTTP

```typescript
import { HttpClient, HttpClientRequest, HttpClientResponse } from '@effect/platform'

const fetchUser = (id: string) =>
  Effect.gen(function* () {
    const client = yield* HttpClient.HttpClient
    const response = yield* client.get(`/users/${id}`)
    const user = yield* HttpClientResponse.schemaBodyJson(UserSchema)(response)
    return user
  })

// HTTP server
import { HttpRouter, HttpServer, HttpServerResponse } from '@effect/platform'

const router = HttpRouter.empty.pipe(
  HttpRouter.get('/users/:id', Effect.gen(function* () {
    const params = yield* HttpRouter.params
    const user = yield* getUser(params.id)
    return yield* HttpServerResponse.json(user)
  }))
)
```

## Running Effects

```typescript
// One-shot (Promise interop)
const result = await Effect.runPromise(myEffect.pipe(Effect.provide(AppLayer)))

// With exit (never throws)
const exit = await Effect.runPromiseExit(myEffect)

// Synchronous (only for pure/sync effects)
const value = Effect.runSync(Effect.succeed(42))
```

## Common Pitfalls

- **R must be satisfied** — if `R` is not `never`, the effect cannot run. Always `Effect.provide(layer)` before `runPromise`.
- **`yield*` not `yield`** — in `Effect.gen`, always use `yield*` (not `yield`). `yield` gives you the raw `Effect` object, not its value.
- **`Effect.try` vs `Effect.tryPromise`** — use `try` for sync throws, `tryPromise` for async Promises.
- **Layer sharing** — `Layer.memoize` (default) means a service is constructed once per layer composition. If you need fresh instances, use `Layer.fresh`.
- **`Data.TaggedError` _tag field** — `_tag` is automatically set to the class name. Use `Effect.catchTag('MyError', ...)` — the string must match exactly.
- **Schema vs Type** — `Schema.Schema.Type<typeof S>` gives the TS type; `Schema.decodeUnknown(S)` validates at runtime. They are different concerns.
