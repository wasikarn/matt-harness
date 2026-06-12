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
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

JOURNAL_DEFAULT = os.path.join(os.path.expanduser("~"), ".claude", "governance-events.jsonl")
LOOP_STATUS = Path(__file__).resolve().parent / "loop-status.py"
# Stalled if the most recent activity is older than this AND the scan flagged
# any signal. 10m matches the plan's threshold_min=10 default; tune via
# --stall-threshold-min for tighter/looser operator posture.
DEFAULT_STALL_THRESHOLD_MIN = 10

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


def check_stall(projects_dir=None, threshold_min=DEFAULT_STALL_THRESHOLD_MIN):
    """Return a stall posture dict for the observe step.

    Wraps scripts/loop-status.py (the wedged-Bash / stale-ScheduleWakeup detector
    ported from affaan-m/ECC, 2026-05-30) and reduces its output to a single
    operator-facing signal. Always returns a dict; never raises. `stalled` is True
    only when loop-status flagged AT LEAST ONE signal AND its oldest flag is past
    the threshold — a parked tool with low age is "pending", not "stalled".

    Contract (per SYNTHESIS row #11 / loop-engineering-closure-roadmap P2.1):
        - Pure read-only — never mutates journal, transcript, or session state.
        - Never blocks, never auto-pauses. Surfaces a suggested_action string for
          the operator to act on. ADR 0002 autonomy invariant: human-gated only.
        - Projects dir is overridable (loop-status.py's --projects-dir) so
          regression fixtures can mock against a temp dir without touching
          ~/.claude/projects. The default still points at the real transcript
          tree in production.
    """
    cmd = [sys.executable, str(LOOP_STATUS), "--json", "--all"]
    if projects_dir:
        cmd.extend(["--projects-dir", str(projects_dir)])

    posture = {
        "stalled": False,
        "scanned": 0,
        "flagged": 0,
        "oldest_signal_age_min": 0,
        "signal_types": [],
        "suggested_action": "no action — loop posture is clean",
        "error": None,
    }
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        posture["error"] = f"{type(e).__name__}: {e}"
        return posture

    if r.returncode not in (0, 1):
        # loop-status signals "1 stale" as rc=1; anything else is a real error.
        posture["error"] = f"loop-status rc={r.returncode}: {r.stderr.strip()[:200]}"
        return posture

    try:
        j = json.loads(r.stdout) if r.stdout.strip() else {}
    except json.JSONDecodeError as e:
        posture["error"] = f"loop-status JSON parse: {e}"
        return posture

    flagged = j.get("flagged") or []
    posture["scanned"] = j.get("scanned", 0)
    posture["flagged"] = len(flagged)
    if not flagged:
        return posture

    # Find the oldest signal across all flagged sessions, in minutes.
    oldest_age_s = 0
    sig_types = set()
    for sess in flagged:
        last = sess.get("last_activity")
        last_ts = None
        if last:
            try:
                last_ts = datetime.fromisoformat(last.replace("Z", "+00:00"))
            except ValueError:
                pass
        sess_max_age = 0
        for s in sess.get("signals") or []:
            sig_types.add(s.get("type", "?"))
            age = s.get("age_seconds") or 0
            if age > sess_max_age:
                sess_max_age = age
        # If we can anchor to last_activity, the signal age is bounded by the
        # recency of the session itself; otherwise fall back to the signal's
        # reported age_seconds.
        anchored = sess_max_age
        if last_ts:
            anchored = max(sess_max_age, int((datetime.now(timezone.utc) - last_ts).total_seconds()))
        if anchored > oldest_age_s:
            oldest_age_s = anchored

    posture["oldest_signal_age_min"] = oldest_age_s // 60
    posture["signal_types"] = sorted(sig_types)
    if posture["oldest_signal_age_min"] >= threshold_min:
        posture["stalled"] = True
        if "stale_bash" in sig_types:
            posture["suggested_action"] = (
                f"wedged Bash call ≥{posture['oldest_signal_age_min']}m old — "
                "interrupt the parked session or inspect the transcript before continuing"
            )
        elif "stale_wakeup" in sig_types:
            posture["suggested_action"] = (
                f"ScheduleWakeup did not fire for {posture['oldest_signal_age_min']}m — "
                "check loop context (cache window / wake-prompt) before continuing"
            )
        else:
            posture["suggested_action"] = (
                f"{len(flagged)} session(s) flagged, oldest signal "
                f"{posture['oldest_signal_age_min']}m — review before continuing"
            )
    return posture


def main():
    ap = argparse.ArgumentParser(description="surface verification_summary gaps for the improvement ritual")
    ap.add_argument("--journal", default=JOURNAL_DEFAULT, help="governance journal path")
    ap.add_argument("--stall-threshold-min", type=int, default=DEFAULT_STALL_THRESHOLD_MIN,
                    help="minutes of staleness that flips a flagged session to 'stalled' (default 10)")
    ap.add_argument("--projects-dir", default=None,
                    help="override the projects root for the stall scan (passed to loop-status.py --projects-dir)")
    ap.add_argument("--no-stall-check", action="store_true",
                    help="skip the loop-status stall scan (for fixtures / quick runs)")
    args = ap.parse_args()

    print(f"=== recursive-improve: verification posture (journal: {args.journal}) ===\n")

    # Loop posture — surfaces wedged Bash / stale ScheduleWakeup before the
    # verification summary. A parked session corrupts the verification signal
    # (the metric for this session may itself be stale), so the operator sees
    # the stall FIRST and can decide whether the gaps table below is
    # trustworthy. NEVER auto-pauses (ADR 0002).
    if not args.no_stall_check:
        posture = check_stall(projects_dir=args.projects_dir, threshold_min=args.stall_threshold_min)
        if posture["error"]:
            print(f"loop posture: ERROR — {posture['error']} (continuing)\n")
        else:
            print("loop posture:")
            print(f"  scanned:  {posture['scanned']} session(s)")
            print(f"  flagged:  {posture['flagged']} (oldest signal: {posture['oldest_signal_age_min']}m)")
            if posture["signal_types"]:
                print(f"  types:    {', '.join(posture['signal_types'])}")
            if posture["stalled"]:
                print(f"  ⚠ STALLED  ({posture['suggested_action']})")
            else:
                print(f"  ok:       {posture['suggested_action']}")
            print()

    load_jsonl = _load_governance_reader()
    evts, n_corrupt, existed = load_jsonl(args.journal)

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
