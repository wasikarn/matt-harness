#!/usr/bin/env python3
"""recursive-improve-observe — the Observe step of the human-gated improvement
ritual (harness-recursive-improvement Phase 4, skills/recursive-improve).

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
LOOP_STATUS = Path(__file__).resolve().parent.parent / "governance" / "loop-status.py"
# Stalled if the most recent activity is older than this AND the scan flagged
# any signal. 10m matches the plan's threshold_min=10 default; tune via
# --stall-threshold-min for tighter/looser operator posture.
DEFAULT_STALL_THRESHOLD_MIN = 10
# Comprehension debt ceiling: pause the loop when debt_count exceeds this.
# Default 5 (per spec §4.4 example). Override via KBG_DEBT_CEILING env var
# (production) or --debt-ceiling flag (ad-hoc + tests).
DEFAULT_DEBT_CEILING = 5
# Comprehension debt ledger: where each component comes from.
# - unverified_changes: derived from the journal's `verification_summary.gaps`
#   summed across latest per-session (what the script already aggregates).
# - unreviewed_audit_findings: SECURITY + REVIEW findings in the journal
#   emitted within the last `DEBT_REVIEW_WINDOW_DAYS` (default 30) that have
#   no matching `verification_verdict` referencing the same `subject_id`.
# - open_prs: NOT in the journal (no pr_opened event). Sourced from the
#   `KBG_DEBT_OPEN_PRS` env var so the operator (or fixture) sets it manually.
#   The honest reflection is that PR count is the operator's local knowledge;
#   wiring gh CLI here would couple observe.py to a host primitive it doesn't
#   own (per bounded-context-dispatch: read DOMAINS.md, don't inline).
DEBT_REVIEW_WINDOW_DAYS = 30

# verification_summary integer fields, in display order.
FIELDS = ["features", "tdd_provenance", "analyzer_pass", "no_trail", "gaps"]


def _load_governance_reader():
    """Import load_jsonl from governance-summary.py (hyphenated filename → importlib).
    Reusing it is the 'no new journal parser' contract: one parse/fail-loud path."""
    path = Path(__file__).resolve().parent.parent / "governance" / "governance-summary.py"
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

    Wraps scripts/governance/loop-status.py (the wedged-Bash / stale-ScheduleWakeup detector
    ported from affaan-m/ECC, 2026-05-30) and reduces its output to a single
    operator-facing signal. Always returns a dict; never raises. `stalled` is True
    only when loop-status flagged AT LEAST ONE signal AND its oldest flag is past
    the threshold — a parked tool with low age is "pending", not "stalled".

    Contract (per SYNTHESIS row #11 / loop-engineering-closure-roadmap P2.1):
        - Pure read-only — never mutates journal, transcript, or session state.
        - Never blocks, never auto-pauses. Surfaces a suggested_action string for
          the operator to act on. the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model autonomy invariant: human-gated only.
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


def compute_debt_ledger(evts, now=None, open_prs=None):
    """Count comprehension debt items per spec §4.4 / SYNTHESIS #41.

    debt_count = open_prs + unverified_changes + unreviewed_audit_findings

    Each component is sourced honestly:
      - open_prs: env var `KBG_DEBT_OPEN_PRS` (int) or the `open_prs` arg
        (used by the CLI to forward the env var). We do NOT shell out to
        `gh` — the journal has no pr_opened event, and the operator's local
        PR count is the truthful source.
      - unverified_changes: sum of `gaps` across the latest verification_summary
        per session (same `_latest_per_session` reduction used in main()).
      - unreviewed_audit_findings: security_finding + review_finding events
        in the last DEBT_REVIEW_WINDOW_DAYS that have no matching
        verification_verdict referencing them as `subject_id`.

    Returns a dict with all three components, the total, and a `within_window`
    int (count of audit findings actually scanned — for transparency).

    Read-only over `evts`; never mutates, never raises. Bad input coerces
    to 0 + stderr warning (same policy as `_ints`).
    """
    from datetime import timedelta
    if now is None:
        now = datetime.now(timezone.utc)
    # ---- open_prs (env / arg) ----
    if open_prs is None:
        env_val = os.environ.get("KBG_DEBT_OPEN_PRS", "0").strip()
        try:
            open_prs = int(env_val or "0")
        except ValueError:
            print(f"warning: KBG_DEBT_OPEN_PRS={env_val!r} unparseable — treating as 0", file=sys.stderr)
            open_prs = 0

    # ---- unverified_changes (from verification_summary) ----
    summaries = [e for e in evts if e.get("event") == "verification_summary"]
    latest = _latest_per_session(summaries)
    unverified_changes = 0
    for e in latest.values():
        f = e.get("fields") or {}
        raw = f.get("gaps", 0)
        try:
            unverified_changes += int(raw or 0)
        except (TypeError, ValueError):
            print(f"warning: gaps={raw!r} unparseable — treating as 0", file=sys.stderr)

    # ---- unreviewed_audit_findings (findings without verdicts, in window) ----
    cutoff_ts = (now - timedelta(days=DEBT_REVIEW_WINDOW_DAYS)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    verdict_subjects = set()
    for e in evts:
        if e.get("event") == "verification_verdict":
            sid = (e.get("fields") or {}).get("subject_id")
            if sid:
                verdict_subjects.add(sid)
    findings = [
        e for e in evts
        if e.get("event") in ("security_finding", "review_finding")
        and (e.get("ts") or "") >= cutoff_ts
    ]
    within_window = len(findings)
    unreviewed = sum(1 for f in findings if f.get("id") not in verdict_subjects)

    return {
        "open_prs": open_prs,
        "unverified_changes": unverified_changes,
        "unreviewed_audit_findings": unreviewed,
        "within_window_findings": within_window,
        "debt_count": open_prs + unverified_changes + unreviewed,
    }


def read_learning_candidates():
    """Read-only Route-B (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model addendum): shell out to the single queue reader
    scripts/read-candidates.sh (avoids the sync-seam audit #37-40 guards) and return
    the open learning candidates, merged + confidence-ranked. NEVER writes the queue.
    Returns [] on clean/empty, None if the reader is missing."""
    script = Path(__file__).resolve().parent.parent / "read-candidates.sh"
    if not script.exists():
        return None
    try:
        out = subprocess.run(["bash", str(script)], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    rows = []
    for ln in out.stdout.splitlines():
        ln = ln.strip()
        if not ln:
            continue
        try:
            rows.append(json.loads(ln))
        except json.JSONDecodeError:
            continue
    return rows


def main():
    ap = argparse.ArgumentParser(description="surface verification_summary gaps for the improvement ritual")
    ap.add_argument("--journal", default=JOURNAL_DEFAULT, help="governance journal path")
    ap.add_argument("--stall-threshold-min", type=int, default=DEFAULT_STALL_THRESHOLD_MIN,
                    help="minutes of staleness that flips a flagged session to 'stalled' (default 10)")
    ap.add_argument("--projects-dir", default=None,
                    help="override the projects root for the stall scan (passed to loop-status.py --projects-dir)")
    ap.add_argument("--no-stall-check", action="store_true",
                    help="skip the loop-status stall scan (for fixtures / quick runs)")
    ap.add_argument("--debt-ceiling", type=int,
                    default=int(os.environ.get("KBG_DEBT_CEILING", str(DEFAULT_DEBT_CEILING))),
                    help="comprehension-debt ceiling (env: KBG_DEBT_CEILING, default 5). "
                         "Pause the loop and surface a warning when debt_count exceeds this.")
    ap.add_argument("--debt-open-prs", type=int, default=None,
                    help="override KBG_DEBT_OPEN_PRS for this run (test/fixture escape hatch)")
    ap.add_argument("--no-debt-check", action="store_true",
                    help="skip the comprehension-debt ledger (for fixtures / quick runs)")
    args = ap.parse_args()

    print(f"=== recursive-improve: verification posture (journal: {args.journal}) ===\n")

    # Loop posture — surfaces wedged Bash / stale ScheduleWakeup before the
    # verification summary. A parked session corrupts the verification signal
    # (the metric for this session may itself be stale), so the operator sees
    # the stall FIRST and can decide whether the gaps table below is
    # trustworthy. NEVER auto-pauses (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model).
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

    # Comprehension debt ledger (SYNTHESIS #41 / spec §4.4). Counts three
    # sources of "what stays manual" — the operator's loop can only act on
    # what they've actually reviewed. When debt_count exceeds the ceiling,
    # surface a PAUSE warning. NEVER auto-blocks (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model) — the operator
    # decides whether to drain the queue or accept the breach.
    if not args.no_debt_check:
        # Read the journal here (load_jsonl is pure; safe to call once).
        _load_jsonl = _load_governance_reader()
        _evts, _, _existed = _load_jsonl(args.journal)
        debt = compute_debt_ledger(_evts, open_prs=args.debt_open_prs)
        print("comprehension debt ledger:")
        print(f"  open_prs:                  {debt['open_prs']}  (KBG_DEBT_OPEN_PRS or --debt-open-prs)")
        print(f"  unverified_changes:        {debt['unverified_changes']}  (sum of latest verification_summary.gaps)")
        print(f"  unreviewed_audit_findings: {debt['unreviewed_audit_findings']}  "
              f"(of {debt['within_window_findings']} findings in last {DEBT_REVIEW_WINDOW_DAYS}d, "
              "no verification_verdict.subject_id match)")
        print(f"  debt_count:                {debt['debt_count']} / ceiling {args.debt_ceiling}")
        if debt["debt_count"] > args.debt_ceiling:
            print(f"  ⚠ DEBT-CEILING BREACHED  ({debt['debt_count']} > {args.debt_ceiling} — "
                  "PAUSE new proposals and drain the queue before iterating)")
        else:
            print(f"  ok:    within ceiling (headroom = {args.debt_ceiling - debt['debt_count']})")
        print()
        # Surface the breach but DO NOT sys.exit(1) — observe is a sensor.
        # The SKILL.md Step 1 callout is the operator-facing pause signal.

    # Learning-candidate queue (Route B, the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model addendum) — read-only. This is a
    # DIFFERENT queue from the comprehension-debt ledger above: that one is "what
    # stays manual"; this one is passively-captured operator corrections/preferences
    # awaiting kbg:learn triage. In L3 --auto, a high-confidence row is an eligible
    # candidate (one per cycle, applied gated at push); the loop READS, never writes
    # the queue (the human drains it via kbg:learn). Default-OFF unless KBG_LEARN_CAPTURE=1.
    cands = read_learning_candidates()
    if cands:
        print("learning-candidate queue (passive capture — kbg:learn to triage):")
        print(f"  open:   {len(cands)} candidate(s)")
        for c in cands[:3]:
            trig = (c.get("trigger") or "").replace("\n", " ")[:60]
            print(f"  - [{c.get('confidence', 0):.2f}] {c.get('kind', '?')}: {trig}")
        if len(cands) > 3:
            print(f"  … and {len(cands) - 3} more")
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
