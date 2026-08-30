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

**Always pass `-readonly`.** It's not optional decoration — it makes "this skill never
writes" true at the SQLite engine level (a write attempt fails with `attempt to write a
readonly database`, exit 8) instead of merely documented as a convention nothing enforces.

```bash
sqlite3 -readonly "$DB" ".tables"
```

Then, for each table name that comes back, report a row count:

```bash
sqlite3 -readonly "$DB" "SELECT COUNT(*) FROM \"$TABLE\";"
```

**Finding the FTS5 search table: query `sqlite_master`, never match on the table name.**
Creating one FTS5 virtual table (e.g. `ideas_fts`) auto-creates several shadow tables
whose names all contain the substring `fts` too (`ideas_fts_data`, `ideas_fts_idx`,
`ideas_fts_docsize`, `ideas_fts_config`, and sometimes `ideas_fts_content`) — matching on
"contains fts" catches all of them, and running `MATCH` or a row count against a shadow
table either errors or reports a meaningless internal number, not an idea count:

```bash
sqlite3 -readonly "$DB" "SELECT name FROM sqlite_master WHERE type='table' AND sql LIKE '%VIRTUAL TABLE%fts5%';"
```

This returns only the real virtual table(s) — the shadow tables are ordinary
`CREATE TABLE` statements, never `CREATE VIRTUAL TABLE`, so they never match. Exclude
every shadow table (same base name, `_data`/`_idx`/`_docsize`/`_config`/`_content`
suffixes) from the row-count step above, too.

Once you have the real FTS table name, offer it to the user as `/search <term>`, escaping
**two separate layers** — FTS5's own query syntax, then the outer SQL string literal:

```bash
FTS_PHRASE="\"${TERM//\"/\"\"}\""              # wrap as an FTS5 phrase, doubling inner "
SQL_LITERAL=$(printf '%s' "$FTS_PHRASE" | sed "s/'/''/g")   # then escape ' for the SQL string
sqlite3 -readonly "$DB" "SELECT * FROM \"$FTS_TABLE\" WHERE \"$FTS_TABLE\" MATCH '$SQL_LITERAL' LIMIT 5;"
```

**Both layers matter, and neither is optional-for-"malicious"-input-only.** An entirely
ordinary search like `user's idea`, run through only the outer SQL-escaping step, throws
an FTS5 syntax error — FTS5 parses its own query string as bareword/phrase syntax, so an
embedded apostrophe needs the phrase wrap regardless of intent. A search deliberately
crafted like `x'; SELECT 'INJECTED' AS proof; --` closes the SQL string literal early and
gets the `sqlite3` CLI to run a second, stacked statement if the outer layer is skipped
— the `-readonly` flag blocks a stacked *write* either way, but wrapping as an FTS5
phrase first (rather than passing the term as a bare FTS5 query) neutralizes the stacked
*read* too: the whole payload becomes literal phrase text with no match, not executable
SQL.

## Reporting

Report table names + row counts, verbatim. If a table looks like it tracks a status or
stage (a column named something like `status`/`stage`/`state`, discoverable via
`sqlite3 -readonly "$DB" ".schema \"$TABLE\""`), group counts by that column instead of reporting a
flat total — but only after confirming the column exists; don't assume `ideas`,
`verdicts`, and `events` are the table names or that any particular column exists.

## Verify / done when

Report the table list and every row count actually returned by `sqlite3` — a table you
expected but didn't see should be stated as missing, not silently omitted. Confirm
`sqlite3` exited 0 for each query; a non-zero exit means `MH_IDEAS_DB` points at something
that isn't a valid SQLite file, not that the database is empty.

## What this skill does NOT do

- Does not write to the database — enforced by `-readonly` on every `sqlite3` call, not
  just a documented convention.
- Does not search matt-harness's own content — use `qmd` for that.
- Does not manage matt-harness's own memory store — use `mh:memory-lint`.
- Does not run, schedule, or maintain the capture pipeline that feeds this database
  (the Telegram intake, dedup, triage, or AI-consultant review steps) — that pipeline is
  the operator's own always-on service, entirely outside any matt-harness surface, the
  same way `~/llm-wiki`'s `ingest.sh` is outside `mh:wiki-scan`. matt-harness only reads
  what's already there.
