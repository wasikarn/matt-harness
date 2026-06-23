---
name: memory-trim
description: "Mechanically archive verbose or closed memory entries while keeping the memory store under its 200-line/25KB load cap. Uses reversible moves, never rm. Use when MEMORY.md is bloated or after a big session. Thai: 'memory trim', 'ย่อ memory', 'archive memory'. Don't use for: semantic memory review, deleting memory permanently, or harness-wide health checks (kbg:harness-audit)."
---

# Memory-Trim

Mechanical fold of verbose/closed entries from `MEMORY.md` to keep the load cap (200L/25KB) healthy. Wraps `memory-lint --auto-archive` with the **A3 rubric** (codified 2026-06-04, [[project_memory_trim_session_2026_06_04]]).

## Workflow

```bash
# 1. Run the action plan in dry-run mode
bash "${CLAUDE_SKILL_DIR}/scripts/memory-trim.sh" plan

# 2. Review the plan; if sane, apply (--yes skips the confirm prompt)
bash "${CLAUDE_SKILL_DIR}/scripts/memory-trim.sh" apply

# 3. Re-lint to confirm no new findings
bash "${CLAUDE_SKILL_DIR}/scripts/memory-lint.sh"
```

The script auto-derives the memory dir from cwd (`~/.claude/projects/<enc>/memory`) and prints before/after size deltas + lint finding count. **Always dry-run first**; `--yes` only after human review.

## What gets proposed

The engine classifies each candidate as **A — stale-superseded**, **B — near-budget-collapse**, or **C — dangling-link-rewrite** under the A3 session guardrails.

The full rubric — guardrails, the A/B/C triggers, actions, and per-class safety notes — is the **single source in [[memory-lint]] action mode**, co-located with `scripts/memory-lint.py` that enforces the thresholds. Read it there before your first apply (and again if a class's trigger feels off — the prose mirrors the code). First-application precedent: [[project_memory_trim_session_2026_06_04]]; `_archive/` consolidation technique: [[reference_memory_store_optimization]].

## Related

- `memory-lint` — the detector + action-mode engine this skill wraps
- `harness-audit` — same shape for the skill/agent/hook ecosystem (check 13 covers MEMORY.md pointer→file)

## Anti-patterns

- **Run on first-time setup** — the store needs to grow before trim has signal. Wait until the store is near the load cap.
- **Trust Class B blindly** — the "pointer carries detail" proxy is heuristic. Always scan the BEFORE/AFTER in dry-run.
- **Skip the dry-run** — `--yes` exists for CI/scripts; humans should always see the plan first.
- **Trim in a single session** — A3 caps the per-session delta (see [[memory-lint]]). If the plan proposes more, defer to a follow-up session.

**Named model** (cc-thinking-skills): trimming the store down rather than adding to it is *via-negativa* (subtractive health, reversible by `mv`). Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
