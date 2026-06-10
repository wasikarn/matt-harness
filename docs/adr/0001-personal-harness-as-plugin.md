# ADR 0001: Personal-harness-as-plugin (Option A)

- **Status**: Accepted
- **Date**: 2026-06-10
- **Decider**: Owner

## Context

The harness needs to be reusable across machines. Three delivery paths were considered:

- **A — Personal symlink farm + plugin shape** — primary consumer is the owner; package
  in plugin shape so external install is possible but not advertised.
- **B — Public-distributable plugin** — full marketplace polish, doctrine opt-in, CI
  release train, public visibility.
- **C — Symlink farm only** — owner-only; no plugin manifest, no external install story.

## Decision

Adopt **Option A**. The repo is the owner's personal harness, packaged in plugin shape so
it *can* be installed — but the primary consumer is the owner. The plugin is **disabled
locally** (`settings.json: "kbg@kobig": false`). It is not published to a public marketplace.

## Consequences

### Delivery paths

#### 1. Owner (symlink farm)

`install.sh` symlinks `agents/ skills/ commands/ hooks/ output-styles/ themes/` into
`~/.claude/` under **bare names** (`/fix-bug`, `code-architect`, …). Doctrine reaches the
session through `dotfiles/claude/CLAUDE.md`, which `@import`s `METHODOLOGY.md` / `RTK.md` /
`ACLI.md` / `DBGATE.md`. The plugin is **disabled locally**.

#### 2. External installer (plugin install)

`/plugin install kbg@kobig` auto-discovers the same components, **namespaced**
(`/kbg:fix-bug`, `/kbg:code-architect`, …). Doctrine reaches the session through
`hooks/doctrine-bootstrap.sh`, which injects the four doctrine files as SessionStart
`additionalContext`.

### Invariant: no double-fire

The owner must never load doctrine (or any hook) twice. Two guards hold this:

1. **The plugin is disabled locally** — so its hooks, including `doctrine-bootstrap.sh`,
   never fire for the owner. This is the load-bearing guard.
2. **Coexistence guard in `doctrine-bootstrap.sh`** — even if the plugin were enabled
   while the symlink farm is active, the hook self-suppresses:

   ```sh
   # hooks/doctrine-bootstrap.sh
   [ -n "$ROOT" ] || exit 0                                  # only act as an installed plugin
   if grep -qs '@METHODOLOGY.md' "$HOME/.claude/CLAUDE.md"; then
     exit 0                                                  # symlinked CLAUDE.md already imports it
   fi
   ```

   While `~/.claude/CLAUDE.md` still `@import`s the doctrine, this hook stays silent; it
   only becomes the sole source after a full cutover (imports removed / symlink gone).
   Guard #2 is belt-and-braces on top of guard #1.

### Deliberate non-goals

- **No doctrine opt-in flag.** Doctrine is mandatory; a personal harness has no anonymous
  users to configure for (`METHODOLOGY` Rule 2 — no speculative configurability).
- **No bundled MCP/LSP servers.** Hooks that need `rtk` / `qmd` / `memory-lint` /
  `code-review-graph` degrade gracefully when absent.
- **No public-marketplace publish, no CI release train.** Versioning and releases are manual.

## Rejected alternatives

- **Option B (public-distributable)** — would require doctrine opt-in, an optional output
  style, CI validation/release, and marketplace polish, and would expose this repo's git
  history. Rejected per METHODOLOGY Rule 2 (no speculative configurability) and Rule 13
  (orchestrate, don't solo — no public-distribution machinery without real downstream
  demand). Revisit only on a concrete external-demand signal (a filed issue, a real
  downstream user); decision is the owner's.
- **Option C (symlink farm only)** — leaves no install path for collaborators / other
  machines the owner owns separately from `dotfiles`. Loses the "doc the install shape
  once" benefit.

## Verification

Conformance verified: `claude plugin validate . --strict` passes (CI-grade — fails on
unrecognized fields / missing metadata).
