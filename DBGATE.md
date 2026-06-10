# DBGATE - Database Write Gate

**Rule:** before ANY database write — `INSERT` / `UPDATE` / `DELETE` / `TRUNCATE` / `ALTER` / `DROP` / `CREATE`, on **staging OR production** — **ask the user first, every time.** Read-only queries (`SELECT`, `EXPLAIN`, `information_schema`) need no confirmation.

**Why:** writes are hard to reverse and staging often carries real production data; each mutation is a per-operation, user-gated decision.

**How:** state the exact statement + target database, get explicit OK, then run. The gate is the assistant asking the user directly — never delegate a write to a sub-agent or auto-confirm. A batch of identical-shape writes may be confirmed together if presented as one set.
