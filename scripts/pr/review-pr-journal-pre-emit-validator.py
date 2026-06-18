#!/usr/bin/env python3
"""
review-pr-journal-pre-emit-validator — pre-emit gate for /review-pr journaler.

This is Layer 2 of the two-layer design in `hooks/JOURNAL-SCHEMA.md`. The
journaler (`scripts/pr/review-pr-journal.py`) is Layer 1: best-effort
emitter that WARNINGs on enum-miss but emits anyway (Q3=a "silent FYI,
never unwinds"). The validator is Layer 2: a pre-emit check that runs
BEFORE the journaler and EXITS 2 if any finding carries an enum-miss,
letting the caller (typically `/review-pr` SKILL.md) AskUserQuestion
the human before any journal append happens.

Why split: an enum-miss verdict that silently appears in the governance
stream gets aggregated downstream as if it were a strict-tier verdict
— the fresh-context audit's 2026-06-11 FLAG-4 case. A separate
pre-emit gate (ask, not deny, per the autonomy invariant) preserves
the journaler's best-effort semantics AND gives the human a chance to
see the drift before it lands in the stream.

Importantly, the journaler does NOT call this validator — the caller
(`/review-pr` SKILL.md step 4) is responsible for running validator
first, then journaler. This keeps Layer 1 unchanged (Q3=a preserved)
and the new Layer 2 additive.

Usage: review-pr-journal-pre-emit-validator.py <scratch_dir>
  scratch_dir/findings.jsonl — per-finding JSONL stream (same shape the
                              journaler reads)
  scratch_dir/.journaled     — per-pair manifest; findings already
                              journaled are SKIPPED (the manifest
                              proves they passed the gate previously)

Exit codes:
  0 — all findings pass enum validation (or all enum-miss findings are
      already in the manifest, i.e. previously passed)
  2 — one or more findings have an enum-miss that is NOT already in
      the manifest; caller MUST ask the human before invoking the
      journaler. Stderr names every offending finding + field.
  2 — findings.jsonl missing/not a regular file, or corrupt JSONL line
      (same fail-loud contract as the journaler).

Lockstep contract: the enum regexes are imported from
review-pr-journal.py so a schema change there propagates here
automatically. Do NOT re-declare the enums in this file.
"""

import argparse
import json
import os
import sys
from pathlib import Path

# Import the journaler's enum regexes — single source of truth.
# The journaler is `scripts/pr/review-pr-journal.py` (hyphenated, exact filename
# = its import name on Python ≥3); we import the module by the same name.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import importlib

rj = importlib.import_module("review-pr-journal")  # noqa: E402

HOOK_ID = "review-pr-pre-emit-validator"


def _check_finding_enums(obj):
    """Return a list of (field, value) tuples for every enum-miss in this
    finding. Empty list = passes. Same regexes as the journaler's
    `_check_enums` (re-imported, not duplicated).
    """
    misses = []
    tier = obj.get("tier")
    if tier is not None and (not isinstance(tier, str) or not rj.TIER_OK.match(tier)):
        misses.append(("tier", tier))
    disposition = obj.get("disposition")
    if disposition is not None and (
        not isinstance(disposition, str) or not rj.DISPOSITION_OK.match(disposition)
    ):
        misses.append(("disposition", disposition))
    decision = obj.get("decision")
    if decision is not None and (
        not isinstance(decision, str) or not rj.DECISION_OK.match(decision)
    ):
        misses.append(("decision", decision))
    return misses


def _load_manifest_local_ids(mark_path):
    """Load .journaled → set of local_id keys. Manifest entries are
    'already passed' and don't need re-validation. On malformed JSONL
    fail loud (same contract as the journaler, test R analog).
    """
    if not os.path.exists(mark_path):
        return set()
    seen = set()
    try:
        with open(mark_path, "r", encoding="utf-8") as f:
            for ln, raw in enumerate(f, 1):
                if not raw.strip():
                    continue
                try:
                    obj = json.loads(raw)
                except json.JSONDecodeError:
                    print(
                        f"{HOOK_ID}: ERROR: {mark_path} line {ln} is not "
                        f"valid JSONL; refusing to validate (a prior run "
                        f"left garbage; fix or delete the manifest)",
                        file=sys.stderr,
                    )
                    sys.exit(2)
                lid = obj.get("local_id")
                if lid:
                    seen.add(lid)
    except (OSError, PermissionError) as e:
        print(
            f"{HOOK_ID}: ERROR: manifest read failed at {mark_path} "
            f"({type(e).__name__}: {e}); refusing to validate without a "
            f"complete dedup set",
            file=sys.stderr,
        )
        sys.exit(2)
    return seen


def main():
    ap = argparse.ArgumentParser(prog="review-pr-journal-pre-emit-validator", add_help=False)
    ap.add_argument(
        "scratch_dir",
        help="Path to the /review-pr scratch dir; must contain findings.jsonl",
    )
    args = ap.parse_args()

    sdir = args.scratch_dir
    findings_path = os.path.join(sdir, "findings.jsonl")
    mark_path = os.path.join(sdir, ".journaled")

    if not os.path.isfile(findings_path):
        print(
            f"{HOOK_ID}: ERROR: missing or not a regular file at {findings_path}; "
            f"cannot validate without findings",
            file=sys.stderr,
        )
        sys.exit(2)

    already_journaled = _load_manifest_local_ids(mark_path)

    n_checked = 0
    n_skipped_already = 0
    n_miss_findings = []  # list of (local_id, [(field, value), ...])

    with open(findings_path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                print(
                    f"{HOOK_ID}: ERROR: corrupt JSONL line at "
                    f"{findings_path}: {line}",
                    file=sys.stderr,
                )
                sys.exit(2)
            if not isinstance(obj, dict):
                # Not a finding; skip silently — the journaler will
                # already skip + log this category.
                continue

            local_id = obj.get("local_id") or ""
            if local_id in already_journaled:
                n_skipped_already += 1
                continue
            if not local_id or not isinstance(local_id, str):
                # local_id is required; treat as a miss (the journaler
                # would fail-loud on this too). The validator surfaces
                # it as a missing-local_id miss so the human sees one
                # combined report.
                n_miss_findings.append(
                    (local_id or "<missing>", [("local_id", local_id)])
                )
                continue

            misses = _check_finding_enums(obj)
            if misses:
                n_miss_findings.append((local_id, misses))
            n_checked += 1

    if n_miss_findings:
        print(
            f"{HOOK_ID}: ASK-GATE: {len(n_miss_findings)} finding(s) failed "
            f"enum validation; AskUserQuestion will surface the choice (proceed/pause/cancel):",
            file=sys.stderr,
        )
        for local_id, misses in n_miss_findings:
            miss_str = ", ".join(
                f"{field}={value!r}" for field, value in misses
            )
            print(f"  - local_id={local_id}: {miss_str}", file=sys.stderr)
        print(
            f"{HOOK_ID}: checked {n_checked} finding(s); {n_skipped_already} "
            f"already in manifest; {len(n_miss_findings)} blocked. "
            f"Per Q3=a + the two-layer design: this validator is Layer 2 "
            f"(ask-gate), the journaler is Layer 1 (best-effort, runs after).",
            file=sys.stderr,
        )
        sys.exit(2)

    print(
        f"{HOOK_ID}: OK: {n_checked} finding(s) passed enum validation "
        f"({n_skipped_already} already in manifest). Journaler is safe to run.",
        file=sys.stderr,
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
