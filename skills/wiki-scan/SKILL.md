---
name: wiki-scan
description: "Scan llm-wiki vault health: orphans, frontmatter, citation integrity, stats. Use when checking vault integrity. Don't use for kbg's memory store (kbg:memory-lint) or semantic search (qmd)."
---

# wiki-scan

Read-only health check over `~/llm-wiki` (the operator's personal knowledge
vault) — orphaned pages, missing frontmatter, raw sources with no wiki page
built from them yet, broken citations, and corpus stats. Wraps the vault's
own `scripts/lint-scan.sh` and `scripts/stats.sh`; never reimplements them.

**Search goes to `qmd` first, not here.** Use the `qmd` MCP `query` tool
scoped to `collection: "llm-wiki"` for finding content by meaning — it's
semantic search, this skill isn't. This skill covers the two things qmd
cannot: vault *health*, and *exact* citation-integrity resolution.

## Graceful-skip preflight

This skill must degrade silently when the vault isn't present — kbg-harness
is a public plugin, and most installs will not have `~/llm-wiki`:

```bash
VAULT="${KBG_WIKI_VAULT:-$HOME/llm-wiki}"
export VAULT
[ -d "$VAULT/wiki" ] || { echo "llm-wiki vault not found at $VAULT — skipping"; exit 0; }
```

Assign `VAULT` as its own statement before referencing it again — a
same-line prefix assignment (`VAULT=... bash "$VAULT/..."`) resolves the
inline `$VAULT` against the shell's prior binding, not the value just set;
splitting the assignment out is what makes the later reference correct.

**`export` it too, not just assign it.** The Run section below invokes
`lint-scan.sh`/`stats.sh` via `bash "$VAULT/scripts/..."` — that correctly
picks *which script file* runs, but each script independently re-derives its
own `VAULT` from its own environment (`VAULT="${VAULT:-$HOME/llm-wiki}"`
internally, not from this skill's `KBG_WIKI_VAULT`). An unexported `VAULT`
never reaches that child process, so the script silently falls back to its
own `$HOME/llm-wiki` default regardless of what `KBG_WIKI_VAULT` pointed at
— confirmed live: the fallback happens to equal the real vault at the
default path, so this reads as working every time, and breaks silently the
one time the vault lives somewhere else. A clean exit code doesn't catch
this either — see Verify below.

## Run

```bash
bash "$VAULT/scripts/lint-scan.sh"
bash "$VAULT/scripts/stats.sh"
```

Both are read-only — verified against the source: each writes only to its own
`mktemp` scratch file, deleted before exit; neither touches `raw/`, `wiki/`,
`log.md`, or `hotcache.md`. `lint-scan.sh` also invokes `check-citations.py`
internally, correctly, after its own `cd` — see the failure-mode guard below
for why that script should never be called directly.

## Reading the `lint-scan.sh` summary

The interpretive work here — parsing the raw output isn't the point, judging
it is. The final line is machine-readable:

```
=== Summary: orphans=N  fm_issues=N  unsourced=N  idx=N  raw_refs=N  body_cites=N  ingests_since_lint=N ===
```

- `orphans` — pages with no inbound `[[wikilink]]`. Some are *intentional*
  (standalone reference pages) — check the page's own frontmatter for an
  explicit `orphan: intentional` marker before flagging it as a defect.
  **This is the canonical count — `stats.sh`'s own "Orphans: N" line can
  disagree and should not be trusted over it.** `stats.sh` builds its
  inbound-link index from `wiki/` alone; `lint-scan.sh` also counts
  `index.md` as a link source (a fix `stats.sh` never received — verified
  live: `lint-scan.sh` reports `orphans=0` on the current vault while
  `stats.sh` reports `Orphans: 18` for the same state). This is a bug in
  the vault's own `stats.sh`, out of scope to fix here (wrap, don't
  reimplement) — just don't repeat its number as the health verdict.
- `fm_issues` — missing or malformed frontmatter fields.
- `unsourced` — a file under `raw/` whose basename appears nowhere in any
  `wiki/*.md` page's text (`lint-scan.sh:90-116`) — a source that was
  ingested but never synthesized into a curated page yet. Skips vendored
  repo snapshots (files carrying `source_path:` instead of `source:`), so
  this only flags article-shaped sources, not reference corpora. Despite
  the name, this is **not** "a wiki page's claim missing a `sources:`
  citation" — that's a different, unrelated failure mode this counter
  doesn't check.
- `idx` — pages missing from `index.md`, or index entries pointing nowhere.
- `raw_refs` — a page's frontmatter `sources:` field naming a `raw/` file
  that doesn't exist.
- `body_cites` — inline `(raw/foo.md)` citations that don't resolve; the
  full `check-citations.py` output above this line breaks these into
  `VALID` / `CASCADE` / `SHORTHAND` / `PROSE` / `BROKEN`. **A `CASCADE`
  verdict is a hint that a citation was likely corrupted by copy-propagation
  from a real error elsewhere — never auto-fix it.** Report it for the
  operator to resolve; don't silently rewrite a citation on inference alone.
- `ingests_since_lint` — how many `ingest.sh` runs have happened since the
  last `lint.sh` (not `lint-scan.sh`) pass. Non-zero isn't a defect by
  itself, just a signal the mutating lint hasn't caught up.

## Verify / done when

Report the Summary line verbatim, with each non-zero counter either
explained (why it's expected) or listed as an open item. Confirm
`lint-scan.sh` exited 0 — it always does by design, so a non-zero exit means
the vault path resolved wrong, not that the vault itself is unhealthy.

Exit 0 alone doesn't prove the *right* vault was scanned, only that *some*
vault was — an unexported `VAULT` (see the preflight above) fails silently
into `$HOME/llm-wiki`, not loudly. If ever running the Run section's
commands standalone, outside this skill's own preflight block, confirm
`VAULT` is actually exported in that shell first.

## Failure-mode guard

1. **`lint.sh` is not `lint-scan.sh` despite the similar name.** `lint.sh`
   mutates — it appends a summary line to `log.md` on every run, even though
   nothing about the name suggests that. Never invoke it from this skill.
2. **`ingest.sh` needs an absolute source path** — see `kbg:wiki-ingest` for
   why; not this skill's concern beyond knowing it if `stats.sh` is being
   used to sanity-check a recent ingest.
3. **Never invoke `check-citations.py` directly.** It only `chdir`s to the
   vault when the caller's cwd basename isn't literally `llm-wiki`
   (`check-citations.py:48-49`) — call it from any directory that happens to
   be *named* `llm-wiki` but isn't the vault, and it silently scans the wrong
   place. `lint-scan.sh` already calls it correctly, post-`cd`; that's the
   only sanctioned path to it.
4. **`lint-wiki.sh` is a third, legacy script sharing the `lint`-shaped
   name — never invoke it either.** Unlike the two scripts above, it has no
   `VAULT` variable and no `cd` at all; it takes an optional positional path
   argument defaulting to `.` (the caller's own cwd). Invoked the same way
   as the two documented scripts (`bash "$VAULT/scripts/lint-wiki.sh"`, no
   argument), it would silently scan wherever the invoking shell happens to
   be — kbg-harness itself, in a normal session — and print confident,
   plausible-looking, and completely meaningless orphan/broken-link counts.
   `lint-scan.sh` is the actively-maintained successor; this one is unused
   by the vault's own docs and exists only from the original import commit.

## What this skill does NOT do

- Does not search vault content — use `qmd`.
- Does not mutate the vault — `lint.sh` and `ingest.sh` are user-invoked only
  (`kbg:wiki-ingest`), never run from here.
- Does not manage kbg's own memory store — use `kbg:memory-lint`.
- Does not check for broken `[[wikilink]]`s — that check only exists in the
  excluded, mutating `lint.sh`. If a user specifically asks about broken
  links, say so explicitly rather than silently answering only the
  orphans/citations portion of the ask.
