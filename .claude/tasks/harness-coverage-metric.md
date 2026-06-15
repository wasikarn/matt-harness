---
slug: harness-coverage-metric
priority: P3 (long-horizon research)
source: .scratch/research/harness-engineering-2026-04.md §"Actionable changes" #6
status: shipped (v0.2.4)
shipped_commits:
  - a56f936 feat(harness): wave 3 gap closure — doctrine, advisory hooks, harness-coverage (v0.2.4)
  - 9b936e5 fix(eval): handle harness-coverage fixture shape in flatten_evals
tag_only_eval: true
follow_up_plans:
  - .claude/tasks/inferential-structural-judge-live-eval.md
  - .claude/tasks/inferential-structural-judge-escalation-mirror.md
target: kbg-harness 0.3.x or later
created: 2026-06-15
related: ADR 0002, decay-cadence.md, inferential-structural-test.md, sensor-fire-notification.md
---

# Plan: Harness-coverage metric (the meta-tool Böckeler calls the right next question)

## Brain dump

Böckeler L553 (verbatim): *"We need a way to evaluate harness coverage and quality similar to what code coverage and mutation testing do for tests."* The article identifies this as the right *last* open question — the meta-tool. Everything else (coherence, conflict-resolution, silent sensors) is a sub-problem of measuring whether the harness is *well-instrumented*.

For kbg-harness specifically, the "harness coverage" question is concrete: out of the 2×2 grid (computational/inferential × feedforward/feedback) × 3 regulation axes (maintainability, architecture fitness, behaviour), what fraction of cells is *populated*? For each populated cell, what fraction of *expected events* actually *fired* in the last N sessions? For each unpopulated cell, is that a *deliberate gap* (e.g. inferential-FB-behaviour is the article's open problem) or a *coverage hole* (we forgot to add a sensor)?

A harness-coverage metric is the layer that turns the `sensors.json` registry (from `sensor-fire-notification.md`) + the journal + the 2×2 grid into a single reportable number — and lets the operator detect *quality theatre* (sensors that always pass, sensors that never fire, sensors that fire but don't surface) the way code coverage detects dead tests.

The metric is **blocked by** the other two sibling plans: it consumes the registry (`sensor-fire-notification.md`) + the verdicts (`inferential-structural-test.md`). It *can* be designed and built in 0.2.x *against mocked verdicts*, but its *useful output* requires the registry + verdicts to have shipped (0.3.x).

## Q&A log

1. **Why is this P3 when the others are P2?** — It is a meta-tool. The other two plans add *new* sensors; this one measures whether the existing sensors are *good*. The other plans are prerequisites (inferential-structural-test adds 1 sensor; sensor-fire-notification adds observability of all sensors; harness-coverage is the *aggregator*). Order: 2 → 1 → 3.
2. **What's the *unit* of coverage?** — Candidate: per-cell coverage = (cells populated / cells total) × (fired-events / expected-events per populated cell). Both factors are machine-derivable from `sensors.json` + the journal.
3. **What's the "expected events per cell"?** — Determined by the cell's purpose. Computational-FF: ≥ 1 PreToolUse event per session (always true). Computational-FB: ≥ 1 PostToolUse/audit event per session (always true if hooks exist). Inferential-FF: ≥ 1 doctrine-injection event per SessionStart (always true). Inferential-FB: ≥ 1 advisory event per N sessions (N=5? configurable). The expected-event thresholds are *sensors.json*'s job — this plan only consumes them.
4. **What's the *output*?** — A 2×2×3 grid (12 cells) with a 0–100% coverage score per cell, plus a global score. Plus a "drift over time" line (last 30 sessions). Plus a "known gap" annotation (a registry entry that says "this cell is intentionally uncovered"). The user-facing surface is a new `kbg:harness-coverage` command, *or* an extension to `kbg:state-of-the-harness`.
5. **What about cells the article says are unsolved (e.g. behaviour-inferential-FB)?** — Those are *annotated* as "article-punted" in the report, not scored 0%. The metric measures *intentional* vs *unintentional* gaps. This requires the 2×2 design grid in `CLAUDE.md` (per Q6 of `sensor-fire-notification.md`) as a cross-reference.
6. **How does this avoid the LLM-judge circularity trap?** — The metric is *deterministic* — it counts events, it does not use a model to judge coverage. The numbers are machine-derived from the journal + the registry. The *interpretation* (is a 0% cell a gap or a feature?) is human.
7. **Is this a `kbg:` skill or a script?** — Both. The deterministic aggregator is a script (`scripts/harness-coverage.py`); the human-facing report is a `kbg:harness-coverage` skill that runs the script and renders the grid.
8. **What's the cost?** — The script runs at human request (not in any hook). It reads `sensors.json` + the journal + a few static configs. Cost: O(seconds), zero tokens.
9. **What's the test?** — A regression fixture: a 30-session journal with known fire rates; the script's output is asserted to match expected grid. Lives at `eval/regressions/harness-coverage.json`.
10. **What does this *not* do?** — It does not *add* sensors. It does not *fix* gaps. It does not *judge* whether a sensor is good (that's a separate inferential layer). It *measures* what is and is not covered. The fix loop is the operator's, gated by `decay-cadence` and the planning workflow.
11. **What if the metric is gamed?** — A "fire the sensor by hand to bump coverage" attack. The mitigation: the metric weights *meaningful* fires (verdicts with non-null top_finding) higher than *trivial* fires (verdict = "no findings"). The weighting is hand-tuned; the script exposes the weights as `--weight-meaningful=0.7 --weight-trivial=0.3`.
12. **Why a 2×2×3 grid specifically?** — The 2×2 is Böckeler's direction × execution-type; the 3 is the article's regulation axes (maintainability / architecture fitness / behaviour). 12 cells = the full regulation space. The 2×2 alone misses the *what* (axis); the 3 alone misses the *how* (computational vs inferential). Together they cover the article's full model.

## Team Members

| Name | Role | Agent Type |
|------|------|------------|
| LEAD-D | Design doc + 2×2×3 grid schema + "intentional gap" annotation author | code-architect |
| LEAD-B | Python aggregator + skill + regression fixture builder | backend-engineer |
| V | Lint + audit + eval validator | code-reviewer |

## Step by Step Tasks

| Task ID | Description | Depends On | Assigned To | Files | Criteria | Constraints |
|---------|-------------|------------|-------------|-------|----------|-------------|
| DOC-1 | Author the design doc | - | LEAD-D | docs/research/harness-coverage-metric-design.md | Resolves all 12 Q&A items; defines the 2×2×3 grid schema; cites Böckeler L493, L553; specifies the "intentional gap" annotation; "From metric to fix" section specifies the 3-step operator loop | — |
| AGG-1 | Author the deterministic aggregator (BLOCKED on sensor-fire-notification.md + inferential-structural-test.md shipping first) | DOC-1 | LEAD-B | scripts/harness-coverage.py | Reads `sensors.json` + journal + 2×2 grid from CLAUDE.md; emits the 12-cell grid + global score; supports `--weight-meaningful` and `--weight-trivial` | No LLM call (deterministic); no `permissionDecision`; degrades on missing files |
| SKILL-1 | Author the human-facing skill | AGG-1 | LEAD-B | skills/harness-coverage/SKILL.md (or extend `state-of-the-harness`) | `kbg:harness-coverage` runs the script and renders a markdown table with the 12 cells + global + drift-over-time | Audit #31.1 canonical sections (Input Contract / Output Format / Failure Modes) |
| FIX-1 | Author the regression fixture | DOC-1, AGG-1, SKILL-1 | LEAD-B | eval/regressions/harness-coverage.json | 30-session synthetic journal + expected grid; eval gate exits 0 | Synthetic journal must be hand-curated to avoid the "test-quality" problem Böckeler L476 warns about |
| DECAY-1 | Wire into `decay-cadence.md` | DOC-1 | LEAD-D | docs/harness-decay-cadence.md (new section) | "Run `kbg:harness-coverage` quarterly; treat any cell that drops below 60% as a decay candidate" | Closes the "silent sensors" gap with a *human cadence*, not an auto-prune |
| INT-1 | End-to-end: cache-update + restart + manual smoke (run skill, observe 12-cell grid) | AGG-1, SKILL-1, FIX-1, DECAY-1 | LEAD-B | (none) | `claude plugin update kbg@kobig` exits 0; `/kbg:harness-coverage` emits 12-cell grid + global + drift | run via V validation step |

## Acceptance Criteria

- [x] DOC-1: design doc resolves all 12 Q&A items validation_command: grep -c '^12\.' docs/research/harness-coverage-metric-design.md
- [x] AGG-1: script runs in < 5s on a real journal, emits a 12-cell grid + global + drift validation_command: time python3 scripts/harness-coverage.py > /dev/null
- [x] SKILL-1: skill has all 3 canonical sections (audit #31.1) validation_command: bash skills/harness-audit/scripts/audit.sh .
- [x] FIX-1: regression fixture is hand-curated (no agent-generated text); 30 sessions, expected grid present validation_command: jq '.sessions | length' eval/regressions/harness-coverage.json
- [x] FIX-1: eval gate exits 0 validation_command: python3 eval/run-eval.py --regression --tag harness-coverage --gate
- [x] INT-1: harness-audit exits 0C/0W (or 0C/0W/1I — only the I1 plugin-cache info) validation_command: bash skills/harness-audit/scripts/audit.sh .
- [x] DECAY-1: decay-cadence has a new section naming `kbg:harness-coverage` as a quarterly-lens surface validation_command: grep -c 'kbg:harness-coverage' docs/harness-decay-cadence.md
- [x] The metric's "intentional gap" annotation is a *first-class* concept in the output (not a footnote) validation_command: grep -c 'intentional_gap\|intentional-gap\|intentional gap' docs/research/harness-coverage-metric-design.md
- [x] No `permissionDecision` / `CronCreate` / `/loop` (autonomy-invariant) validation_command: git grep -n 'permissionDecision\|CronCreate\|/loop' scripts/harness-coverage.py skills/harness-coverage/SKILL.md

## Validation Commands

- `bash skills/harness-audit/scripts/audit.sh .` — manifest, schema, descriptions
- `bash hooks/tests/test-critical-hooks.sh` — critical-hooks regression
- `python3 eval/run-eval.py --regression --tag harness-coverage --gate` — eval gate green
- `time python3 scripts/harness-coverage.py | head -50` — manual smoke: 12-cell grid + global
- `claude plugin validate --strict .` — manifest valid (new skill + new script → plugin-surface change → version bump required)
- `git grep -n 'permissionDecision\|CronCreate\|/loop' scripts/harness-coverage.py skills/harness-coverage/SKILL.md` — autonomy-invariant scan (expect 0)
- `claude plugin update kbg@kobig` — plugin cache update + restart Claude Code

## What this plan does NOT do

- Does NOT add sensors (separate plans: inferential-structural-test.md, sensor-fire-notification.md)
- Does NOT auto-prune based on coverage (decay-cadence is human-gated; the metric informs, not decides)
- Does NOT judge *quality* of a sensor's verdicts (the metric counts events, not whether they are good)
- Does NOT weight the article's 2×2 differently from the operator's local model (Böckeler's 2×2 is the substrate, not the score; the operator's `sensors.json` `fallback_role` is the score's modifier)
- Does NOT run on a cron / unattended loop (autonomy-invariant forbids; the metric runs on operator request)
- Does NOT publish to any external service (Slack, email, etc.) — output is harness-internal

## Sequencing

This plan is **blocked by** `inferential-structural-test.md` (verdicts) and `sensor-fire-notification.md` (registry). The right order is:

1. sensor-fire-notification.md (adds the registry, makes staleness observable)
2. inferential-structural-test.md (adds 1 new verdicts-emitting sensor)
3. harness-coverage.md (this plan — aggregates the registry + the verdicts + the static 2×2)

