---
name: adonisjs-patterns
description: "AdonisJS v5 patterns: IoC container, Lucid ORM (ActiveRecord), Japa tests, VineJS validation, middleware, auth guards, and ace CLI commands."
metadata:
  origin: kbg
  tathep_projects:
    - tathep-platform-api
    - bluedragon-eye-analytics-api
---

# AdonisJS v5 Patterns

## IoC Container

AdonisJS uses constructor injection — not factory functions. Always use `@inject()` on classes that receive services:

```typescript
import { inject } from '@adonisjs/core'

@inject()
export class UserService {
  constructor(private db: Database) {}
}
```

Register singletons in a service provider (`providers/app_provider.ts`):

```typescript
app.container.singleton(UserService, () => new UserService())
```

## Lucid ORM (ActiveRecord)

Lucid is ActiveRecord — the model IS the query builder. This differs from Drizzle/Prisma DataMapper pattern.

```typescript
// Define
class User extends BaseModel {
  @column({ isPrimary: true }) declare id: number
  @column() declare email: string
  @column.dateTime({ autoCreate: true }) declare createdAt: DateTime

  @hasMany(() => Post) declare posts: HasMany<typeof Post>
}

// Query
const user = await User.findOrFail(id)
const users = await User.query().where('active', true).preload('posts').paginate(page, 20)

// Create/Update
const user = await User.create({ email, name })
await user.merge({ name: 'new' }).save()
```

Transactions wrap via `db.transaction`:

```typescript
const trx = await db.transaction()
try {
  const user = await User.create({ email }, { client: trx })
  await trx.commit()
} catch {
  await trx.rollback()
}
```

## Japa Test Runner

AdonisJS uses Japa, not Jest or Vitest. Tests live in `tests/`.

```typescript
// tests/unit/user_service.spec.ts
import { test } from '@japa/runner'

test.group('UserService', (group) => {
  group.each.setup(async () => {
    await resetDatabase()
  })

  test('creates user', async ({ assert }) => {
    const user = await UserService.create({ email: 'a@b.com' })
    assert.equal(user.email, 'a@b.com')
  })
})

// HTTP tests use the client fixture
test('GET /users', async ({ client }) => {
  const response = await client.get('/users').loginAs(adminUser)
  response.assertStatus(200)
  response.assertBodyContains({ data: [] })
})
```

Run: `node ace test` or `node ace test --files=tests/unit/**.spec.ts`

## VineJS Validation

Validators live in `app/validators/`. Always validate at the controller boundary:

```typescript
import vine from '@vinejs/vine'

export const createUserValidator = vine.compile(
  vine.object({
    email: vine.string().email().normalizeEmail(),
    name: vine.string().minLength(2).maxLength(100),
    role: vine.enum(['admin', 'user']),
  })
)

// In controller
async store({ request }: HttpContext) {
  const data = await request.validateUsing(createUserValidator)
  return User.create(data)
}
```

## Middleware

Three layers: global (kernel), named (route), inline. Apply in `start/kernel.ts`:

```typescript
// Named middleware (applied per-route)
export const middleware = router.named({
  auth: () => import('#middleware/auth_middleware'),
  throttle: () => import('#middleware/throttle_middleware'),
})

// Route usage
router.get('/dashboard', [DashboardController]).use(middleware.auth())
```

Middleware signature:

```typescript
export default class AuthMiddleware {
  async handle({ auth, response }: HttpContext, next: NextFn) {
    await auth.authenticate()  // throws if unauthenticated
    await next()
  }
}
```

## Auth Guards

AdonisJS auth supports multiple guards per-request:

```typescript
// start/auth.ts
const authConfig = defineConfig({
  default: 'web',
  guards: {
    web: sessionGuard({ useRememberMeTokens: false }),
    api: tokensGuard({ provider: tokens.dbTokensProvider({ model: () => import('#models/user') }) }),
  },
})

// Controller — check guard explicitly
async show({ auth }: HttpContext) {
  const user = await auth.use('api').authenticate()
  // or: await auth.authenticateUsing(['web', 'api'])
}
```

## Ace CLI

Common commands:

```bash
node ace make:controller users --resource   # CRUD controller
node ace make:model user -m                 # model + migration
node ace make:migration create_users_table
node ace make:validator create_user
node ace make:middleware auth
node ace migration:run                      # apply migrations
node ace migration:rollback
node ace db:seed                            # run seeders
```

## Common Pitfalls

- **Lucid preload is eager** — `preload()` always runs a second query; it is NOT a JOIN. For JOINs, use `query().join()` explicitly.
- **`findOrFail` vs `find`** — `findOrFail` throws `ModelNotFoundException` (auto-converted to 404); `find` returns `null`.
- **Container bindings are lazy** — a binding registered in `boot()` is not resolved until first use.
- **`@column.dateTime`** — always use `DateTime` (from Luxon) not `Date`. Lucid serializes/deserializes via Luxon automatically.
- **Japa `client` fixture** — requires `apiClient` plugin. Must be in `tests/bootstrap.ts` plugins array.
- **Migration file naming** — must match `YYYYMMDDHHMMSS_description.ts`; ace generates this automatically.
