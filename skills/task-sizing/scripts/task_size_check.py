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
