# Cost-ledger module

`hooks/mod/cost-ledger.ts` is mh's one hooks module (a Claude Code mod, GH #323). It is an
observer: it never denies, asks, rewrites or answers for core. The shell hooks stay the base:
`cost-tracker.sh`, `costs.jsonl` and every gate are unchanged, and the transcript-priced total in
`costs.jsonl` stays the authoritative session cost (GH #334, option A). The module adds one
thing: a cross-check against Claude Code's own cost ledger.

## What it records

After each main-loop turn (`turn.complete` with no `agentId`), it reads
`$.session.usage().cost.usd`, the session's cost as `/cost` totals it, and appends one row to
`~/.local/share/kbg/metrics/cost-ledger.jsonl`:

```
{ t, session_id, turn_id, usd, delta, reset }
```

- `usd`: the ledger's running total, as Claude Code reports it. This is the primary field.
- `delta`: `usd` minus the previous reading in this module load. The first reading counts in
  full. A drop means a new process took over the session id and its ledger started from zero, so
  `delta = usd` and `reset: true`.
- A failed read becomes `{ t, session_id, turn_id, error }`. A failed append is a `$.ui.log` line
  (debug log outside a hot-reload session) and the row is lost; the next row's `delta` carries the
  growth.
- `usage()` with no `cost` (a host that keeps no ledger) writes nothing.

Subagent turns write no row; their spend shows up in the enclosing main turn's `delta`, because
the ledger covers the whole session.

Names verified against the `claude-code.d.ts` that CLI 2.1.288 writes: `turn.complete`'s input
(`TurnCompleteFields`: `turnId`, `agentId` absent on the main loop), `$.session.usage()` returning
`SessionUsage.cost?: SessionCost` with `usd: number`. `turn.step` was not used: it is a
streaming event per model request, not per turn. `session.measure` also carries `cost` and fires
after each main-thread turn, but has no turn id and was not probed under `claude -p`.

## How cost-report reads it

`skills/meta/cost-report/scripts/cost-report-dedup.js` prints one `ledger cross-check:` line: the
transcript total vs the ledger total over the sessions present in both files, and the gap. It
recomputes each session's ledger total from the `usd` sequence in file order with the same rule
and ignores the stored `delta`, which restarts when the module reloads. The rule and the line's
three cases are in `skills/meta/cost-report/references/data-model.md`, section
"Gap to Claude Code's own ledger".

## When modules are off

Nothing is written, and the only loss is the cross-check line: cost-report prints
`ledger cross-check: no ledger data (...)`, not zero and not an error. Modules are off on CLIs
before 2.1.287, under `--bare`, `--safe-mode`, `disableAllHooks`, `allowManagedHooksOnly`,
`allowManagedModsOnly`, in an untrusted workspace, and when Anthropic's remote switch serves off.
A reload after such a flip drops the module mid-session.

## Turning it off

There is no mh-only switch. Claude Code's own switches stop it: `--safe-mode` for one session,
or `"disableAllHooks": true`, which also stops mh's shell hooks and gates. Disabling `mh` in
`/plugin` stops all of mh. A mh-only switch (a `userConfig` field) is easy to add if anyone needs
it.

## Minimum CLI

The module needs Claude Code 2.1.287 or later (code.claude.com `plugins/mods/overview`). This is
documentation only: `plugin.json` has no field for a minimum version. On older CLIs the
`modules` key is harmless: `claude plugin validate` 2.1.261 (CI's pin at the time of writing)
accepts it, and a 2.1.240 runtime ran the command hooks and ignored the module (#323).

## Rules for this file

- **One module per plugin.** Claude Code refuses a second `modules` entry. Any later module
  feature joins this file.
- **Never a gate.** A module fails open whenever modules are off, so deny and ask logic stays in
  shell hooks (#323's keep/port table).
- **Tests.** `tests/mods/cost-ledger.test.ts` runs under `claude plugin test .` from the repo
  root, with Claude Code's mods test kit. `tests/hooks/test-cost-ledger-module.sh` wraps it for
  the gauntlet and prints `SKIP` on a CLI with no `plugin test`. `tsc` is not run (the repo has
  no TypeScript toolchain); `claude plugin validate` reads the module source.
- Loading the plugin from a folder (`--plugin-dir`) makes the engine write
  `.claude-plugin/types/` there; it carries its own `.gitignore`.

## Known limits

- Spend after the last main-loop turn (a background subagent that ends after it, any request
  Claude Code makes after that turn) is not read.
- A new process whose first reading is above the old total reads as growth, not a reset, so the
  ledger total runs low for that session.
- The baseline lives in a module variable, so after a reload the first row's `delta` equals
  `usd`. The report's recomputation is unaffected.
