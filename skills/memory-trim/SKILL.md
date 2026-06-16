---
name: memory-trim
last_reviewed_reason: 'not reviewed in 2026-06-11 epic; deferred to quarterly cadence in docs/harness-decay-cadence.md (first sweep 2026-09)'
description: "memory-trim"
---

# Memory-Trim

Mechanical fold of verbose/closed entries from `MEMORY.md` to keep the load cap (200L/25KB) healthy. Wraps `memory-lint --auto-archive` with the **A3 rubric** (codified 2026-06-04, [[project_memory_trim_session_2026_06_04]]):

- **<2KB delta per session** — never collapse the whole store; trim only the worst
- **<30 min elapsed** — if it takes longer, the store is unhealthy in ways trim won't fix
- **Reversible** — every move is `mv` (never `rm`); collapsed pointers stay grep-able in `_archive/`

## Workflow

```bash
# 1. Run the action plan in dry-run mode
bash skills/memory-trim/scripts/memory-trim.sh plan

# 2. Review the plan; if sane, apply (--yes skips the confirm prompt)
bash skills/memory-trim/scripts/memory-trim.sh apply

# 3. Re-lint to confirm no new findings
python3 skills/memory-lint/scripts/memory-lint.py
```

The script auto-derives the memory dir from cwd (`~/.claude/projects/<enc>/memory`) and prints before/after size deltas + lint finding count. **Always dry-run first**; `--yes` only after human review.

## What gets proposed

| Class | Trigger | Action | Safety |
|---|---|---|---|
| **A — stale-superseded** | MEMORY.md pointer has `**SUPERSEDED**` marker + topic has 0 surviving inbound `[[wikilinks]]` | `mv <topic> _archive/<date>/` + collapse pointer to 1-line stub | Always safe (marker = user intent) |
| **B — near-budget-collapse** | MEMORY.md >80% cap + pointer ≥250 chars + topic >5KB + pointer ≥ 1.2x first paragraph | Replace pointer with ~80-char stub + add `supersedes:` note in topic | Editorial; review each rewrite |
| **C — dangling-link-rewrite** | Surviving file's `[[wikilink]]` resolves to nothing or to `_archive/` | Rewrite `[[X]]` → `[[<ledger>]]` | Mechanical when target is already-archived |

For the underlying rubric and first-application precedent, see `[[project_memory_trim_session_2026_06_04]]` and `[[reference_memory_store_optimization]]` (the `_archive/` consolidation technique).

## Related

- `memory-lint` — the detector + action-mode engine this skill wraps
- `harness-audit` — same shape for the skill/agent/hook ecosystem (check 13 covers MEMORY.md pointer→file)

## Anti-patterns

- **Run on first-time setup** — the store needs to grow before trim has signal. Wait until >80% cap.
- **Trust Class B blindly** — the "pointer carries detail" proxy is heuristic. Always scan the BEFORE/AFTER in dry-run.
- **Skip the dry-run** — `--yes` exists for CI/scripts; humans should always see the plan first.
- **Trim in a single session** — A3 caps at <2KB. If the plan proposes more, defer to a follow-up session.
