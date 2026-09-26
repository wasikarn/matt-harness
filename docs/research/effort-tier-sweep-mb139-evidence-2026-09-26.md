# Effort-tier sweep evidence (`mb139`, 2026-09-26)

Raw evidence backing the effort-tier decisions in `CHANGELOG.md` `[1.1.138]`-`[1.1.141]` for
`backend-architect`, `requirement-analyst`, `blind-spot-hunter`, `code-architect`, and
`plan-reviewer`. Archived here because the numbers were previously verifiable only against a
session scratchpad, gone once that session ends — a durable risk (a verification fixture belongs
in the repo, not a session temp dir), not a one-off.

## Files

- `effort-tier-sweep-mb139-run-script-2026-09-26.sh` — the exact sweep script that produced this
  data: baseline (current effort tier) vs. alt (candidate tier) A/B per agent, `--scaffold`
  included (the fix for the invalidated `mb78` sweep — see `[1.1.139]`), wrapped in
  `scripts/_lib/eval-default-enabled.sh`.
- `effort-tier-sweep-mb139-evidence-2026-09-26.json` — per agent, per arm (`baseline`/`alt`), per
  case: score, pass/fail, cost, and every grader's `{name, passed, explanation}`. This is a
  condensed extract of each `claude plugin eval` run's `aggregate-result.json` (dropped:
  `promptMarkdown`, `tracePath`, per-run timestamps — none of it is needed to re-derive any
  CHANGELOG claim, and including it would have made this file ~20x larger for no evidentiary
  gain).

## What each CHANGELOG number maps to

- `[1.1.140]`: "`backend-architect` scored 1.0 on all 6 cases in both arms" →
  `backend-architect.baseline.cases[*].arms.with[0].score` and
  `backend-architect.alt.cases[*].arms.with[0].score`, all `1`.
- `[1.1.140]`: "`code-architect-ambiguous-requirement` dropped 1.0→0.667 at `medium`" →
  `code-architect.baseline.cases[0].arms.with[0].score` (`1`) vs.
  `code-architect.alt.cases[0].arms.with[0].score` (`0.667`), grader `names-ambiguity` failed in
  the alt arm.
- `[1.1.141]`: the cost-ceiling correction (`layer-direction` skipped in both arms, not baseline
  only) → `code-architect.{baseline,alt}.cases[3].arms.with[0].graders[]`, grader
  `cites-analog-quality`, both showing `"skipped: cost ceiling"`.
- `[1.1.138]`: the floor-artifact finding for `requirement-analyst`/`blind-spot-hunter`/
  `plan-reviewer` is about the earlier, invalidated `mb78` sweep, not this one — not represented
  here.

Every score/grader claim in `[1.1.140]`/`[1.1.141]` is independently reconstructible from the JSON
file alone; nothing here depends on the scratchpad still existing.
