# Decision log

One row per Rule-14-scored decision, appended by hand at the moment a session ACTS on it. Not the
source of truth for the score — that lives in the linked artifact. This exists so a confidence band
becomes checkable evidence over time instead of decoration (`docs/reference/operating-model.md`'s
own stated evidence order: deterministic results first, then trajectory, then track record, then
confidence last).

**Write events:** append a row with `Outcome: open` at scoring/acting time (the main session — no
subagent writes this; reviewer agents are read-only by contract). A later session — a
`mh:deep-audit`, a post-mortem, or a `revisit_if` tripwire firing — fills in the outcome column when
it's known. Outcome vocabulary: `held` / `partly` / `reversed` / `open`.

**Build trigger**: at 20 closed (non-`open`) rows, build a per-band hit-rate scorer ("of decisions
marked `high`, what fraction held") — not Brier scoring, which needs numeric probabilities and
can't be computed from coarse `{level, reason}` bands. Below 20 rows, any calibration statistic is
noise.

**Kill condition**: if this file still has only its 5 seeded rows (no row appended since) by
2026-12-31, delete it — checked by the next `mh:deep-audit` run on this repo. An append-only log
nobody fills is decoration with extra steps. (A plain row-count threshold can't express this: the
file is seeded at exactly 5, so "fewer than 5 rows" can never fire — found by `mh:deep-audit`
2026-09-20.)

| Date | Decision | Artifact | Verdict | totalRange @ p=0.2 | verdictStable | Confidence | Outcome |
|------|----------|----------|---------|---------------------|---------------|------------|---------|
| 2026-09-20 | Weight-sensitivity check | `docs/research/decision-making-methods-2026-09-19.md` §4 row 2 | build (7.35) | [7.26, 7.45] | true | medium — thin evidence on sensitivity analysis' practical yield in this repo specifically | open |
| 2026-09-20 | Confidence bands + outcome log | `docs/research/decision-making-methods-2026-09-19.md` §4 row 3 | build (7.25) | [6.91, 7.55] | **false** — fragile | medium — strong calibration literature, but the *pass* call itself is weight-sensitive | open |
| 2026-09-20 | ADR status frontmatter | `docs/research/decision-making-methods-2026-09-19.md` §4 row 4 | build (7.65) | [7.40, 7.87] | true | high — mechanical mapping to mattpocock-skills' existing ADR-FORMAT.md schema, no interpretation | open |
| 2026-09-20 | Name the veto convergence | `docs/research/decision-making-methods-2026-09-19.md` §4 row 5 | build if cheap (6.95) | [6.36, 7.47] | false — fragile (low-risk regardless: doc-only, no code path) | high — doc-only, restates an already-shipped mechanism (plan-reviewer/idea-audit fatal floors) | open |
| 2026-09-20 | Frame `revisit_if` as a tripwire | `docs/research/decision-making-methods-2026-09-19.md` §4 row 6 | build if cheap (6.70) | [6.26, 7.19] | false — fragile (low-risk regardless: doc-only, no code path) | high — doc-only field-description change, no behavior impact | open |
