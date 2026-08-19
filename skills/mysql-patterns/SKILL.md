---
name: mysql-patterns
description: MySQL/MariaDB schema, query, indexing, transaction, replication, and pool patterns. Use when designing or troubleshooting MySQL/MariaDB. Don't use for non-MySQL databases.
bucket: patterns
metadata:
  origin: ECC
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

## Query Patterns

### Upsert

Cross-engine-compatible form:

```sql
INSERT INTO user_settings (user_id, setting_key, setting_value)
VALUES (?, ?, ?)
ON DUPLICATE KEY UPDATE
    setting_value = VALUES(setting_value),
    updated_at = CURRENT_TIMESTAMP;
```

MySQL row-alias form:

```sql
INSERT INTO user_settings (user_id, setting_key, setting_value)
VALUES (?, ?, ?) AS new
ON DUPLICATE KEY UPDATE
    setting_value = new.setting_value,
    updated_at = CURRENT_TIMESTAMP;
```

Use the row-alias form only after confirming the target is MySQL. Use
`VALUES(col)` for MariaDB or mixed MySQL/MariaDB fleets.

### Keyset Pagination

```sql
SELECT id, name, created_at
FROM products
WHERE (created_at, id) < (?, ?)
ORDER BY created_at DESC, id DESC
LIMIT 50;
```

Back it with an index that matches the cursor:

```sql
CREATE INDEX idx_products_created_id ON products (created_at, id);
```

Do not use deep `OFFSET` pagination on large tables; it makes the server scan
and discard rows before returning the page.

### JSON Fields

Use JSON columns for extension data, not fields needing heavy relational
filtering or constraints.

```sql
CREATE TABLE events (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    payload JSON NOT NULL,
    event_type VARCHAR(64)
        GENERATED ALWAYS AS (JSON_UNQUOTE(JSON_EXTRACT(payload, '$.type'))) STORED,
    KEY idx_events_type (event_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

For frequently queried JSON paths, expose and index a generated column. Keep
foreign keys, ownership, tenancy, and lifecycle fields relational.

### Full-Text Search

```sql
ALTER TABLE articles ADD FULLTEXT KEY ft_articles_title_body (title, body);

SELECT id, title, MATCH(title, body) AGAINST (? IN NATURAL LANGUAGE MODE) AS score
FROM articles
WHERE MATCH(title, body) AGAINST (? IN NATURAL LANGUAGE MODE)
ORDER BY score DESC
LIMIT 20;
```

Use external search when you need typo tolerance, complex ranking, cross-table
facets, or language-specific analysis beyond built-in full-text.

## Transactions

Keep transactions short and lock rows in a consistent order:

```sql
START TRANSACTION;

SELECT id, balance
FROM accounts
WHERE id IN (?, ?)
ORDER BY id
FOR UPDATE;

UPDATE accounts SET balance = balance - ? WHERE id = ?;
UPDATE accounts SET balance = balance + ? WHERE id = ?;

COMMIT;
```

Deadlock and lock-wait checklist:

- Lock rows in a deterministic order across code paths.
- Do external API calls before opening the transaction, not inside it.
- Add indexes for predicates used in `UPDATE`, `DELETE`, and locking reads.
- On deadlock, roll back and retry the whole transaction with a bounded retry
  budget.
- Capture `SHOW ENGINE INNODB STATUS\G` soon after a deadlock; it is overwritten
  by later events.
- Drop to `READ COMMITTED` on insert-heavy hot paths where phantom reads are tolerable — MySQL's default `REPEATABLE READ` uses next-key/gap locks that serialize concurrent inserts into a scanned range; `READ COMMITTED` releases them. Keep `REPEATABLE READ` for integrity-sensitive read-modify-write. Check isolation level before blaming missing-index or lock-ordering for insert stalls.

Queue-style worker claim:

```sql
START TRANSACTION;

SELECT id
FROM jobs
WHERE status = 'pending'
ORDER BY created_at
LIMIT 1
FOR UPDATE SKIP LOCKED;

UPDATE jobs
SET status = 'processing', started_at = CURRENT_TIMESTAMP
WHERE id = ?;

COMMIT;
```

Use `SKIP LOCKED` only for queue-like workloads where skipping a locked row is
acceptable. It is not a replacement for normal transactional consistency.

## Connection Pools

SQLAlchemy example:

```python
from sqlalchemy import create_engine

engine = create_engine(
    "mysql+mysqlconnector://app:secret@db.internal/app",
    pool_size=10,
    max_overflow=5,
    pool_timeout=30,
    pool_recycle=240,
    pool_pre_ping=True,
    connect_args={"connect_timeout": 5},
)
```

Node.js `mysql2` example:

```javascript
import mysql from 'mysql2/promise';

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  enableKeepAlive: true,
  keepAliveInitialDelay: 30000,
});

const [rows] = await pool.execute(
  'SELECT id, total FROM orders WHERE account_id = ? LIMIT 50',
  [accountId],
);
```

Keep application pool recycling below the server `wait_timeout`. If the server
uses `wait_timeout = 300`, a `pool_recycle` around 240 seconds is coherent;
`pool_pre_ping` still helps recover from network and failover events.

**Bound the aggregate, not just per-instance.** For multi-instance deploys (N AdonisJS/FastAPI/Node pods × `pool_size`), `(pool_size + max_overflow) × instances < max_connections` must hold with ~20% headroom for replicas/migrations — otherwise fan-out hits "Too many connections". Size the per-pod pool down from the server cap, not up from workload alone.

## Diagnostics

Useful first-pass commands:

```sql
SHOW FULL PROCESSLIST;
SHOW ENGINE INNODB STATUS\G;
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'long_query_time';
```

Enable the slow log in a controlled environment:

```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;
SET GLOBAL log_queries_not_using_indexes = 'ON';
```

Use `EXPLAIN ANALYZE` only when it is safe to execute the query. It runs the
statement and can be expensive on production-sized data.

## Replication

Read replicas can lag. Do not route read-your-own-write paths, checkout flows,
permission checks, or idempotency-key reads to a replica immediately after a
write.

```sql
-- MySQL legacy terminology, still common in existing fleets
SHOW SLAVE STATUS\G;

-- Newer terminology where supported
SHOW REPLICA STATUS\G;
```

Check the engine/version before standardizing on one command. Monitor replica
SQL thread health, IO thread health, and lag, not just whether the TCP
connection is alive.

**Before pinning read-after-write to primary on lag, tune parallel apply.** Replica: set `replica_parallel_workers` + `replica_parallel_type=LOGICAL_CLOCK` (MySQL 8.0.26+ `replica_` prefix; MariaDB: `slave_parallel_workers` + `slave_parallel_mode=optimistic` — no `slave_parallel_type` there — `slave_parallel_mode` is the tunable). MySQL primary: set `binlog_transaction_dependency_tracking=WRITESET` with `binlog_format=ROW` for max parallelism — skip it and parallelism degrades to group-commit granularity. Parallel apply cuts lag by the parallelism factor for independent transactions; little help on serial/hot-row workloads. Pinning reads to primary is the fallback (worse horizontal scaling), not the first move.

## Security

```sql
CREATE USER 'app'@'%' IDENTIFIED BY 'use-a-secret-manager';
GRANT SELECT, INSERT, UPDATE, DELETE ON appdb.* TO 'app'@'%';

ALTER USER 'app'@'%' REQUIRE SSL;

SELECT user, host
FROM mysql.user
WHERE user = '';

DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'%';
```

Security review points:

- Do not grant `ALL PRIVILEGES` or `*.*` to application users.
- Require TLS for application users when traffic crosses hosts or networks.
- Store credentials in the platform secret manager, not in examples, scripts, or
  repo files.
- Separate migration/admin users from runtime application users.
- Audit public network exposure and bind addresses before tuning performance.

## Configuration

Example starting point for a dedicated database host:

```ini
[mysqld]
innodb_buffer_pool_size = 4G
innodb_flush_log_at_trx_commit = 1
sync_binlog = 1

max_connections = 300
thread_cache_size = 50

wait_timeout = 300
interactive_timeout = 300
innodb_lock_wait_timeout = 10

slow_query_log = ON
long_query_time = 1
log_queries_not_using_indexes = ON

log_bin = mysql-bin
binlog_format = ROW
binlog_expire_logs_seconds = 604800
```

Treat configuration values as a prompt for review, not a universal preset. Size
memory, connections, log retention, and durability from workload, hardware,
backup policy, and recovery objectives.

**Size `innodb_buffer_pool_size` on hit-rate, not RAM percentage.** Compute `1 - Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests` from `SHOW GLOBAL STATUS` (or the `Buffer pool hit rate: X / Y` line in `SHOW ENGINE INNODB STATUS\G`): `<99%`: grow the pool; `>=99%`: stop — p99 is bound elsewhere (query plan/indexing, redo-log flushing, lock waits, I/O), not RAM. Defaulting to "70-80% of RAM" wastes memory once the working set fits.

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
