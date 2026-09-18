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
field, a non-positive max or negative weight, or every item flagged
insufficient) exits 1 with a one-line reason on stderr and prints no JSON.
The caller must treat that as a hard fail, never as license to score by hand.
"""
import json
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
    for it in items:
        try:
            item_id, s, m, w = it["id"], it["score"], it["max"], it["weight"]
            insufficient = bool(it.get("insufficient", False))
        except (KeyError, TypeError):
            _die(f"malformed score entry: {it!r}")
        if not all(isinstance(x, (int, float)) for x in (s, m, w)):
            _die(f"score/max/weight must be numeric: {it!r}")
        if m <= 0:
            _die(f"'{item_id}': max must be positive, got {m}")
        if w < 0:
            _die(f"'{item_id}': weight must be non-negative, got {w}")
        weight_sum += w
        if insufficient:
            continue
        scored_weight_sum += w
        raw_sum += (s / m) * w
        if (s / m) < floor_pct:
            below_floor.append(item_id)
    if scored_weight_sum == 0:
        _die("every item is insufficient evidence; cannot compute a total")
    total = round(raw_sum / scored_weight_sum * weight_sum, 2)

    pass_threshold = payload.get("passThreshold")
    verdict = None
    if pass_threshold is not None:
        verdict = total >= pass_threshold and not below_floor

    primary_id = payload.get("primaryId")
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

    print("weighted-score.py selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        json.dump(score(json.load(sys.stdin)), sys.stdout, indent=2)
        print()
