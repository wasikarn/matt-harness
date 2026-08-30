---
name: idea-scan
description: "Scan a personal ideas.db (SQLite: ideas/verdicts/events/FTS5), read-only, if present. Use when checking idea-backlog status. Don't use for mh's own memory (mh:memory-lint)."
model: inherit
effort: low
---

# idea-scan

Read-only introspection over an operator's own external idea-pipeline database (a
personal capture → triage → verdict → skill-graduation tool, kept entirely outside
matt-harness — see the boundary note below). This skill only reads; it never writes to
that database.

matt-harness ships no such database and no schema for one — there is no fixed table
layout to assume. This skill introspects whatever schema is actually there instead of
guessing column names.

## Graceful-skip preflight

Most installs will not have this database — matt-harness is a public plugin, and the
underlying pipeline is one operator's personal tool, not something matt-harness bundles
or requires:

```bash
DB="${MH_IDEAS_DB:-}"
[ -n "$DB" ] || { echo "MH_IDEAS_DB not set — no personal ideas.db configured, skipping"; exit 0; }
[ -f "$DB" ] || { echo "MH_IDEAS_DB=$DB but no file there — skipping"; exit 0; }
command -v sqlite3 >/dev/null 2>&1 || { echo "sqlite3 not installed — skipping"; exit 0; }
export DB
```

Unlike `mh:wiki-scan`'s `~/llm-wiki` default, there is no conventional default path here
— require `MH_IDEAS_DB` explicitly rather than guessing a path and silently scanning the
wrong file (or a stale leftover) if it happens to exist somewhere.

## Run

```bash
sqlite3 "$DB" ".tables"
```

Then, for each table name that comes back, report a row count:

```bash
sqlite3 "$DB" "SELECT COUNT(*) FROM \"$TABLE\";"
```

If any table name contains `fts` (an FTS5 virtual table), that is the search entry
point — offer it to the user as `/search <term>`:

```bash
sqlite3 "$DB" "SELECT * FROM \"$FTS_TABLE\" WHERE \"$FTS_TABLE\" MATCH '$TERM' LIMIT 5;"
```

Quote `$TERM` as a single SQLite string literal; FTS5 MATCH syntax accepts bareword and
phrase queries the same way `sqlite3`'s CLI does.

## Reporting

Report table names + row counts, verbatim. If a table looks like it tracks a status or
stage (a column named something like `status`/`stage`/`state`, discoverable via
`sqlite3 "$DB" ".schema \"$TABLE\""`), group counts by that column instead of reporting a
flat total — but only after confirming the column exists; don't assume `ideas`,
`verdicts`, and `events` are the table names or that any particular column exists.

## Verify / done when

Report the table list and every row count actually returned by `sqlite3` — a table you
expected but didn't see should be stated as missing, not silently omitted. Confirm
`sqlite3` exited 0 for each query; a non-zero exit means `MH_IDEAS_DB` points at something
that isn't a valid SQLite file, not that the database is empty.

## What this skill does NOT do

- Does not write to the database — no INSERT/UPDATE/DELETE, ever.
- Does not search matt-harness's own content — use `qmd` for that.
- Does not manage matt-harness's own memory store — use `mh:memory-lint`.
- Does not run, schedule, or maintain the capture pipeline that feeds this database
  (the Telegram intake, dedup, triage, or AI-consultant review steps) — that pipeline is
  the operator's own always-on service, entirely outside any matt-harness surface, the
  same way `~/llm-wiki`'s `ingest.sh` is outside `mh:wiki-scan`. matt-harness only reads
  what's already there.
