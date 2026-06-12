# kbg — Claude Code Harness (Plugin)

[![Version](https://img.shields.io/badge/version-0.1.9-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A **personal Claude Code harness** delivered as an installable plugin (`kbg@kobig`) — 27 senior-specialist agents, 32 workflow skills, 16 slash commands, governance hooks across 14 lifecycle events, and always-on doctrine injection. No symlink farm, no manual wiring — components auto-discover from the plugin cache.

> **First time here?** Read [`docs/onboarding.md`](docs/onboarding.md) for a 10-minute cold-start.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What You Get](#what-you-get)
- [Requirements](#requirements)
- [Architecture](#architecture)
- [Development](#development)
- [Documentation](#documentation)
- [License](#license)

---

## Quick Start

```bash
# 1. Add marketplace
/plugin marketplace add wasikarn/kbg-harness

# 2. Install
/plugin install kbg@kobig

# 3. Verify
/plugin list                    # look for kbg@kobig
/kbg:review-pr --help           # confirm components load
```

The plugin is **opt-in** (`defaultEnabled: false`) — nothing injects until you enable it in `settings.json`.

**Uninstall:** `/plugin uninstall kbg`  
**Disable (keep installed):** `"kbg@kobig": false` in `settings.json`

---

## What You Get

After `/plugin install kbg@kobig`, Claude Code loads all components from the plugin cache (`~/.claude/plugins/cache/kobig/kbg/<version>/`).

| Component | Count | How to Use |
|-----------|-------|-----------|
| **Agents** | 27 | Spawn via `kbg:<agent>` (e.g. `kbg:code-architect`) |
| **Skills** | 32 | Invoke via `/kbg:<skill>` (e.g. `/kbg:review-pr`) |
| **Commands** | 16 | Invoke via `/kbg:<command>` (e.g. `/kbg:ship-merge`) |
| **Hooks** | 32 scripts | Governance + doctrine across 14 lifecycle events |
| **Output Styles** | 1 | `TECH-LEAD-THAI` (Thai-code-switched register) |
| **Themes** | 1 | `catppuccin-mocha` |

### Most-Used Commands

| Command | When |
|---------|------|
| `/kbg:pre-ship-verify` | Before every PR — runs `ACCEPTANCE.md` + eval-harness gate |
| `/kbg:review-pr` | After pushing a PR — multi-agent review (code, tests, security, types) |
| `/kbg:ship-merge` | After PR approval — verifies diff + merges |
| `/kbg:fix-bug` | Non-trivial bug fixes — 7-phase workflow with TDD |
| `/kbg:feature-dev` | New features — 7-phase guided development |
| `/kbg:team-plan` / `/kbg:team-build` | Agent-team planning + execution (opt-in Agent Teams) |

### Governance Hooks

Hooks fire on 14 lifecycle events (SessionStart, PreToolUse, PostToolUse, UserPromptSubmit, PermissionRequest/Denied, Stop, SessionEnd, PreCompact, TeammateIdle, TaskCreated, TaskCompleted, etc.):

- **Safety gates** — block dangerous git ops, doctrine edits via Bash, alias shadowing, secret reads, DB writes
- **Audit trail** — append-only governance journal (`~/.claude/governance-events.jsonl`)
- **Doctrine injection** — `METHODOLOGY.md` / `RTK.md` / `ACLI.md` / `DBGATE.md` on every session start
- **Test-claim enforcement** — blocks TaskCompleted events claiming tests pass without a `validation_command:`

---

## Requirements

| Need | Version | Why |
|------|---------|-----|
| Claude Code | ≥ v2.1.154 | Honors `defaultEnabled: false` (opt-in) |
| `python3` | any | Doctrine injection JSON-escapes; two hooks use it |
| `git` | any | Git-aware skills/hooks |
| `bash`, `grep`, `sed` | standard | Hook scripts |
| `jq` | optional | Audit journaling and self-guards |

**Optional integrations** (gracefully degrade when absent):

| Tool | Unlocks |
|------|---------|
| `rtk` | Token-optimized Bash proxy (60–90% savings) |
| `code-review-graph` | Review-context graph (status + incremental update) |
| `qmd` | Local markdown-search reindex |
| `SUPERSET_HOME_DIR` | Agent-activity notifications |

> These are **not bundled** — the core runs without any of them.

---

## Architecture

### Plugin Delivery Model

There is **one delivery path**: the plugin cache at `~/.claude/plugins/cache/kobig/kbg/<version>/`. The owner dogfoods the same plugin that external installers use. See [`docs/adr/0001-personal-harness-as-plugin.md`](docs/adr/0001-personal-harness-as-plugin.md).

**Cache-invalidation is manual:** when you modify any plugin surface (agent, skill, command, hook), bump version in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then run `claude plugin update kbg@kobig` and restart Claude Code.

### Autonomy Invariant (ADR 0002)

No autonomous or unattended self-repair loop. Every self-improvement iteration stops at a human `AskUserQuestion` gate. `recursive-improve` carries `disable-model-invariant: true` so the model cannot self-start it. See [`docs/adr/0002-autonomy-invariant.md`](docs/adr/0002-autonomy-invariant.md).

### Key Files

| File | Purpose |
|------|---------|
| [`hooks/hooks.json`](hooks/hooks.json) | Hook registry across 14 lifecycle events |
| [`hooks/_lib.sh`](hooks/_lib.sh) | Shared helpers (audit logging, journal append, permission decisions) |
| [`eval/run-eval.py`](eval/run-eval.py) | Eval harness — 14 datasets + 9 regression fixtures |
| [`scripts/orchestrate-dispatch.py`](scripts/orchestrate-dispatch.py) | Workflow DAG resolver + fan-out cap enforcer |
| [`scripts/auth-health-check.py`](scripts/auth-health-check.py) | gh / MCP / plugins health probe |
| [`BOUNDARY.md`](BOUNDARY.md) | Auto-regenerated capability map (skills / agents / commands / hooks) |

---

## Development

### Validation (run before any commit touching hooks/skills/agents/commands)

```bash
# Plugin manifest validation
claude plugin validate --strict .

# Critical-hooks smoke tests (204 tests)
bash hooks/tests/test-critical-hooks.sh

# Harness self-audit (must be 0 Critical / 0 Warnings)
bash skills/harness-audit/scripts/audit.sh .

# Eval harness (dataset + regression fixtures)
python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate
```

### Adding Components

1. **Agent** — create `agents/<name>.md` with frontmatter. Auto-discovered.
2. **Skill** — create `skills/<name>/SKILL.md` with `## Input Contract`, `## Output Format`, `## Failure Modes`.
3. **Command** — create `commands/<name>.md` with frontmatter. Update manifest counts.
4. **Hook** — create `hooks/<name>.sh`, add to `hooks/hooks.json`, add tests if a gate.

After any addition: bump manifest versions → validate → commit → push → `claude plugin update kbg@kobig` → restart.

### Branch Model

Single-branch (`develop` only). Commit + push direct. No feature branches.

---

## Documentation

- [`docs/onboarding.md`](docs/onboarding.md) — 10-minute cold-start
- [`CONTEXT.md`](CONTEXT.md) — Domain language, autonomy invariant, delivery model
- [`METHODOLOGY.md`](METHODOLOGY.md) — 13-rule behavioral doctrine
- [`CHANGELOG.md`](CHANGELOG.md) — Release notes (Keep-a-Changelog, SemVer)
- [`CLAUDE.md`](CLAUDE.md) — Guidance for future Claude Code instances working in this repo
- [`BOUNDARY.md`](BOUNDARY.md) — Auto-regenerated cross-context inventory
- [`docs/adr/`](docs/adr/) — Architecture decision records

---

## License

MIT — see [`LICENSE`](LICENSE).

---

## For External Installers

This is a **personal harness**, not a general-purpose toolkit. Enabling `kbg` makes `METHODOLOGY` / `RTK` / `ACLI` / `DBGATE` mandatory context in every session, plus the `TECH-LEAD-THAI` output style. There is no opt-in flag.

To use components **without** doctrine injection: install the marketplace and invoke individual `/kbg:<command>` / `/kbg:<skill>` / agents **without** enabling `kbg` in `settings.json`.

No support SLA; best-effort, pre-`1.0.0`.
