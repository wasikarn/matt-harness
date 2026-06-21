# kbg — Claude Code Harness (Plugin)

[![Version](https://img.shields.io/badge/version-0.3.4-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A **personal Claude Code harness** delivered as an installable plugin (`kbg@kobig`).
It adds 29 specialist agents, 40 workflow skills, 22 slash commands, and 46 governance
hooks across 14 lifecycle events — plus always-on doctrine injection. No symlink farm,
no manual wiring: components auto-discover from the plugin cache.

> **Newest additions (v0.3.4):** observability + learning — three ECC concept-gaps closed within kbg's invariants: `kbg:learn` (human-gated session-pattern capture → memory), a `cost-capture` SessionEnd hook + `kbg:harness-health --cost` (honest token telemetry — the measurement half of METHODOLOGY Rule 6), and a read-only MCP inventory (`auth-health-check.py --mcp`).
> (v0.3.2-0.3.3: ECC structure comparison → 2 clarity renames + `examples/` starters + a hook-count reconciliation. v0.3.0: **L3 bounded autonomy** — [ADR 0003](docs/adr/0003-l3-bounded-autonomy.md) supersedes ADR 0002's L2-only architecture; opt-in `KBG_AUTONOMY_L3`, default OFF == L2. See CHANGELOG.)

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
- [Repository Structure](#repository-structure)
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
| **Skills** | 40 | Invoke via `kbg:<skill>` (e.g. `kbg:review-pr`, `kbg:ship-change`) or let them auto-fire |
| **Commands** | 22 | Invoke via `/kbg:<command>` or `/ideate`, `/ideate-search` (user-only slash triggers) |
| **Hooks** | 46 scripts | Run automatically on SessionStart, PreToolUse, PostToolUse, SessionEnd, etc. (36 tracked as sensors) |
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
| `kbg:learn` | Capture durable session learnings → memory, gated by an `AskUserQuestion` approval |
| `kbg:harness-audit` | Run the harness self-audit on demand |

---

## Governance Hooks

46 hook scripts fire on 14 lifecycle events (61 registrations total; 36 tracked as sensors for staleness). They are split into four cells:

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

3. **Autonomy invariant (ADR 0002 → ADR 0003).** **Default (L2):** no autonomous or
unattended self-repair loops; every improvement iteration stops at a human approval gate.
**L3 (opt-in, `KBG_AUTONOMY_L3=1`, default OFF):** a bounded loop runs unattended within an
owner-approved run, commits local-only, and is gated at *push* not per mutation
([ADR 0003](docs/adr/0003-l3-bounded-autonomy.md)). Either way `kbg:recursive-improve` keeps
`disable-model-invocation: true` so the model cannot self-start it, and L4 stays rejected.

4. **Single branch model.** The repo uses `develop` only. No feature branches.

5. **Cache-invalidation is manual.** After any plugin surface change, bump both
`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, then run
`claude plugin update kbg@kobig` and restart Claude Code.

6. **Restart is required.** Commands, skills, and hooks are loaded into the plugin cache
at startup. A missing `/ideate-search` almost always means the restart step was skipped.

---

## Repository Structure

Directory-level layout. The auto-generated `BOUNDARY.md` is the **file-level** capability map (kept current by `inventory-boundary.sh`), so this stays high-level and stable.

```text
kbg-harness/
├── .claude-plugin/       # Plugin + marketplace manifests (plugin.json, marketplace.json)
├── agents/               # 29 senior-specialist subagents (one .md each, flat)
├── skills/               # 40 workflow skills (one dir each: SKILL.md + optional references/, scripts/) + _lib/ helpers
├── commands/             # 22 user-facing slash commands (legacy surface per CC docs; kept for the verb layer)
├── hooks/                # Governance hooks across 14 lifecycle events, grouped by role:
│   ├── gates/            #   PreToolUse deny/ask gates           (computational feedforward)
│   ├── advisory/         #   journal-only sensors                (inferential feedback — never block)
│   ├── lifecycle/        #   TaskCompleted / Stop enforcement
│   ├── session/          #   SessionStart doctrine injection + capture
│   ├── post-tool/        #   PostToolUse audits
│   ├── maintenance/      #   periodic upkeep
│   └── hooks.json        #   registry (which script fires on which event)
├── output-styles/        # Live-response registers (senior-eng default, staff-eng opt-in)
├── contexts/             # Working-frames loaded by /context (dev / review / research)
├── themes/               # Terminal themes
├── scripts/              # Orchestration + health + eval-support scripts (no LLM dispatch — see ADR 0002)
├── eval/                 # Eval harness: datasets/ + regressions/ + run-eval.py (the "build" gate)
├── tests/                # Critical-hooks suite + skill/_lib tests
├── git-hooks/            # pre-commit (fast) + pre-push (full parallel gauntlet)
├── docs/                 # Governance docs, grouped: adr/ reference/ research/ agents/ skill-template/
├── examples/             # Project-type CLAUDE.md starters (reference only — not auto-loaded)
├── METHODOLOGY.md RTK.md ACLI.md DBGATE.md   # L1 doctrine — always injected every session (no manual copy)
├── CLAUDE.md             # Project instructions (architecture requiring multi-file reading)
├── BOUNDARY.md           # Auto-generated capability map (regenerate after surface changes)
└── README.md             # This file
```

**Relative to ECC's layout:** the core skeleton (`.claude-plugin/ agents/ skills/ commands/ hooks/ scripts/ tests/`) is the shared Claude Code plugin convention. kbg's differences are deliberate: doctrine is **always-injected** (`METHODOLOGY/RTK/ACLI/DBGATE`) rather than a `rules/` dir copied into `~/.claude/`; there is **no `mcp-configs/`** ([non-goal](CLAUDE.md): no bundled MCP/LSP servers); and `hooks/` + `docs/` are **grouped by role** rather than flat. The one ECC pattern recently adopted is `examples/` (project-type `*-CLAUDE.md` starters, [v0.3.2](CHANGELOG.md)). See [ADR 0001](docs/adr/0001-personal-harness-as-plugin.md) for the single-delivery-path model and [ADR 0002](docs/adr/0002-autonomy-invariant.md) / [ADR 0003](docs/adr/0003-l3-bounded-autonomy.md) for the autonomy stance (L2 default, opt-in L3 bounded loop, no self-launching cron/`/loop` primitives).

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
- [`docs/adr/`](docs/adr/) — Architecture decision records (start with ADR 0001 and ADR 0002; ADR 0003 supersedes 0002's architecture for L3)

---

## License

MIT — see [`LICENSE`](LICENSE).
