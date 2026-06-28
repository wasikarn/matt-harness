# kbg — Claude Code Harness

[![Version](https://img.shields.io/badge/version-v0.1.0-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A personal [Claude Code](https://docs.anthropic.com/en/docs/claude-code) harness packaged as an installable plugin (`kbg@kobig`). Drop it in and you get 49 specialist agents, 113 workflow skills, and 68 slash commands — plus two output-style registers and a terminal theme. No symlink farm, no manual wiring; components auto-discover from the plugin cache.

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

<details>
<summary>mattpocock/skills — 17 skills</summary>

`ask-matt` · `codebase-design` · `diagnosing-bugs` · `domain-modeling` · `grilling` (expanded with modes) · `handoff` · `implement` · `improve-codebase-architecture` · `prototype` · `resolving-merge-conflicts` · `setup-matt-pocock-skills` · `tdd` · `teach` · `to-issues` · `to-prd` · `triage` · `writing-great-skills`

</details>

<details>
<summary>affaan-m/everything-claude-code — 85 skills</summary>

`agent-architecture-audit` · `agent-eval` · `agent-harness-construction` · `agent-self-evaluation` · `agent-sort` · `agentic-engineering` · `angular-developer` · `api-design` · `architecture-decision-records` · `autonomous-loops` · `backend-patterns` · `benchmark` · `bun-runtime` · `code-tour` · `codebase-onboarding` · `coding-standards` · `context-budget` · `cost-aware-llm-pipeline` · `cpp-coding-standards` · `cpp-testing` · `dart-flutter-patterns` · `database-migrations` · `deep-research` · `deployment-patterns` · `django-patterns` · `django-security` · `django-tdd` · `docker-patterns` · `documentation-lookup` · `dotnet-patterns` · `e2e-testing` · `error-handling` · `eval-harness` · `fastapi-patterns` · `flutter-dart-code-review` · `frontend-a11y` · `frontend-patterns` · `gateguard` · `git-workflow` · `github-ops` · `golang-patterns` · `golang-testing` · `hexagonal-architecture` · `intent-driven-development` · `java-coding-standards` · `knowledge-ops` · `kotlin-coroutines-flows` · `kotlin-exposed-patterns` · `kotlin-ktor-patterns` · `kotlin-patterns` · `kotlin-testing` · `kubernetes-patterns` · `latency-critical-systems` · `mysql-patterns` · `nestjs-patterns` · `nuxt4-patterns` · `orch-add-feature` · `orch-build-mvp` · `orch-change-feature` · `orch-fix-defect` · `orch-pipeline` · `orch-refine-code` · `postgres-patterns` · `production-audit` · `python-patterns` · `python-testing` · `react-patterns` · `react-performance` · `react-testing` · `redis-patterns` · `repo-scan` · `rules-distill` · `rust-patterns` · `rust-testing` · `safety-guard` · `search-first` · `security-review` · `springboot-patterns` · `springboot-security` · `springboot-tdd` · `strategic-compact` · `swift-concurrency-6-2` · `swiftui-patterns` · `team-agent-orchestration` · `terminal-ops` · `verification-loop` · `vue-patterns`

</details>

<details>
<summary>affaan-m/everything-claude-code — 48 agents</summary>

`a11y-architect` · `architect` · `build-error-resolver` · `chief-of-staff` · `code-architect` · `code-explorer` · `code-reviewer` · `code-simplifier` · `comment-analyzer` · `conversation-analyzer` · `cpp-build-resolver` · `cpp-reviewer` · `dart-build-resolver` · `database-reviewer` · `django-build-resolver` · `django-reviewer` · `doc-updater` · `docs-lookup` · `e2e-runner` · `fastapi-reviewer` · `flutter-reviewer` · `go-build-resolver` · `go-reviewer` · `harness-optimizer` · `java-build-resolver` · `java-reviewer` · `kotlin-build-resolver` · `kotlin-reviewer` · `loop-operator` · `mle-reviewer` · `performance-optimizer` · `planner` · `pr-test-analyzer` · `python-reviewer` · `react-build-resolver` · `react-reviewer` · `refactor-cleaner` · `rust-build-resolver` · `rust-reviewer` · `security-reviewer` · `silent-failure-hunter` · `spec-miner` · `swift-build-resolver` · `swift-reviewer` · `tdd-guide` · `type-design-analyzer` · `typescript-reviewer` · `vue-reviewer`

</details>

<details>
<summary>affaan-m/everything-claude-code — 64 commands</summary>

`aside` · `build-fix` · `checkpoint` · `code-review` · `cost-report` · `cpp-build` · `cpp-review` · `cpp-test` · `epic-publish` · `epic-review` · `epic-sync` · `epic-unblock` · `epic-validate` · `fastapi-review` · `feature-dev` · `flutter-build` · `flutter-review` · `flutter-test` · `go-build` · `go-review` · `go-test` · `jira` · `kotlin-build` · `kotlin-review` · `kotlin-test` · `learn` · `learn-eval` · `multi-backend` · `multi-execute` · `multi-frontend` · `multi-plan` · `multi-workflow` · `orch-add-feature` · `orch-build-mvp` · `orch-change-feature` · `orch-fix-defect` · `orch-refine-code` · `plan` · `plan-prd` · `pr` · `project-init` · `prp-commit` · `prp-implement` · `prp-plan` · `prp-pr` · `prp-prd` · `python-review` · `quality-gate` · `react-build` · `react-review` · `react-test` · `refactor-clean` · `resume-session` · `review-pr` · `rust-build` · `rust-review` · `rust-test` · `save-session` · `skill-create` · `skill-health` · `test-coverage` · `update-codemaps` · `update-docs` · `vue-review`

</details>

<details>
<summary>kbg-native surfaces</summary>

**Skills (9):** `decide` · `thinking` · `adonisjs-patterns` · `drizzle-patterns` · `effect-ts-patterns` · `grpc-node-patterns` · `hono-patterns` · `langchain-langgraph-patterns` · `tauri-v2-patterns`

**Agents (1):** `agent-evaluator`

**Commands (4):** `epic-claim` · `epic-decompose` · `pm2` · `security-scan`

**Output Styles (2):** `senior-eng` · `staff-eng`

**Themes (1):** `catppuccin-mocha`

</details>

---

## License

MIT — see [`LICENSE`](LICENSE).
