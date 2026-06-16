#!/usr/bin/env python3
"""harness-coverage.py — deterministic 12-cell harness-coverage aggregator.

Reads hooks/sensors.json and ~/.claude/governance-events.jsonl and
emits the 2x2x3 grid (Bockeler 2026-04, L356-L374 + L437-L479) per the
data contract in docs/research/harness-coverage-metric-design.md section 3.
Read-only: no LLM call, no subprocess, no network.
Exit codes: 0 = success (incl. missing-file degradation); 1 = hard error.
"""
import argparse
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_SENSORS_PATH = REPO_ROOT / "hooks" / "sensors.json"
DEFAULT_JOURNAL_PATH = Path.home() / ".claude" / "governance-events.jsonl"

# 2x2x3 Cartesian product (4 directions x 3 axes = 12 cells). The ids
# are the contract (section 2); not discovered from CLAUDE.md.
DIRECTIONS = ("comp-ff", "comp-fb", "inf-ff", "inf-fb")
AXES = ("maintainability", "arch-fit", "behaviour")
DIRECTION_PREFIX = {d: f"{d}-" for d in DIRECTIONS}
CELL_IDS = tuple(f"{d}-{a}" for d in DIRECTIONS for a in AXES)

# Known intentional-gap cell per section 3.4. Append new gaps here with
# the 4 required fields (rationale, article_citation, kbg_decision_ref,
# revisit_when). Cite an L-number or ADR section.
KNOWN_INTENTIONAL_GAPS = {
    "inf-fb-behaviour": {
        "rationale": (
            "Bockeler L465-L478 names behaviour-inferential-FB as the article's "
            "deepest open problem; kbg's verification-gate, fabrication-verdict-log, "
            "and inferential-structural-judge are advisory-only per ADR 0002 L115 "
            "(LLM-judge-circularity mitigation)."
        ),
        "article_citation": "L465-L478",
        "kbg_decision_ref": "ADR 0002 L115",
        "revisit_when": (
            "When a non-model-class judge (different model family) is available; "
            "the autonomy invariant forbids a model-driven gating decision from this "
            "cell in the meantime."
        ),
    },
}

# fallback_role in sensors.json (e.g. computational-FF) -> cell id (comp-ff).
FALLBACK_ROLE_TO_DIRECTION = {
    "computational-FF": "comp-ff", "computational-FB": "comp-fb",
    "inferential-FF": "inf-ff", "inferential-FB": "inf-fb",
}

# Verdict event types: inferential_structural_verdict carries fields.top_finding
# (non-null = meaningful, null = trivial); inferential_structural_verdict_skipped
# is fired-but-trivial (reason in fields.reason, e.g. budget, agent_absent).
VERDICT_EVENT_TYPES = frozenset(
    {"inferential_structural_verdict", "inferential_structural_verdict_skipped"}
)


def _make_cell(cell_id, direction, axis):
    """Empty cell dict pre-populated with all section-3 keys."""
    return {
        "cell_id": cell_id, "direction": direction, "axis": axis,
        "population": {"sensors_listed": 0, "sensors_enabled": 0},
        "activation": {"expected_events_per_window": 0, "actual_events_in_window": 0,
                       "fires_skipped_budget": 0, "fires_skipped_absent": 0},
        "verdict_quality": {"meaningful_fires": 0, "trivial_fires": 0,
                            "weight_meaningful": 0.7, "weight_trivial": 0.3, "weighted_score": 0.0},
        "cell_score_pct": 0, "drift_vs_prev_window_pct": 0,
        "status": "populated", "intentional_gap": None,
    }


def _load_registry(path):
    """Load hooks/sensors.json. Empty on missing file; sys.exit(1) on malformed JSON."""
    if not path.exists():
        print(f"warning: registry not found at {path}; treating as empty", file=sys.stderr)
        return {"version": 0, "sensors": []}
    try:
        data = json.load(path.open())
    except json.JSONDecodeError as e:
        print(f"error: malformed JSON in {path}: {e}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(data, dict) or "sensors" not in data:
        print(f"error: {path} missing top-level 'sensors' key", file=sys.stderr)
        sys.exit(1)
    if not isinstance(data["sensors"], list):
        print(f"error: {path} 'sensors' is not a list", file=sys.stderr)
        sys.exit(1)
    return data


def _stream_journal(path, since, until=None):
    """Yield events with since <= ts < until. Streaming; skips bad lines with a warning."""
    if not path.exists():
        print(f"warning: journal not found at {path}; treating as empty", file=sys.stderr)
        return
    with path.open() as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except json.JSONDecodeError as e:
                print(f"warning: {path}:{lineno} malformed JSON ({e}); skipping", file=sys.stderr)
                continue
            ts = _parse_ts(evt.get("ts"))
            if ts is None or ts < since:
                continue
            if until is not None and ts >= until:
                continue
            yield evt


def _parse_ts(raw):
    """ISO-8601 -> datetime. Naive timestamps are treated as UTC."""
    if not isinstance(raw, str) or not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def _cells_from_registry(registry, window_sessions, wm, wt):
    """Build the 12-cell map; sensors with no per-axis tag populate all 3 axes."""
    by_dir = {d: [] for d in DIRECTIONS}
    for sensor in registry.get("sensors", []):
        d = FALLBACK_ROLE_TO_DIRECTION.get(sensor.get("fallback_role") or "")
        if d and sensor.get("enabled", True):
            by_dir[d].append(sensor.get("name", ""))

    cells = {}
    for cell_id in CELL_IDS:
        direction, axis = next(
            ((d, cell_id[len(p):]) for d, p in DIRECTION_PREFIX.items() if cell_id.startswith(p)),
            (None, None),
        )
        if direction is None:
            continue
        cell = _make_cell(cell_id, direction, axis)
        names = by_dir[direction]
        cell["population"]["sensors_listed"] = len(names)
        cell["population"]["sensors_enabled"] = len(names)
        cell["activation"]["expected_events_per_window"] = window_sessions
        cell["verdict_quality"]["weight_meaningful"] = wm
        cell["verdict_quality"]["weight_trivial"] = wt
        if cell_id in KNOWN_INTENTIONAL_GAPS:
            cell["intentional_gap"] = KNOWN_INTENTIONAL_GAPS[cell_id]
            cell["status"] = "intentional_gap"
            cell["population"] = {"sensors_listed": 0, "sensors_enabled": 0}
            cell["activation"] = {"expected_events_per_window": 0, "actual_events_in_window": 0,
                                  "fires_skipped_budget": 0, "fires_skipped_absent": 0}
        cells[cell_id] = cell
    return cells


def _direction_sensor_index(registry):
    """direction -> set of enabled sensor names (membership lookup)."""
    return {d: {s.get("name", "") for s in registry.get("sensors", [])
                if FALLBACK_ROLE_TO_DIRECTION.get(s.get("fallback_role") or "") == d
                and s.get("enabled", True)}
            for d in DIRECTIONS}


def _aggregate_journal(cells, direction_sensors, events):
    """Apply each event to the matching-direction cell. Mutates in place.

    Journal uses `event` (not event_type), `hook` (not hook_name), `ts` (not
    timestamp); we accept both spellings. Events from hooks not in the
    registry are dropped.
    """
    for evt in events:
        event_type = evt.get("event") or evt.get("event_type")
        hook_name = evt.get("hook") or evt.get("hook_name")
        if not event_type or not hook_name:
            continue
        target = next((d for d, names in direction_sensors.items() if hook_name in names), None)
        if target is None:
            continue
        for cell in cells.values():
            if cell["direction"] == target:
                _apply_event_to_cell(cell, event_type, evt)


def _apply_event_to_cell(cell, event_type, evt):
    """Apply one event to one cell. Skipped events go to fires_skipped_*; verdict trivial/meaningful is per top_finding."""
    if event_type == "inferential_structural_verdict_skipped":
        reason = (evt.get("fields") or {}).get("reason", "")
        cell["activation"]["fires_skipped_absent" if reason == "agent_absent" else "fires_skipped_budget"] += 1
        cell["verdict_quality"]["trivial_fires"] += 1
        return
    if event_type not in VERDICT_EVENT_TYPES:
        cell["activation"]["actual_events_in_window"] += 1
        return
    cell["activation"]["actual_events_in_window"] += 1
    if (evt.get("fields") or {}).get("top_finding"):
        cell["verdict_quality"]["meaningful_fires"] += 1
    else:
        cell["verdict_quality"]["trivial_fires"] += 1


def _score_cells(cells, prev_scores):
    """Compute cell_score_pct, drift, and status (section 3.2 + 3.3)."""
    for cell in cells.values():
        if cell["status"] == "intentional_gap":
            continue
        vq = cell["verdict_quality"]
        m, t, wm, wt = vq["meaningful_fires"], vq["trivial_fires"], vq["weight_meaningful"], vq["weight_trivial"]
        vq["weighted_score"] = (m * wm + t * wt) / max(1, m + t)
        expected = max(1, cell["activation"]["expected_events_per_window"])
        cell["cell_score_pct"] = round(100 * (cell["activation"]["actual_events_in_window"] / expected) * vq["weighted_score"])
        if prev_scores is not None and cell["cell_id"] in prev_scores:
            cell["drift_vs_prev_window_pct"] = cell["cell_score_pct"] - prev_scores[cell["cell_id"]]
        if cell["intentional_gap"] is not None:
            cell["status"] = "intentional_gap"
        elif cell["population"]["sensors_listed"] == 0:
            cell["status"] = "coverage_hole"
        elif cell["activation"]["actual_events_in_window"] == 0:
            cell["status"] = "stale"
        else:
            cell["status"] = "populated"


def _global_rollup(cells):
    """Average over populated cells only (gaps/holes excluded from denominator)."""
    populated = [c for c in cells.values() if c["status"] == "populated"]
    n = max(1, len(populated))
    return {
        "populated_cells": len(populated),
        "coverage_hole_cells": sum(1 for c in cells.values() if c["status"] == "coverage_hole"),
        "intentional_gap_cells": sum(1 for c in cells.values() if c["status"] == "intentional_gap"),
        "global_score_pct": round(sum(c["cell_score_pct"] for c in populated) / n) if populated else 0,
        "drift_30d_pct": round(sum(c["drift_vs_prev_window_pct"] for c in populated) / n),
    }


def _render_json(cells, rollup, window_sessions):
    """Full section-3 schema. `grid` is ordered by CELL_IDS for stable diffs."""
    return {
        "schema_version": 1,
        "computed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
        "window_sessions": window_sessions,
        "grid": [cells[cid] for cid in CELL_IDS],
        "global": rollup,
    }


def _render_markdown(cells, rollup, window_sessions):
    """12-row markdown table: cell_id, status, score, drift, gap (truncated to 30 chars)."""
    header = "| cell_id | status | cell_score_pct | drift_pct | intentional_gap |\n|---|---|---:|---:|---|"
    rows = [header]
    for cid in CELL_IDS:
        c = cells[cid]
        gap = c["intentional_gap"]["rationale"][:30] + "..." if c["intentional_gap"] else ""
        rows.append(f"| {c['cell_id']} | {c['status']} | {c['cell_score_pct']} | {c['drift_vs_prev_window_pct']} | {gap} |")
    rollup_line = (f"\n**Global:** populated={rollup['populated_cells']} "
                   f"holes={rollup['coverage_hole_cells']} "
                   f"gaps={rollup['intentional_gap_cells']} "
                   f"score={rollup['global_score_pct']}% drift_30d={rollup['drift_30d_pct']}%\n")
    return "\n".join(rows) + rollup_line + f"_window_sessions={window_sessions}_\n"


def _build_parser():
    p = argparse.ArgumentParser(prog="harness-coverage.py",
                                 description="Deterministic 12-cell harness-coverage aggregator.")
    p.add_argument("--format", choices=("json", "markdown"), default="json", help="Output format (default: json)")
    p.add_argument("--window-sessions", type=int, default=30, help="Rolling window size in sessions (default: 30)")
    p.add_argument("--weight-meaningful", type=float, default=0.7, help="Weight for meaningful fires (default: 0.7)")
    p.add_argument("--weight-trivial", type=float, default=0.3, help="Weight for trivial fires (default: 0.3)")
    p.add_argument("--journal-path", type=Path, default=DEFAULT_JOURNAL_PATH,
                   help=f"Governance journal path (default: {DEFAULT_JOURNAL_PATH})")
    p.add_argument("--sensors-path", type=Path, default=DEFAULT_SENSORS_PATH,
                   help=f"Sensor registry path (default: {DEFAULT_SENSORS_PATH})")
    return p


def main(argv=None):
    args = _build_parser().parse_args(argv)
    if args.window_sessions <= 0:
        print("error: --window-sessions must be > 0", file=sys.stderr)
        return 1
    if args.weight_meaningful < 0 or args.weight_trivial < 0:
        print("error: weights must be non-negative", file=sys.stderr)
        return 1

    # Window cut-off in days: the metric is a 30-session rolling window
    # but the journal has no session-id -> wall-clock join table, so we
    # approximate with `window_sessions` days (capped at 180). Prior
    # window is `[prev_cut_off, cut_off)` so drift is the true deltas.
    window_days = min(180, max(1, args.window_sessions))
    now = datetime.now(timezone.utc)
    cut_off = now - timedelta(days=window_days)
    prev_cut_off = cut_off - timedelta(days=window_days)

    journal_exists = args.journal_path.exists()
    if not journal_exists:
        print(f"warning: journal not found at {args.journal_path}; treating as empty", file=sys.stderr)

    registry = _load_registry(args.sensors_path)
    cells = _cells_from_registry(registry, args.window_sessions, args.weight_meaningful, args.weight_trivial)
    prev_cells = _cells_from_registry(registry, args.window_sessions, args.weight_meaningful, args.weight_trivial)
    if journal_exists:
        idx = _direction_sensor_index(registry)
        _aggregate_journal(cells, idx, _stream_journal(args.journal_path, since=cut_off))
        _aggregate_journal(prev_cells, idx, _stream_journal(args.journal_path, since=prev_cut_off, until=cut_off))

    _score_cells(prev_cells, prev_scores=None)
    prev_scores = {cid: prev_cells[cid]["cell_score_pct"] for cid in CELL_IDS}
    _score_cells(cells, prev_scores=prev_scores)
    rollup = _global_rollup(cells)

    if args.format == "json":
        json.dump(_render_json(cells, rollup, args.window_sessions), sys.stdout, indent=2, sort_keys=False)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(_render_markdown(cells, rollup, args.window_sessions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
