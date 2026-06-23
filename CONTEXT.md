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
- **Autonomy is human-gated (the autonomy invariant).** **Default (L2):** no
  autonomous or unattended self-repair loop, and no multi-iteration loop that
  runs without a human gate between iterations — every self-improvement
  iteration stops at a human `AskUserQuestion` gate before any mutation.
  **L3 (opt-in, `KBG_AUTONOMY=1`, default OFF):** a *bounded* unattended
  self-repair loop may run within an owner-approved run — but it still cannot
  self-start (`recursive-improve` stays `disable-model-invocation: true`),
  commits **local-only**, and is **human-gated at push**, not per mutation
  (ADR 0003). Either way the model cannot self-launch the loop, and **L4** (no
  human gate at all) stays rejected. The gate is a deliberate
  **judgment-preservation** choice — not a capability gap to be closed as
  models improve; the same loop machinery preserves or destroys engineering
  judgment depending on operator intent, and the loop can't tell the
  difference. L3 keeps that judgment at the irreversible (push) boundary; it
  relaxes only the per-mutation gate on reversible local commits. This is the
  canonical home for the invariant that `recursive-improve` cites.

  **See [ADR 0002](docs/adr/0002-autonomy-invariant.md)** for the L2-era
  decision record (rejected alternatives, 5 implementation surfaces, 3
  verification pillars) and **[ADR 0003](docs/adr/0003-l3-bounded-autonomy.md)**
  for the L3 supersession (the two-gate model + the standing-consent
  reconciliation).

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
