#!/usr/bin/env python3
"""
loop-status — detect wedged Bash calls and stale ScheduleWakeup across local
Claude Code sessions.

Scans ~/.claude/projects/**/*.jsonl transcripts, pairs each tool_use block with
its tool_result, and reports tool_use blocks left UNMATCHED past a staleness
threshold — the signature of a parked/wedged session (a Bash call whose result
never came back, or a ScheduleWakeup that never fired). Read-only.

Ported (lean) from affaan-m/ECC scripts/loop-status.js, 2026-05-30 — core
detection only; the upstream --watch / --write-dir snapshot machinery is
intentionally omitted (re-run on demand instead).

Usage:
  loop-status.py [--bash-timeout-seconds N] [--json] [--all]
    --bash-timeout-seconds N  age before a pending tool is "stale" (default 1800 = 30m)
    --json                    machine-readable output
    --all                     scan every session (default: only sessions whose
                              transcript was modified in the last 24h)

Exit: 0 = nothing stale, 1 = at least one stale signal found.
"""
import argparse
import glob
import json
import os
import sys
from datetime import datetime, timezone

PROJECTS = os.path.expanduser("~/.claude/projects")


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def iter_tool_blocks(entry):
    """Yield ('use', id, name) / ('result', tool_use_id, None) from an entry."""
    msg = entry.get("message") or {}
    content = msg.get("content")
    if not isinstance(content, list):
        return
    for b in content:
        if not isinstance(b, dict):
            continue
        t = b.get("type")
        if t == "tool_use" and b.get("id"):
            yield ("use", b["id"], b.get("name", "?"))
        elif t == "tool_result" and b.get("tool_use_id"):
            yield ("result", b["tool_use_id"], None)


def scan_session(path, now, bash_timeout):
    pending = {}  # tool_use id -> (name, timestamp)
    last_ts = None
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts = parse_ts(entry.get("timestamp")) or last_ts
                if ts:
                    last_ts = ts
                for kind, key, name in iter_tool_blocks(entry):
                    if kind == "use":
                        pending[key] = (name, ts)
                    else:
                        pending.pop(key, None)
    except OSError:
        return None

    signals = []
    for name, ts in pending.values():
        if name not in ("Bash", "ScheduleWakeup"):
            continue
        age = (now - ts).total_seconds() if ts else None
        if age is not None and age >= bash_timeout:
            signals.append({
                "type": "stale_bash" if name == "Bash" else "stale_wakeup",
                "tool": name,
                "age_seconds": int(age),
            })
    return {
        "session": os.path.basename(path),
        "pending": len(pending),
        "signals": signals,
        "last_activity": last_ts.isoformat() if last_ts else None,
    }


def main():
    ap = argparse.ArgumentParser(description="Detect wedged Bash / stale ScheduleWakeup across Claude sessions.")
    ap.add_argument("--bash-timeout-seconds", type=int, default=1800)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--all", action="store_true")
    args = ap.parse_args()

    now = datetime.now(timezone.utc)
    files = sorted(
        glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True),
        key=os.path.getmtime,
        reverse=True,
    )
    if not args.all:
        cutoff = now.timestamp() - 24 * 3600
        files = [f for f in files if os.path.getmtime(f) >= cutoff]

    results = []
    for f in files:
        r = scan_session(f, now, args.bash_timeout_seconds)
        if r is not None:
            results.append(r)
    flagged = [r for r in results if r["signals"]]

    if args.json:
        print(json.dumps({"scanned": len(results), "flagged": flagged}, indent=2))
        return 1 if flagged else 0

    if not flagged:
        print(f"OK — scanned {len(results)} session(s), no stale Bash / pending ScheduleWakeup.")
        return 0

    print(f"⚠ {len(flagged)} session(s) with stale signals:\n")
    for r in flagged:
        print(f"  {r['session']}  (last activity {r['last_activity']})")
        for s in r["signals"]:
            age = s.get("age_seconds")
            age_str = f"{age // 60}m{age % 60}s" if age is not None else "unknown age"
            print(f"    - {s['type']}: {s['tool']} pending {age_str}")
    print("\nOpen the transcript or interrupt the parked session.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
