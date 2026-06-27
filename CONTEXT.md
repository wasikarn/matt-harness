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
`CLAUDE.md §Plugin delivery model`.

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
- **Operating model: scoped denials, advisory review, operator-as-authority
  (CLAUDE.md §The operating model (current), supersedes the
  L2-L5 autonomy ratchet that previously lived in `docs/adr/`).** The harness is a **friction layer, not a
  hard wall**: it **denies the irrecoverable set computationally and advises on
  the rest**; the **operator is the authority at every irreversible boundary**.
  There is **no autonomy flag** (the `KBG_AUTONOMY` ratchet and its
  `KBG_REVIEW_DONE`/`KBG_L5_SHIP_ALLOWLIST` keys are retired), **no enforced
  maker≠checker ship-gate**, and **no model self-start**. Review is **advisory**,
  not a hard-coded gate; the maker≠checker bar stays a human judgment matched to
  stakes.
  - **Scoped denials (computational feedforward)** — `block-dangerous-git.sh`
    (force-push-to-main/master deny, develop ask, fix/feat allow;
    `reset --hard` / `clean -f` / `branch -D` / `checkout .` / `restore .` /
    `core.hooksPath` / `commit --amend` / `git rm -r` / `switch --force` deny;
    remote-mutation ask; `--no-verify`/`-n` hook-bypass blocked) +
    `block-dangerous-bash.sh` (non-git destructive surface: `rm -rf` all flag
    forms, `find -exec rm`, `dd`, SQL DDL) deny the irrecoverable set. The safe
    operator force (`--force-with-lease`) is allowed.
  - **Advisory reminders (non-blocking)** — `advisory-push-reminder.sh`,
    `tmux-reminder`, `commit-quality-reminder` surface review prompts; they
    never block.
  - **The gauntlet as a general validation runner** — `run-gauntlet.sh`
    validates (CI + operator); the retired `gauntlet_run` SHA-bound push-leg
    ship-gate is gone, so the gauntlet validates but does not authorize a ship.
  - **Judgment preservation (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model, preserved append-only)** — the gate that
    *denies* a mutation or a ship stays **computational, never a model**. The
    model is **veto-only** — it can force a rollback, never bless or ship. This
    is the canonical home for the principle `recursive-improve` cites — a
    **judgment-preservation** choice, not a capability gap to be closed as
    models improve.
  - **The cage retained as a safety-surface manifest** — `scripts/cage.txt`
    stays as the consequential-safety-surface manifest;
    `decision-provenance-nudge.sh` keeps reading it as the single source for
    "caged path" provenance classification. The cage forbids the doctrine prose files
    (CLAUDE.md / METHODOLOGY.md / RTK.md / ACLI.md / DBGATE.md / CONTEXT.md / DOMAINS.md) —
    loop-authored doctrine stays out.
  - **No model self-start** — `recursive-improve` keeps
    `disable-model-invocation: true` (audit #32 CRIT, guarded by the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model) and
    survives as the Observe → Propose → `AskUserQuestion` human-gated ritual —
    every iteration stops at a human gate before any mutation. The L4 launchd
    self-launch machinery is decommissioned; there is no OS-scheduler
    self-start either.

  Four variants stay **out of scope by design** (each would need a new superseding
  prose edit): the *model* self-starting a loop, a *model*-authorizing ship, the loop
  authoring its own doctrine edits, and removing the cage. These are principle-bounded,
  not capability-bounded — reopening them on a "models are better now" argument
  is foreclosed.

  **See** CLAUDE.md §The operating model (current) (the
  operating model) and the no-model-self-start rule in METHODOLOGY.md Rule 8 and CLAUDE.md
  (judgment-preservation principle + foreclosures, preserved append-only).

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
