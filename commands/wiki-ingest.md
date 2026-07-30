---
name: wiki-ingest
description: "Ingest a source document into the llm-wiki vault from any project. Don't use for searching the vault (qmd MCP, collection llm-wiki) or kbg's own memory store (kbg:learn)."
argument-hint: <absolute/path/to/source.md> [topic]
disable-model-invocation: true
disable-model-invocation-reason: mutates the operator's personal vault outside this repo — copies into raw/, creates a wiki/ page, and appends to log.md (and, when the guard allows it, hotcache.md). A human must type /kbg:wiki-ingest themselves.
---

# Wiki Ingest

Copy a source document into `~/llm-wiki` and register it — wraps the vault's
own `scripts/ingest.sh`, never reimplements it. User-invoked only: this writes
to the operator's personal vault, outside this repo, and the write is
append-only-by-design rather than cleanly reversible.

## Usage

```
/kbg:wiki-ingest /abs/path/to/source.md [topic]
```

- `source` (required): **must be an absolute path.** `ingest.sh` runs `cd
  "$VAULT"` before it checks the file exists — a path relative to the
  caller's cwd resolves against the vault instead and either fails or
  silently matches the wrong file.
- `topic` (optional, default `general`): destination subdirectory under
  `raw/` and `wiki/` — e.g. `ai-agents`, `design-patterns`, `startups`.

## What it writes

Four writes, all outside this repo:

1. `raw/<topic>/<basename>` — a copy of the source (skipped if the source is
   already under `raw/`).
2. `wiki/<topic>/src-<slug>.md` — a new curated page for the source.
3. `log.md` — an append-only journal entry.
4. `hotcache.md` — an append, **conditionally** (see gotcha 3 below).

## Preflight

Graceful-skip if the vault isn't present — this command must degrade silently
on any install that doesn't have `~/llm-wiki`:

```bash
VAULT="${KBG_WIKI_VAULT:-$HOME/llm-wiki}"
[ -d "$VAULT/wiki" ] || { echo "llm-wiki vault not found at $VAULT — nothing to ingest into"; exit 0; }
```

Resolve `source` to an absolute path before invoking — if the operator gave a
relative path, resolve it against their actual cwd, not the vault.

## Invocation

```bash
VAULT="${KBG_WIKI_VAULT:-$HOME/llm-wiki}" \
  bash "${KBG_WIKI_VAULT:-$HOME/llm-wiki}/scripts/ingest.sh" /abs/path/to/source.md <topic>
```

(Repeats the full `${KBG_WIKI_VAULT:-$HOME/llm-wiki}` expression rather than
referencing `$VAULT` on the same line — a prefix assignment's value isn't
visible to a same-line expansion in bash, so referencing `$VAULT` here would
silently resolve against whatever was already exported, not this value.)

## Three gotchas (verified against the live scripts, not assumed)

1. **Absolute path required.** `ingest.sh:8` runs `cd "$VAULT"` before the
   `[ ! -f "$SOURCE" ]` test at `:19` — see Usage above.
2. **`hotcache.md` has a ≤500-word invariant.** A large source can push it
   over; flag this to the operator rather than appending blind.
3. **The hotcache append can be silently skipped** — `ingest.sh:81` guards it
   with `grep -q "## Last session.*ingest" hotcache.md`, meant to avoid a
   duplicate append within one session. If the vault's `hotcache.md` already
   has a heading matching that pattern from an earlier session (common — the
   heading text often contains the word "ingest"), the guard trips
   permanently and the append never happens, contradicting this command's own
   write-contract above. **Do not just report success.** After invoking,
   check whether it actually wrote:
   ```bash
   git -C "${KBG_WIKI_VAULT:-$HOME/llm-wiki}" diff --stat hotcache.md
   ```
   If empty, tell the operator plainly that the hotcache append was skipped
   and why, rather than silently letting the vault's "read hotcache.md first"
   contract go stale.

## Output contract

Report back:

1. The four target paths (§ What it writes), each marked written / skipped.
2. `ingest.sh`'s own stdout verbatim.
3. The `hotcache.md` diff-stat check from gotcha 3 — explicit skip notice if
   it didn't change.
4. Suggested next step: `kbg:wiki-scan` to confirm the new page doesn't
   introduce an orphan or a broken citation.
