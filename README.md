# kbg — Claude Code Harness (Plugin)

[![Version](https://img.shields.io/badge/version-0.2.86-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A **personal Claude Code harness** delivered as an installable plugin (`kbg@kobig`).
It adds 29 specialist agents, 38 workflow skills, 21 slash commands, and 44 governance
hooks across 14 lifecycle events — plus always-on doctrine injection. No symlink farm,
no manual wiring: components auto-discover from the plugin cache.

> **Newest additions (v0.2.86):** foreign-CWD portability sweep completed; all plugin-delivered internal
> doc recipes now resolve via `${KBG_PLUGIN_ROOT}`, stale cross-references fixed, and remaining
> relative self-check paths in `docs/common-mistakes.md` were converted.

> **First time here?** Read [`docs/onboarding.md`](docs/onboarding.md) for a 10-minute
cold-start, then [`METHODOLOGY.md`](METHODOLOGY.md) for the behavioral doctrine.

---

## Table of Contents

- [Quick Start](#quick-start)
- [First Steps After Installing](#first-steps-after-installing)
- [What You Get](#what-you-get)
- [Daily Commands](#daily-commands)
- [Governance Hooks](#governance-hooks)
- [Optional Integrations](#optional-integrations)
- [Important Caveats](#important-caveats)
- [Development](#development)
- [Documentation](#documentation)
- [License](#license)

---

## Quick Start

Inside Claude Code:

```text
# 1. Add the marketplace (only needed once)
/plugin marketplace add wasikarn/kbg-harness

# 2. Install the plugin
/plugin install kbg@kobig

# 3. Enable it (the plugin ships with defaultEnabled: false)
#    Open your Claude Code settings.json and add:
#    "kbg@kobig": true

# 4. Restart Claude Code
#    The plugin cache is only reloaded on startup.

# 5. Verify
/kbg-help
```

**Uninstall:** `/plugin uninstall kbg`  
**Disable (keep installed):** set `"kbg@kobig": false` in your Claude Code `settings.json`

If a command is missing after install, the most common cause is forgetting step 4.
Run `claude plugin update kbg@kobig` and restart.

---

## First Steps After Installing

After restart, every new session automatically loads four doctrine files as
additional context:

1. [`METHODOLOGY.md`](METHODOLOGY.md) — 13 behavioral rules
2. [`RTK.md`](RTK.md) — runtime keyboard / CLI conventions
3. [`ACLI.md`](ACLI.md) — agent command-line interface patterns
4. [`DBGATE.md`](DBGATE.md) — database access rules

These are mandatory context; there is no opt-out. If you only want individual
commands without doctrine injection, invoke `/kbg:<command>` without enabling the
plugin in `settings.json`.

Try these one-liners to confirm everything loads:

```text
/kbg-help              # quick-reference card of all commands
/kbg:pre-ship-verify   # show the pre-ship acceptance gate
/ideate How should we cache slow API responses?
/ideate-search caching
```

---

## What You Get

After enabling and restarting, Claude Code loads everything from the plugin cache
(`~/.claude/plugins/cache/kobig/kbg/<version>/`).

| Component | Count | How to Use |
|---|---|---|
| **Agents** | 29 | Spawn via `kbg:<agent>` (e.g. `kbg:code-architect`, `kbg:security-reviewer`) |
| **Skills** | 38 | Invoke via `kbg:<skill>` (e.g. `kbg:review-pr`, `kbg:ship-change`) or let them auto-fire |
| **Commands** | 21 | Invoke via `/kbg:<command>` or `/ideate`, `/ideate-search` (user-only slash triggers) |
| **Hooks** | 44 scripts | Run automatically on SessionStart, PreToolUse, PostToolUse, SessionEnd, etc. |
| **Output Styles** | 2 | `senior-eng` (default live-response register), `staff-eng` (opt-in cross-boundary) |
| **Themes** | 1 | `catppuccin-mocha` |

### Spotlight Commands

| Command | What it does |
|---|---|
| `/ideate <problem>` | Parallel divergent ideation under 5 rotating cognitive frames |
| `/ideate-search <query>` | Search every past `/ideate` run stored in the local `qmd` index |
| `/kbg:pre-ship-verify` | Run `ACCEPTANCE.md` + eval-harness gate before a PR |
| `/kbg:review-pr` | Multi-agent review (code, tests, security, types) over the diff |
| `/kbg:ship-task` | Full 9-step senior-engineer loop: plan → implement → verify → ship |
| `/kbg:fix-bug` | Non-trivial bug fixes with TDD and root-cause capture |
| `/kbg:feature-dev` | New feature development with types-first contract |
| `/kbg:team-plan` / `/kbg:team-build` | Agent-team planning + execution (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) |
| `/kbg:wave-status` / `/kbg:team-cleanup` | Inspect and tear down persistent teammates |

### Spotlight Skills

| Skill | When to use |
|---|---|
| `kbg:ideate` | Open-ended design, architecture, naming, fuzzy-debug |
| `kbg:review-pr` | Post-push PR review across multiple quality dimensions |
| `kbg:ship-change` | Land a scoped change with acceptance gating |
| `kbg:orchestrate` | Build a multi-agent plan with a hard fan-out cap |
| `kbg:types-first` | Define contracts before parallel implementation |
| `kbg:recursive-improve` | Self-improvement loop — always stops at a human `AskUserQuestion` gate |
| `kbg:harness-audit` | Run the harness self-audit on demand |

---

## Governance Hooks

44 hook scripts fire on 14 lifecycle events. They are split into four cells:

| | Feedforward (before the act) | Feedback (after the act) |
|---|---|---|
| **Computational** | Block dangerous git ops, secret reads, DB writes, alias shadowing, doctrine edits via Bash | Audit every edit, run post-edit tests, diff security review |
| **Inferential** | Inject doctrine, surface iron-rule reminders, skill nudges | Journal verification verdicts, fabrication verdicts, structural-judge advisories |

Key properties:

- **Advisory only.** Inferential sensors never emit `permissionDecision`; they journal
evidence and let the human decide.
- **Always-on doctrine.** `hooks/session/doctrine-bootstrap.sh` injects `METHODOLOGY.md`,
`RTK.md`, `ACLI.md`, and `DBGATE.md` on every SessionStart sub-event.
- **Append-only journal.** Governance events are written to `~/.claude/governance-events.jsonl`.

See [`hooks/JOURNAL-SCHEMA.md`](hooks/JOURNAL-SCHEMA.md) for the event format.

---

## Optional Integrations

The core runs with only `python3`, `git`, and `bash`. These unlock extra features:

| Tool | Unlocks |
|---|---|
| `qmd` | `/ideate-search`, local markdown reindex, journal queries |
| `ollama` + `all-minilm:latest` | Convergence detector for `/ideate` (warns when you ideate the same problem repeatedly) |
| `rtk` | Token-optimized Bash proxy |
| `code-review-graph` | Review-context graph status + incremental updates |
| `SUPERSET_HOME_DIR` | Agent-activity notifications |

`qmd` and `ollama` are particularly important for the ideate features:

```bash
# qmd is needed for /ideate-search
qmd collection show ideate-memory

# ollama is needed for the convergence detector
ollama list | grep all-minilm
ollama pull all-minilm:latest
```

All integrations degrade gracefully when absent — the plugin never hard-fails because
an optional tool is missing.

---

## Important Caveats

1. **Personal harness, not a product.** `kbg` encodes one operator's workflow choices.
There is no support SLA; versions are pre-`1.0.0`.

2. **Doctrine injection is mandatory.** Enabling `kbg` makes `METHODOLOGY`, `RTK`,
`ACLI`, and `DBGATE` context in every session, plus the `senior-eng` output style.
There is no opt-out flag.

3. **Autonomy invariant (ADR 0002).** No autonomous or unattended self-repair loops.
`kbg:recursive-improve` carries `disable-model-invocation: true` so the model cannot
self-start it; every improvement iteration stops at a human approval gate.

4. **Single branch model.** The repo uses `develop` only. No feature branches.

5. **Cache-invalidation is manual.** After any plugin surface change, bump both
`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then run
`claude plugin update kbg@kobig` and restart Claude Code.

6. **Restart is required.** Commands, skills, and hooks are loaded into the plugin cache
at startup. A missing `/ideate-search` almost always means the restart step was skipped.

---

## Development

### Validation (run before any commit touching hooks, skills, agents, commands, or manifests)

```bash
# Plugin manifest strict validation (works from any project CWD when KBG_PLUGIN_ROOT is exported)
claude plugin validate --strict "${KBG_PLUGIN_ROOT}"

# Critical-hooks smoke tests
bash "${KBG_PLUGIN_ROOT}/tests/hooks/runners/test-critical-hooks.sh"

# Harness self-audit (must be 0 Critical / 0 Warnings)
bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" "${KBG_PLUGIN_ROOT}"

# Eval harness (dataset + regression fixtures)
python3 "${KBG_PLUGIN_ROOT}/eval/run-eval.py" --dataset "${KBG_PLUGIN_ROOT}/eval/datasets/" --regression --gate

# Or run the full parallel gauntlet
bash "${KBG_PLUGIN_ROOT}/scripts/run-gauntlet.sh"
```

### Adding Components

1. **Agent** — create `agents/<name>.md` with frontmatter (`name`, `description`, `tools` allowlist). Auto-discovered.
2. **Skill** — create `skills/<name>/SKILL.md` with frontmatter. Add Input/Output/Failure sections only where there is a real contract. Auto-discovered.
3. **Command** — create `commands/<name>.md` with frontmatter. Update manifest counts only when adding/removing a component.
4. **Hook** — create `hooks/<name>.sh`, register in `hooks/hooks.json`, and add tests if it is a gate.

After any addition: bump both manifest versions → validate → commit → push →
`claude plugin update kbg@kobig` → restart.

### Regenerate the Capability Map

```bash
bash "${KBG_PLUGIN_ROOT}/skills/inventory/scripts/inventory-boundary.sh" --repo-only > "${KBG_PLUGIN_ROOT}/BOUNDARY.md"
```

---

## Documentation

When the plugin is installed, internal docs live in the plugin cache and must be read via Bash with `KBG_PLUGIN_ROOT` (see [`docs/reference/reasoning-models.md`](docs/reference/reasoning-models.md) for examples). Relative markdown links below resolve only from the repo root.

- [`docs/onboarding.md`](docs/onboarding.md) — 10-minute cold-start
- [`METHODOLOGY.md`](METHODOLOGY.md) — 13-rule behavioral doctrine
- [`DOMAINS.md`](DOMAINS.md) — Bounded-context dispatch table and cross-context orchestration rules
- [`CLAUDE.md`](CLAUDE.md) — Guidance for Claude Code instances working in this repo
- [`BOUNDARY.md`](BOUNDARY.md) — Auto-regenerated cross-context inventory
- [`docs/reference/reasoning-models.md`](docs/reference/reasoning-models.md) — 39 vendored mental models (cc-thinking-skills) and where kbg already applies them
- [`CHANGELOG.md`](CHANGELOG.md) — Release notes
- [`docs/adr/`](docs/adr/) — Architecture decision records (start with ADR 0001 and ADR 0002)

---

## License

MIT — see [`LICENSE`](LICENSE).
