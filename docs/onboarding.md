# kbg-harness — First 10 minutes

A cold-start for working in (or with) the kbg-harness repo. If you read this
file and nothing else, you can name what the repo is, where doctrine lives, and
the three commands you'll use most. Stays ≤500 tokens on purpose — in-repo,
in-context, no scroll.

## What this repo is (1 sentence)

A personal Claude Code harness delivered as an installable plugin (`kbg@kobig`):
27 subagents, 26 skills, 8 commands, governance hooks, and mandatory doctrine
injection. See [`CONTEXT.md`](../CONTEXT.md) for the bounded-context model.

## The 4 doctrine files (read in this order)

1. [`METHODOLOGY.md`](../METHODOLOGY.md) — 13-rule behavioral doctrine. **Start here.**
2. [`CONTEXT.md`](../CONTEXT.md) — domain language + the **autonomy invariant** (no L3/L4 loops).
3. [`docs/adr/0002-autonomy-invariant.md`](adr/0002-autonomy-invariant.md) — irreversible decision record for L2-only.
4. [`BOUNDARY.md`](../BOUNDARY.md) — auto-regenerated capability map (skills / agents / commands / hooks).

The four are auto-injected on every SessionStart by `hooks/doctrine-bootstrap.sh`.
No manual `@import` needed.

## The 3 commands you'll use most

| Command | When | What it does |
|---|---|---|
| `/kbg:pre-ship-verify` | Before every PR | Runs `ACCEPTANCE.md` + eval-harness gate; blocks ship on failure. |
| `/kbg:review-pr` | After pushing a PR | Multi-agent review (code, tests, security, types) over the diff. |
| `/kbg:ship-merge` | After PR approval | Verifies the diff + merges. The human gate sits between review and merge. |

Other useful ones: `/kbg:fix-bug`, `/kbg:feature-dev`, `/kbg:team-plan`,
`/kbg:team-build`, `/kbg:hotfix`. Full list in [`BOUNDARY.md`](../BOUNDARY.md).

## The 1 thing to never do

**Do not relax ADR 0002.** No autonomous loops, no L3/L4 model-as-gate, no
self-improving-harness-via-PRs. The autonomy invariant is load-bearing — it
preserves the operator's judgment over loop velocity. If a feature requires an
unattended loop, the answer is "out of scope by design," not "amend ADR."

## Recurring cadences (read once, never re-derive)

- **Harness decay sweep** — every quarter, prune dead weight. See
  [`docs/harness-decay-cadence.md`](harness-decay-cadence.md).
- **Harness audit** — run the `harness-audit` skill on demand. CRIT findings block ship.

## If you only have 60 seconds

Read this file's first three sections. If you have 5 more minutes, skim
[`METHODOLOGY.md`](../METHODOLOGY.md). If you have 10 more, read
[`CONTEXT.md`](../CONTEXT.md) §"Autonomy invariant" + ADR 0002 rejected-alternatives table.
