#!/usr/bin/env python3
"""ideate-convergence.py — query local convergence history for kbg:ideate.

Reads ~/.claude/state/ideate-embeddings.jsonl and prints a summary of how
similar today's ideate runs are to each other. The embedding vectors are
computed by the SessionEnd hook via the local Ollama API (all-minilm); this
script is stdlib-only for querying.

Usage:
    python3 scripts/ideate-convergence.py
    python3 scripts/ideate-convergence.py --last 10
    python3 scripts/ideate-convergence.py --today
    python3 scripts/ideate-convergence.py --status warning
"""

import argparse
import json
import math
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def load_records(path):
    if not path.exists():
        return []
    records = []
    with path.open("r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as e:
                print(f"[ideate-convergence] WARN: malformed JSONL line {i}: {e}", file=sys.stderr)
    return records


def main(argv=None):
    parser = argparse.ArgumentParser(description="Query kbg:ideate convergence history.")
    parser.add_argument("--last", type=int, help="Show last N records.")
    parser.add_argument("--today", action="store_true", help="Show today's records only.")
    parser.add_argument("--status", choices=["ok", "warning", "unknown"], help="Filter by convergence status.")
    parser.add_argument("--threshold", type=float, default=0.85, help="Cosine threshold for warning (default: 0.85).")
    parser.add_argument("--state-dir", type=Path, default=Path.home() / ".claude" / "state", help="State directory.")
    args = parser.parse_args(argv)

    emb_file = args.state_dir / "ideate-embeddings.jsonl"
    records = load_records(emb_file)

    if not records:
        print("No convergence records found. Run ideate first.")
        return 0

    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # Filter
    filtered = records
    if args.today:
        filtered = [r for r in filtered if r.get("date") == today]
    if args.status:
        filtered = [r for r in filtered if r.get("convergence_status") == args.status]
    if args.last:
        filtered = filtered[-args.last:]

    if not filtered:
        print("0 records match the filter.")
        return 0

    print(f"## ideate convergence records (n={len(filtered)})")
    print(f"state: {emb_file}\n")
    print("| ts | problem | status | reason |")
    print("|---|---|---|---|")
    for r in filtered:
        ts = r.get("ts", "")[:19]
        problem = (r.get("problem") or "")[:50].replace("|", "\\|")
        status = r.get("convergence_status", "unknown")
        reason = (r.get("convergence_reason") or "")[:60].replace("|", "\\|")
        print(f"| {ts} | {problem} | {status} | {reason} |")

    # Cross-similarity for records with embeddings.
    with_emb = [r for r in filtered if r.get("embedding")]
    if len(with_emb) >= 2:
        print(f"\n## pairwise cosine similarity (threshold {args.threshold})")
        print("| problem A | problem B | similarity |")
        print("|---|---|---|")
        for i in range(len(with_emb)):
            for j in range(i + 1, len(with_emb)):
                a, b = with_emb[i], with_emb[j]
                sim = cosine(a["embedding"], b["embedding"])
                flag = " ⚠️" if sim >= args.threshold else ""
                pa = (a.get("problem") or "")[:30].replace("|", "\\|")
                pb = (b.get("problem") or "")[:30].replace("|", "\\|")
                print(f"| {pa} | {pb} | {sim:.3f}{flag} |")

    return 0


if __name__ == "__main__":
    sys.exit(main())
