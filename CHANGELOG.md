# Changelog

All notable changes to `kbg` are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

Pre-`1.0.0`: breaking changes may land in any `0.x` release.

## [0.1.0] — 2026-06-10

Initial packaged release. `kbg` was extracted from the owner's `dotfiles` harness into a
standalone, self-contained Claude Code plugin (`.claude-plugin/{plugin,marketplace}.json`,
`${CLAUDE_PLUGIN_ROOT}`-portable hooks).

### Added

- **27 senior-specialist agents** — `code-architect`, `backend-engineer`, `frontend-engineer`,
  `security-reviewer`, `devops-engineer`, `test-engineer`, `code-reviewer`, `code-explorer`,
  `silent-failure-hunter`, `type-design-analyzer`, and others (full list: `claude plugin details kbg`).
- **25 workflow skills** — `orchestrate`, `clarify-first`, `harness-audit`, `recursive-improve`,
  `article-mine`, `decommission`, `migrate`, `research-brief`, `tech-humanize`, … (`skills/_lib/`
  holds shared shell helpers and is not a skill).
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

- Not published to a public marketplace. Distribution is private (`BIG-TATHEP/kbg-harness`).
- Best-effort maintenance; no support SLA or backwards-compatibility guarantee pre-`1.0.0`. Fork to
  customize.
