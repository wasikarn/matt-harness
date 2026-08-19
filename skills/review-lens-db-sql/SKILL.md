---
name: review-lens-db-sql
description: DB/SQL query-safety checklist for code-reviewer's db-aspect dispatch. Use when code-reviewer is dispatched for the db lens. Don't use for authoring guidance — kbg:mysql-patterns/kbg:drizzle-patterns instead.
bucket: review
metadata:
  origin: kbg
---

# DB/SQL Query Safety Lens

Loaded by `code-reviewer` when `kbg:review-pr` dispatches the `db` aspect. Scoped to this
project's stack — MySQL/MariaDB (`kbg:mysql-patterns`) and Drizzle ORM (`kbg:drizzle-patterns`).
Check raw SQL, query builders, and Drizzle calls alike.

- **UPDATE/DELETE without WHERE** — mutates or destroys every row in the table.
  Tag this **CRITICAL**, not `agents/code-reviewer.md`'s Code Quality section's
  default HIGH — an unscoped mass mutation is as irreversible as anything in
  that file's Security section, and "data-loss risk" is not a style nit that
  a HIGH label communicates. This is
  the severity once the Pre-Report Gate's proof is met, not a bypass of it —
  usually trivial here, since the unscoped query text is its own trigger; if
  a genuine scoping guard exists elsewhere (a dynamically-built WHERE, an ORM
  hook) that the diff doesn't show, demote per the gate's own rule.
- **Unindexed WHERE/JOIN columns** — a filter or join column with no index forces
  a full table scan; check migrations for a matching index before approving a new
  query pattern.
- **Missing transaction boundaries** — multiple related writes (e.g. debit +
  credit, create-parent-then-child) that aren't wrapped in a transaction leave
  the DB in a half-written state on partial failure.
- **Unparameterized queries** — this duplicates `agents/code-reviewer.md`'s Security
  section's SQL-injection check; flag it there, not twice here.
- **N+1 queries** — see `agents/code-reviewer.md`'s Node.js/Backend Patterns section;
  the same false-positive guard (fixed-cardinality loops, DataLoader/batching) applies.

Confirm each applicable bullet before filing a finding — done when every row above has
either a cited `file:line` or an explicit "checked, not applicable."

```typescript
// BAD: two related writes with no transaction — a failure between them
// leaves an order with no matching payment row
await db.insert(orders).values(order);
await db.insert(payments).values(payment);

// GOOD: atomic
await db.transaction(async (tx) => {
  await tx.insert(orders).values(order);
  await tx.insert(payments).values(payment);
});
```
