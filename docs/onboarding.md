# kbg-harness — First 10 minutes

A cold-start for working in (or with) the kbg-harness repo. If you read this
file and nothing else, you can name what the repo is, where doctrine lives, and
the three commands you'll use most. Stays ≤500 tokens on purpose — in-repo,
in-context, no scroll.

## What this repo is (1 sentence)

A personal Claude Code harness delivered as an installable plugin (`kbg@kobig`):
13 subagents, 49 skills, 25 commands, governance hooks, and mandatory doctrine
injection.

## The 4 doctrine files (read in this order)

1. [`METHODOLOGY.md`](../METHODOLOGY.md) — staff-engineer behavioral doctrine (decision triad + reasoning scaffold). **Start here.**
2. [`DOMAINS.md`](../DOMAINS.md) — bounded-context dispatch table + cross-context orchestration rules.
3. `CLAUDE.md` §The operating model — the current operating model (scoped denials + advisory review + operator-as-authority; no autonomy flag, no maker-checker ship-gate, no model self-start). The L2–L5 autonomy ratchet that previously lived in `METHODOLOGY.md or CLAUDE.md` through `0005-...` is retired — see CLAUDE.md §The operating model for what survives (the no-model-self-start rule) and what was retired (L3 cage, L4 self-launch, L5 auto-push). Four model-/cage-removing variants stay out of scope by design.
4. [`BOUNDARY.md`](../BOUNDARY.md) — auto-regenerated capability map (skills / agents / commands / hooks).

The four are auto-injected on every SessionStart by `hooks/session/doctrine-bootstrap.sh`.
No manual `@import` needed.

## The 3 commands you'll use most

| Command | When | What it does |
|---|---|---|
| `/ship-task` | From idea to shipped | Full 9-step senior-engineer loop; embeds acceptance gating before the ship step. |
| `/review-pr` | After pushing a PR | Multi-agent review (code, tests, security, types) over the diff. |
| `/ship-merge` | After PR approval | Verifies the diff + merges. The human gate sits between review and merge. |

Other useful ones: `/fix-bug`, `/deep-dive`, `/frame`,
`/ideate`. Full list in [`BOUNDARY.md`](../BOUNDARY.md).

## The 1 thing to never do

**Do not relax the autonomy invariant past a deliberate superseding ADR.** The operating model
turns only by a human-authored, recorded superseding decision — never a flag flip, never a loop
self-edit (the cage forbids `CLAUDE.md`, `METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md`,
`settings.json`, and any caged path in `scripts/cage.txt`). The L3–L5 ladder (L3 bounded autonomy,
L4 self-launch within a cage, L5 auto-push behind a computational ship-gate) was retired when the
L2–L5 ratchet was superseded — see `CLAUDE.md` §The operating model. Four variants stay
**out of scope by design** (each would need a new superseding decision): the *model* self-launching
the loop, a *model*-authorizing ship-gate, the loop authoring its own doctrine, and removing the
cage. The invariant is load-bearing
— it preserves the operator's judgment; the gate that authorizes a mutation
or ship stays **computational, never a model**.

## Recurring cadences (read once, never re-derive)

- **Harness decay sweep** — every quarter, prune dead weight. See
  [`docs/harness-decay-cadence.md`](harness-decay-cadence.md).
- **Harness audit** — run the `harness-audit` skill on demand. CRIT findings block ship.

## If you only have 60 seconds

Read this file's first three sections. If you have 5 more minutes, skim
[`METHODOLOGY.md`](../METHODOLOGY.md). If you have 10 more, read
[`DOMAINS.md`](../DOMAINS.md) and [`METHODOLOGY.md Rule 8 + CLAUDE.md §The operating model`](METHODOLOGY.md or CLAUDE.md §"Rejected alternatives".

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
- **[the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model addendum](METHODOLOGY.md or CLAUDE.md — 10 deferred items + L2 alternatives.
