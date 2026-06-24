#!/usr/bin/env python3
# harness-health.py — read-only query surface over the governance journal.
# See skills/harness-health/SKILL.md for the contract; see
# docs/research/inferential-structural-judge-design.md §3 (verdict schema)
# and §7 SURF-1 (the surfacing contract). Stdlib only, no subprocess.

import argparse
import datetime as dt
import json
import os
import sys

DEFAULT_JOURNAL = os.path.expanduser("~/.claude/governance-events.jsonl")
DEFAULT_SENSORS = "hooks/sensors.json"
VERDICT = "inferential_structural_verdict"
SKIPPED = "inferential_structural_verdict_skipped"
JUDGMENT = (VERDICT, SKIPPED)


def warn(msg):
    print(f"[harness-health] WARN: {msg}", file=sys.stderr)


def load_journal(path):
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


def load_sensors(path):
    if not os.path.isfile(path):
        return [], False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return json.load(f).get("sensors", []), True
    except (OSError, ValueError) as e:
        warn(f"could not parse {path}: {e}")
        return [], False


def filter_events(events, args):
    out = list(events)
    if args.sensor:
        out = [e for e in out if e.get("hook") == args.sensor]
    if args.event_type == "verdict":
        out = [e for e in out if e.get("event") == VERDICT]
    elif args.event_type == "skipped":
        out = [e for e in out if e.get("event") == SKIPPED]
    if args.min_score is not None:
        out = [e for e in out
               if isinstance((e.get("fields") or {}).get("score"), (int, float))
               and e["fields"]["score"] >= args.min_score]
    if args.since is not None:
        cutoff = (dt.datetime.now(dt.timezone.utc)
                  - dt.timedelta(days=args.since)).isoformat(
            timespec="milliseconds").replace("+00:00", "Z")
        out = [e for e in out if e.get("ts", "") >= cutoff]
    if args.last is not None:
        out = out[-args.last:]
    return out


def render_verdicts(events, args):
    print(f"## Verdicts (n={len(events)})")
    print(f"journal: {args.journal}\n")
    if not events:
        print("0 events match")
        print(f"query: --min-score {args.min_score} --since {args.since} "
              f"--sensor {args.sensor} --last {args.last}")
        return
    print("| ts | score | recommendation | hook | top_finding |")
    print("|---|---|---|---|---|")
    for e in events:
        f = e.get("fields") or {}
        tf = (f.get("top_finding") or "").replace("|", "\\|")[:80]
        print(f"| {e.get('ts','?')} | {f.get('score','?')} | "
              f"{f.get('recommendation','?')} | {e.get('hook','?')} | {tf} |")


def render_staleness(sensors, journal):
    # L553: fire count makes the silent sensor visible — a high score
    # on zero fires is indistinguishable from "no scoring happened".
    print("## Sensor staleness")
    print(f"sensors: {DEFAULT_SENSORS}  journal: {journal}\n")
    last_fired, fire_count = {}, {}
    for e in load_journal(journal):
        h = e.get("hook")
        if not h:
            continue
        ts = e.get("ts", "")
        if h not in last_fired or ts > last_fired[h]:
            last_fired[h] = ts
        fire_count[h] = fire_count.get(h, 0) + 1
    today = dt.datetime.now(dt.timezone.utc)
    print("| sensor | max_silent_days | last_fired | days_silent | fire_count | enabled |")
    print("|---|---|---|---|---|---|")
    for s in sensors:
        lf = last_fired.get(s["name"], "")
        ds = "(never)"
        if lf:
            try:
                ds = (today - dt.datetime.fromisoformat(
                    lf.replace("Z", "+00:00"))).days
            except ValueError:
                pass
        print(f"| {s['name']} | {s.get('max_silent_days','?')} | {lf or '(never)'} "
              f"| {ds} | {fire_count.get(s['name'], 0)} | {s.get('enabled','?')} |")


def render_dual_fire_count(sensors, journal):
    # L553 mitigation: verdict count + fired-event count per sensor. A
    # high score on zero fired events = "high quality" or "inadequate
    # detection" — show both so the operator can tell.
    print("## Dual fire-count (L553 mitigation)")
    print(f"sensors: {DEFAULT_SENSORS}  journal: {journal}\n")
    verdicts, events, last_score = {}, {}, {}
    for e in load_journal(journal):
        h = e.get("hook")
        if not h:
            continue
        events[h] = events.get(h, 0) + 1
        if e.get("event") in JUDGMENT:
            verdicts[h] = verdicts.get(h, 0) + 1
        if e.get("event") == VERDICT:
            f = e.get("fields") or {}
            if isinstance(f.get("score"), (int, float)):
                ts = e.get("ts", "")
                if h not in last_score or ts > last_score[h][0]:
                    last_score[h] = (ts, f["score"])
    print("| sensor | verdict_count | fired_event_count | last_verdict_score |")
    print("|---|---|---|---|")
    for s in sensors:
        ls = last_score.get(s["name"], (None, None))[1]
        print(f"| {s['name']} | {verdicts.get(s['name'], 0)} | "
              f"{events.get(s['name'], 0)} | "
              f"{ls if ls is not None else '(none)'} |")


def render_cost(journal, args):
    # Token usage from the cost-capture SessionEnd hook. Tokens only — no dollar
    # estimate (no honest local price signal; see hooks/session/cost-capture.sh).
    print("## Token usage (cost_capture)")
    print(f"journal: {journal}\n")
    rows = [e for e in load_journal(journal) if e.get("event") == "cost_capture"]
    if args.last is not None:
        rows = rows[-args.last:]
    if not rows:
        print("0 cost_capture events (the cost-capture SessionEnd hook journals one per session)")
        return
    print("| ts | session | messages | total | input | output | cache_write | cache_read |")
    print("|---|---|---|---|---|---|---|---|")
    grand = 0
    for e in rows:
        f = e.get("fields") or {}
        t = f.get("total")
        if isinstance(t, int):
            grand += t
        sid = (e.get("session") or "?")[:8]
        print(f"| {e.get('ts','?')} | {sid} | {f.get('messages','?')} | {f.get('total','?')} "
              f"| {f.get('input','?')} | {f.get('output','?')} | "
              f"{f.get('cache_write','?')} | {f.get('cache_read','?')} |")
    print(f"\n**Σ total tokens across {len(rows)} session(s): {grand:,}** "
          f"(tokens only — no $ estimate)")


def main():
    ap = argparse.ArgumentParser(prog="harness-health",
        description=("Read-only query surface over the governance journal. "
                     "Surfaces inferential-structural-judge verdicts and "
                     "sensor staleness."))
    ap.add_argument("--last", type=int, default=None, help="last N events (after other filters)")
    ap.add_argument("--since", type=float, default=None, help="events newer than N days")
    ap.add_argument("--min-score", type=float, default=None, help="filter verdicts with fields.score >= N")
    ap.add_argument("--sensor", default=None, help="filter by hook name")
    ap.add_argument("--event-type", choices=("verdict", "skipped", "all"),
                    default="all", help="verdict | skipped | all (default all)")
    ap.add_argument("--staleness", action="store_true", help="show per-sensor staleness + fire_count")
    ap.add_argument("--dual-fire-count", action="store_true",
                    help="L553 mitigation: verdict_count + fired_event_count per sensor")
    ap.add_argument("--cost", action="store_true",
                    help="show per-session token usage from cost_capture events (tokens only, no $)")
    ap.add_argument("--journal", default=DEFAULT_JOURNAL)
    ap.add_argument("--sensors", default=DEFAULT_SENSORS)
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON instead of markdown")
    if len(sys.argv) == 1:  # no CLI flags → print help + exit 0 (task spec; argparse exits 2 on no-args)
        ap.print_help(); return 0
    args = ap.parse_args()

    wants_verdicts = not (args.staleness or args.dual_fire_count or args.cost)
    if wants_verdicts and not os.path.isfile(args.journal):
        print(f"ERROR: journal not found: {args.journal}", file=sys.stderr); return 1
    if not wants_verdicts and not os.path.isfile(args.journal):
        warn(f"journal not found: {args.journal} — staleness will show all sensors silent")

    sensors, sensors_ok = load_sensors(args.sensors)
    if (args.staleness or args.dual_fire_count) and not sensors_ok:
        warn(f"sensors registry not found: {args.sensors} — skipping staleness output"); sensors = []

    filtered = filter_events(load_journal(args.journal), args)
    if args.json:
        print(json.dumps({
            "journal": args.journal, "sensors": args.sensors,
            "verdicts": [e for e in filtered if e.get("event") in JUDGMENT],
            "sensors_registry": sensors,
        }, indent=2, default=str))
        return 0
    if args.staleness and sensors: render_staleness(sensors, args.journal); print()
    if args.dual_fire_count and sensors: render_dual_fire_count(sensors, args.journal); print()
    if args.cost: render_cost(args.journal, args); print()
    if wants_verdicts: render_verdicts(filtered, args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
