# kbg-harness — First 10 minutes

A cold-start for working in (or with) the kbg-harness repo. If you read this
file and nothing else, you can name what the repo is, where doctrine lives, and
the three commands you'll use most. Stays ≤500 tokens on purpose — in-repo,
in-context, no scroll.

## What this repo is (1 sentence)

A personal Claude Code harness delivered as an installable plugin (`kbg@kobig`):
29 subagents, 40 skills, 22 commands, governance hooks, and mandatory doctrine
injection. See [`DOMAINS.md`](../DOMAINS.md) for the bounded-context model.

## The 4 doctrine files (read in this order)

1. [`METHODOLOGY.md`](../METHODOLOGY.md) — 13-rule behavioral doctrine. **Start here.**
2. [`DOMAINS.md`](../DOMAINS.md) — bounded-context dispatch table + cross-context orchestration rules.
3. [`docs/adr/0002-autonomy-invariant.md`](adr/0002-autonomy-invariant.md) — the autonomy invariant: the load-bearing *principle* + foreclosures (no L4, no self-launch, no model-as-gate). L3 *bounded* autonomy is the opt-in successor in [`ADR 0003`](adr/0003-l3-bounded-autonomy.md).
4. [`BOUNDARY.md`](../BOUNDARY.md) — auto-regenerated capability map (skills / agents / commands / hooks).

The four are auto-injected on every SessionStart by `hooks/session/doctrine-bootstrap.sh`.
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

**Do not relax the autonomy invariant.** No L4, no self-launching loops
(cron / `/loop` / `CronCreate`), no model-as-gate, no self-improving-harness-via-PRs.
The invariant is load-bearing — it preserves the operator's judgment over loop
velocity. **L3 *bounded* autonomy IS in scope** (opt-in `KBG_AUTONOMY`, default
OFF, push-gated — [ADR 0003](adr/0003-l3-bounded-autonomy.md)); it was adopted by a
deliberate *superseding ADR*, not a flag flip. So: change the architecture only
through a new ADR (the 0003 mechanism); a self-launching / L4 / model-as-gate
feature is "out of scope by design."

## Recurring cadences (read once, never re-derive)

- **Harness decay sweep** — every quarter, prune dead weight. See
  [`docs/harness-decay-cadence.md`](harness-decay-cadence.md).
- **Harness audit** — run the `harness-audit` skill on demand. CRIT findings block ship.

## If you only have 60 seconds

Read this file's first three sections. If you have 5 more minutes, skim
[`METHODOLOGY.md`](../METHODOLOGY.md). If you have 10 more, read
[`DOMAINS.md`](../DOMAINS.md) and [`docs/adr/0002-autonomy-invariant.md`](adr/0002-autonomy-invariant.md) §"Rejected alternatives".

## What we've shipped recently (2026-06-12)

The 2026-06-12 closure work lifted 10 capabilities Partial → Present
(SYNTHESIS audit). For *why*, see [`CHANGELOG.md`](../CHANGELOG.md) §
Unreleased → Phase 1.1–2.5.

- **`scripts/auth-health-check.py`** — gh/MCP/plugins health probe (3-state).
- **`scripts/orchestrate-dispatch.py` + 3 specs** — coordination-as-code.
- **`hooks/gates/db-write-gate.sh` + `KBG_ENFORCE_TASK_COMPLETED`** — opt-OUT task gate.
- **`recursive-improve` skill** — stall detection + debt ceiling.
- **`eval/run-eval.py` + 24 fixtures** — eval harness + anti-cheat exits.
- **`scripts/governance/audit-to-memory.py` + `memory-lint`** — learning-memory loop.
- **[ADR 0002 addendum](adr/0002-addendum-deferred-items.md)** — 10 deferred items + L2 alternatives.
