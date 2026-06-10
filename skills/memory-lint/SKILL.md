---
name: memory-lint
description: "Use this skill whenever the user wants to lint memory, check memory health, find broken cross-links, or after any memory edit (add/edit/remove). Catches dangling [[links]], orphaned facts, index drift, and load-budget violations. Deterministic bookkeeping checks only. Do NOT use for: writing memories (just Write the file), semantic contradiction/staleness review (needs an LLM pass), or skill/agent/hook health (use harness-audit)."
---

# memory-lint

Karpathy's llm-wiki **Lint** operation for the memory store: catch the bookkeeping rot a human would let slide — dangling `[[links]]`, orphaned facts, index drift. Deterministic; semantic checks (contradictions, stale claims) are a separate LLM pass.

**When to use:** after writing/editing/removing memories, or on demand to check memory health.

**When NOT to use:** writing a memory (just Write it + add the MEMORY.md line), semantic review of memory *content*, or skill-ecosystem health (use `harness-audit`).

---

## Run

```bash
python3 ~/.claude/skills/memory-lint/scripts/memory-lint.py
# or point at a specific store:
python3 ~/.claude/skills/memory-lint/scripts/memory-lint.py /path/to/memory
```

Auto-derives the store from the current repo (`~/.claude/projects/<enc>/memory`). Exit code = finding count; 0 = clean.

## Checks

| Check | Catches |
|---|---|
| **Dangling links** | `[[target]]` resolving to no memory (by filename stem or `name:` slug; strips `[[t\|alias]]`) |
| **Orphans** | indexed in MEMORY.md but no `[[links]]` in or out — disconnected from the wikilink graph |
| **Index drift** | MEMORY.md ↔ files, **both** directions (unindexed file + stale pointer) |
| **Load budget** | MEMORY.md within the official 200-line / 25KB session-load cap (warn ≥80%, fail if over — trailing entries silently never load) |

`[[ ]]` is memory↔memory only. Reference skills/doctrine (`decommission`, METHODOLOGY) in prose with backticks, not `[[links]]` — those resolve to no memory and surface as dangling.

**Author links by filename stem** (the file name minus `.md`), not the `name:` slug. A link resolves by filename-stem OR `name:`, but `name:` fields are inconsistent storewide (hyphen vs underscore, prefixed or not — 81/110 differed from their filename as of 2026-06-08), so the filename stem is the one identifier guaranteed to resolve. The SessionStart `memory-lint-check` hook surfaces danglers each session (advisory; silent when clean).

## METHODOLOGY

- **Rule 12 (fail loud):** a broken cross-link or orphan is silent rot; exit code = finding count makes it visible.
- **Rule 8 (read before write):** before adding a memory, lint surfaces an existing one it should link to or supersede.

## Related

- `harness-audit` — same shape for the skill/agent/hook ecosystem (check 13 covers MEMORY.md pointer→file; this covers the reverse + links)
- `inventory` — lists artifacts; doesn't judge memory health
