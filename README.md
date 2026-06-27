# kbg — Claude Code Harness (Plugin)

[![Version](https://img.shields.io/badge/version-v0.1.0-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A **personal Claude Code harness** delivered as an installable plugin (`kbg@kobig`).
It adds 29 specialist agents, 28 workflow skills, 13 slash commands, and 50 governance
hooks across 14 lifecycle events — plus always-on doctrine injection. No symlink farm,
no manual wiring: components auto-discover from the plugin cache.

> **Operating model (v0.4.x):** CLAUDE.md §The operating model (current) supersedes the L2–L5 autonomy ladder. The harness **denies the irrecoverable set computationally** (scoped denials: `block-dangerous-git.sh` + `block-dangerous-bash.sh`) and **advises on the rest** (advisory reminders: `advisory-push-reminder`, `tmux-reminder`, `commit-quality-reminder`); the **operator is the authority at every irreversible boundary**. No autonomy flag, no enforced maker-checker ship-gate, no model self-start. The gauntlet (`run-gauntlet.sh`) remains as a general validation runner. (The L2–L5 ratchet that previously lived under `docs/adr/` is retired; the no-model-self-start rule in METHODOLOGY.md + CLAUDE.md §The operating model is what survives.)
> (v0.3.x: `kbg:learn` + `cost-capture` + read-only MCP inventory. See CHANGELOG.)

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
/ship-task             # show the full 9-step senior-engineer loop
/ideate How should we cache slow API responses?
/ideate-search caching
```

---

## What You Get

After enabling and restarting, Claude Code loads everything from the plugin cache
(`~/.claude/plugins/cache/kobig/kbg/<version>/`).

| Component | Count | How to Use |
|---|---|---|
| **Agents** | 32 | Spawn via `kbg:<agent>` (e.g. `kbg:code-architect`, `kbg:security-reviewer`) |
| **Skills** | 28 | Invoke via `kbg:<skill>` (e.g. `kbg:review-pr`, `kbg:ship-change`) or let them auto-fire |
| **Commands** | 13 | Invoke via `/<command>` or `kbg:<command>` (e.g. `/ship-task`, `/ideate`, `/frame`) |
| **Hooks** | 50 scripts | Run automatically on SessionStart, PreToolUse, PostToolUse, SessionEnd, etc. (38 tracked as sensors) |
| **Output Styles** | 2 | `senior-eng` (default live-response register), `staff-eng` (opt-in cross-boundary) |
| **Themes** | 1 | `catppuccin-mocha` |

### Spotlight Commands

| Command | What it does |
|---|---|
| `/ideate <problem>` | Parallel divergent ideation under 5 rotating cognitive frames |
| `/ideate-search <query>` | Search every past `/ideate` run stored in the local `qmd` index |
| `/ship-task` | Full 9-step senior-engineer loop: plan → implement → verify → ship (embeds acceptance gating) |
| `/review-pr` | Multi-agent review (code, tests, security, types) over the diff |
| `/fix-bug` | Non-trivial bug fixes with TDD and root-cause capture |
| `/deep-dive` | Research briefs and structural exploration |

### Spotlight Skills

| Skill | When to use |
|---|---|
| `/ideate` | Open-ended design, architecture, naming, fuzzy-debug |
| `kbg:review-pr` | Post-push PR review across multiple quality dimensions |
| `kbg:ship-change` | Land a scoped change with acceptance gating |
| `kbg:orchestrate` | Build a multi-agent plan with a hard fan-out cap |
| `kbg:decide` | Structured decision support: Judgment Ladder + probe/strategize/debate lenses |
| `kbg:incident` | Chaotic/time-pressed stabilization with embedded hotfix path |
| `kbg:recursive-improve` | Self-improvement loop — always stops at a human `AskUserQuestion` gate |
| `kbg:learn` | Capture durable session learnings → memory, gated by an `AskUserQuestion` approval |
| `kbg:harness-audit` | Run the harness self-audit on demand |

---

## Governance Hooks

50 hook scripts fire on 14 lifecycle events (66 registrations total; 38 tracked as sensors for staleness). They are split into four cells:

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

3. **Operating model (CLAUDE.md §The operating model (current), 2026-06-25).** CLAUDE.md §The operating model (current) supersedes the L2–L5
autonomy ladder. The harness
**denies the irrecoverable set computationally** — scoped denials
(`block-dangerous-git.sh` + `block-dangerous-bash.sh`) block dangerous git and
bash operations with no operator flag — and **advises on the rest**: advisory
reminders (`advisory-push-reminder`, `tmux-reminder`, `commit-quality-reminder`)
journal evidence and nudge, never emit a `permissionDecision`. The **operator is
the authority at every irreversible boundary**: no autonomy flag, no enforced
maker-checker ship-gate, no model self-start. `kbg:recursive-improve` keeps
`disable-model-invocation: true`. The gauntlet (`run-gauntlet.sh`) remains as a
general validation runner the operator invokes; it is not a ship-gate consumer.

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
├── skills/               # 28 workflow skills (one dir each: SKILL.md + optional references/, scripts/) + _lib/ helpers
├── commands/             # 13 user-facing slash commands (legacy surface per CC docs; kept for the verb layer)
├── hooks/                # Governance hooks across 14 lifecycle events, grouped by role:
│   ├── gates/            #   PreToolUse deny/ask gates           (computational feedforward)
│   ├── advisory/         #   journal-only sensors                (inferential feedback — never block)
│   ├── lifecycle/        #   TaskCompleted / Stop enforcement
│   ├── session/          #   SessionStart doctrine injection + capture
│   ├── post-tool/        #   PostToolUse audits
│   ├── maintenance/      #   periodic upkeep
│   └── hooks.json        #   registry (which script fires on which event)
├── output-styles/        # Live-response registers (senior-eng default, staff-eng opt-in)
├── contexts/             # Working-frames loaded by /frame (dev / review / research)
├── themes/               # Terminal themes
├── scripts/              # Orchestration + health + eval-support scripts (no LLM dispatch — see the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model)
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

**Relative to ECC's layout:** the core skeleton (`.claude-plugin/ agents/ skills/ commands/ hooks/ scripts/ tests/`) is the shared Claude Code plugin convention. kbg's differences are deliberate: doctrine is **always-injected** (`METHODOLOGY/RTK/ACLI/DBGATE`) rather than a `rules/` dir copied into `~/.claude/`; there is **no `mcp-configs/`** ([non-goal](CLAUDE.md): no bundled MCP/LSP servers); and `hooks/` + `docs/` are **grouped by role** rather than flat. The one ECC pattern recently adopted is `examples/` (project-type `*-CLAUDE.md` starters, [v0.3.2](CHANGELOG.md)). See the plugin-delivery model section in CLAUDE.md for the single-delivery-path model and CLAUDE.md §The operating model (current) for the operating model (scoped denials + advisory review + operator-as-authority).

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
- [`docs/reference/env-vars.md`](docs/reference/env-vars.md) — every operator-tunable env var (default + effect + reader)
- [`CHANGELOG.md`](CHANGELOG.md) — Release notes
- `CLAUDE.md` — Architecture decision records (start with the **plugin delivery model** section and `§The operating model`; the L2–L5 autonomy ladder that previously lived under `docs/adr/` is retired)

---

## Upstream Attribution

kbg-harness aggregates components from the following upstream projects. All are used under their respective licenses.

| Source | License | Components adopted |
|---|---|---|
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | 19 skills — `ask-matt`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`, `grill-me`, `grill-with-docs`, `grilling`, `handoff`, `implement`, `improve-codebase-architecture`, `prototype`, `resolving-merge-conflicts`, `setup-matt-pocock-skills`, `tdd`, `teach`, `to-issues`, `to-prd`, `triage`, `writing-great-skills` (copied 2026-06-28 @ v1.0.1) |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | 37 skills — `agent-sort`, `api-design`, `architecture-decision-records`, `backend-patterns`, `bun-runtime`, `coding-standards`, `dart-flutter-patterns`, `database-migrations`, `deployment-patterns`, `docker-patterns`, `documentation-lookup`, `e2e-testing`, `error-handling`, `fastapi-patterns`, `flutter-dart-code-review`, `gateguard`, `github-ops`, `git-workflow`, `hexagonal-architecture`, `knowledge-ops`, `mysql-patterns`, `postgres-patterns`, `production-audit`, `python-patterns`, `python-testing`, `react-patterns`, `react-performance`, `react-testing`, `redis-patterns`, `rust-patterns`, `rust-testing`, `safety-guard`, `search-first`, `security-review`, `strategic-compact`, `terminal-ops`, `verification-loop` (copied 2026-06-28 @ 2bc924fa; +14 added 2026-06-28); 28 agents — `a11y-architect`, `architect`, `build-error-resolver`, `code-architect`, `code-explorer`, `code-reviewer`, `comment-analyzer`, `dart-build-resolver`, `database-reviewer`, `docs-lookup`, `e2e-runner`, `fastapi-reviewer`, `flutter-reviewer`, `mle-reviewer`, `performance-optimizer`, `planner`, `pr-test-analyzer`, `python-reviewer`, `react-build-resolver`, `react-reviewer`, `refactor-cleaner`, `rust-build-resolver`, `rust-reviewer`, `security-reviewer`, `silent-failure-hunter`, `tdd-guide`, `type-design-analyzer`, `typescript-reviewer` (copied 2026-06-28 @ 2bc924fa); 33 commands — `aside`, `build-fix`, `checkpoint`, `code-review`, `fastapi-review`, `feature-dev`, `flutter-build`, `flutter-review`, `flutter-test`, `jira`, `learn`, `learn-eval`, `plan`, `plan-prd`, `pr`, `prp-commit`, `prp-implement`, `prp-plan`, `prp-pr`, `prp-prd`, `python-review`, `react-build`, `react-review`, `react-test`, `refactor-clean`, `resume-session`, `review-pr`, `rust-build`, `rust-review`, `rust-test`, `save-session`, `test-coverage`, `update-docs` (copied 2026-06-28 @ 2bc924fa; skipped: `harness-audit` ECC-specific Node.js dep, `cost-report` ECC hook dep, `security-scan` ecc-agentshield dep, `quality-gate` ECC Node.js hook dep); 3 contexts — `dev`, `research`, `review` (copied 2026-06-28 @ 2bc924fa) |

---

## License

MIT — see [`LICENSE`](LICENSE).
