# CONTEXT

Domain language for `kbg-harness` — a personal Claude Code harness delivered as a
Claude Code plugin.

> **First time here?** Read [`docs/onboarding.md`](docs/onboarding.md) first
> (≤500 tokens; 10-minute cold-start). Come back for the bounded-context model
> once you know what ships where.

## Bounded context

**Personal-harness-as-plugin (Option A), post-cutover.** The repo is the owner's
personal Claude Code harness, packaged as an installable plugin (`kbg@kobig`).
The owner **dogfoods the plugin** — the same delivery shape that external
installers use is the delivery shape the owner uses day-to-day. There is no
separate "owner" path. See
[`docs/adr/0001-personal-harness-as-plugin.md`](docs/adr/0001-personal-harness-as-plugin.md).

## Delivery path

**Single delivery: the `kbg@kobig` plugin (persistent-enabled).** `install.sh`
in the sibling `dotfiles` repo sets `enabledPlugins["kbg@kobig"] = true` in
`~/.claude/settings.json`; the plugin is the sole source for `agents/`,
`skills/`, `commands/`, `hooks/`, `output-styles/`, and `themes/`. All
components are auto-discovered and namespaced under `kbg:` (so a skill is
invoked as `kbg:fix-bug`, a command as `/kbg:fix-bug`).

Doctrine reaches the session through `hooks/session/doctrine-bootstrap.sh`, a
**matcher-less SessionStart hook** that injects `METHODOLOGY.md` / `RTK.md` /
`ACLI.md` / `DBGATE.md` as `hookSpecificOutput.additionalContext` on every
SessionStart sub-event (`startup`, `resume`, `clear`, `compact`). The legacy
symlink-farm delivery was torn down in commits `962bfce` + `f7c2459` +
`94f709c` (see `CHANGELOG.md` [Unreleased]); the persistent-enable strategy is
the steady state going forward.

## Invariants

- **No double-fire.** Doctrine (and any hook) must never load twice for the
  owner. Two guards hold this: (1) `install.sh` neuters all six
  `install_claude_*` symlink-farm calls (see `dotfiles/install.sh:969-981`),
  so the only source of governance hooks is the plugin's `hooks.json`; (2) the
  `doctrine-bootstrap.sh` hook self-suppresses when `~/.claude/CLAUDE.md`
  `@import`s doctrine (it does not, post-cutover).
- **Doctrine is mandatory.** No opt-in flag — a personal harness has no
  anonymous users to configure for. (METHODOLOGY Rule 2: no speculative
  configurability.)
- **No bundled MCP/LSP servers.** Hooks that depend on `rtk` / `qmd` /
  `memory-lint` / `code-review-graph` must degrade gracefully when those tools
  are absent.
- **Autonomy is human-gated within a cage floor (the autonomy invariant).**
  The ratchet turns only by a deliberate, human-authored, recorded ADR —
  never a flag flip, never a loop self-edit (the cage forbids `docs/adr/**`).
  One opt-in arming key, `KBG_AUTONOMY` (`1` = armed, unset/`0` = OFF, default
  OFF); which capabilities an armed run has is set by the committed slice code,
  not the key value.
  - **L2 (default):** no autonomous or unattended self-repair loop, and no
    multi-iteration loop that runs without a human gate — every
    self-improvement iteration stops at a human `AskUserQuestion` gate per
    mutation; `recursive-improve` keeps `disable-model-invocation: true`
    (the model can't self-start).
  - **L3 (opt-in, [ADR 0003](docs/adr/0003-l3-bounded-autonomy.md)):** a
    bounded unattended loop runs within an owner-approved run, commits
    local-only, and is **human-gated at push (Gate 2)**, not per mutation; the
    in-loop gate is **computational** (the gauntlet, never a model).
  - **L4 (opt-in, [ADR 0004](docs/adr/0004-l4-autonomy.md)):** self-launch
    (#1, an **OS scheduler** — not the model — self-starts) + a veto-only
    model-gate (#3, trialed on one low-stakes skill) + auto-inject (#4);
    auto-push (#2) is **dropped**, the human stays at Gate 2.
  - **L5 (opt-in, [ADR 0005](docs/adr/0005-l5-auto-push.md)):** re-adds
    auto-push/auto-merge (#2); the human leaves the push loop, replaced by a
    **computational** ship-gate (the gauntlet); the model stays veto-only and
    gains no ship authority. Enable is gated by ADR 0004's i/ii/iii (N≥20
    clean cycles, F1/F2/F3 closed, cumulative cap).

  **The deepest invariant, preserved at every level:** the gate that
  *authorizes* a mutation or a ship stays **computational, never a model**.
  The model is veto-only at L4/L5 — it can force a rollback, never bless or
  ship. The cage is retained at every level: the loop may auto-improve the
  non-safety surface, but it cannot disable its own brakes or rewrite its
  governing ADRs. This is the canonical home for the invariant that
  `recursive-improve` cites — a **judgment-preservation** choice, not a
  capability gap to be closed as models improve. Four variants stay **out of
  scope by design** (each needs a new superseding ADR): the *model*
  self-launching, a *model*-authorizing ship-gate, the loop authoring its own
  ADRs, and removing the cage.

  **See** [ADR 0002](docs/adr/0002-autonomy-invariant.md) (L2-era principle +
  foreclosures), [ADR 0003](docs/adr/0003-l3-bounded-autonomy.md) (the two-gate
  model), [ADR 0004](docs/adr/0004-l4-autonomy.md) (self-launch within the
  cage, push kept), and [ADR 0005](docs/adr/0005-l5-auto-push.md) (auto-push
  behind a computational ship-gate).

## Components

| Directory | Owner + External install as |
| --- | --- |
| `agents/` | `kbg:<agent-name>` (e.g. `kbg:code-architect`) |
| `skills/` | `kbg:<skill-name>` (e.g. `kbg:fix-bug`) |
| `commands/` | `/kbg:<command-name>` (e.g. `/kbg:fix-bug`) |
| `hooks/` | `hooks.json` registers them; `doctrine-bootstrap.sh` fires on all SessionStart |
| `output-styles/` | `kbg:<style-name>` |
| `themes/` | `kbg:<theme-name>` |

All components are namespaced under `kbg:` — bare-name invocation is no longer
the delivery model.

## Doctrine files (mandatory imports)

`METHODOLOGY.md`, `ACLI.md`, `DBGATE.md`, `RTK.md` — reach the session through
`hooks/session/doctrine-bootstrap.sh` (a single source for both owner and external
installers). The four files live in the plugin root and are injected as
SessionStart `additionalContext`.

## Deliberate non-goals

- No public-marketplace publish, no CI release train. (Plugin-validation CI
  does run — `.github/workflows/validate.yml` — it is a conformance gate, not
  a release train.)
- No bundled dependencies — hooks degrade gracefully.
- No Option B (public-distributable) machinery unless a concrete
  external-demand signal arrives.

## Post-cutover audit history

- 2026-06-11: 4-agent post-cutover audit (`.scratch/post-cutover-audit-2026-06-11/`)
  surfaced this rewrite. The previous version of this file (pre-cutover) described
  the rejected "two delivery paths" strategy.
