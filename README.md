# kbg — Claude Code Harness

[![Version](https://img.shields.io/badge/version-v0.58.7-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) harness packaged as an installable plugin (`kbg@kobig`). Drop it in and you get 17 specialist agents, 33 bundled workflow skills, and 17 slash commands, plus a set of matt-pocock skills installed separately via `gh skill` (see Quick Start), an output-style register, and a terminal theme. No symlink farm, no manual wiring: components auto-discover from the plugin cache.

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

# 4. Required — install matt-pocock's skills via GitHub CLI (kbg's hooks,
#    commands, and remaining skills route to these by bare name; they are
#    not bundled in the plugin). Requires `gh` v2.95+.
gh skill install mattpocock/skills engineering/prototype --agent claude-code --scope user
gh skill install mattpocock/skills engineering/resolving-merge-conflicts --agent claude-code --scope user
gh skill install mattpocock/skills engineering/ask-matt --agent claude-code --scope user
gh skill install mattpocock/skills engineering/code-review --agent claude-code --scope user
gh skill install mattpocock/skills engineering/codebase-design --agent claude-code --scope user
gh skill install mattpocock/skills engineering/diagnosing-bugs --agent claude-code --scope user
gh skill install mattpocock/skills engineering/domain-modeling --agent claude-code --scope user
gh skill install mattpocock/skills productivity/grilling --agent claude-code --scope user
gh skill install mattpocock/skills engineering/grill-with-docs --agent claude-code --scope user
gh skill install mattpocock/skills productivity/handoff --agent claude-code --scope user
gh skill install mattpocock/skills engineering/improve-codebase-architecture --agent claude-code --scope user
gh skill install mattpocock/skills engineering/research --agent claude-code --scope user
gh skill install mattpocock/skills engineering/setup-matt-pocock-skills --agent claude-code --scope user
gh skill install mattpocock/skills engineering/tdd --agent claude-code --scope user
gh skill install mattpocock/skills productivity/teach --agent claude-code --scope user
gh skill install mattpocock/skills engineering/to-spec --agent claude-code --scope user
gh skill install mattpocock/skills engineering/to-tickets --agent claude-code --scope user
gh skill install mattpocock/skills engineering/triage --agent claude-code --scope user
gh skill install mattpocock/skills engineering/wayfinder --agent claude-code --scope user
gh skill install mattpocock/skills productivity/writing-great-skills --agent claude-code --scope user

# 5. Restart Claude Code (plugin cache + global skills load on startup)

# 6. Smoke-test
kbg:kbg-help
```

> **Note:** The plugin ships with `defaultEnabled: false`. Step 3 is required.
>
> **Note:** Step 4 is required, not optional. 17 of kbg's own skills and several
> hooks/commands were migrated off vendored forks onto these `gh skill`-installed,
> unnamespaced skills (v0.46.0). A fresh clone/install is not self-contained
> without them. Re-sync later with `gh skill update <name>`.

**Uninstall:** `/plugin uninstall kbg`  
**Disable (keep installed):** set `"kbg@kobig": false` in `settings.json`

After changing any surface: bump both manifest versions → `claude plugin validate --strict .` → commit → push → `claude plugin update kbg@kobig` → restart.

---

## What You Get

| Component | Count | How to invoke |
|---|---|---|
| **Skills** | 33 | `kbg:<skill>` — e.g. `kbg:pr`, `kbg:orchestrate` (some matt-origin skills now install via `gh skill`, unnamespaced — e.g. `grilling`) |
| **Agents** | 17 | Spawned by Claude or via the `Task` tool — e.g. `code-architect` |
| **Commands** | 17 | `/<command>` — e.g. `/ship`, `/address-review`, `/fix-bug` |
| **Output Styles** | 1 | `staff-eng` — sole live-response register, self-calibrates terse vs full framing by stakes |
| **Contexts** | 3 | `dev` · `review` · `research` — loaded by `/frame` to set session posture |
| **Themes** | 1 | `catppuccin-mocha` |

> Hooks: SessionStart doctrine injection (METHODOLOGY.md), PreToolUse gates in `hooks/gates/`, advisory sensors in `hooks/advisory/`, and cost tracking in `hooks/stop/`. The operating model: gates deny the irrecoverable set; sensors journal but never gate.

---

## Spotlight

### Commands

| Command | What it does |
|---|---|
| `/ship` | Land a code change end-to-end: classify, implement, test, review, fix-loop, merge |
| `/fix-bug` | Guided 7-phase bug-fix with diagnostic + test-first patterns |
| `/security-scan` | AgentShield scan of harness surfaces via the `security-reviewer` agent |
| `/ship-merge` · `/ship-release` | Pre-merge gate · end-to-end release ceremony |

### Skills

| Skill | When to reach for it |
|---|---|
| `kbg:pr` | Create a GitHub PR — templated body, previewed for confirmation before creation |
| `kbg:decide` | Judgment Ladder: `clarify` / `probe` / `decide` / `strategize` / `critique` modes |
| `kbg:score-decision` | Weighted numeric verdict for a decision — pass/fail + confidence + trace |
| `grilling` | Relentless interview to stress-test a plan before building |
| `kbg:orchestrate` | Triage competing tasks → route each to inline / parallel / sequential / drop |
| `kbg:agent-architecture-audit` | 12-layer diagnostic for wrapper regression, memory pollution, repair loops |
| `kbg:context-budget` | Token usage audit — finds bloat and produces prioritized savings |
| `kbg:security-auditor` | OWASP Top 10, secrets scanning, threat-model + remediation |
| `kbg:production-audit` | Local-evidence production readiness check — no external service required |
| `kbg:harness-audit` | Deterministic fleet/schema/structural audit of this plugin |

### Agents

Agents run in a delegated sub-task context. Claude spawns them automatically, or you can request one explicitly via the `Task` tool.

| Agent | Role |
|---|---|
| `code-architect` | System design, module boundaries, and dependency decisions |
| `backend-architect` | API contracts, service boundaries, data ownership, caching, reliability — the systems-design layer above framework-narrow `*-patterns` skills |
| `security-reviewer` | OWASP Top 10, secrets detection, auth flows, and injection risks |
| `code-reviewer` | Quality, correctness, patterns, and missing edge cases |
| `performance-optimizer` | Bottleneck analysis, profiling strategy, and optimization trade-offs |
| `refactor-cleaner` | Dead code removal, simplification, and naming cleanup |
| `silent-failure-hunter` | Finds errors swallowed by catch-all handlers or missing error returns |
| `spec-miner` | Extracts implicit requirements from code when no spec doc exists |
| `requirement-analyst` | Senior-level requirement analysis of a ticket/spec/PRD — ambiguities, missing ACs, edge cases, readiness verdict |
| `typescript-reviewer` · `python-reviewer` · `flutter-reviewer` · `nextjs-reviewer` | Language/framework-specific review — type safety, idioms, async correctness, Dart/Flutter widgets, Next.js App Router rendering/caching |
| `build-error-resolver` | Fixes build/type errors with minimal diffs |
| `summarizer` | Clarity/compression specialist — condenses long content into filler-free prose for any audience |
| `ideate-critic` | Fresh-context critic for `/ideate` Phase 2 — scores, clusters, and deepens divergent ideas |
| `task-prep-checker` | Fresh-context verifier for a `task-prep` handoff prompt — runs the golden-rule colleague test |

### Tathep Platform

Tathep-scoped stack-pattern skills: kbg-native where no upstream fit existed,
restored unmodified from ECC where it did (`dart-flutter-patterns`).

| Skill | When to reach for it |
|---|---|
| `kbg:adonisjs-patterns` | AdonisJS v5 routes, Lucid ORM, Japa tests, VineJS validation, and Edge templates |
| `kbg:drizzle-patterns` | Drizzle ORM schema, migrations, relations, and query patterns for PostgreSQL / MySQL / SQLite |
| `kbg:effect-ts-patterns` | Effect-TS layers, services, typed error channels, and functional pipelines |
| `kbg:grpc-node-patterns` | gRPC client/server with `@grpc/grpc-js`, TypeScript codegen, streaming, and error codes |
| `kbg:hono-patterns` | Hono routes, middleware, validation, and deployment for Bun / Node.js / edge runtimes |
| `kbg:langchain-langgraph-patterns` | LangChain chains, agents, RAG pipelines, and LangGraph stateful multi-step workflows |
| `kbg:fastapi-patterns` | FastAPI structure, Pydantic v2, dependency injection, async handlers, service layers |
| `kbg:mysql-patterns` | MySQL / MariaDB schema, indexing, transactions, replication, and pool patterns |
| `kbg:tauri-v2-patterns` | Tauri v2 IPC commands, capabilities / permissions model, Rust app state, events, and plugins |
| `kbg:dart-flutter-patterns` | Dart/Flutter null safety, state management (BLoC/Riverpod/Provider), GoRouter, Dio, Freezed, clean architecture |

---

## Repository Layout

```text
kbg-harness/
├── .claude-plugin/       # plugin.json + marketplace.json (both must be bumped on each release)
├── agents/               # 17 specialist subagents (.md each)
├── skills/               # 33 workflow skills (SKILL.md per directory)
├── commands/             # 17 slash commands
├── hooks/                # gates/ (deny) · advisory/ (journal) · session/ (inject) · stop/ (cost)
├── output-styles/        # staff-eng — sole live-response register
├── contexts/             # dev / review / research session frames
├── themes/               # catppuccin-mocha.json
├── scripts/              # Validation helpers (run-gauntlet.sh — full parallel gauntlet)
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

# Full gauntlet (plugin-validate + shell-lint + JSON lint + harness-audit)
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

> **Point-in-time snapshot (counts as of 2026-07-17), not live-derived.** There is no
> `origin:` frontmatter field on surface files to auto-regenerate this table: it's a
> manual tally. To browse what's actually shipping today: `ls skills/`, `ls agents/`,
> `ls commands/` (real current fleet: 33 skills · 17 agents · 17 commands).

| Source | License | Adopted |
|---|---|---|
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | 20 skills, installed verbatim via `gh skill` (not vendored — see Quick Start), 0 kbg-modified |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | 85 skills · 48 agents · 64 commands · 3 contexts |
| [TJBoudreaux/cc-thinking-skills](https://github.com/TJBoudreaux/cc-thinking-skills) | MIT | 39 mental models vendored into `docs/reference/thinking-skills/skills/` (on-demand reference, not an auto-discovered skill) |
| kbg-native | MIT | 33 skills · 17 agents · 17 commands |

---

## License

MIT. See [`LICENSE`](LICENSE).
