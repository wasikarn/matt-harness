#!/usr/bin/env python3
"""Deterministic ranker for mh:ideate Phase 2.

stdin:  {"scores": {"<ideaId>": {"novelty": 0-10, "viability": 0-10, "fit": 0-10,
                                  "trap": null | "<reason>"}, ...}, "topK": 3}
stdout: {"totals": {id: float}, "shortlist": [id...], "runnerUp": id | null,
         "nonObviousPick": id | null, "traps": [id...]}

The model scores and writes reasons; this script does the arithmetic (weighted
total, ordering, top-K, runner-up, non-obvious pick) so a wrong hand sum can
never reach the output. Run with --selftest to check it.
"""
import json
import math
import sys

W = (0.35, 0.40, 0.25)  # novelty, viability, fit; viability heaviest by design


def _die(reason):
    print(f"rank.py: {reason}", file=sys.stderr)
    sys.exit(1)


def _validated(item_id, s):
    # 2026-09-20 audit: this script's own docstring claims to mirror
    # scripts/_lib/weighted-score.py's contract ("this script does the
    # arithmetic... so a wrong hand sum can never reach the output") -- that
    # file was hardened against exactly this input class, this one wasn't.
    # A bool is silently 0/1 in arithmetic (True * 0.35 == 0.35), and
    # Python's json module accepts the non-standard NaN/Infinity/-Infinity
    # literals by default -- either would silently corrupt totals/ordering
    # with no error (nan comparisons are always False, so sorted()/max()
    # never raise on one).
    for k in ("novelty", "viability", "fit"):
        v = s.get(k)
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            _die(f"'{item_id}'.{k} must be numeric, not bool: {v!r}")
        if isinstance(v, float) and not math.isfinite(v):
            _die(f"'{item_id}'.{k} must be finite: {v!r}")
    return s


def rank(payload):
    scores = payload["scores"]
    for i, s in scores.items():
        _validated(i, s)
    top_k = int(payload.get("topK", 3))
    totals = {
        i: round(s["novelty"] * W[0] + s["viability"] * W[1] + s["fit"] * W[2], 2)
        for i, s in scores.items()
    }
    traps = [i for i, s in scores.items() if s.get("trap")]
    ranked = sorted((i for i in scores if i not in traps),
                    key=lambda i: (-totals[i], i))
    shortlist = ranked[:top_k]
    runner_up = ranked[top_k] if len(ranked) > top_k else None
    pick = max(shortlist, key=lambda i: (scores[i]["novelty"] + scores[i]["viability"] * 0.5, -ranked.index(i))) if shortlist else None
    return {"totals": totals, "shortlist": shortlist, "runnerUp": runner_up,
            "nonObviousPick": pick, "traps": traps}


def _selftest():
    out = rank({"topK": 2, "scores": {
        "a": {"novelty": 7, "viability": 6, "fit": 8, "trap": None},
        "b": {"novelty": 9, "viability": 9, "fit": 9, "trap": "false economy"},
        "c": {"novelty": 3, "viability": 9, "fit": 9, "trap": None},
        "d": {"novelty": 8, "viability": 5, "fit": 5, "trap": None},
    }})
    assert out["totals"]["a"] == 6.85, out["totals"]
    assert out["traps"] == ["b"]
    assert out["shortlist"] == ["c", "a"], out["shortlist"]  # c=7.9, a=6.85, d=6.05
    assert out["runnerUp"] == "d"
    assert out["nonObviousPick"] == "a"  # a: 7+3=10 beats c: 3+4.5=7.5
    assert rank({"scores": {}})["runnerUp"] is None

    # Non-finite and boolean scores must fail closed, not silently corrupt
    # the ranking (2026-09-20 audit).
    for bad in (
        {"a": {"novelty": True, "viability": 8, "fit": 7, "trap": None}},
        {"a": {"novelty": float("nan"), "viability": 8, "fit": 7, "trap": None}},
        {"a": {"novelty": float("inf"), "viability": 8, "fit": 7, "trap": None}},
        {"a": {"novelty": "7", "viability": 8, "fit": 7, "trap": None}},
    ):
        try:
            rank({"scores": bad})
            raise AssertionError(f"expected rank() to reject {bad!r}")
        except SystemExit as e:
            assert e.code == 1

    print("rank.py selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        json.dump(rank(json.load(sys.stdin)), sys.stdout, indent=2)
        print()
