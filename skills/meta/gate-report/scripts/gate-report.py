#!/usr/bin/env python3
# Reads ~/.local/share/kbg/metrics/gate-decisions.jsonl (hooks/gates/_journal.py's own
# log -- non-allow verdicts only: ask/deny/allow-suppressed (one row per write, "count" matches),
# plus a shadow rule's
# would_deny/would_ask, GH #337, listed per rule with sample commands) and prints an ask-count
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
    shadow = {}         # (gate_id, rule) -> {"n", "sessions", "samples"}: GH #337 would_* rows
    first_ts = last_ts = None
    total = 0
    skipped = 0
    sessionless = 0     # rows with no session_id: test fixtures / direct gate runs, not live hooks
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
            # GH #378: one secret-scan allow-suppressed row stands for "count" matches (older
            # rows, one per match, have none). Anything but a positive int counts as one.
            n = row.get("count", 1)
            if type(n) is not int or n < 1:
                n = 1
            # Live hook calls always carry a session_id, so a row without one came from a test
            # or a direct gate run (the real journal held 268,206 of them beside ~830 rows with
            # an id, drowning every count); it is tallied apart and kept out of the report. A
            # fake id does not make a row live: older tests wrote "test-session" and "s" rows,
            # and those still count.
            if row.get("session_id") is None:
                sessionless += n
                continue
            gate_id = row.get("id", "(unknown)")
            decision = row.get("decision", "(unknown)")
            tool_name = row.get("tool_name", "(unknown)")
            ts = row.get("ts")
            counts[(gate_id, decision)] += n
            tools[tool_name] += n
            total += n
            if str(decision).startswith("would_"):
                s = shadow.setdefault((gate_id, row.get("rule", "(unknown)")),
                                      {"n": 0, "sessions": set(), "samples": []})
                s["n"] += 1
                s["sessions"].add(row.get("session_id"))
                cmd = row.get("command")
                if cmd and cmd not in s["samples"] and len(s["samples"]) < 3:
                    s["samples"].append(cmd)
            if ts:
                first_ts = ts if first_ts is None or ts < first_ts else first_ts
                last_ts = ts if last_ts is None or ts > last_ts else last_ts

    ignored = f"Ignored {sessionless} session-less row(s) (no session_id: test or direct gate runs, not live hook calls)."
    if total == 0 and sessionless:
        print("Gate journal has no events with a session_id.")
        print(ignored)
        return 0
    if total == 0:
        print("Gate journal is empty — no ask/deny events logged yet.")
        return 0

    print(f"Gate journal: {total} ask/deny event(s)" + (f", {skipped} unparsable line(s) skipped" if skipped else ""))
    if first_ts and last_ts:
        print(f"Range: {first_ts} .. {last_ts}")
    if sessionless:
        print(ignored)
    print()
    print("By gate x decision (ask-count only — no resolution timestamp is logged, so this")
    print("is never a wait-time metric):")
    for (gate_id, decision), n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {gate_id}  {decision}")
    print()
    print("By tool:")
    for tool_name, n in sorted(tools.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {tool_name}")
    if shadow:
        print()
        print("Shadow rules (matched but allowed; check the samples for false positives before promoting):")
        for (gate_id, rule), s in sorted(shadow.items(), key=lambda kv: -kv[1]["n"]):
            print(f"  {s['n']:5d}  {gate_id}  {rule}  ({len(s['sessions'])} session(s))")
            for cmd in s["samples"]:
                print("         e.g. " + " ".join(cmd.split())[:160])
    return 0


if __name__ == "__main__":
    sys.exit(main())
