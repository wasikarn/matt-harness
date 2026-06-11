# Changelog

All notable changes to `kbg` are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

Pre-`1.0.0`: breaking changes may land in any `0.x` release.

## [0.1.2] — 2026-06-11

Patch release — surfaces two post-`0.1.1` fixes as a clean release line. No new features, no
breaking changes.

### Fixed

- **G15 (P0): harness-audit cache-version hardcode.** `audit.sh:70` hardcoded `0.1.0` as the
  default plugin-cache path. When the cache bumped to `0.1.1/` (or any future `0.x.y/`), the
  hardcoded default pointed at a missing directory, silently setting `PLUGIN_ACTIVE=0` and
  disabling the F1 plugin-aware bypass — surfacing **61 false-positive CRITs** on `audit.sh`
  (the very thing the F1 rework in `0.1.1` was meant to fix). Now resolves the cache version
  dynamically via `ls | sort -V | tail -1`. (`846452a`)

### Added

- **CI: `.github/workflows/validate.yml`** — runs `claude plugin validate --strict .` on every
  push and PR to `main` and `develop`. Catches schema / manifest drift before publish; pairs
  with the existing pre-commit harness-audit + critical-hooks gates. (`9f704f0`)

## [Unreleased]

### Fixed

- manifest: bump skill count 25 → 26 (memory-trim added)

### Changed

- **Delivery model: symlink farm → persistent plugin-enable.** The owner now installs `kbg` via
  `claude plugin install` + `enabledPlugins["kbg@kobig"]: true` and dogfoods exactly what an
  external installer gets — **superseding** the 0.1.0 "bare-name symlink farm, plugin disabled
  locally" model below. `install.sh`'s component-symlink steps are neutered and the in-`~/.claude`
  symlink farm removed, so the plugin is the single delivery path. (`dotfiles` `962bfce`)
- **Manifest accuracy** — `marketplace.json` description aligned with `plugin.json` ("governance
  hooks across 14 lifecycle events"); `.code-review-graph/` gitignored so no stale local SQLite
  cache ships; `version` retained (omitting it fails `claude plugin validate --strict`). (`c50710b`)

### Fixed

- **Doctrine loads on every session start, not just fresh start.** `doctrine-bootstrap.sh` moved
  from the `startup` matcher into a no-matcher SessionStart group, so METHODOLOGY/RTK/ACLI/DBGATE
  inject on **resume** and **clear** too — matching the old `@import` behavior (`CLAUDE.md` was read
  on every session). Previously a resumed session got no doctrine once the dotfiles `@import` glue
  was removed. (`cc9bee8`)

### Known issues

- `harness-audit` F1 ("component not symlinked to `~/.claude/`") false-positives under the plugin
  delivery model — it predates the cutover and still assumes the symlink farm. Pending
  plugin-awareness rework.

## [0.1.0] — 2026-06-10

Initial packaged release. `kbg` was extracted from the owner's `dotfiles` harness into a
standalone, self-contained Claude Code plugin (`.claude-plugin/{plugin,marketplace}.json`,
`${CLAUDE_PLUGIN_ROOT}`-portable hooks).

### Added

- **27 senior-specialist agents** — `code-architect`, `backend-engineer`, `frontend-engineer`,
  `security-reviewer`, `devops-engineer`, `test-engineer`, `code-reviewer`, `code-explorer`,
  `silent-failure-hunter`, `type-design-analyzer`, and others (full list: `claude plugin details kbg`).
- **25 workflow skills** (now 26 in `0.1.1`; `memory-trim` added) — `orchestrate`, `clarify-first`,
  `harness-audit`, `recursive-improve`, `article-mine`, `decommission`, `migrate`, `research-brief`,
  `tech-humanize`, `memory-trim`, … (`skills/_lib/` holds shared shell helpers and is not a skill).
- **8 slash commands** — `address-review`, `deep-dive`, `feature-dev`, `fix-bug`, `post-mortem`,
  `ship-merge`, `ship-release`, `status-update`.
- **Governance hooks across 14 lifecycle events** — SessionStart, PreToolUse, PostToolUse,
  UserPromptSubmit, PermissionRequest/Denied, Stop, SessionEnd, PreCompact, and others. All hook
  commands resolve via `${CLAUDE_PLUGIN_ROOT}` (no hardcoded paths).
- **Always-on doctrine injection** — `METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md` injected at
  SessionStart via `doctrine-bootstrap.sh`.
- **TECH-LEAD-THAI output style** and the **catppuccin-mocha** theme.

### Design

- **Personal-harness-as-plugin (the deliberate model).** `kbg` is the owner's single source of
  truth, shipped as a plugin artifact. The owner installs it via a bare-name symlink farm
  (`install.sh`), **not** via plugin-install; the plugin is disabled locally
  (`settings.json: "kbg@kobig": false`) so its hooks never double-fire against the symlinked copy.
  See `docs/ARCHITECTURE.md`.
- **Doctrine is mandatory, not opt-in.** A stranger who installs and enables `kbg` inherits the
  owner's METHODOLOGY/RTK/ACLI/DBGATE conventions as-is. This is intentional for a personal harness;
  see `README.md` → "For external installers" for how to disable or adapt.
- **No bundled MCP/LSP servers** (`MCP servers (0)`, `LSP servers (0)`). Hooks that shell out to
  external tools (`rtk`, `qmd`, `memory-lint`, `code-review-graph`) degrade gracefully when those
  tools are absent.
- **Cost:** ~12.3k tokens always-on per session (doctrine + skill/agent descriptions), per
  `claude plugin details kbg`.

### Notes

- Not published to a public marketplace. Distribution is private (`wasikarn/kbg-harness`).
- Best-effort maintenance; no support SLA or backwards-compatibility guarantee pre-`1.0.0`. Fork to
  customize.
