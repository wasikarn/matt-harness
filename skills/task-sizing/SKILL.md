---
name: task-sizing
description: "task-sizing"
---

# Task Sizing

> **Subagent self-check:** If you were dispatched as a sub-agent for a specific task, **do not re-orchestrate.** Return your scoped output (a `done-when` artifact, a `Report:` block, or your done-criterion evidence) to the parent. The parent owns the prioritization + dispatch loop; you own one well-bounded deliverable.

Size and shape tasks so that a team of agents finishes faster, with fewer merge conflicts and less wasted context. This skill is the planning-phase counterpart to `orchestrate` (runtime dispatch) and `team-plan` (plan authoring).

## Input Contract

- **Needs:** a `/team-plan` artifact (`.claude/tasks/<slug>.md`) or a user request to size a proposed plan. The skill operates on the `## Step by Step Tasks` table.
- **When the plan is missing:** ask the user to run `/team-plan` first, or provide the task list directly.
- **Defaults:** assume the plan uses the standard table columns (`Task ID`, `Description`, `Depends On`, `Assigned To`, `Files`, `Criteria`).

## The 5-6 rule

Per article `agent-teams-best-practices`, **5-6 tasks per agent is the sweet spot.**

- **< 3 tasks** = under-utilization. The agent burns context-setup tokens for marginal work. Merge the crumbs into one coherent task or assign the agent additional scope.
- **> 8 tasks** = context thrashing. The agent switches too often, loses track of file state, and reports progress in low-value increments.
- **The rule is per-agent, not per-plan.** A plan with 4 agents and 24 tasks is fine (6 each). A plan with 2 agents and 20 tasks is not (10 each — split into two waves or add agents).

## Task size heuristics

| Dimension | Too small | Too big | Just right |
|-----------|-----------|---------|------------|
| **Description** | < 30 chars, or "just run X" (use a command instead) | Vague novel ("implement auth system") | 1 concrete sentence: "Add POST /users with email validation" |
| **Files touched** | No files assigned (纯 coordination / 纯 research) | > 3 files owned by one task | 1-2 files, clearly named |
| **Acceptance criteria** | None listed | > 2 criteria (creeping scope) | 1-2 criteria, each machine-checkable |
| **Dependencies** | 0 (island task — merge with a sibling) | > 2 upstream tasks (serial bottleneck) | 1 dependency max |
| **Time estimate** | < 15 min (use inline or a command) | > 4 hours (no natural check-in) | 2-4 hours |

**Anti-patterns:**
- "Update docs after X" as a standalone task → merge into X.
- "Fix lint" as a standalone task → merge into the task that introduced the lint.
- A task with no files and no criteria → drop or merge; it is not verifiable.

## Splitting oversized tasks

When a task violates the "too big" column above, split it before `/team-build`. Three proven patterns:

1. **Interface-first split.** Extract the API contract, type definition, or database schema as its own task. This becomes Wave 1; implementation tasks depend on it. This prevents the "types agent and API agent disagree on `UserSettings` shape" failure from article `task-distribution`.
2. **Layer split.** Decompose backend → frontend → integration → tests. Each layer is one task. The backend task exports the contract; the frontend task consumes it via `UPSTREAM CONTRACTS` (F9 template in `skills/orchestrate/SKILL.md`).
3. **File split.** When files are independent (e.g., `src/api/users.py` and `src/api/billing.py`), assign one file per task. Never split a single file across two agents — that causes silent overwrites.

## Merging undersized tasks

1. **Same file + same owner.** If two tasks touch `src/components/Dashboard.tsx` and both are assigned to `frontend-engineer`, merge them into one task with combined criteria.
2. **Update docs after X.** Documentation that depends on X's deliverable belongs in X's task. The acceptance criterion becomes: "Feature works AND `README.md` section Y is updated."
3. **No files + no criteria.** Drop the task. If it is pure coordination ("tell the API agent to start"), that is the lead's job, not a task board entry.

## Wave balancing

A `/team-build` plan is executed in waves: all Wave 1 tasks run in parallel, then Wave 2, etc.

| Wave | Purpose | Task count |
|------|---------|------------|
| **Wave 1** | Foundational setup — schemas, types, contracts, migrations | 3-5 tasks |
| **Wave 2+** | Implementation layers that consume Wave 1 contracts | 2-4 tasks each |
| **Final wave** | Integration validators + end-to-end checks (INT-N) | 1-3 tasks |

**Total waves for a feature: 3-5.** More than 5 waves means the plan is too coarse-grained; merge waves or enlarge task scope. Fewer than 3 waves means the feature is small enough for `/feature-dev` (single-agent).

**Wave bands vs. the F8 min-3 floor (different axes — they do not conflict).** The task counts above are the width of an *auto-resolved* wave: a property of the dependency graph, which legitimately narrows as a feature integrates (the 7-agent pattern's later waves are often a single task — that is correct, not under-parallelized). The F8 "min 3 / max 5" band is a *different* axis — how many teammates a lead *chooses* to fan out into one explicit `type: parallel` stage. A later wave with 2 ready tasks is the DAG narrowing, never flagged. The dispatcher's F8.4 advisory fires only on an explicit `parallel` agent fan-out below 3 (`scripts/orchestrate/planner.py` `f8_4_under_warnings`), never on auto-resolved wave width; a fixed diverse-lens panel (e.g. code-review + security-review = 2 by design) opts out with `panel: true`.

**F8.5 hard cap:** If any wave has >5 tasks, split the wave or merge tasks. A "20-35 items" prompt is NOT a cap — the LLM will overshoot (audit 2026-06-12: 44 items spawned from a 20-35 prompt). Clamp in code, not in prose. See `skills/orchestrate/SKILL.md` § Bounded fan-out.

## Output Format

This skill produces **revised task tables** (or a verbal sizing verdict) and optionally emits the embedded self-check script's report. The output is planning guidance, not code.

- **Verbal verdict:** "Split task API-1 into API-1a (contract) and API-1b (implementation). Merge V-1 and INT-1."
- **Self-check report:** a terminal table of stats + wave counts + agent load + flag count.
- **Revised plan file:** the updated `## Step by Step Tasks` table, rewritten to disk only if the user confirms.

## Self-check script

Embed this script in your planning workflow to catch sizing violations before `/team-build`.

```python
#!/usr/bin/env python3
"""Task sizing self-check — reads a /team-plan artifact and reports size stats.

Usage:
    python3 task_size_check.py .claude/tasks/<slug>.md

Exit codes:
    0 = all tasks within bounds
    1 = plan file malformed or missing table
    2 = one or more sizing flags found
"""
import argparse
import re
import sys
from pathlib import Path
from collections import defaultdict


def extract_table(text: str, header: str) -> list[dict]:
    """Extract a markdown table under `header` into list-of-dict rows."""
    pattern = rf'##\s+{re.escape(header)}\s*\n(.*?)(?=##\s+|\Z)'
    match = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
    if not match:
        return []
    section = match.group(1)
    lines = [l.rstrip() for l in section.splitlines() if l.strip().startswith('|')]
    if len(lines) < 2:
        return []
    headers = [h.strip().lower() for h in lines[0].split('|') if h.strip()]
    rows = []
    for line in lines[2:]:  # skip header and separator
        cells = [c.strip() for c in line.split('|')]
        # Trim leading/trailing empties caused by outer pipes
        while cells and cells[0] == '':
            cells.pop(0)
        while cells and cells[-1] == '':
            cells.pop()
        if len(cells) < len(headers):
            continue
        row = {}
        for i, h in enumerate(headers):
            row[h] = cells[i] if i < len(cells) else ''
        rows.append(row)
    return rows


def build_waves(tasks: list[dict]) -> dict[int, list[dict]]:
    """Derive waves from Depends On using a simple DAG sort."""
    task_ids = {t.get('task id', '').strip(): t for t in tasks}
    deps = {}
    for t in tasks:
        tid = t.get('task id', '').strip()
        raw = t.get('depends on', '').strip()
        if raw in ('-', '', 'none'):
            deps[tid] = set()
        else:
            deps[tid] = {d.strip() for d in raw.split(',') if d.strip()}

    # Iteratively assign waves
    wave = {}
    placed = set()
    current_wave = 1
    while len(placed) < len(tasks):
        batch = {tid for tid, upstreams in deps.items()
                 if tid not in placed and upstreams.issubset(placed)}
        if not batch:
            # Cycle or missing dependency — place remaining in next wave
            batch = {t.get('task id', '').strip() for t in tasks
                     if t.get('task id', '').strip() not in placed}
        for tid in batch:
            wave[tid] = current_wave
            placed.add(tid)
        current_wave += 1

    waves = defaultdict(list)
    for t in tasks:
        tid = t.get('task id', '').strip()
        waves[wave.get(tid, 1)].append(t)
    return dict(waves)


def main():
    parser = argparse.ArgumentParser(description='Task sizing self-check')
    parser.add_argument('plan_file', type=Path)
    args = parser.parse_args()

    text = args.plan_file.read_text(encoding='utf-8')
    tasks = extract_table(text, 'Step by Step Tasks')

    if not tasks:
        print("No tasks found — check the plan file has a `## Step by Step Tasks` table.")
        sys.exit(1)

    total = len(tasks)
    desc_lengths = [len(t.get('description', '')) for t in tasks]
    files_counts = []
    criteria_counts = []
    deps_counts = []
    for t in tasks:
        files = t.get('files', '').strip()
        criteria = t.get('criteria', '').strip()
        deps = t.get('depends on', '').strip()
        files_n = 0 if files in ('', '(none)', '-') else len(files.split())
        criteria_n = 0 if criteria in ('', '(none)', '-') else len(criteria.split())
        deps_n = 0 if deps in ('', '-', 'none') else len([d for d in deps.split(',') if d.strip()])
        files_counts.append(files_n)
        criteria_counts.append(criteria_n)
        deps_counts.append(deps_n)

    waves = build_waves(tasks)

    print(f"Tasks: {total}")
    print(f"Avg description length: {sum(desc_lengths)/len(desc_lengths):.1f} chars")
    print(f"Tasks with no files: {sum(1 for c in files_counts if c == 0)}")
    print(f"Tasks with >3 files: {sum(1 for c in files_counts if c > 3)}")
    print(f"Tasks with >2 criteria: {sum(1 for c in criteria_counts if c > 2)}")
    print(f"Tasks with >2 dependencies: {sum(1 for c in deps_counts if c > 2)}")
    print(f"Waves: {len(waves)}")
    for w, ts in sorted(waves.items()):
        print(f"  Wave {w}: {len(ts)} tasks")
        if len(ts) > 5:
            print(f"    ⚠️  F8.5 overflow — split or merge (cap = 5)")
        if w == 1 and not (3 <= len(ts) <= 5):
            print(f"    ⚠️  Wave 1 expected 3-5 tasks (found {len(ts)})")
        if w > 1 and not (2 <= len(ts) <= 4):
            print(f"    ⚠️  Wave {w} expected 2-4 tasks (found {len(ts)})")

    # Agent grouping
    agents = defaultdict(list)
    for t in tasks:
        agent = t.get('assigned to', 'unknown').strip()
        agents[agent].append(t)

    print(f"\nAgents: {len(agents)}")
    for agent, ts in sorted(agents.items()):
        label = f"  {agent}: {len(ts)} tasks"
        if len(ts) < 3:
            label += "  ⚠️ under-utilized (<3)"
        elif len(ts) > 8:
            label += "  ⚠️ context-thrashing risk (>8)"
        else:
            label += "  ✅"
        print(label)

    # Size flags
    flags = 0
    for t in tasks:
        tid = t.get('task id', '?').strip()
        desc = t.get('description', '')
        files = t.get('files', '').strip()
        criteria = t.get('criteria', '').strip()
        deps = t.get('depends on', '').strip()
        files_n = 0 if files in ('', '(none)', '-') else len(files.split())
        criteria_n = 0 if criteria in ('', '(none)', '-') else len(criteria.split())
        deps_n = 0 if deps in ('', '-', 'none') else len([d for d in deps.split(',') if d.strip()])

        if len(desc) < 30:
            print(f"⚠️ {tid}: description < 30 chars — merge or drop")
            flags += 1
        if not files and not criteria:
            print(f"⚠️ {tid}: no files + no criteria — drop or merge")
            flags += 1
        if files_n > 3:
            print(f"⚠️ {tid}: >3 files — split by interface/layer/file")
            flags += 1
        if criteria_n > 2:
            print(f"⚠️ {tid}: >2 criteria — split into sub-tasks")
            flags += 1
        if deps_n > 2:
            print(f"⚠️ {tid}: >2 dependencies — split or resequence")
            flags += 1

    if flags:
        print(f"\n{flags} sizing flag(s) found — revise before /team-build.")
        sys.exit(2)
    else:
        print("\n✅ All tasks within size bounds.")
        sys.exit(0)


if __name__ == '__main__':
    main()
```

## Failure Modes to Avoid

1. **Splitting by function instead of by file.** "Agent A writes the first half of `src/api/users.py`, agent B writes the second half" → silent overwrite. The boundary is file-level, never function-level.
2. **Forgetting the interface-first task.** If Wave 1 has no contract/schema task, parallel agents in Wave 2 will invent incompatible shapes. Always extract the shared interface as Wave 1.
3. **Treating "validation" as a single task.** One validator per component is the minimum. For cross-component features, add an integration validator (INT-N) that blocks on ALL builders.
4. **Ignoring the F8.5 hard cap at planning time.** A prompt asking for "20-35 items" is not a cap. If the plan has >5 tasks in any wave, split the wave or merge tasks before `/team-build` dispatches.
5. **Verbal estimates without observable done-whens.** "Make the code work" is not a criterion. Every task must have an observable check a reviewer can run.

## Cross-references

- `skills/orchestrate/SKILL.md` § F8.5 (bounded fan-out hard cap) and F9 spawn-prompt template (file ownership + upstream contracts).
- `commands/team-plan.md` — plan artifact format with `## Step by Step Tasks` table that the self-check script consumes.
- `commands/team-build.md` — wave execution and validation chain.
- Article `agent-teams-best-practices` (claudefa.st) — empirical 5-6 tasks/agent sweet spot.
- Article `task-distribution` (claudefa.st) — 7-agent feature pattern, validation chains, and cross-domain coordination.
