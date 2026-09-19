#!/usr/bin/env python3
"""Deterministic weighted scorer for mh:deep-audit and mh:idea-audit.

stdin:  {"scores": [{"id": str, "score": num, "max": num, "weight": num,
                      "insufficient": bool}, ...],
         "floorPct": 0-1, "passThreshold": num | omitted, "primaryId": str | omitted}
stdout: {"total": float, "weightSum": float, "belowFloor": [id...],
         "pass": bool | null, "primaryWeightOk": bool | null}

The model scores each dimension and writes reasons; this script does the
arithmetic (weighted total, floor check, pass/fail) so a wrong hand sum or a
hand-renormalized total can never reach a Final Verdict. Mirrors
skills/workflow/ideate/scripts/rank.py's contract and --selftest convention.

An `insufficient`-flagged item is dropped from both the numerator and the
denominator, so `total` renormalizes over the weights that actually scored
-- never divides by the full declared weight sum, which would be
arithmetically identical to scoring the dropped item 0.

Fails closed: any input this script cannot compute (a missing/non-numeric
field, a bool or non-finite score/max/weight, a non-positive max or negative
weight, a duplicate id, every item flagged insufficient, or the `primaryId`
item itself flagged insufficient) exits 1 with a one-line reason on stderr
and prints no JSON. The last case matters because `insufficient` items are
dropped from the total's numerator/denominator (see below) with no separate
signal -- for an ordinary axis that's a fair renormalization, but for the
axis a caller declared `primaryId` (the one that "can't be diluted to
parity" per mh:idea-audit's own Rule 14 rationale) it would silently produce
a complete-looking total with the single most load-bearing axis missing.
Found by mh:deep-audit 2026-09-19: idea-audit's own SKILL.md deliberately
omits `passThreshold` for this phase ("a scored verdict... not a single
pass/fail gate"), so nothing downstream was catching this case either.
The caller must treat that as a hard fail, never as license to score by hand.
"""
import json
import math
import sys
from typing import NoReturn


def _die(reason: str) -> NoReturn:
    print(f"weighted-score: {reason}", file=sys.stderr)
    sys.exit(1)


def score(payload):
    items = payload.get("scores")
    if not isinstance(items, list) or not items:
        _die("'scores' must be a non-empty list")
    weight_sum = 0.0
    scored_weight_sum = 0.0
    raw_sum = 0.0
    below_floor = []
    floor_pct = payload.get("floorPct", 0.0)
    primary_id = payload.get("primaryId")
    primary_insufficient = False
    seen_ids = set()
    for it in items:
        try:
            item_id, s, m, w = it["id"], it["score"], it["max"], it["weight"]
            insufficient = bool(it.get("insufficient", False))
        except (KeyError, TypeError):
            _die(f"malformed score entry: {it!r}")
        for x in (s, m, w):
            if isinstance(x, bool) or not isinstance(x, (int, float)):
                _die(f"score/max/weight must be numeric, not bool: {it!r}")
            if isinstance(x, float) and not math.isfinite(x):
                _die(f"score/max/weight must be finite: {it!r}")
        if m <= 0:
            _die(f"'{item_id}': max must be positive, got {m}")
        if w < 0:
            _die(f"'{item_id}': weight must be non-negative, got {w}")
        if item_id in seen_ids:
            _die(f"duplicate id '{item_id}' in scores")
        seen_ids.add(item_id)
        weight_sum += w
        if insufficient:
            if item_id == primary_id:
                primary_insufficient = True
            continue
        scored_weight_sum += w
        raw_sum += (s / m) * w
        if (s / m) < floor_pct:
            below_floor.append(item_id)
    if scored_weight_sum == 0:
        _die("every item is insufficient evidence; cannot compute a total")
    if primary_insufficient:
        _die(f"primaryId '{primary_id}' is insufficient evidence; a total that drops the "
             f"single largest-weighted axis and renormalizes over the rest is not a "
             f"meaningful score, it's the floor tripping under another name")
    total = round(raw_sum / scored_weight_sum * weight_sum, 2)

    pass_threshold = payload.get("passThreshold")
    verdict = None
    if pass_threshold is not None:
        verdict = total >= pass_threshold and not below_floor

    primary_ok = None
    if primary_id is not None:
        weights = {it["id"]: it["weight"] for it in items}
        if primary_id not in weights:
            _die(f"primaryId '{primary_id}' not found among scores")
        primary_w = weights[primary_id]
        primary_ok = all(primary_w > w for pid, w in weights.items() if pid != primary_id)

    return {"total": total, "weightSum": weight_sum, "belowFloor": below_floor,
            "pass": verdict, "primaryWeightOk": primary_ok}


def _selftest():
    dims = [
        {"id": "correctness", "score": 8, "max": 10, "weight": 3, "insufficient": False},
        {"id": "completeness", "score": 7, "max": 10, "weight": 2, "insufficient": False},
        {"id": "claim_accuracy", "score": 9, "max": 10, "weight": 2, "insufficient": False},
        {"id": "regression_safety", "score": 6, "max": 10, "weight": 2, "insufficient": False},
        {"id": "simplicity", "score": 8, "max": 10, "weight": 1, "insufficient": False},
    ]
    out = score({"scores": dims, "floorPct": 0.5, "passThreshold": 7.0})
    assert out["total"] == 7.6, out["total"]
    assert out["belowFloor"] == []
    assert out["pass"] is True

    # Mark regression_safety insufficient: renormalized total must differ from
    # the divide-by-full-weight-sum value (which equals scoring it 0 -> 6.4).
    dims_partial = [dict(d) for d in dims]
    dims_partial[3] = {**dims_partial[3], "insufficient": True}
    out2 = score({"scores": dims_partial, "floorPct": 0.5, "passThreshold": 7.0})
    assert out2["total"] == 8.0, out2["total"]  # renormalized: (2.4+1.4+1.8+0.8)/8*10
    wrong_divide_by_full = round(sum(
        (d["score"] / d["max"]) * d["weight"] for d in dims if d["id"] != "regression_safety"
    ), 2)
    assert wrong_divide_by_full == 6.4 and wrong_divide_by_full != out2["total"]

    # Floor trip: a scored (not insufficient) dim under floorPct of its own max.
    dims_low = [dict(d) for d in dims]
    dims_low[4] = {**dims_low[4], "score": 4}  # 4/10 = 0.4 < 0.5 floor
    out3 = score({"scores": dims_low, "floorPct": 0.5, "passThreshold": 7.0})
    assert out3["belowFloor"] == ["simplicity"]
    assert out3["pass"] is False

    # All-insufficient must fail closed, not divide by zero.
    try:
        score({"scores": [{"id": "x", "score": 5, "max": 10, "weight": 1, "insufficient": True}]})
        raise AssertionError("expected SystemExit on all-insufficient input")
    except SystemExit as e:
        assert e.code == 1

    # Malformed input (max <= 0) fails closed, not with a ZeroDivisionError.
    try:
        score({"scores": [{"id": "x", "score": 5, "max": 0, "weight": 1, "insufficient": False}]})
        raise AssertionError("expected SystemExit on max<=0")
    except SystemExit as e:
        assert e.code == 1

    # primaryId strictly-greatest check (idea-audit's never-tied-for-first rule).
    axes = [
        {"id": "fidelity", "score": 80, "max": 100, "weight": 40, "insufficient": False},
        {"id": "fit", "score": 70, "max": 100, "weight": 30, "insufficient": False},
        {"id": "risk", "score": 60, "max": 100, "weight": 30, "insufficient": False},
    ]
    assert score({"scores": axes, "primaryId": "fidelity"})["primaryWeightOk"] is True
    axes_tied = [dict(a) for a in axes]
    axes_tied[1] = {**axes_tied[1], "weight": 40}
    assert score({"scores": axes_tied, "primaryId": "fidelity"})["primaryWeightOk"] is False

    # The primaryId axis marked insufficient must fail closed, not silently
    # renormalize the total over the remaining axes as if the primary axis
    # never existed -- the single largest-weighted axis vanishing without a
    # trace is the floor tripping under another name.
    axes_primary_insufficient = [dict(a) for a in axes]
    axes_primary_insufficient[0] = {**axes_primary_insufficient[0], "insufficient": True}
    try:
        score({"scores": axes_primary_insufficient, "primaryId": "fidelity"})
        raise AssertionError("expected SystemExit when the primaryId axis is insufficient")
    except SystemExit as e:
        assert e.code == 1

    # A non-primary axis marked insufficient must NOT trip this new check --
    # only ever hits the ordinary renormalization path.
    axes_other_insufficient = [dict(a) for a in axes]
    axes_other_insufficient[1] = {**axes_other_insufficient[1], "insufficient": True}
    out_other = score({"scores": axes_other_insufficient, "primaryId": "fidelity"})
    assert out_other["primaryWeightOk"] is True, out_other

    # A duplicate id must not be silently allowed to defeat the strictly-
    # greatest check by collapsing to one entry in the weights dict.
    axes_dup = axes + [{**axes[1], "weight": 40}]  # second "fit" entry, tied weight
    try:
        score({"scores": axes_dup, "primaryId": "fidelity"})
        raise AssertionError("expected SystemExit on duplicate id")
    except SystemExit as e:
        assert e.code == 1

    # Non-finite and boolean scores must fail closed, not silently coerce or
    # let json's non-standard Infinity/NaN literals flip a rubric to pass:true.
    for bad in (
        [{"id": "a", "score": float("inf"), "max": 10, "weight": 3, "insufficient": False},
         {"id": "b", "score": 3, "max": 10, "weight": 2, "insufficient": False}],
        [{"id": "a", "score": float("nan"), "max": 10, "weight": 3, "insufficient": False},
         {"id": "b", "score": 5, "max": 10, "weight": 2, "insufficient": False}],
        [{"id": "a", "score": True, "max": 10, "weight": 3, "insufficient": False},
         {"id": "b", "score": 5, "max": 10, "weight": 2, "insufficient": False}],
    ):
        try:
            score({"scores": bad, "passThreshold": 7.0})
            raise AssertionError(f"expected SystemExit on non-numeric/non-finite input: {bad}")
        except SystemExit as e:
            assert e.code == 1

    # Floor boundary: a score exactly at floorPct * max must NOT trip
    # belowFloor -- the check is strictly '<', not '<='. Discriminates a
    # future <= regression, which both idea-audit/SKILL.md and the CHANGELOG
    # now state as the documented behavior.
    at_floor = score({"scores": [{"id": "x", "score": 5, "max": 10, "weight": 1,
                                   "insufficient": False}], "floorPct": 0.5})
    assert at_floor["belowFloor"] == [], at_floor

    print("weighted-score.py selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        json.dump(score(json.load(sys.stdin)), sys.stdout, indent=2)
        print()
