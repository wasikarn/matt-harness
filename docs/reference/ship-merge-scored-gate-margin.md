# ship-merge scored-gate margin invariant

Deep-dive for anyone editing `commands/ship-merge.md` Phase 1 step 6's criteria table, weights,
or the 70/40 thresholds. Not needed to run `/ship-merge` — read this only when changing the gate
itself.

## Background

Phase 1 step 6's automation-bias guard scores the Critical-findings criterion **0** (but keeps
its 30 weight in the denominator, not renormalized away) whenever a sensitive-path diff was
reviewed `own-branch` instead of `pr-by-number`. That criterion is also exempt from the 40-point
fatal-weakness floor — the sole exemption in the gate — so the merge doesn't STOP purely because
of the deliberate zero; it has to fail the weighted 70-point threshold on its own merits instead.

## The worked numbers

A solo/no-CI repo has CI verified-N/A (drops out of the weight base), leaving Critical (30,
scored 0) + freshness (20) + coverage (10) = 60 weight base:

    (30·0 + 20·100 + 10·100) ÷ 60 = 50   → below 70 → STOP

A repo with real CI keeps every remaining criterion in play:

    (30·0 + 25·100 + 20·100 + 10·100) ÷ 85 ≈ 64.7   → still below 70 → STOP

Notice the no-CI case (50) scores *lower* than the real-CI case (≈64.7) despite an identical
automation-bias zero. Excluding a passing criterion from the denominator concentrates the zeroed
criterion's proportional weight (30/60 = 50% vs. 30/85 ≈ 35%) — less deterministic signal makes
the self-tiered claim *harder* to overcome, not easier. A no-CI repo is not the more lenient case
for this guard; it's the stricter one.

With Approval status removed from scoring (2026-07-23 — GitHub doesn't count the author's own
approval, so it could never clear for a self-authored PR), a sensitive-path own-branch review can
no longer pass Phase 1 on deterministic signals alone, however green CI is.

## The margin invariant

This margin is a **live invariant to re-check after any edit to the table above** — not a
one-time property of a single new row, and not fully captured by recomputing only the
non-Critical sum.

The general breakpoint: `(D × 100) ÷ (C + D) ≥ 70`, where `D` is the combined weight of every
criterion *except* Critical findings and `C` is Critical findings' own current weight. Solving
gives `D ≥ (7/3) × C`.

At today's `C = 30` that's `D ≥ 70`:

- CI-present case starts at `D = 55` — a `+15` delta breaks it.
- No-CI case starts at `D = 30` — a `+40` delta breaks it.

One new criterion at weight ≥15, several smaller criteria summed across separate future edits, or
an *existing* criterion re-weighted upward (e.g. CI status 25→40) all reach it.

**Those two starting numbers assume `C` stays at 30.** Lowering Critical findings' own weight,
alone, with nothing else touched, moves the breakpoint itself and won't show up if you only
recompute `D`. Concretely: `C: 30→23` with `D` unchanged at 55 gives `5500 ÷ 78 ≈ 70.5` —
defeated, even though `D` never moved.

**After any table change, recompute both `C` and `D` and re-solve the ratio** — don't validate
one edit against a fixed printed threshold and assume the table as a whole is still safe. Not
hypothetical: the 2026-07-23 Approval-status removal already moved this arithmetic once.

## Known gap (filed 2026-07-29, `/kbg:compliance-audit` on v0.68.97 — not yet closed)

This invariant only covers edits to the criteria table's own weights (`C` and `D`). The "70" pass
threshold — shared infrastructure across this whole scored gate, also referenced by the floor
rule and the N/A-renormalization logic — can be edited directly (e.g. `70` → `60`) to reach the
identical bypass with zero edits to the table, and nothing in this guard's recheck trigger ("any
edit to the table above") would flag it. Closing it properly means auditing the shared threshold
across all of Phase 1 step 6, not just this guard — out of scope for a single-paragraph fix, left
open pending a dedicated pass.
