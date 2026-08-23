---
name: mysql-patterns
description: MySQL/MariaDB schema, query, indexing, transaction, replication, and pool patterns. Use when designing or troubleshooting MySQL/MariaDB. Don't use for non-MySQL databases.
bucket: patterns
metadata:
  origin: ECC
model: inherit
effort: high
---

# MySQL Patterns

Use this skill when working on MySQL or MariaDB schema design, migrations,
slow-query investigation, queue-style transactions, connection pools, or
production database configuration. Prefer exact version checks before applying a
feature-specific pattern because MySQL and MariaDB have diverged in several SQL
details.

## Live Docs

For current MySQL/MariaDB syntax (window functions, JSON, generated columns, replication), see the [MySQL docs](https://dev.mysql.com/doc/) or MariaDB equivalent via context7.

## Activation

- Designing MySQL or MariaDB tables, indexes, and constraints
- Reviewing migrations before they run on large production tables
- Debugging slow queries, lock waits, deadlocks, or connection exhaustion
- Adding keyset pagination, upserts, full-text search, JSON columns, or queues
- Configuring application connection pools, read replicas, TLS, or slow logs

## Version Check

Identify the engine and version before applying patterns. Key differences:

- MySQL documents row aliases as the replacement for `VALUES(col)` in
  `ON DUPLICATE KEY UPDATE`; `VALUES(col)` is deprecated there.
- MariaDB documents `VALUES(col)` as the supported way to reference inserted
  values in `ON DUPLICATE KEY UPDATE`; use it for cross-engine compatibility.
- `SKIP LOCKED` is appropriate for queue-like work only. It skips locked rows
  and can return an inconsistent view, so do not use it for general accounting
  or integrity-sensitive reads.

## Schema Defaults

| Use Case | Prefer | Avoid |
| --- | --- | --- |
| Surrogate primary keys | `BIGINT UNSIGNED AUTO_INCREMENT` | `INT` for tables that can grow beyond 2B rows |
| UUID lookup keys | `BINARY(16)` with conversion helpers | `VARCHAR(36)` primary keys on hot tables |
| Money and exact quantities | `DECIMAL(p, s)` | `FLOAT` or `DOUBLE` |
| User-facing text | `utf8mb4` tables and indexes | MySQL `utf8` / `utf8mb3` defaults |
| Application timestamps | `DATETIME` with UTC managed by the app | Assuming `DATETIME` stores time zone metadata |
| Soft deletes | `deleted_at DATETIME NULL` plus scoped indexes | Filtering soft-deleted rows without an index |
| Extensible status values | lookup table or constrained `VARCHAR` | `ENUM` when values change often |

## Indexing

Composite index order usually follows equality predicates first, then range/sort columns. Use `EXPLAIN` before adding or changing an index to detect:

**Signals to investigate:**

| Field | Risk Signal |
| --- | --- |
| `type` | `ALL` on a large table |
| `key` | `NULL` when a selective predicate exists |
| `rows` | Very high row estimate for an interactive path |
| `Extra` | `Using temporary`, `Using filesort`, or broad `Using where` |

Avoid adding indexes blindly. Each index adds write cost, migration time,
backup size, and buffer-pool pressure.

**Target `Using index` in `Extra`, not just the absence of bad signals** — a covering composite carrying the `SELECT`ed columns serves the query index-only, skipping the clustered-key lookup (one I/O per row saved); one covering composite beats two single-column indexes (avoids `index_merge`). **Before adding an index for a full scan, check the predicate first**: `WHERE YEAR(col) = ?` / `WHERE LOWER(col) = ?` defeats an existing index (non-sargable — rewrite as a range or bare-column equality); a string-vs-int-literal comparison triggers implicit coercion and a scan. Fix the predicate, not the index.

## Pattern Map

Full SQL/code for every pattern below lives in `reference.md` — this file carries the trigger
and the decision rule; load the reference section when actually writing the SQL/config:

- **Upsert** — `VALUES(col)` form for MariaDB or mixed fleets; MySQL row-alias form only after
  confirming the target is MySQL. `reference.md#upsert`.
- **Keyset pagination** — `(created_at, id)` cursor + matching composite index; never deep
  `OFFSET` on large tables (scans and discards rows). `reference.md#keyset-pagination`.
- **JSON fields** — JSON for extension data only; index frequently-queried paths via STORED
  generated columns; keep FKs/ownership/tenancy/lifecycle relational. `reference.md#json-fields`.
- **Full-text search** — built-in `FULLTEXT` first; external search only for typo tolerance,
  complex ranking, cross-table facets, or language analysis. `reference.md#full-text-search`.
- **Transactions** — short transactions, deterministic lock order, external calls outside the
  transaction; deadlock checklist and the isolation-level rule (`READ COMMITTED` on insert-heavy
  hot paths where phantom reads are tolerable — default `REPEATABLE READ` gap locks serialize
  concurrent inserts; keep RR for integrity-sensitive read-modify-write; check isolation before
  blaming missing-index/lock-ordering for insert stalls). `SKIP LOCKED` queue-claim shape:
  queue-like workloads only, never general consistency. `reference.md#transactions`.
- **Connection pools** — SQLAlchemy/mysql2 configs; recycle below server `wait_timeout` +
  pre-ping; bound the **aggregate**: `(pool_size + max_overflow) × instances < max_connections`
  with ~20% headroom, sized down from the server cap. `reference.md#connection-pools`.
- **Diagnostics** — first-pass `SHOW` commands, slow-log enablement; `EXPLAIN ANALYZE` executes
  the query — only when safe on production-sized data. `reference.md#diagnostics`.
- **Replication** — never route read-your-own-write/checkout/permission/idempotency reads to a
  lagging replica; before pinning reads to primary, tune parallel apply
  (`replica_parallel_workers` + `LOGICAL_CLOCK`, primary `WRITESET` dependency tracking; MariaDB
  uses `slave_parallel_mode=optimistic`) — pinning is the fallback, not the first move.
  Monitor SQL/IO thread health and lag, not TCP liveness. `reference.md#replication`.
- **Security** — least-privilege runtime user, TLS across hosts, secret-manager credentials,
  separate migration/admin users, audit exposure before perf tuning. `reference.md#security`.
- **Configuration** — starting-point `my.cnf` as a review prompt, not a preset; size
  `innodb_buffer_pool_size` on buffer-pool hit-rate (`<99%` grow, `>=99%` stop — p99 is bound
  elsewhere), not a RAM percentage. `reference.md#configuration`.

## Anti-Patterns

| Anti-Pattern | Risk | Better Pattern |
| --- | --- | --- |
| `SELECT *` in hot paths | Over-fetching and brittle clients | Select explicit columns |
| Deep `OFFSET` pagination | Linear scans and slow pages | Keyset pagination |
| No index on foreign-key joins | Slow joins and lock-heavy deletes | Index FK columns intentionally |
| Long transactions | Lock waits and large undo history | Commit small units of work |
| Direct DML against `mysql.user` | Grant-table corruption risk | Use `CREATE USER`, `ALTER USER`, `DROP USER` |
| Application user with admin grants | High blast radius | Least-privilege runtime user |
| Pool recycle above `wait_timeout` | Stale pooled connections | Recycle below timeout and pre-ping |
| Replica reads after writes | Stale user-facing state | Pin read-after-write flows to primary |

## Output Expectations

When this skill is used for review, return:

1. Engine/version assumptions.
2. Highest-risk correctness, lock, security, and migration issues.
3. Exact SQL or code changes for the safe path.
4. Validation plan: `EXPLAIN`, migration dry run, lock/deadlock check, and
   rollback criteria.
5. Any MySQL/MariaDB syntax differences that affect the recommendation.

## Related

- Skill: `backend-patterns` - API and service-layer patterns
- Skill: `kbg:security-auditor` - secret handling, auth, and least privilege
- Agent: `code-reviewer` - broader review workflow
- Agent: `performance-optimizer` - once a query-level bottleneck is confirmed, for the
  application-side fix (batching, caching, in-memory structure) around it

## Verify before use

1. Before applying, verify any pattern against your MySQL/MariaDB version's docs.
   APIs drift across versions; if one has moved, the Anti-Patterns above name where each silently fails — never copy unverified, check the changelog.
