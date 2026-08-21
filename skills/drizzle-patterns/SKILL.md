---
name: drizzle-patterns
description: "Drizzle ORM patterns: schema, type inference, migrations, query builder, relations, transactions. Use when building Drizzle apps on PostgreSQL/SQLite. Don't use for Prisma or TypeORM."
bucket: patterns
metadata:
  origin: kbg
model: inherit
effort: high
---

# Drizzle ORM Patterns

## Schema Definition

Schema is TypeScript code — not a config file. One schema file per table or feature area:

```typescript
import { pgTable, uuid, varchar, integer, timestamp, boolean, index, pgEnum } from 'drizzle-orm/pg-core'

export const statusEnum = pgEnum('status', ['pending', 'active', 'archived'])

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: varchar('email', { length: 255 }).notNull().unique(),
  name: varchar('name', { length: 100 }).notNull(),
  status: statusEnum('status').notNull().default('pending'),
  age: integer('age'),
  emailVerified: boolean('email_verified').notNull().default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
// Array-return form for the third argument — the current documented pattern.
// The older object-return form (`(table) => ({ emailIdx: ... })`) still
// compiles but triggers a deprecation warning since drizzle-orm v0.36.0.
}, (t) => [
  index('users_email_idx').on(t.email),
  index('users_status_created_idx').on(t.status, t.createdAt),
])

// Type inference — use these instead of writing types manually
export type User = typeof users.$inferSelect
export type NewUser = typeof users.$inferInsert
```

## Drizzle Client Setup

```typescript
import { drizzle } from 'drizzle-orm/node-postgres'  // or 'drizzle-orm/bun-sqlite'
import { Pool } from 'pg'
import * as schema from './schema'

const pool = new Pool({ connectionString: process.env.DATABASE_URL })
export const db = drizzle(pool, { schema })
```

For Bun with PostgreSQL:

```typescript
import { drizzle } from 'drizzle-orm/bun-sql'
import { SQL } from 'bun'

const sql = new SQL(process.env.DATABASE_URL!)
export const db = drizzle(sql, { schema })
```

## Query Builder

Drizzle queries look like SQL — no magic ORM abstractions:

```typescript
import { eq, and, or, gt, lt, gte, like, inArray, isNull, desc, asc, count, sql } from 'drizzle-orm'

// Select
const users = await db.select().from(usersTable)
const user = await db.select().from(usersTable).where(eq(usersTable.id, id)).limit(1)

// Select specific columns (reduces data transfer)
const names = await db.select({ id: usersTable.id, email: usersTable.email }).from(usersTable)

// Insert
const [user] = await db.insert(usersTable).values({ email, name }).returning()

// Update
const [updated] = await db.update(usersTable)
  .set({ name: 'new name', updatedAt: new Date() })
  .where(eq(usersTable.id, id))
  .returning()

// Delete
await db.delete(usersTable).where(eq(usersTable.id, id))

// Upsert
await db.insert(usersTable)
  .values({ id, email, name })
  .onConflictDoUpdate({ target: usersTable.id, set: { name, updatedAt: new Date() } })
```

## Joins

No magic — write SQL-style joins:

```typescript
const result = await db
  .select({
    user: usersTable,
    post: { id: postsTable.id, title: postsTable.title },
  })
  .from(usersTable)
  .leftJoin(postsTable, eq(postsTable.userId, usersTable.id))
  .where(eq(usersTable.status, 'active'))
  .orderBy(desc(usersTable.createdAt))
  .limit(20)
  .offset(page * 20)
```

## Relations (Separate from Foreign Keys)

`relations()` is a runtime helper for typed relational queries — it does NOT create DB constraints:

```typescript
import { relations } from 'drizzle-orm'

export const usersRelations = relations(usersTable, ({ many }) => ({
  posts: many(postsTable),
}))

export const postsRelations = relations(postsTable, ({ one, many }) => ({
  author: one(usersTable, { fields: [postsTable.userId], references: [usersTable.id] }),
  comments: many(commentsTable),
}))

// Query with relations (requires schema passed to drizzle())
const usersWithPosts = await db.query.usersTable.findMany({
  with: { posts: { with: { comments: true } } },
  where: eq(usersTable.status, 'active'),
  limit: 10,
})
```

**Why `with` matters — avoiding N+1:** fetching users, then querying `postsTable` per user in a
loop (`for (const u of users) { u.posts = await db.select().from(postsTable).where(eq(postsTable.userId, u.id)) }`)
issues one query per row — N+1 round trips for N users. The relational query API above resolves
the same data as exactly one SQL query total, no matter how deep the `with` nesting goes — Drizzle
compiles it into a `LEFT JOIN LATERAL` with JSON aggregation (Postgres, standard MySQL) or
correlated subquery-selects (SQLite, PlanetScale MySQL, TiDB — dialects without `LATERAL`), never
one query per relation depth. Prefer `with` over a manual per-row loop whenever fetching a parent
and its children together —
a plain `leftJoin` also avoids N+1, but returns one duplicated parent row per child, so it still
needs an app-side group-by to reassemble the nested shape `with` gives you directly.

## Transactions

```typescript
const result = await db.transaction(async (tx) => {
  const [user] = await tx.insert(usersTable).values({ email }).returning()
  await tx.insert(profilesTable).values({ userId: user.id })
  return user
  // rollback automatically on throw
})

// Nested transactions (savepoints)
await db.transaction(async (tx) => {
  try {
    await tx.transaction(async (innerTx) => {
      await innerTx.insert(logsTable).values({ event: 'start' })
      throw new Error('inner fail')  // rolls back innerTx only
    })
  } catch {}
  await tx.insert(usersTable).values({ email })  // outer tx still active
})
```

## Dynamic Queries

```typescript
const query = db.select().from(usersTable).$dynamic()

if (filter.status) {
  query.where(eq(usersTable.status, filter.status))
}
if (filter.search) {
  query.where(like(usersTable.email, `%${filter.search}%`))
}

const users = await query.limit(20)
```

## Prepared Statements

Prepared statements skip query parsing on repeat calls:

```typescript
const getUserById = db.select().from(usersTable)
  .where(eq(usersTable.id, sql.placeholder('id')))
  .prepare('get_user_by_id')

const user = await getUserById.execute({ id: '123' })
```

## Migrations (drizzle-kit)

```bash
# drizzle.config.ts
export default defineConfig({
  schema: './src/db/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
})

# Generate migration from schema changes
npx drizzle-kit generate

# Push schema directly (dev only — destructive, skips migration files)
npx drizzle-kit push

# Apply pending migrations
npx drizzle-kit migrate

# Open Drizzle Studio (visual DB browser)
npx drizzle-kit studio
```

Apply migrations in code (e.g., on startup):

```typescript
import { migrate } from 'drizzle-orm/node-postgres/migrator'
await migrate(db, { migrationsFolder: './drizzle' })
```

## Common Pitfalls

- **`push` vs `generate + migrate`** — `push` directly applies schema changes (no migration files), suitable for dev only. In production, always use `generate` + `migrate` for auditable, reversible migrations.
- **Relations are NOT foreign keys** — `relations()` only affects query builder behavior. Add actual FK constraints in the schema definition (`references()`).
- **Returning clause required for insert result** — `db.insert(...).values(...).returning()` returns an array. Without `.returning()`, insert returns no rows.
- **`.$inferSelect` vs `.$inferInsert`** — infer types from schema, not manually. `$inferInsert` makes all fields with defaults optional.
- **Drizzle Studio port** — defaults to port 4983. Don't confuse with the app dev server.
- **N+1 queries from a manual loop** — `for (const u of users) { await db.select()...where(eq(t.userId, u.id)) }` issues one query per row. Use `with` (relational queries), or batch with `inArray(t.userId, ids)` + an app-side group-by; a `leftJoin` also avoids N+1 but duplicates the parent row per child, so it needs that same app-side grouping step.

## Verify before use

1. Before applying, verify any pattern against Drizzle's current docs.
   APIs drift across versions; if one has moved, the Common Pitfalls above name where each silently fails — never copy unverified, avoid drift by checking the changelog.
