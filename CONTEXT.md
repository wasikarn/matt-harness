# CONTEXT

Domain language for `kbg-harness` — a personal Claude Code harness packaged in plugin shape.

## Bounded context

**Personal-harness-as-plugin (Option A).** The repo is the owner's personal harness, packaged
so it *can* be installed externally — but the primary consumer is the owner, who does not
plugin-install it. It is not published to a public marketplace. See
[`docs/adr/0001-personal-harness-as-plugin.md`](docs/adr/0001-personal-harness-as-plugin.md).

## Delivery paths

- **Owner (symlink farm).** `install.sh` symlinks `agents/`, `skills/`, `commands/`, `hooks/`,
  `output-styles/`, `themes/` into `~/.claude/` under bare names. Doctrine reaches the session
  through `dotfiles/claude/CLAUDE.md` (which `@import`s the four doctrine files).
- **External installer (plugin install).** `/plugin install kbg@kobig` auto-discovers the same
  components, **namespaced** under `kbg:`. Doctrine reaches the session through
  `hooks/doctrine-bootstrap.sh`, which injects the four doctrine files as SessionStart
  `additionalContext`.

## Invariants

- **No double-fire.** Doctrine (and any hook) must never load twice for the owner. Two guards
  hold this: (1) the plugin is disabled locally (`settings.json: "kbg@kobig": false`); (2) the
  `doctrine-bootstrap.sh` hook self-suppresses when the symlinked `CLAUDE.md` already imports
  doctrine.
- **Doctrine is mandatory.** No opt-in flag — a personal harness has no anonymous users to
  configure for. (METHODOLOGY Rule 2: no speculative configurability.)
- **No bundled MCP/LSP servers.** Hooks that depend on `rtk` / `qmd` / `memory-lint` /
  `code-review-graph` must degrade gracefully when those tools are absent.

## Components

| Directory | Owner installs as | External install as |
| --- | --- | --- |
| `agents/` | bare agent names (e.g. `code-architect`) | `kbg:code-architect` |
| `skills/` | bare skill names (e.g. `fix-bug`) | `kbg:fix-bug` |
| `commands/` | bare slash names (e.g. `/fix-bug`) | `/kbg:fix-bug` |
| `hooks/` | owner path (no fire) | `doctrine-bootstrap.sh` fires on SessionStart |
| `output-styles/` | bare style names | `kbg:*` |
| `themes/` | bare theme names | `kbg:*` |

## Doctrine files (mandatory imports)

`METHODOLOGY.md`, `ACLI.md`, `DBGATE.md`, `RTK.md` — reach the session through the owner's
`dotfiles/claude/CLAUDE.md` (symlink farm) or `hooks/doctrine-bootstrap.sh` (external install).
Both paths must inject the same four files.

## Deliberate non-goals

- No public-marketplace publish, no CI release train, no plugin validation CI.
- No bundled dependencies — hooks degrade gracefully.
- No Option B (public-distributable) machinery unless a concrete external-demand signal arrives.
