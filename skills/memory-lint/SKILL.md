---
name: memory-lint
description: "memory-lint"
---

# memory-lint

Karpathy's llm-wiki **Lint** operation for the memory store: catch the bookkeeping rot a human would let slide — dangling `[[links]]`, orphaned facts, index drift. Deterministic; semantic checks (contradictions, stale claims) are a separate LLM pass.

**When to use:** after writing/editing/removing memories, or on demand to check memory health.

**When NOT to use:** writing a memory (just Write it + add the MEMORY.md line), semantic review of memory *content*, or skill-ecosystem health (use `harness-audit`).

---

## Run

```bash
# Detector mode (default — read-only, exit code = finding count)
python3 skills/memory-lint/scripts/memory-lint.py
# or point at a specific store:
python3 skills/memory-lint/scripts/memory-lint.py /path/to/memory

# Action mode (apply the A3 trim rubric — dry-run by default)
python3 skills/memory-lint/scripts/memory-lint.py --auto-archive --dry-run
python3 skills/memory-lint/scripts/memory-lint.py --auto-archive --yes
```

Auto-derives the store from the current repo (`~/.claude/projects/<enc>/memory`). Exit code = finding count; 0 = clean.

## Action mode (`--auto-archive`)

Mechanical fold of verbose/closed entries, codified by the A3 rubric in [[project_memory_trim_session_2026_06_04]]:

- **<2KB delta per session** — never collapse the whole store; trim only the worst
- **<30 min elapsed** — if it takes longer, the store is unhealthy in ways trim won't fix
- **Reversible** — every move is `mv` (never `rm`); collapsed pointers stay grep-able in `_archive/`

| Class | Trigger | Action |
|---|---|---|
| **A — stale-superseded** | MEMORY.md pointer has `**SUPERSEDED**` marker + topic has 0 surviving inbound `[[wikilinks]]` | `mv <topic> _archive/<date>/` + collapse pointer to 1-line stub |
| **B — near-budget-collapse** | MEMORY.md >80% cap + pointer ≥250 chars + topic >5KB + pointer ≥ 1.2x first paragraph | Replace pointer with ~80-char stub + add `supersedes:` note in topic |
| **C — dangling-link-rewrite** | Surviving file's `[[wikilink]]` resolves to nothing or to `_archive/` | Rewrite `[[X]]` → `[[<ledger>]]` |

Default for `--auto-archive` is dry-run with confirm prompt; `--yes` skips the prompt (use for CI/scripts). `--json` produces machine-readable output (mode-aware: detector JSON for plain lint, action-plan JSON for `--auto-archive --dry-run`).

For the wrapper skill (`plan` / `apply` / `status` subcommands + before/after size deltas), see [[memory-trim]].

## Consuming audit drafts (companion to lint)

The `scripts/audit-to-memory.py` script (in this repo's `scripts/`) generates
a `draft-audit-findings.md` in this memory store after every audit. Treat it
as a **separation-of-duties buffer** between "the audit ran" and "the lesson
is in memory":

1. **Lint first** (above) to surface what already exists.
2. **Open the draft** — `~/.claude/projects/<enc>/memory/draft-audit-findings.md`.
3. For each item, decide:
   - **Promote** — write a dedicated `<slug>.md` with proper frontmatter + add a
     1-line pointer to `MEMORY.md`. Reword the "Why" / "How to apply" sections;
     the draft captures what the audit *said*, not what you should *remember*.
   - **Discard** — the item was noise, rediscovery, or already captured.
   - **Defer** — write a one-liner to `deferred-<date>.md` for a future audit
     to revisit (e.g., items blocked by ADR 0002).
4. **Re-lint** to confirm the new entries are linked and the index is in sync.

The script **never** writes to `MEMORY.md` directly (preserves the autonomy
invariant: the human reviews, the model does not auto-promote). If a draft
sits unread, the next audit run will overwrite it — treat drafts as
**time-limited inputs**, not durable artifacts.

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
- `memory-trim` — wraps action mode with `plan` / `apply` / `status` subcommands + before/after size deltas

## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
