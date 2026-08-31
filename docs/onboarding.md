# matt-harness — First 10 minutes

A cold-start for working in (or with) the matt-harness repo. If you read this
file and nothing else, you can name what the repo is, where doctrine lives, and
the three commands you'll use most. Stays ≤500 tokens on purpose — in-repo,
in-context, no scroll.

## What this repo is (1 sentence)

A personal Claude Code harness delivered as an installable plugin (`mh@wasikarn`):
skills, agents, commands, governance hooks, and mandatory doctrine injection —
see `BOUNDARY.md` below for the live count.

## The 3 doctrine files (read in this order)

1. [`METHODOLOGY.md`](METHODOLOGY.md) — staff-engineer behavioral doctrine (decision triad + reasoning scaffold). **Start here.** The only one auto-injected on every SessionStart, by `hooks/session/doctrine-bootstrap.sh` — no manual `@import` needed.
2. `CLAUDE.md`'s Operating model (under its Architecture section) — the current operating model: computational deny-gates for the irrecoverable set (`hooks/gates/`), advisory sensors for the rest (`hooks/advisory/`), no autonomy flag, no maker-checker ship-gate, no model self-start. The L2–L5 autonomy ladder that previously lived here was retired in the v0.6.0 "reset: rebuild from scratch" cut — see CLAUDE.md's "Why — the unifying crux" for what replaced it (verifier-separation: an LLM judging its own output is circular, so gates stay deterministic shell, never a model). Read manually, not injected.
3. [`BOUNDARY.md`](../BOUNDARY.md) — auto-regenerated capability map (skills / agents / commands / hooks). Read manually, not injected.

## The 3 commands you'll use most

| Command | When | What it does |
|---|---|---|
| `/mattpocock-skills:implement` | From spec/tickets to committed code | Implements with `mattpocock-skills:tdd` where possible, typechecks, runs the suite, commits. |
| `mattpocock-skills:code-review` | After pushing a PR | Standards + spec review over the diff (parallel sub-agents). |
| `mh:ship-merge` | After review | Verifies the diff + merges. The human gate sits between review and merge. |

Other useful ones: `mattpocock-skills:diagnosing-bugs`, `research`, `mh:frame`,
`mh:ideate`. Full list in [`BOUNDARY.md`](../BOUNDARY.md).

## The 1 thing to never do

**Do not let the model edit the code that judges it.** `hooks/gates/verifier-protect.sh`
asks for explicit human approval before any edit to `hooks/gates/**`, `hooks/hooks.json`
(the deny-gates + wiring), or the harness-audit verifier (`skills/meta/harness-audit/scripts/audit.sh`
+ `checks/**`) — no env-var bypass. The L3–L5 autonomy ladder (bounded-autonomy cage, self-launch,
auto-push ship-gate) that previously enforced this via a caged file list was retired in the v0.6.0
reset; today's protection is this computational deny-gate, not a file-based cage. The invariant is
load-bearing — the gate that authorizes a mutation or ship stays **computational, never a model**
(see `CLAUDE.md`'s "Why — the unifying crux": an LLM judging its own output is circular —
"two optimists agreeing").

## Recurring cadences (read once, never re-derive)

- **Harness decay sweep** — every quarter, prune dead weight. See
  [`docs/harness-decay-cadence.md`](harness-decay-cadence.md).
- **Harness audit** — run the `harness-audit` skill on demand. CRIT findings block ship.

## If you only have 60 seconds

Read this file's first three sections. If you have 5 more minutes, skim
[`METHODOLOGY.md`](METHODOLOGY.md). If you have 10 more, read CLAUDE.md's
Operating model, under its Architecture section (the "Rejected alternatives" notes).

## What's shipped

See [`CHANGELOG.md`](../CHANGELOG.md) for the dated history. This file intentionally
doesn't track "recently shipped" — a moving target here just goes stale (as this
section itself did across the v0.6.0 "reset: rebuild from scratch" cut).
