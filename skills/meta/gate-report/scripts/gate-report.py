#!/usr/bin/env python3
# Reads ~/.local/share/kbg/metrics/gate-decisions.jsonl (hooks/gates/_journal.py's own
# log -- non-allow verdicts only: ask/deny/allow-suppressed) and prints an ask-count
# report: how often each gate asked or denied, not how long a user took to answer --
# _journal.py's row has no resolution timestamp, so a wait-time metric isn't derivable
# from this log (docs/research/ai-native-sdlc-playbook-audit-2026-08-28.md Round 4).
import json
import os
import sys
from collections import Counter

MH_GATE_JOURNAL_PATH = "MH_GATE_JOURNAL_PATH"  # same env var _journal.py itself reads


def default_path():
    home = os.environ.get("HOME")
    if not home or not os.path.isabs(home):
        return None
    return os.path.join(home, ".local", "share", "kbg", "metrics", "gate-decisions.jsonl")


def main():
    path = os.environ.get(MH_GATE_JOURNAL_PATH) or default_path()
    if not path or not os.path.isfile(path):
        print("Gate journal not set up.")
        return 0

    counts = Counter()  # (gate_id, decision) -> count
    tools = Counter()   # tool_name -> count
    first_ts = last_ts = None
    total = 0
    skipped = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except ValueError:
                skipped += 1
                continue
            gate_id = row.get("id", "(unknown)")
            decision = row.get("decision", "(unknown)")
            tool_name = row.get("tool_name", "(unknown)")
            ts = row.get("ts")
            counts[(gate_id, decision)] += 1
            tools[tool_name] += 1
            total += 1
            if ts:
                first_ts = ts if first_ts is None or ts < first_ts else first_ts
                last_ts = ts if last_ts is None or ts > last_ts else last_ts

    if total == 0:
        print("Gate journal is empty — no ask/deny events logged yet.")
        return 0

    print(f"Gate journal: {total} ask/deny event(s)" + (f", {skipped} unparsable line(s) skipped" if skipped else ""))
    if first_ts and last_ts:
        print(f"Range: {first_ts} .. {last_ts}")
    print()
    print("By gate x decision (ask-count only — no resolution timestamp is logged, so this")
    print("is never a wait-time metric):")
    for (gate_id, decision), n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {gate_id}  {decision}")
    print()
    print("By tool:")
    for tool_name, n in sorted(tools.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {tool_name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
