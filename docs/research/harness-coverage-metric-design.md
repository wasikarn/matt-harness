# Harness-coverage metric — design

**Status:** design (DOC-1 complete; AGG-1, SKILL-1, FIX-1, DECAY-1, INT-1 downstream)
**Plan:** `.claude/tasks/harness-coverage-metric.md`
**Author:** LEAD-D (code-architect) on the `harness-coverage-metric` plan
**Date:** 2026-06-15
**Resolves:** all 12 Q items from the plan's Q&A log (per Q-table below)

> **Citations predate the v0.6.0 reset** (commit `c452102`). Some rule numbers, line
> citations, and skill/command names below (e.g. `METHODOLOGY.md Rule N`, `kbg:perf`,
> `/ship-task`) no longer resolve. Accurate as a snapshot of the harness at time of
> writing — not a live reference.

---

## 1. Purpose & placement in the harness

Böckeler (2026-04, L553, verbatim) names this as the right *last* open question — and the L488–498 ambient-affordances sidebar (L493 in particular: *"Bounded by ambient affordances"*) is the substrate the metric treats as a first-class input: *"We need a way to evaluate harness coverage and quality similar to what code coverage and mutation testing do for tests."* The article frames it as the meta-tool — the layer that turns the *parts* of a harness (guides, sensors, doctrine) into a single reportable property of the *whole* harness. Everything else in `.scratch/research/harness-engineering-2026-04.md` §"Actionable changes" (#1–#5) is a sub-problem of measuring whether the harness is *well-instrumented*.

For kbg-harness specifically, the metric is concrete: extend the existing 2×2 (computational / inferential × feedforward / feedback) into a **2×2×3 grid** by adding Böckeler's three regulation axes (L437–479: **maintainability**, **architecture fitness**, **behaviour**). The 12 cells are the *coverage surface*. For each cell, the metric reports:

1. **Population** — is a sensor (or pair-of-sensors) listed in `hooks/sensors.json` that occupies this cell? (Empty cells are *intentional gaps* or *coverage holes* — see §3.)
2. **Activation** — over the last N sessions (default N=30), did the registered sensor(s) actually *fire* with a non-skipped event? (Silent sensors = "high quality or inadequate detection?" per L553.)
3. **Verdict quality** — for sensors that fire, what fraction carry a meaningful verdict (non-null `top_finding`, non-empty `dimensions`, `score > 0` for the inferential-FB judge) vs trivial ("no findings this session")? (The 0.7 / 0.3 weighting from Q&A #11.)
4. **Drift** — the 30-session rolling score vs the previous 30-session window. (Per Q&A #8: deterministic, no model.)

The output is a 12-cell scorecard with a global rollup + 30-session drift line, rendered as a markdown table by `scripts/evals/harness-coverage.py`. The metric is **deterministic** — it counts events, parses JSON, and computes arithmetic. It does **not** call a model. The *interpretation* of a 0% cell (gap vs feature) is human; the metric surfaces the question, the operator answers it.

## 2. The 2×2×3 grid (12 cells, enumerated)

The 2×2 is Böckeler's **direction × execution type** (L356–L374; mirrored in `CLAUDE.md:47–63`). The 3 is the article's three **regulation axes** (L437–479: maintainability, architecture fitness, behaviour). 4 directions × 3 axes = 12 cells. The cell id format is `<direction>-<axis>` where direction ∈ `{comp-ff, comp-fb, inf-ff, inf-fb}` and axis ∈ `{maintainability, arch-fit, behaviour}`. The id is machine-checkable and JSON-friendly (lowercase, hyphen-separated, no spaces).

| Axis \\ Direction | **comp-ff** | **comp-fb** | **inf-ff** | **inf-fb** |
|---|---|---|---|---|
| **maintainability** | `comp-ff-maintainability` | `comp-fb-maintainability` | `inf-ff-maintainability` | `inf-fb-maintainability` |
| **arch-fit** | `comp-ff-arch-fit` | `comp-fb-arch-fit` | `inf-ff-arch-fit` | `inf-fb-arch-fit` |
| **behaviour** | `comp-ff-behaviour` | `comp-fb-behaviour` | `inf-ff-behaviour` | `inf-fb-behaviour` |

The same 12 ids, grouped by axis (the report-back shape the lead requested — 3 axis rows × 4 direction cells):

- **maintainability** — `comp-ff-maintainability`, `comp-fb-maintainability`, `inf-ff-maintainability`, `inf-fb-maintainability`
- **arch-fit** — `comp-ff-arch-fit`, `comp-fb-arch-fit`, `inf-ff-arch-fit`, `inf-fb-arch-fit`
- **behaviour** — `comp-ff-behaviour`, `comp-fb-behaviour`, `inf-ff-behaviour`, `inf-fb-behaviour`

The choice of **axes-as-rows, directions-as-columns** (and not the inverse) is deliberate: the 3 axes are the *what* (Böckeler L437), the 2×2 is the *how* (L356). Reading the table row-wise asks "for the maintainability axis, do we cover all 4 directions?" — which is the question a maintenance-decay audit actually asks. Reading column-wise asks "for computational-FF, do we cover all 3 axes?" — which is what a `BOUNDARY.md` cross-reference would ask. The metric supports both views; the lead's quarterly review (per `decay-cadence.md` integration) reads row-wise.

### Current kbg-harness cell population (per `.scratch/research/harness-engineering-2026-04.md` §"5×2×2 scorecard")

| Axis \\ Direction | comp-ff | comp-fb | inf-ff | inf-fb |
|---|---|---|---|---|
| **maintainability** | populated (8 PreToolUse gates) | populated (post-edit-audit, security-diff-review, 204+ critical-hooks tests, 38 audit checks) | populated (doctrine-bootstrap, iron-rule-reminder, orchestrator-nudge, 28 skill descriptions) | populated (kbg:review-pr, kbg:code-reviewer — advisory only) |
| **arch-fit** | populated (JOURNAL-SCHEMA.md, 14-event hook surface, 1536-char description budget) | populated (BOUNDARY.md auto-regen, last_permission_review cadence) | populated (token budgets via METHODOLOGY, kbg:perf skill) | populated (`agents/inferential-structural-judge.md` — advisory only) |
| **behaviour** | populated (ACCEPTANCE.md → run-acceptance) | populated (eval/run-eval.py --gate, run-acceptance 5-state) | populated (`/ship-task` Phase 5 acceptance gate) | **intentional gap** — kbg's `verification-gate.sh` precedent is advisory-only by design; `inferential-structural-judge` is the same pattern |

The `arch-fit` × `inf-fb` cell is **populated** (`agents/inferential-structural-judge.md` occupies it). The `behaviour` × `inf-fb` cell is an **intentional gap** (Böckeler L465–478 punts; the kbg pattern is to journal verdicts and let the operator interpret, not block). The distinction between the two is the §3 annotation.

## 3. Cell schema (the data contract)

This is the JSON shape the Wave-2 backend-engineer (`AGG-1`) will read as the data contract for `scripts/evals/harness-coverage.py`. The aggregator emits one entry per cell, plus a global rollup. The schema is intentionally **deterministic and self-describing** — every field is either a count, a percentage, or a fixed-enum annotation. No model in the loop.

```jsonc
{
  "schema_version": 1,
  "computed_at": "2026-06-15T16:45:12.345Z",
  "window_sessions": 30,                       // N from Q&A #2; configurable via --window-sessions=N
  "grid": [
    {
      "cell_id": "comp-ff-maintainability",
      "direction": "comp-ff",                  // "comp-ff" | "comp-fb" | "inf-ff" | "inf-fb"
      "axis":      "maintainability",          // "maintainability" | "arch-fit" | "behaviour"
      "population": {
        "sensors_listed":  8,                  // count of sensors in hooks/sensors.json whose fallback_role == "computational-FF" and whose description-tag matches the axis
        "sensors_enabled": 8
      },
      "activation": {
        "expected_events_per_window":  30,     // N sessions × >=1 PreToolUse:computational-FF per session (see §3.1)
        "actual_events_in_window":     27,     // counted from JOURNAL-SCHEMA.md JSONL, event_type=hook_fired, hook_name in (listed sensors)
        "fires_skipped_budget":         0,
        "fires_skipped_absent":         0
      },
      "verdict_quality": {
        "meaningful_fires": 22,                // fires whose payload carries a non-null top_finding / non-zero dimensions
        "trivial_fires":     5,                // fires whose payload is "no findings" / empty dimensions
        "weight_meaningful": 0.7,              // CLI-overridable (--weight-meaningful=0.7)
        "weight_trivial":    0.3,              // CLI-overridable (--weight-trivial=0.3)
        "weighted_score":   (22*0.7 + 5*0.3) / 27  // see §3.2
      },
      "cell_score_pct": 89,                    // activation × verdict_quality, 0..100, rounded
      "drift_vs_prev_window_pct": 4,           // 30-day rolling delta; +ve = improving
      "status": "populated",                   // see §3.3
      "intentional_gap": null                  // see §3.4; non-null if the cell is a deliberate non-population
    },
    {
      "cell_id": "inf-fb-behaviour",
      "direction": "inf-fb",
      "axis":      "behaviour",
      "population": { "sensors_listed": 0, "sensors_enabled": 0 },
      "activation": { "expected_events_per_window": 0, "actual_events_in_window": 0, "fires_skipped_budget": 0, "fires_skipped_absent": 0 },
      "verdict_quality": { "meaningful_fires": 0, "trivial_fires": 0, "weight_meaningful": 0.7, "weight_trivial": 0.3, "weighted_score": 0 },
      "cell_score_pct": 0,
      "drift_vs_prev_window_pct": 0,
      "status": "intentional_gap",
      "intentional_gap": {
        "rationale": "Böckeler L465–478 names behaviour-inferential-FB as the unsolved elephant; kbg's verification-gate.sh / fabrication-verdict-log.sh / inferential-structural-judge are advisory-only by the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model §L115 (LLM-judge-circularity mitigation).",
        "article_citation": "L465–478",
        "kbg_decision_ref": "the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model §L115",
        "revisit_when": "When a non-model-class judge (different model family) is available; the autonomy invariant forbids model-driven permissionDecision from this cell in the meantime."
      }
    }
    // …10 more cells…
  ],
  "global": {
    "populated_cells": 11,                     // 12 - intentional-gap-cells
    "coverage_hole_cells": 1,                  // unpopulated + intentional_gap == null
    "intentional_gap_cells": 1,                // populated == 0 + intentional_gap != null
    "global_score_pct": 72,                    // weighted average across populated cells
    "drift_30d_pct": 3
  }
}
```

### 3.1 Expected-events-per-window (the activation denominator)

The `expected_events_per_window` field is the activation denominator. It is *not* a hard target — a PreToolUse gate that doesn't fire is often the *correct* outcome (no dangerous command attempted). The value is the *upper bound* used to detect silent sensors. The mapping is:

| Direction | `expected_events_per_window` | Rationale |
|---|---|---|
| `comp-ff` | `window_sessions` (e.g. 30 for 30 sessions) | A PreToolUse:computational-FF hook must observe ≥ 1 Bash per session for it to be "covering" — silent is "not exercised" not "high quality" |
| `comp-fb` | `window_sessions` | Same: a PostToolUse/audit computational sensor is "covering" only if it actually evaluated a tool call |
| `inf-ff` | `window_sessions` (specifically SessionStart count) | Doctrine injection fires once per SessionStart; the activator count is the session count |
| `inf-fb` | `1` per session where diff.size > 0 | Inferential-FB sensors run on session-end / post-edit; an empty diff is the *strongest* accept signal (per the peer design doc §6), so the denominator excludes empty-diff sessions |

The thresholds live in `hooks/sensors.json` (per Q2 of `sensor-fire-notification.md`); the aggregator reads them via the registry's `should_fire_when` field and converts event-type + matcher to an event-bucket (PreToolUse = 1/day, SessionStart = 30 days, etc.). The mapping is hand-curated, not env-var-driven, per METHODOLOGY Rule 2 (no speculative configurability).

### 3.2 Weighted score (verdict-quality vs raw fires)

The `weighted_score` per cell separates *raw fire count* from *meaningful fire count*. The 0.7 / 0.3 split (per Q&A #11) defends against the "fire the sensor by hand to bump coverage" attack: a sensor that fires but always journals `top_finding: null` is gamed. The formula is:

```
weighted_score = (meaningful_fires * weight_meaningful + trivial_fires * weight_trivial)
                 / max(1, meaningful_fires + trivial_fires)
cell_score_pct = round(100 * (actual_events / expected_events) * weighted_score)
```

A sensor that fires on every session but always with `top_finding: null` scores ~30% (not 100%). A sensor that fires half the time but with non-null `top_finding` on every fire scores ~70% × 50% = 35% — still below 60%, which the `decay-cadence` quarterly review treats as a "decay candidate" (per the plan's DECAY-1 row). The 0.7 / 0.3 split is **hand-tuned**, not learned, and exposed as CLI flags so a future operator can re-tune (this is not speculative configurability — it is a knob on the *metric*, not a knob on the harness).

### 3.3 `status` enum (cell health bucket)

The `status` field collapses the 6 derived numbers into a single bucket the operator can scan:

| `status` | Condition | Operator reads this as |
|---|---|---|
| `populated` | `sensors_listed > 0` AND `intentional_gap == null` | The cell is instrumented; check the score for health |
| `intentional_gap` | `sensors_listed == 0` AND `intentional_gap != null` | A known-and-accepted non-population; do **not** add a sensor here without a follow-up plan that revises `intentional_gap.revisit_when` |
| `coverage_hole` | `sensors_listed == 0` AND `intentional_gap == null` | The metric *is* asking the question "should we add a sensor here?"; operator answers in the next quarterly review |
| `stale` | `sensors_listed > 0` AND `actual_events_in_window == 0` AND `intentional_gap == null` | A populated cell with zero fires — exactly the L553 problem ("sensors never fire — high quality or inadequate detection?") |

The 4-way split is what makes the metric *interpretable*. A `coverage_hole` is the call to action; `intentional_gap` is the documented decision; `populated` is the steady-state; `stale` is the silent-sensor alarm.

### 3.4 `intentional_gap` annotation (first-class, not a footnote)

An `intentional_gap` is a **first-class field** in the cell schema (§3 above) — not a markdown footnote, not a sidecar file, not a comment in `sensors.json`. The annotation is *co-located with the cell* so the aggregator, the skill, and the decay-cadence review all read the same source of truth. The annotation has 4 required fields (`rationale`, `article_citation`, `kbg_decision_ref`, `revisit_when`) — the `revisit_when` is what makes the gap a *decision*, not a *forget*.

For kbg-harness, the **known intentional gaps** (the "3+ known-gap examples" the lead asked for) are:

1. **`inf-fb-behaviour`** (cell_id: `inf-fb-behaviour`) — Böckeler L465–478 names this as the article's deepest open problem; kbg's `verification-gate.sh` / `fabrication-verdict-log.sh` / `inferential-structural-judge` are all advisory-only per the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model §L115 (LLM-judge-circularity). Revisit when: a different model class is available for judging, OR a non-model judge (mutation testing, property-based tests) lands for behaviour. **This is the textbook "article-punted" gap.**
2. **`inf-ff-arch-fit`** (cell_id: `inf-ff-arch-fit`) — kbg's `kbg:perf` skill is the *only* inferential-FF on architecture fitness, and it is operator-triggered (a `kbg:` command), not a hook (no SessionStart injection). The metric does *not* score it as a `coverage_hole` because the absence-of-hook is a deliberate trade-off: ambient-affordance injection for arch-fit would inflate SessionStart `additionalContext` size beyond the useful budget. This mirrors Böckeler L493 — *"Bounded by ambient affordances"* (Ned Letcher, in the L488–498 sidebar) — which frames *operator-triggered skill* as a legitimate ambient affordance rather than a missing hook. Revisit when: a SessionStart `additionalContext` budget > ~2k tokens is acceptable (currently METHODOLOGY:113-118 caps it implicitly). **This is a budget-driven gap, not an article-punted gap, and it is grounded in L493.**
3. **`inf-ff-maintainability`** (cell_id: `inf-ff-maintainability`) — partial: the 28 skill `description:` blocks (per `audit.sh:773-880` staleness detection) are *ambient-affordance* inferential-FF, but they are not enumerated in `sensors.json` (the registry lists hook-events only, per Q6 of `sensor-fire-notification.md`). The metric treats this as `intentional_gap` *for registry-aggregation purposes* — the descriptions are real coverage, just outside the registry's hook-event scope. Revisit when: the registry grows a "skills-as-FF" section (a future `sensors.json` v2 schema extension). **This is a registry-scope gap, not a coverage gap.**

A future sensor addition can revise the annotation (set `intentional_gap: null`, change `status` to `populated`) — but the change must be *intentional* (a hand-edit of the cell row in the aggregator's enumeration table, or a follow-up plan that resolves the gap). The metric does **not** auto-promote a gap when fires appear, because that would invert the annotation's purpose: the gap is a *decision*, not a *side-effect*.

## 4. From metric to fix (3-step operator loop)

A coverage number without a remediation path is a vanity metric. The 3-step loop the operator runs when the quarterly review (`scripts/evals/harness-coverage.py` via `decay-cadence`) flags a `coverage_hole` or `stale` cell:

1. **Read the cell's `intentional_gap` annotation first.** If the cell is `intentional_gap`, the answer is "no fix" — the gap is documented. The metric is doing its job by *not* prompting action. (This step is the load-bearing reason the annotation is first-class: without it, the operator would default to "add a sensor", which is wrong for the 3 known gaps above.)
2. **If the cell is `coverage_hole` or `stale`, open a follow-up plan** in `.claude/tasks/` (template: 1×DOC + 1×AGG/SKILL/FIX/INT, modelled on the three sibling plans). The follow-up plan **must** either (a) add a sensor and update `hooks/sensors.json` + the cell enumeration, or (b) explicitly annotate the cell as a new `intentional_gap` with a `revisit_when` clause. No third option — "ignore and revisit later" is captured in `revisit_when`, not in a separate TODO comment.
3. **The follow-up plan's `AGG-1` row** is a new commit to `hooks/sensors.json` (or a future registry extension) **and** a one-line update to the aggregator's cell-enumeration table. The next `scripts/evals/harness-coverage.py` run will then score the cell as `populated` (or, if the annotation is revised, as `intentional_gap` with the new rationale). The metric is *self-updating through the operator's normal planning workflow* — no separate "metric update" step is needed.

The loop is **human-gated at step 2** (per the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model / autonomy invariant). The metric does not open follow-up plans itself; it surfaces the question. This is the symmetric counterpart of `verification-gate.sh`'s "advisory only" stance: the metric is a *sensor*, not a *gate*. The autonomy invariant forbids cron / unattended mutation, so the "loop" is operator-driven, with `decay-cadence` as the cadence.

## 5. Gaming the metric (Q&A #11)

Three named attack vectors, each with a mitigation:

1. **"Fire the sensor by hand to bump coverage."** An operator runs the sensor's hook outside the harness lifecycle to inflate `actual_events_in_window`. **Mitigation:** the `weighted_score` (§3.2) only counts fires whose payload carries a non-null `top_finding` (or non-zero `dimensions` for the inferential-FB judge). A manually-triggered fire that journals an empty payload scores 0 on the meaningful axis. The 0.7 / 0.3 weighting (CLI-overridable via `--weight-meaningful=0.7 --weight-trivial=0.3`) means the gamed sensor cannot reach 100% on the cell_score_pct axis; it caps at ~30% if every fire is trivial. **This is the Q&A #11 mitigation, named explicitly.**
2. **"Annotate every cell as `intentional_gap` to hit 100% globally."** An operator marks all 12 cells as gaps and reads the global score as "100% of gaps are documented" — a metric of documentation effort, not coverage. **Mitigation:** the `intentional_gap` annotation has 4 required fields including `revisit_when` and `article_citation` (a specific Böckeler L-number OR an ADR §L-number). A cell cannot be `intentional_gap` without a citation to *some* documented decision. The aggregator also reports `intentional_gap_cells` as a *separate* global counter (not folded into `global_score_pct`) so the operator can read "11/12 populated, 1/12 intentional gap" without ambiguity.
3. **"Tune the weights to make every cell pass."** An operator bumps `--weight-meaningful=1.0 --weight-trivial=0.0` (or inverts to `--weight-meaningful=0.0`) to game the formula. **Mitigation:** the metric surfaces the active weights in the report's header (`weight_meaningful: 0.7, weight_trivial: 0.3`); `decay-cadence`'s quarterly review reads the *trend* of the weighted score across 4 windows, not the absolute value. A sudden re-tune shows up as a discontinuity in the drift line. The audit script's future `--harness-coverage-suspicious-tune` check (out of scope for this plan) would flag a > 0.2 step-change in weights.

The three mitigations are *non-overlapping*: (1) defends payload, (2) defends annotation, (3) defends formula. None of them defend *sensor count* — that is intentionally countable, because the *number* of sensors in a cell is the load-bearing signal for "is this cell instrumented at all?" (L553's central question).

## 6. Boundaries (Q&A #10, #82)

What the metric does **not** do, by design (and why each exclusion is load-bearing):

- **Does not add sensors.** A `coverage_hole` triggers a *follow-up plan*, not an auto-registered sensor. Sensors are hand-curated in `hooks/sensors.json` (per Q6 of `sensor-fire-notification.md`); the registry is the operator's intentional model, not a learned one. Auto-registration would invert the registry's purpose: the registry documents *what the operator chose to instrument*, not *what happens to fire*.
- **Does not judge sensor quality.** A sensor that fires with `top_finding: "everything is fine"` every session scores 100% on the trivial axis, 0% on the meaningful axis, and lands at 30% cell_score_pct. The metric *exposes* the trivial-fire pattern but does *not* call it "low quality" — that is an inferential judgment, and the metric is deterministic (per Q&A #6). The future `inferential-structural-judge` (per the sibling plan) is the right layer for sensor-quality judgment; the metric is the layer for sensor-*presence* judgment.
- **Does not auto-prune.** A `stale` cell is *surfaced*, not *actioned*. `decay-cadence` is human-gated; the metric informs, the operator decides. Auto-pruning would be a mutation on the registry, which the autonomy invariant forbids.
- **Does not run on cron / unattended loop.** The aggregator is a standalone script (`scripts/evals/harness-coverage.py` runs on operator request). The autonomy invariant (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model) forbids `CronCreate` and `/loop`; the metric respects this by being read-only-on-demand. The cadence comes from the operator's quarterly `decay-cadence` review, not from a scheduler.
- **Does not weight the 2×2 or 3 axes differently by default.** All 12 cells are equally weighted in the global rollup. The article's 2×2 is the *substrate*; the operator's local 2×2 (per `CLAUDE.md:47–63`) is the *score* — but the metric treats them identically and lets the operator's reading of the cell-level scores carry the weighting. A future v2 schema could add `cell_weight` per axis (e.g. behaviour weighted higher in safety-critical harnesses), but per METHODOLOGY Rule 2 that is not pre-baked.
- **Does not publish externally.** Output is harness-internal: the skill renders a markdown table, the script emits JSON. No Slack, no email, no webhook. The decay-cadence review is the *only* surface that broadcasts the metric, and the broadcast is the operator's quarterly decision to act (or not) on a flagged cell.
- **Does not score LLM-judge circularity as coverage.** A `verification-gate.sh` advisory verdict and a `kbg:review-pr` deep verdict are both `inf-fb-*` cells; both score by the same activation × quality formula. The metric does not *know* that one is a 1,000-token SessionEnd pass and the other is a 4,000-token multi-pass review — the cost is the cost-attribution layer's job (per `inferential-structural-judge-design.md:5`), not the metric's. Conflating quality with cost would invert the layer separation.

## 7. Cross-references to sibling plans

The metric is the *aggregator* over the other two Wave-1 / 0.2.x plans:

- **`sensor-fire-notification.md`** — provides the `hooks/sensors.json` registry (31 entries, hand-curated). The metric reads the registry to determine `population.sensors_listed` and `sensors_enabled`. The `fallback_role` field maps 1-to-1 to the metric's `direction` axis (computational-FF → `comp-ff`, etc.). The `max_silent_days` field is *not* the activation threshold — the metric uses its own `expected_events_per_window` (§3.1) because cadence (days) and activation (fires-per-N-sessions) are different dimensions. This is the same Q2 distinction the sibling plan draws (`days ≠ session-count`).
- **`inferential-structural-test.md`** — provides the `inferential-structural-judge` SessionEnd sensor that occupies `inf-fb-arch-fit` and (with its 4 dimensions: over-engineering, arch-drift, test-pattern, doctrine-conformance) feeds the `verdict_quality` axis of multiple cells. The peer design doc's §3 verdict schema is the data shape the metric reads to compute `meaningful_fires` (non-null `top_finding`, non-empty `dimensions`).
- **`harness-decay-cadence.md`** (this is the *other* Wave-1 teammate's file, not this one) — receives the integration in its own DOC/DECAY row. The decay-cadence quarterly review is the operator's cadence for reading the metric; the metric does not own the cadence.
- **`METHODOLOGY.md:113-118`** ("Token Budgets Are Not Advisory") — the metric itself runs at zero token cost (§3 deterministic). Cost-attribution for the *sensors it measures* lives in their own design docs.

The 0.3.x target window (per the plan's `target: kbg-harness 0.3.x or later` frontmatter) is the right horizon because the metric's *useful output* requires both the registry and the verdicts to be live. It can be *designed and built in 0.2.x* (this DOC-1 + AGG-1 + SKILL-1 + FIX-1 chain) against mocked verdicts; the live-output version lands when the siblings land.

## 8. Q&A resolution status (resolves all 12 Q items from the plan's `## Q&A log`)

The plan's acceptance criterion #1 reads: *"Design doc explicitly addresses the 12 Q items it owns in a Q&A resolution table."* This table is the audit trail. Every Q item is **Resolved** — this design doc owns all 12, unlike the peer design doc (`inferential-structural-judge-design.md`) which split 9 / 3 between itself and follow-up plans. The metric's design is self-contained; it depends on the registry + verdicts for *data*, but the *schema* is fully defined here.

| Q# | Q summary (1-line from plan) | Status | Where resolved |
|----|------------------------------|--------|----------------|
| Q1 | Why is this P3 when the others are P2? | **Resolved** | §1 (meta-tool; the other two plans add sensors, this one measures them); §7 (0.3.x target because of dependency) |
| Q2 | What's the *unit* of coverage? | **Resolved** | §3.1 (`expected_events_per_window`); §3 (per-cell coverage = activation × verdict_quality) |
| Q3 | What's the "expected events per cell"? | **Resolved** | §3.1 (per-direction mapping table); `hooks/sensors.json` is the threshold source |
| Q4 | What's the *output*? | **Resolved** | §3 (the 12-cell JSON shape); §2 (the markdown table render); §1 (the global rollup + 30-session drift) |
| Q5 | What about cells the article says are unsolved? | **Resolved** | §3.4 (the `intentional_gap` first-class annotation); §2 row 3 (the `inf-fb-behaviour` example) |
| Q6 | How does this avoid the LLM-judge-circularity trap? | **Resolved** | §1 (the metric is deterministic, no model call); §6 (the "does not judge sensor quality" boundary) |
| Q7 | Is this a `kbg:` skill or a script? | **Resolved** | §1 + §3 (the script `scripts/evals/harness-coverage.py` emits the JSON in §3 and renders the markdown table) |
| Q8 | What's the cost? | **Resolved** | §1 (O(seconds), zero tokens; runs on operator request, not in any hook); §6 (no cron / no /loop) |
| Q9 | What's the test? | **Resolved** | §3.2 (the 0.7/0.3 weighting is the test contract); §5 (the three gaming vectors are the test cases); the regression fixture at `eval/regressions/harness-coverage.json` lives in the plan's FIX-1 row and is out of scope for this DOC |
| Q10 | What does this *not* do? | **Resolved** | §6 (the 7-item Boundaries list, each with rationale) |
| Q11 | What if the metric is gamed? | **Resolved** | §5 (the 3 attack vectors + 3 mitigations; the 0.7/0.3 split is named explicitly) |
| Q12 | Why a 2×2×3 grid specifically? | **Resolved** | §2 (the 12-cell enumeration); §1 (the rationale — 2×2 is the *how*, 3 axes is the *what*, both from Böckeler L356–L374 + L437–L479) |

## 8.1 Plan-Q&A mirror (verbatim from `.claude/tasks/harness-coverage-metric.md` ## Q&A log)

The 12 plan questions are quoted verbatim below so the design doc can be grepped for each one independently of the resolution table:

1. Why is this P3 when the others are P2?
2. What's the *unit* of coverage?
3. What's the "expected events per cell"?
4. What's the *output*?
5. What about cells the article says are unsolved (e.g. behaviour-inferential-FB)?
6. How does this avoid the LLM-judge-circularity trap?
7. Is this a `kbg:` skill or a script?
8. What's the cost?
9. What's the test?
10. What does this *not* do?
11. What if the metric is gamed?
12. Why a 2×2×3 grid specifically? — The 2×2 is Böckeler's direction × execution-type; the 3 is the article's regulation axes (maintainability / architecture fitness / behaviour). 12 cells = the full regulation space. The 2×2 alone misses the *what* (axis); the 3 alone misses the *how* (computational vs inferential). Together they cover the article's full model.

**Summary:** 12 of 12 Q items resolved in this design doc. 0 of 12 deferred. The metric is *defined* in this doc; the *implementation* (AGG-1, SKILL-1, FIX-1, DECAY-1) is the team's job, not the design's.

## 9. Open questions for Wave 2-5

The downstream agents need to make the following decisions, which this doc deliberately does not pre-commit:

- **AGG-1 (Python aggregator author):** the exact `jq` / `python` parsing strategy for the JSONL journal (per `JOURNAL-SCHEMA.md`); the cell-enumeration source-of-truth location (a YAML/JSON file the script reads, or a Python literal — either is fine; the *data contract* is §3); the `--window-sessions` and `--weight-*` CLI flag grammar; the JSON envelope's `schema_version` migration policy.
- **SKILL-1 (renderer author):** the exact markdown table layout for the human render (axis-rows × direction-columns is the §2 shape; the script can add a "Top 3 cells to fix" header summary). No new `kbg:` skill is required; the script emits the report directly.
- **FIX-1 (regression fixture author):** the 30-session synthetic journal entries (hand-curated per Q9 of the peer plan — the L476 "AI-generated tests" warning applies to coverage fixtures too); the expected-grid ground truth (12 cells × 4 fields = 48 numbers); the bucket-threshold pass criterion for `--gate`.
- **DECAY-1 (decay-cadence integrator, in `.claude/tasks/harness-decay-cadence.md` — owned by the other Wave-1 teammate, not this one):** the exact quarterly-review section wording; the "treat any cell below 60% as a decay candidate" threshold (per the plan's DECAY-1 row) and its interaction with the §3.3 `status` enum.
- **INT-1 (integration smoke):** the manual smoke procedure (run a session that touches ≥ 1 file, observe the `scripts/evals/harness-coverage.py` render shows 12 cells + global + drift). The smoke does *not* require the registry to be live; the aggregator runs against an empty registry and emits 12 cells with `status: "coverage_hole"`, which is the correct first-run state.

The downstream agents should *not* re-open the §3 schema (it is the data contract). The downstream agents *should* surface drift between the schema and the implementation back to this doc as XREF updates (a hand-edit of §3, not a silent field rename).

---

**Backwards compatibility:** this design doc adds *no* plugin surface. The Wave-2 work (AGG-1, SKILL-1, FIX-1, DECAY-1) is the surface change. The 204-test critical-hooks suite continues to pass without modification (the metric is not a hook; it reads the journal, it does not register as an event source).
