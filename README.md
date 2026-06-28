# kbg — Claude Code Harness

[![Version](https://img.shields.io/badge/version-v0.2.0-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) harness packaged as an installable plugin (`kbg@kobig`). Drop it in and you get 49 specialist agents, 113 workflow skills, and 68 slash commands — plus two output-style registers and a terminal theme. No symlink farm, no manual wiring; components auto-discover from the plugin cache.

Built on the **composer-not-creator** principle: the best upstream harness tools ([ECC](https://github.com/affaan-m/everything-claude-code), [mattpocock/skills](https://github.com/mattpocock/skills)) bundled into one plugin, extended only where the Tathep platform stack demands it.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What You Get](#what-you-get)
- [Spotlight](#spotlight)
- [Repository Layout](#repository-layout)
- [Development](#development)
- [Documentation](#documentation)
- [Attribution](#attribution)
- [License](#license)

---

## Quick Start

Run these commands inside Claude Code:

```text
# 1. Register the marketplace source (once per machine)
/plugin marketplace add wasikarn/kbg-harness

# 2. Install
/plugin install kbg@kobig

# 3. Enable — add to your Claude Code settings.json:
#    "kbg@kobig": true

# 4. Restart Claude Code (plugin cache loads on startup)

# 5. Smoke-test
kbg:thinking
```

> **Note:** The plugin ships with `defaultEnabled: false`. Step 3 is required.

**Uninstall:** `/plugin uninstall kbg`  
**Disable (keep installed):** set `"kbg@kobig": false` in `settings.json`

After changing any surface: bump both manifest versions → `claude plugin validate --strict .` → commit → push → `claude plugin update kbg@kobig` → restart.

---

## What You Get

| Component | Count | How to invoke |
|---|---|---|
| **Skills** | 113 | `kbg:<skill>` — e.g. `kbg:thinking`, `kbg:decide`, `kbg:grilling` |
| **Agents** | 49 | Spawned by Claude or via the `Task` tool — e.g. `kbg:code-architect` |
| **Commands** | 68 | `/<command>` — e.g. `/review-pr`, `/plan`, `/feature-dev` |
| **Output Styles** | 2 | `senior-eng` (default) · `staff-eng` (opt-in for cross-boundary decisions) |
| **Contexts** | 3 | `dev` · `review` · `research` — loaded by `/frame` to set session posture |
| **Themes** | 1 | `catppuccin-mocha` |

> Governance hooks are pending rebuild; `hooks/` is intentionally empty in v0.1.0.

---

## Spotlight

### Commands

| Command | What it does |
|---|---|
| `/review-pr` | Multi-dimension PR review — code, tests, security, and types over the diff |
| `/code-review` | Deep review for the current file or selection |
| `/plan` | Structured implementation plan |
| `/feature-dev` | Full feature loop: plan → implement → verify |
| `/pr` | GitHub PR with auto-generated title and body |
| `/security-scan` | Vulnerability scan via the `security-auditor` agent |
| `/learn` | Capture durable session learnings into memory |
| `/checkpoint` | Snapshot session state for resume |

### Skills

| Skill | When to reach for it |
|---|---|
| `kbg:thinking` | Index of 39 mental models — pick 1–3 for any complex or ambiguous problem |
| `kbg:decide` | Judgment Ladder: `probe` / `decide` / `strategize` modes |
| `kbg:grilling` | Relentless interview to stress-test a plan; `with-docs` also produces ADRs |
| `kbg:gateguard` | Fact-forcing gate — demands concrete investigation before any write or edit |
| `kbg:agent-architecture-audit` | 12-layer diagnostic for wrapper regression, memory pollution, repair loops |
| `kbg:eval-harness` | Formal EDD framework with pass@k metrics for LLM system evaluation |
| `kbg:context-budget` | Token usage audit — finds bloat and produces prioritized savings |
| `kbg:security-review` | OWASP Top 10, secrets scanning, and auth review |
| `kbg:production-audit` | Local-evidence production readiness check — no external service required |
| `kbg:architecture-decision-records` | Capture decisions as structured ADRs during a session |

### Agents

Agents run in a delegated sub-task context — Claude spawns them automatically or you can request one explicitly via the `Task` tool.

| Agent | Role |
|---|---|
| `code-architect` | System design, module boundaries, and dependency decisions |
| `security-reviewer` | OWASP Top 10, secrets detection, auth flows, and injection risks |
| `planner` | Implementation blueprints — breaks a goal into ordered, concrete steps |
| `code-reviewer` | Quality, correctness, patterns, and missing edge cases |
| `performance-optimizer` | Bottleneck analysis, profiling strategy, and optimization trade-offs |
| `tdd-guide` | Enforces red → green → refactor; writes the failing test first |
| `refactor-cleaner` | Dead code removal, simplification, and naming cleanup |
| `silent-failure-hunter` | Finds errors swallowed by catch-all handlers or missing error returns |
| `spec-miner` | Extracts implicit requirements from code when no spec doc exists |
| `type-design-analyzer` | Evaluates TypeScript type modelling — narrows `any`, improves generics |

### Tathep Platform

kbg-native skills for the Tathep project stack — created because no upstream fit existed.

| Skill | When to reach for it |
|---|---|
| `kbg:adonisjs-patterns` | AdonisJS v5 routes, Lucid ORM, Japa tests, VineJS validation, and Edge templates |
| `kbg:drizzle-patterns` | Drizzle ORM schema, migrations, relations, and query patterns for PostgreSQL / MySQL / SQLite |
| `kbg:effect-ts-patterns` | Effect-TS layers, services, typed error channels, and functional pipelines |
| `kbg:grpc-node-patterns` | gRPC client/server with `@grpc/grpc-js`, TypeScript codegen, streaming, and error codes |
| `kbg:hono-patterns` | Hono routes, middleware, validation, and deployment for Bun / Node.js / edge runtimes |
| `kbg:langchain-langgraph-patterns` | LangChain chains, agents, RAG pipelines, and LangGraph stateful multi-step workflows |
| `kbg:tauri-v2-patterns` | Tauri v2 IPC commands, capabilities / permissions model, Rust app state, events, and plugins |

---

## Repository Layout

```text
kbg-harness/
├── .claude-plugin/       # plugin.json + marketplace.json (both must be bumped on each release)
├── agents/               # 49 specialist subagents (.md each)
├── skills/               # 113 workflow skills (SKILL.md per directory)
├── commands/             # 68 slash commands
├── hooks/                # Empty — governance hooks pending rebuild
├── output-styles/        # senior-eng (default), staff-eng (opt-in)
├── contexts/             # dev / review / research session frames
├── themes/               # catppuccin-mocha.json
├── scripts/              # Validation helpers (run-gauntlet.sh stub)
├── docs/
│   ├── onboarding.md     # 10-minute cold-start
│   └── reference/        # thinking-skills library, reasoning-models.md, env-vars.md
├── git-hooks/            # pre-commit (lint + JSON + syntax) · pre-push (gauntlet)
├── CLAUDE.md             # Project instructions for Claude Code instances
└── CHANGELOG.md          # Release notes
```

---

## Development

### Validation

```bash
# Only live validation gate
claude plugin validate --strict .

# Full gauntlet (stub in v0.1.0)
bash scripts/run-gauntlet.sh
```

### Git Hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

| Hook | What it runs |
|---|---|
| `pre-commit` | `bash -n` + shellcheck, JSON validation, harness-audit |
| `pre-push` | Full gauntlet |

### Adding a Component

1. Create the file following the pattern of an existing component in the same directory.  
   - **Skill** → `skills/<name>/SKILL.md` with `name` + `description` (≤ 25 words) frontmatter  
   - **Agent** → `agents/<name>.md` with `name`, `description` (≤ 25 words), `tools` frontmatter  
   - **Command** → `commands/<name>.md` with frontmatter  
2. Bump `version` in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
3. `claude plugin validate --strict .`
4. Commit and push.
5. `claude plugin update kbg@kobig` → restart Claude Code.

---

## Documentation

| File | What's in it |
|---|---|
| [`docs/onboarding.md`](docs/onboarding.md) | 10-minute cold-start guide |
| [`docs/reference/reasoning-models.md`](docs/reference/reasoning-models.md) | 39 vendored mental models (cc-thinking-skills) |
| [`docs/reference/env-vars.md`](docs/reference/env-vars.md) | Operator-tunable environment variables |
| [`CLAUDE.md`](CLAUDE.md) | Architecture and non-obvious gotchas for Claude Code instances |
| [`CHANGELOG.md`](CHANGELOG.md) | Release notes |

---

## Attribution

kbg-harness aggregates components from these upstream projects under their respective licenses.

| Source | License | Adopted |
|---|---|---|
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | 17 skills |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | 85 skills · 48 agents · 64 commands · 3 contexts |
| [TJBoudreaux/cc-thinking-skills](https://github.com/TJBoudreaux/cc-thinking-skills) | MIT | 39 mental models vendored into `kbg:thinking` |
| kbg-native | MIT | 9 skills · 1 agent · 4 commands · 2 output styles · 1 theme |

Component names follow the `origin:` frontmatter field in each surface file. To browse what's available: `ls skills/`, `ls agents/`, `ls commands/`.

---

## License

MIT — see [`LICENSE`](LICENSE).
