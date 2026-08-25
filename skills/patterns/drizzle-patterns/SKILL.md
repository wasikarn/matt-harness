---
name: drizzle-patterns
description: "Drizzle ORM patterns: schema, type inference, migrations, query builder, relations, transactions. Use when building Drizzle apps on PostgreSQL/SQLite. Don't use for Prisma or TypeORM."
metadata:
  origin: kbg
model: inherit
effort: high
---

# Drizzle ORM Patterns

## Pattern Map

Full code for every pattern below lives in `reference.md` — this file carries the trigger and
the decision rule; load the reference section when actually writing the code:

- **Schema definition** — schema is TypeScript, one file per table/feature area; array-return
  form for the index callback (object-return deprecated since drizzle-orm v0.36.0); infer types
  via `$inferSelect`/`$inferInsert`, never hand-write them. `reference.md#schema-definition`.
- **Client setup** — `drizzle(pool, { schema })`; Bun uses `drizzle-orm/bun-sql` with Bun's own
  `SQL` client. Passing `schema` is what enables `db.query.*` relational queries.
  `reference.md#drizzle-client-setup`.
- **Query builder** — SQL-shaped select/insert/update/delete/upsert; select explicit columns to
  cut transfer; `.returning()` to get rows back. `reference.md#query-builder`.
- **Joins** — explicit SQL-style `leftJoin` with a shaped select object.
  `reference.md#joins`.
- **Relations** — `relations()` is a runtime query helper, NOT a DB constraint; `with` resolves
  nested data as exactly one SQL query (`LEFT JOIN LATERAL` + JSON aggregation on Postgres/MySQL,
  correlated subqueries on SQLite/PlanetScale/TiDB), so prefer it over per-row loops (N+1) — a
  plain `leftJoin` also avoids N+1 but duplicates the parent row per child and needs app-side
  grouping. `reference.md#relations-separate-from-foreign-keys`.
- **Transactions** — `db.transaction(async (tx) => ...)`, auto-rollback on throw; nested
  transactions are savepoints (inner rollback leaves the outer active).
  `reference.md#transactions`.
- **Dynamic queries** — `.$dynamic()` for conditionally-built where chains.
  `reference.md#dynamic-queries`.
- **Prepared statements** — `sql.placeholder` + `.prepare()` to skip parsing on repeat calls.
  `reference.md#prepared-statements`.
- **Migrations** — `drizzle-kit generate` + `migrate` for production (auditable, reversible);
  `push` is dev-only and destructive; apply-on-startup via the `migrate()` helper.
  `reference.md#migrations-drizzle-kit`.

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
