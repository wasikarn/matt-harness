# ADR 0001: Personal-harness-as-plugin (Option A), post-cutover

- **Status**: Accepted (revised 2026-06-11 after kbg-cutover)
- **Date**: 2026-06-10 (revised 2026-06-11)
- **Decider**: Owner

## Context

The harness needs to be reusable across machines. Three delivery paths were considered:

- **A — Single-plugin delivery (persistent-enabled, owner dogfoods)** — the
  repo ships as a Claude Code plugin (`kbg@kobig`); the owner installs it like
  any external consumer. One source, one delivery path.
- **B — Public-distributable plugin** — full marketplace polish, doctrine
  opt-in, CI release train, public visibility.
- **C — Symlink farm only** — owner-only; no plugin manifest, no external
  install story.

## Decision

Adopt **Option A (single-plugin delivery, persistent-enabled)**. The repo is
the owner's personal harness, packaged as an installable plugin. The owner
**dogfoods the same plugin** they publish — there is no separate "owner"
delivery path. The plugin is **enabled by default** in `~/.claude/settings.json`
(`enabledPlugins["kbg@kobig"] = true`); the previous "plugin disabled locally,
owner uses symlink farm" strategy was retired in commits `962bfce` +
`f7c2459` + `94f709c` (see `CHANGELOG.md` [Unreleased]).

## Consequences

### Delivery path (single, post-cutover)

`install.sh` in the sibling `dotfiles` repo sets
`enabledPlugins["kbg@kobig"] = true` in `~/.claude/settings.json`. The
plugin's `hooks.json` registers all governance hooks; the plugin's
`agents/`, `skills/`, `commands/`, `output-styles/`, and `themes/` are
auto-discovered and **namespaced** under `kbg:` (so a skill is invoked as
`kbg:fix-bug`, a command as `/kbg:fix-bug`). All governance components flow
from the plugin cache (`~/.claude/plugins/cache/kobig/kbg/<version>/`).

Doctrine reaches the session through `hooks/doctrine-bootstrap.sh`, a
**matcher-less SessionStart hook** that injects `METHODOLOGY.md` / `RTK.md` /
`ACLI.md` / `DBGATE.md` as `hookSpecificOutput.additionalContext` on every
SessionStart sub-event (`startup`, `resume`, `clear`, `compact`).

### Invariant: no double-fire

The owner must never load doctrine (or any hook) twice. Two guards hold this:

1. **`install.sh` neuters all six `install_claude_*` symlink-farm calls**
   (`dotfiles/install.sh:969-981`). The only source of governance hooks is
   the plugin's `hooks.json`. This is the **load-bearing guard** post-cutover.
2. **Coexistence guard in `doctrine-bootstrap.sh`** — the hook
   self-suppresses when `~/.claude/CLAUDE.md` `@import`s doctrine:

   ```sh
   # hooks/doctrine-bootstrap.sh
   if grep -qs '@METHODOLOGY.md' "$HOME/.claude/CLAUDE.md"; then
     exit 0  # CLAUDE.md already imports doctrine — don't double-inject
   fi
   ```

   Post-cutover, `~/.claude/CLAUDE.md` does not `@import` doctrine (the dead
   `@RTK.md` import was removed in this audit pass, 2026-06-11), so the hook
   fires on every SessionStart. Guard #2 is belt-and-braces on top of guard
   #1.

### Deliberate non-goals

- **No doctrine opt-in flag.** Doctrine is mandatory; a personal harness has
  no anonymous users to configure for (`METHODOLOGY` Rule 2 — no speculative
  configurability).
- **No bundled MCP/LSP servers.** Hooks that need `rtk` / `qmd` /
  `memory-lint` / `code-review-graph` degrade gracefully when absent.
- **No public-marketplace publish, no CI release train.** Versioning and
  releases are manual.

## Rejected alternatives

- **Option B (public-distributable)** — would require doctrine opt-in, an
  optional output style, CI validation/release, and marketplace polish, and
  would expose this repo's git history. Rejected per METHODOLOGY Rule 2 (no
  speculative configurability) and Rule 13 (orchestrate, don't solo — no
  public-distribution machinery without real downstream demand). Revisit only
  on a concrete external-demand signal (a filed issue, a real downstream
  user); decision is the owner's.
- **Option C (symlink farm only)** — leaves no install path for
  collaborators / other machines the owner owns separately from `dotfiles`.
  Loses the "doc the install shape once" benefit. Was the pre-cutover owner
  path; torn down in commit `962bfce` (2026-06-11).
- **Option A-pre-cutover (two delivery paths)** — original ADR called for
  "Owner (symlink farm) + External installer (plugin install)" as two
  coexisting paths. The cutover retired the owner-symlink-farm half because
  the dual paths (a) were a perpetual source of drift (the symlink farm
  could fall behind the plugin cache), (b) doubled the surface for the
  no-double-fire invariant, and (c) obscured the canonical install shape
  for any future external user. Single delivery = single source of truth.

## Verification

Conformance verified: `claude plugin validate . --strict` passes (CI-grade —
fails on unrecognized fields / missing metadata).

Post-cutover acceptance: `.scratch/kbg-cutover-ACCEPTANCE.md` in the sibling
`dotfiles` repo, re-runnable via
`python3 .scratch/run-cutover-acceptance.py`. The 4-child contract
machine-verifies the cutover (manifest, enable-verify, teardown, document).
