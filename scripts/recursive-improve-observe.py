#!/usr/bin/env python3
"""recursive-improve-observe — the Observe step of the human-gated improvement
ritual (harness-recursive-improvement Phase 4, claude/skills/recursive-improve).

Reads the governance journal's `verification_summary` events (emitted by
`verification-gate.sh` at SessionEnd — the one session-scopable verification
feed), keeps the LATEST event per session, and surfaces sessions whose `gaps`
count is > 0 as improvement triggers. That is the data the ritual acts on: a
gap means a feature shipped `no-trail` without a named `optout_reason`.

Read-only. Exit 0 always (a report for a human to act on, not a gate). The
journal is parsed via governance-summary.py's `load_jsonl` — the single JSONL
parser, no second one (same contract as verification-tier-audit.py).

This script only OBSERVES. It does not rank, propose, or run harness-audit —
that judgment belongs to the ritual (SKILL.md). It also never infers: it
reports the posture the journal recorded, nothing more.

Usage:
    recursive-improve-observe.py [--journal PATH]
"""
import argparse
import importlib.util
import os
import sys
from pathlib import Path

JOURNAL_DEFAULT = os.path.join(os.path.expanduser("~"), ".claude", "governance-events.jsonl")

# verification_summary integer fields, in display order.
FIELDS = ["features", "tdd_provenance", "analyzer_pass", "no_trail", "gaps"]


def _load_governance_reader():
    """Import load_jsonl from governance-summary.py (hyphenated filename → importlib).
    Reusing it is the 'no new journal parser' contract: one parse/fail-loud path."""
    path = Path(__file__).resolve().parent / "governance-summary.py"
    spec = importlib.util.spec_from_file_location("governance_summary", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load governance-summary.py from {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)  # main() is __main__-guarded — no side effects on import
    return mod.load_jsonl


def _latest_per_session(summaries):
    """Keep the most recent verification_summary per session. The journal is
    append-only, so an earlier gappy event and a later clean one can coexist for
    one session; only the latest reflects current posture. ts is ISO8601 UTC
    (one producer), so a lexical max is the chronological max; a missing ts sorts
    earliest so a real timestamp always wins."""
    latest = {}
    for e in summaries:
        sid = e.get("session")
        ts = e.get("ts") or ""
        prev = latest.get(sid)
        if prev is None or ts >= (prev.get("ts") or ""):
            latest[sid] = e
    return latest


def _ints(fields):
    """The five verification_summary counts as ints. A missing field → 0 (an absent
    optional field is not corruption). A field that is PRESENT but unparseable is
    coerced to 0 AND surfaced to stderr — silently zeroing it would mask a real gap,
    and the codebase's rule is malformed→surface (verification-gate.sh counts a
    malformed tier as a gap, not as clean). load_jsonl already fails loud on a corrupt
    LINE; this guards the field level."""
    out = {}
    for k in FIELDS:
        raw = fields.get(k, 0)
        try:
            out[k] = int(raw or 0)
        except (TypeError, ValueError):
            out[k] = 0
            if raw is not None and raw != "":
                print(f"warning: unparseable {k}={raw!r} — treating as 0", file=sys.stderr)
    return out


def main():
    ap = argparse.ArgumentParser(description="surface verification_summary gaps for the improvement ritual")
    ap.add_argument("--journal", default=JOURNAL_DEFAULT, help="governance journal path")
    args = ap.parse_args()

    load_jsonl = _load_governance_reader()
    evts, n_corrupt, existed = load_jsonl(args.journal)

    print(f"=== recursive-improve: verification posture (journal: {args.journal}) ===\n")
    if not existed:
        print("(no journal yet — nothing to observe)")
        sys.exit(0)

    summaries = [e for e in evts if e.get("event") == "verification_summary"]
    if not summaries:
        print("(no verification_summary events recorded yet — run a session with a .scratch/<feature>/verification-trail.md)")
        if n_corrupt:
            print(f"({n_corrupt} corrupt journal line(s) skipped — see stderr)")
        sys.exit(0)

    latest = _latest_per_session(summaries)
    rows = sorted(((sid, _ints(e.get("fields") or {})) for sid, e in latest.items()),
                  key=lambda r: r[0] or "")

    print(f"{'session':24} {'features':>8} {'tdd':>4} {'analyzer':>8} {'no_trail':>8} {'gaps':>5}")
    print(f"{'-'*24} {'-'*8} {'-'*4} {'-'*8} {'-'*8} {'-'*5}")
    tot = {k: 0 for k in FIELDS}
    for sid, c in rows:
        print(f"{(sid or '?'):24} {c['features']:>8} {c['tdd_provenance']:>4} "
              f"{c['analyzer_pass']:>8} {c['no_trail']:>8} {c['gaps']:>5}")
        for k in FIELDS:
            tot[k] += c[k]

    print(f"\ntotals: {len(rows)} session(s) · {tot['features']} feature(s) · "
          f"tdd-provenance={tot['tdd_provenance']} · analyzer-pass={tot['analyzer_pass']} · "
          f"no-trail={tot['no_trail']} · gaps={tot['gaps']}")
    if n_corrupt:
        print(f"({n_corrupt} corrupt journal line(s) skipped — see stderr)")

    triggers = [(sid, c) for sid, c in rows if c["gaps"] > 0]
    if triggers:
        print("\nimprovement triggers (sessions with verification gaps):")
        for sid, c in triggers:
            print(f"  - {sid}: {c['gaps']} gap(s) — feature(s) shipped no-trail without a named optout_reason")
        print("\nnext: run `harness-audit` for concrete candidates, then propose → ask → act → verify.")
    else:
        print("\nno verification gaps recorded — harness verification posture is clean.")

    sys.exit(0)


if __name__ == "__main__":
    main()
