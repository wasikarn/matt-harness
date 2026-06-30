#!/usr/bin/env python3
# harness-health.py — read-only query surface over the live cost ledger.
# Part of `kbg:harness-audit --health`; see skills/harness-audit/SKILL.md for the contract.
# The cost-tracker Stop hook appends one row per session to costs.jsonl
# (see hooks/stop/cost-tracker.sh). Stdlib only, no subprocess, no LLM in the loop.
#
# The verdict + staleness lenses that previously read the governance journal and
# hooks/sensors.json were retired in the v0.6.0 cut reconciliation — both sources
# are gone. --health now surfaces the one live signal: per-session token cost.

import argparse
import datetime as dt
import json
import os
import sys

DEFAULT_COSTS = os.path.expanduser("~/.local/share/kbg/metrics/costs.jsonl")


def warn(msg):
    print(f"[harness-health] WARN: {msg}", file=sys.stderr)


def load_rows(path):
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, raw in enumerate(f, 1):
            raw = raw.strip()
            if not raw:
                continue
            try:
                yield json.loads(raw)
            except ValueError:
                warn(f"skipping malformed line {n} in {path}")


def filter_rows(rows, args):
    out = list(rows)
    if args.since is not None:
        cutoff = (dt.datetime.now(dt.timezone.utc)
                  - dt.timedelta(days=args.since)).isoformat(
            timespec="milliseconds").replace("+00:00", "Z")
        out = [r for r in out if r.get("timestamp", "") >= cutoff]
    if args.last is not None:
        out = out[-args.last:]
    return out


def render_cost(rows):
    print(f"## Token usage (costs.jsonl)\nledger: {DEFAULT_COSTS}\n")
    if not rows:
        print("0 rows — the cost-tracker Stop hook appends one per session")
        return
    print("| ts | session | model | input | output | cache_write | cache_read | est_cost_usd |")
    print("|---|---|---|---|---|---|---|---|")
    gin = gout = gcw = gcr = 0
    gcost = 0.0
    for r in rows:
        i, o, cw, cr = (r.get("input_tokens", 0), r.get("output_tokens", 0),
                        r.get("cache_write_tokens", 0), r.get("cache_read_tokens", 0))
        cost = r.get("estimated_cost_usd", 0.0)
        gin += i; gout += o; gcw += cw; gcr += cr
        gcost += cost if isinstance(cost, (int, float)) else 0.0
        sid = (r.get("session_id") or "?")[:8]
        print(f"| {r.get('timestamp','?')} | {sid} | {r.get('model','?')} | {i:,} | "
              f"{o:,} | {cw:,} | {cr:,} | {cost:.4f} |")
    print(f"\n**Σ across {len(rows)} session(s): input {gin:,} · output {gout:,} · "
          f"cache_write {gcw:,} · cache_read {gcr:,} · est_cost ${gcost:.4f}** "
          f"(rates are heuristic — see hooks/stop/cost-tracker.sh)")


def main():
    ap = argparse.ArgumentParser(prog="harness-health",
        description="Read-only query surface over the live cost ledger (costs.jsonl).")
    ap.add_argument("--last", type=int, default=None, help="last N sessions (after other filters)")
    ap.add_argument("--since", type=float, default=None, help="sessions newer than N days")
    ap.add_argument("--costs", default=DEFAULT_COSTS, help="path to costs.jsonl ledger")
    ap.add_argument("--json", action="store_true", help="emit JSON instead of markdown")
    if len(sys.argv) == 1:  # no CLI flags → print help + exit 0
        ap.print_help(); return 0
    args = ap.parse_args()

    rows = list(filter_rows(load_rows(args.costs), args))
    if args.json:
        print(json.dumps({"ledger": args.costs, "sessions": rows}, indent=2, default=str))
        return 0
    if not rows and not os.path.isfile(args.costs):
        print(f"ERROR: ledger not found: {args.costs}", file=sys.stderr); return 1
    render_cost(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())