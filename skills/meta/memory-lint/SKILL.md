---
name: memory-lint
description: "Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health."
model: inherit
effort: medium
---

# memory-lint

Karpathy's llm-wiki **Lint** operation for the memory store: catch the bookkeeping rot a human would let slide — dangling `[[links]]`, orphaned facts, index drift. Deterministic; semantic review of memory content stays a human (or separately-invoked LLM) call.

**When to use:** after writing/editing/removing memories, or on demand to check memory health.

**When NOT to use:** writing a memory (just Write it + add the MEMORY.md line), semantic review of memory *content*, or skill-ecosystem health (use `harness-audit`).

## Run

```bash
# Detector mode (default — read-only, exit code = finding count)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py"
# or point at a specific store:
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" /path/to/memory

# Action mode (apply the A3 trim rubric — dry-run by default)
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --auto-archive --dry-run
python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --auto-archive --yes
```

Auto-derives the store from the current repo (`~/.claude/projects/<enc>/memory`). **Verify** the run against the exit code: it equals the finding count, so 0 confirms a clean store.

## Action mode (`--auto-archive`)

See `references/action-mode.md` for the full A/B/C/D rubric (trigger/action/safety
table for each class), the `--trim` plan/apply/status workflow, and the thresholds'
source-of-truth note.

## Checks

| Check | Catches |
|---|---|
| **Dangling links** | `[[target]]` resolving to no memory (by filename stem or `name:` slug; strips `[[t\|alias]]`) — suggests a close-name match (stdlib `difflib`, cutoff 0.6) when one exists, to catch typos |
| **Orphans** | indexed in MEMORY.md but no `[[links]]` in or out — disconnected from the wikilink graph |
| **Index drift** | MEMORY.md and files, both directions (stale pointer, plus UNINDEXED — which is **reachability-aware** since v0.68.241: a file with no pointer but `[[link]]`-reachable from an indexed root is the fold rule's Context layer, never a finding; only unindexed AND unreachable files fire) |
| **Load budget** | MEMORY.md within the official 200-line / 25KB session-load cap (warn ≥80%, fail if over — trailing entries silently never load) |

`[[ ]]` is memory↔memory only. Reference skills/doctrine (`decommission`, METHODOLOGY) in prose with backticks, not `[[links]]` — those resolve to no memory and surface as dangling.

**Author links by filename stem** (the file name minus `.md`), not the `name:` slug. A link resolves by filename-stem OR `name:`, but `name:` fields are inconsistent storewide (hyphen vs underscore, prefixed or not — 81/110 differed from their filename as of 2026-06-08), so the filename stem is the one identifier guaranteed to resolve. The SessionStart `memory-health-nudge` hook (`hooks/session/memory-health-nudge.sh`) surfaces danglers each session — advisory, silent when clean. Rebuild rationale: `docs/research/agent-memory-engineering-2026-08-07.md` proposal A1.

## METHODOLOGY

- **Fail loud:** a broken cross-link or orphan is silent rot; exit code = finding count makes it visible.
- **Read before write:** before adding a memory, lint surfaces an existing one it should link to or supersede.
- **Memory authoring format:** one lesson per file, frontmatter (`name:`, `description:`), body with the fact plus `**Why:**` and `**How to apply:**`, link related memories with `[[slug]]`; dedupe against existing files before writing, and never delete — archive under `_archive/` (see the A3 rubric above).

## Failure modes

- **Skipping straight to apply.** `--auto-archive --yes` without first reading the `--dry-run` plan
  can `mv` entries you meant to keep — always review the plan-mode action list before applying.
- **Linking by `name:` slug instead of filename stem.** `name:` fields are inconsistent storewide
  (hyphen vs underscore, prefixed or not) — a link authored against the slug can resolve to nothing
  even though the file exists. Always link by filename stem.
- **Using `[[links]]` for non-memory references.** Wikilinks only resolve memory↔memory — a link to
  a skill or doctrine file (`decommission`, METHODOLOGY) always shows as dangling. Use backticked
  prose references for those instead.

## Related

- `harness-audit` — same shape for the skill/agent/hook ecosystem
