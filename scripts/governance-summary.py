#!/usr/bin/env python3
"""governance-summary — read-back for the write-only governance telemetry streams.

The hooks emit ~7 audit streams into ~/.claude/*.log (+ governance-events.jsonl),
but nothing reads them — a half-closed feedback loop (sensor with no analysis).
This is the analysis end: digest the streams, flag anomalies, show recent activity.

Usage:
    python3 governance-summary.py            # full digest
    python3 governance-summary.py --since 7  # only last N days
    python3 governance-summary.py --stream bypass-audit   # one stream, full

Read-only. Never mutates the logs. Exit 0 always (reporting tool, not a gate).
"""
import argparse
import json
import os
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone

CLAUDE_DIR = os.path.join(os.path.expanduser("~"), ".claude")

# Tab-delimited streams. Value = 0-based index of the "category" field used for
# the breakdown (None = free-text, no breakdown). Verified against live logs
# 2026-05-30: every hook writes `printf '%s\t...'` — TAB, not pipe.
TAB_STREAMS = {
    "evidence-trail.log": 2,        # tool (WebSearch/WebFetch)
    "bypass-audit.log": 3,          # [DISABLED_HOOKS] list (bracket-wrapped at column 3)
    "fabrication-verdict.log": 4,   # verdict (fabricated/clean/doesn't exist)
    "auto-mode-denials.log": None,  # free-text reason
    "post-edit-audit.log": 3,       # finding code prefix (LARGE_FILE:…)
    "security-diff-review.log": 3,  # finding code prefix (MISSING_AUTH:…)
    "config-change.log": 3,         # changed path (dedup target)
}
JSONL_STREAMS = ["governance-events.jsonl"]  # structured nested-envelope journal

# Event registry — claude/hooks/JOURNAL-SCHEMA.md is the SSOT; this set must
# mirror its table. The two can drift (markdown vs code), but the cost is bounded:
# an event not listed here is WARNED, never dropped — the taxonomy is open so a
# new producer can ship before the registry is updated. That warn-on-unknown is
# the drift safety-net, so a full SSOT-codegen isn't worth it for five events.
KNOWN_EVENTS = {
    "security_finding", "config_change", "fabrication_verdict",
    "bypass_audit", "review_finding", "verification_verdict",
    "verification_summary",
}

# Streams that dual-write into governance-events.jsonl during migration (B1).
# Maps the legacy TSV basename -> the hook id its JSONL twin carries, so a
# dual-written event is deduped on (hook, ts_second, category) — JSONL wins.
# Only the migrated logger appears here; other TSV streams never collide.
DUAL_WRITTEN = {
    "config-change.log": "config-change-log",
}

# A stream averaging more than this many lines/calendar-day = runaway noise.
RUNAWAY_PER_DAY = 200


def parse_ts(line):
    """Leading ISO8601 token before the first TAB. None if unparseable."""
    head = line.split("\t", 1)[0].strip()
    try:
        return datetime.fromisoformat(head)  # py3.11+ accepts trailing Z
    except ValueError:
        return None


def category(line, idx):
    """Tab field at idx, reduced to its leading token (strips ': detail')."""
    if idx is None:
        return None
    parts = line.split("\t")
    if idx >= len(parts):
        return "?"
    return _lead_token(parts[idx])


def _lead_token(s):
    """First ':'/whitespace-delimited token of s; '?' if empty. Same reduction
    category() applies to TSV fields, so JSONL and TSV dedup keys line up."""
    tokens = str(s).split(":")[0].split()
    return tokens[0] if tokens else "?"


def jsonl_key(ev):
    """(hook, ts_second_iso, category) for cross-stream dedup; None if incomplete.
    Reads the nested `fields` with a flat fallback (e.get('category')) so events
    written before the nested-envelope migration still key correctly (B1)."""
    hook = ev.get("hook")
    fields = ev.get("fields") or {}
    cat = (fields.get("category") or ev.get("category")
           or fields.get("path") or fields.get("file"))
    dt = parse_ts(ev.get("ts", ""))
    if not (hook and dt and cat):
        return None
    return (hook, dt.replace(microsecond=0).isoformat(), _lead_token(cat))


def _within(ts, cutoff):
    """True if ts is at/after cutoff, or unparseable (mirrors load_lines). Stays
    robust to legacy naive-ts journal events written before the aware-ts
    migration: a naive-vs-aware compare raises TypeError, which we treat as
    'keep' rather than crash the digest (Rule 12). Once every producer emits an
    aware ts, this guard becomes dead and can be dropped."""
    if ts is None:
        return True
    try:
        return ts >= cutoff
    except TypeError:
        return True


def load_jsonl(path):
    """Parse a JSONL journal fail-loud: returns (events, n_corrupt, existed).
    A corrupt line is logged to stderr with its line number and skipped — one
    bad append never sinks the whole digest (the old list-comprehension at this
    spot crashed the entire run on the first malformed line)."""
    if not os.path.exists(path):
        return [], 0, False
    evts, n_corrupt = [], 0
    name = os.path.basename(path)
    with open(path, errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            if not line.strip():
                continue
            try:
                evts.append(json.loads(line))
            except json.JSONDecodeError as e:
                n_corrupt += 1
                print(f"warning: corrupt JSONL line {i} in {name}: {e}", file=sys.stderr)
    return evts, n_corrupt, True


def load_lines(path, since_days):
    if not os.path.exists(path):
        return None  # distinguish "missing" from "empty"
    cutoff = None
    if since_days is not None:
        cutoff = datetime.now(timezone.utc).astimezone() - timedelta(days=since_days)
    rows = []
    with open(path, errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            ts = parse_ts(line)
            # _within guards a naive-vs-aware compare: security-diff-review.log
            # writes a naive (no-Z) ts, which would otherwise crash --since here.
            if cutoff is not None and not _within(ts, cutoff):
                continue
            rows.append((ts, line))
    return rows


def day_span(rows):
    """Calendar days from first to last timestamp (inclusive). Min 1."""
    dates = [ts.date() for ts, _ in rows if ts]
    if not dates:
        return 1
    return (max(dates) - min(dates)).days + 1


def digest_stream(name, rows, cat_idx):
    """One-line summary + top categories + runaway flag (calendar-day rate)."""
    total = len(rows)
    span = day_span(rows)
    per_day = total / span
    flag = "  ⚠️ RUNAWAY" if per_day > RUNAWAY_PER_DAY else ""
    cats = Counter(c for c in (category(l, cat_idx) for _, l in rows) if c)
    top = ", ".join(f"{v}×{c}" for v, c in cats.most_common(3)) if cats else "(free-text)"
    return f"{name:26} {total:>6} lines / {span:>2}d ({per_day:>5.0f}/day){flag}\n{'':28}{top}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", type=int, metavar="DAYS", help="only events in last N days")
    ap.add_argument("--stream", help="dump one stream's recent lines instead of digest")
    args = ap.parse_args()

    if args.stream:
        path = os.path.join(CLAUDE_DIR, args.stream if "." in args.stream else args.stream + ".log")
        rows = load_lines(path, args.since)
        if rows is None:
            print(f"missing: {path}")
            return
        for _, line in rows[-50:]:
            print(line)
        return

    scope = f"last {args.since}d" if args.since else "all time"
    print(f"=== governance telemetry digest ({scope}) — {CLAUDE_DIR} ===\n")

    anomalies = []

    # Load the evidence journal(s) FIRST so the TAB-stream loop can dedup a
    # dual-written event against its JSONL twin (B1: JSONL wins). Fail-loud.
    jsonl_loaded = {}
    dedup_keys = set()
    for name in JSONL_STREAMS:
        evts, n_corrupt, existed = load_jsonl(os.path.join(CLAUDE_DIR, name))
        if args.since is not None and evts:
            cutoff = datetime.now(timezone.utc).astimezone() - timedelta(days=args.since)
            evts = [e for e in evts if _within(parse_ts(e.get("ts", "")), cutoff)]
        jsonl_loaded[name] = (evts, n_corrupt, existed)
        for e in evts:
            k = jsonl_key(e)
            if k:
                dedup_keys.add(k)

    dropped_dups = 0
    for name, cat_idx in TAB_STREAMS.items():
        rows = load_lines(os.path.join(CLAUDE_DIR, name), args.since)
        if rows is None:
            print(f"{name:26} — missing")
            continue
        if not rows:
            print(f"{name:26}      0 lines")
            continue
        # B1 dedup: for a dual-written stream, drop each TSV line whose
        # (hook, ts_second, category) twin already lives in the JSONL journal.
        dup_hook = DUAL_WRITTEN.get(name)
        if dup_hook and dedup_keys:
            kept = []
            for ts, line in rows:
                key = (dup_hook,
                       ts.replace(microsecond=0).isoformat() if ts else None,
                       category(line, cat_idx))
                if key[1] is not None and key in dedup_keys:
                    dropped_dups += 1
                else:
                    kept.append((ts, line))
            rows = kept
        if not rows:
            print(f"{name:26}      0 lines (all deduped vs journal)")
            continue
        print(digest_stream(name, rows, cat_idx))
        span = day_span(rows)
        if len(rows) / span > RUNAWAY_PER_DAY:
            # name the dominant value so the cause is visible, not just the symptom
            vals = Counter(l.split("\t")[cat_idx] for _, l in rows
                           if cat_idx is not None and len(l.split("\t")) > cat_idx)
            top = vals.most_common(1)
            detail = f" — {top[0][1]}/{len(rows)} are {os.path.basename(top[0][0])}" if top else ""
            anomalies.append(f"{name}: {len(rows)} lines / {span}d ≈ {len(rows)//span}/day{detail}")
        print()

    for name in JSONL_STREAMS:
        evts, n_corrupt, existed = jsonl_loaded[name]
        if not existed:
            print(f"{name:26} — never emitted (no qualifying event yet)")
            continue
        if not evts:
            # empty-existing vs all-corrupt are different failures (mirror the
            # missing-vs-empty distinction load_lines makes for TSV).
            if n_corrupt:
                print(f"{name:26} — ALL {n_corrupt} line(s) corrupt (parse failed)")
                anomalies.append(f"{name}: all {n_corrupt} line(s) corrupt — journal unreadable")
            else:
                print(f"{name:26}      0 events (empty)")
            continue
        kinds = Counter(e.get("event", "?") for e in evts)
        suffix = f"  +{n_corrupt} corrupt" if n_corrupt else ""
        print(f"{name:26} {len(evts):>6} events  ({', '.join(f'{k}×{c}' for k, c in kinds.most_common())}){suffix}")
        # verification_summary carries exit_reason (F4 — Five Honest Exit Reasons).
        # Surface the session-posture breakdown so the digest tells you not just
        # *how many* summaries fired, but *how the sessions ended*.
        vs_evts = [e for e in evts if e.get("event") == "verification_summary"]
        if vs_evts:
            exit_counts = Counter((e.get("fields") or {}).get("exit_reason", "?") for e in vs_evts)
            print(f"{'':28}verification_summary exit_reason: {', '.join(f'{v}×{k}' for k, v in exit_counts.most_common())}")
        unknown = sorted({e.get("event", "?") for e in evts} - KNOWN_EVENTS)
        if unknown:
            print(f"{'':28}⚠️ unknown event(s) not in registry: {', '.join(unknown)}")
            anomalies.append(f"{name}: unknown event(s) {', '.join(unknown)} — update JOURNAL-SCHEMA.md")
        if n_corrupt:
            anomalies.append(f"{name}: {n_corrupt} corrupt line(s) skipped (see stderr)")

    if dropped_dups:
        print(f"\n  {dropped_dups} cross-stream duplicate(s) deduped (JSONL wins)")

    if anomalies:
        print("\n--- anomalies ---")
        for a in anomalies:
            print(f"  ⚠️ {a}")


if __name__ == "__main__":
    main()
