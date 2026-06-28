# kbg — Claude Code Harness (Plugin)

[![Version](https://img.shields.io/badge/version-v0.1.0-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml/badge.svg)](https://github.com/wasikarn/kbg-harness/actions/workflows/validate.yml)

A **personal Claude Code harness** delivered as an installable plugin (`kbg@kobig`). It adds 31 specialist agents, 63 workflow skills, and 37 slash commands — plus two output-style registers and a terminal theme. No symlink farm, no manual wiring: components auto-discover from the plugin cache.

> **v0.1.0 rebuild.** This is a clean rebuild from scratch. Governance hooks are pending rebuild (`hooks/` is empty). The L2–L5 autonomy ladder is retired.

---

## Table of Contents

- [Quick Start](#quick-start)
- [What You Get](#what-you-get)
- [Spotlight](#spotlight)
- [Repository Structure](#repository-structure)
- [Development](#development)
- [Documentation](#documentation)
- [Upstream Attribution](#upstream-attribution)
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

# 5. Verify — invoke any skill
kbg:thinking
```

**Uninstall:** `/plugin uninstall kbg`  
**Disable (keep installed):** set `"kbg@kobig": false` in `settings.json`

After any plugin surface change: bump both manifest versions → `claude plugin validate --strict .` → commit → push → `claude plugin update kbg@kobig` → restart.

---

## What You Get

| Component | Count | How to use |
|---|---|---|
| **Agents** | 31 | Spawned automatically or via `Task` tool (e.g. `kbg:code-architect`, `kbg:security-reviewer`) |
| **Skills** | 63 | Invoke via `kbg:<skill>` (e.g. `kbg:thinking`, `kbg:decide`, `kbg:grilling`) |
| **Commands** | 37 | Invoke via `/<command>` (e.g. `/review-pr`, `/plan`, `/feature-dev`) |
| **Hooks** | 0 | Pending rebuild — `hooks/` is empty |
| **Output Styles** | 2 | `senior-eng` (default), `staff-eng` (opt-in for cross-boundary decisions) |
| **Themes** | 1 | `catppuccin-mocha` |
| **Contexts** | 3 | `dev`, `review`, `research` — loaded by `/frame` to set session posture |

---

## Spotlight

### Key Commands

| Command | What it does |
|---|---|
| `/review-pr` | Multi-dimension PR review (code, tests, security, types) over the diff |
| `/code-review` | Deep code review for the current file or selection |
| `/plan` | Generate a structured implementation plan |
| `/feature-dev` | Full feature development loop: plan → implement → verify |
| `/learn` | Capture durable session learnings into memory |
| `/checkpoint` | Snapshot session state for resume |
| `/pr` | Create a GitHub PR with auto-generated title and body |
| `/security-scan` | Security vulnerability scan using the security-auditor agent |

### Key Skills

| Skill | When to use |
|---|---|
| `kbg:thinking` | On-demand index of 39 mental models — pick 1–3 for any complex, ambiguous, or high-stakes problem |
| `kbg:decide` | Judgment Ladder decision support: `probe` / `decide` / `strategize` modes |
| `kbg:grilling` | Relentless interview to stress-test a plan; `with-docs` mode also produces ADRs |
| `kbg:agent-architecture-audit` | 12-layer agent stack diagnostic — finds wrapper regression, memory pollution, repair loops |
| `kbg:eval-harness` | Formal EDD framework with pass@k metrics for LLM system evaluation |
| `kbg:context-budget` | Token usage audit — identifies bloat and produces prioritized savings |
| `kbg:architecture-decision-records` | Capture decisions as structured ADRs during sessions |
| `kbg:production-audit` | Local-evidence production readiness check — no external service |
| `kbg:security-review` | Security review covering OWASP Top 10, secrets, and auth |
| `kbg:gateguard` | Fact-forcing gate that demands concrete investigation before any Edit/Write/Bash |

---

## Repository Structure

```text
kbg-harness/
├── .claude-plugin/       # Plugin + marketplace manifests (plugin.json, marketplace.json)
├── agents/               # 31 senior-specialist subagents (one .md each)
├── skills/               # 63 workflow skills (one dir each: SKILL.md + optional references/)
├── commands/             # 37 user-facing slash commands
├── hooks/                # Empty — governance hooks pending rebuild
├── output-styles/        # senior-eng (default), staff-eng (opt-in)
├── contexts/             # dev / review / research frames (loaded by /frame)
├── themes/               # catppuccin-mocha.json
├── scripts/              # Validation + health scripts (run-gauntlet.sh stub)
├── docs/                 # Onboarding, reference docs, thinking-skills library
│   ├── onboarding.md     #   10-minute cold-start
│   └── reference/        #   thinking-skills/, reasoning-models.md, env-vars.md
├── git-hooks/            # pre-commit (fast lint/JSON/syntax) + pre-push (gauntlet)
├── CLAUDE.md             # Project instructions for Claude Code instances
├── CHANGELOG.md          # Release notes
└── README.md             # This file
```

---

## Development

### Validation

```bash
# Plugin manifest (the only live validation gate)
claude plugin validate --strict .

# Full parallel gauntlet (stub in v0.1.0)
bash scripts/run-gauntlet.sh
```

### Git Hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

`pre-commit`: syntax/lint (`bash -n` + shellcheck), JSON validation, harness-audit.  
`pre-push`: full gauntlet.

### Adding a Component

1. **Skill** — create `skills/<name>/SKILL.md` with `name` + `description` (≤25 words) frontmatter. Auto-discovered.
2. **Agent** — create `agents/<name>.md` with `name`, `description` (≤25 words), `tools` frontmatter. Auto-discovered.
3. **Command** — create `commands/<name>.md` with frontmatter. Auto-discovered.
4. Bump both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` versions.
5. `claude plugin validate --strict .` → commit → push → `claude plugin update kbg@kobig` → restart.

---

## Documentation

- [`docs/onboarding.md`](docs/onboarding.md) — 10-minute cold-start
- [`docs/reference/reasoning-models.md`](docs/reference/reasoning-models.md) — 39 vendored mental models (cc-thinking-skills)
- [`docs/reference/env-vars.md`](docs/reference/env-vars.md) — operator-tunable env vars
- [`CLAUDE.md`](CLAUDE.md) — architecture and non-obvious gotchas for Claude Code instances
- [`CHANGELOG.md`](CHANGELOG.md) — release notes

---

## Upstream Attribution

kbg-harness aggregates components from the following upstream projects under their respective licenses.

| Source | License | Components adopted |
|---|---|---|
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | 17 skills — `ask-matt`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`, `grilling` (expanded from upstream with modes), `handoff`, `implement`, `improve-codebase-architecture`, `prototype`, `resolving-merge-conflicts`, `setup-matt-pocock-skills`, `tdd`, `teach`, `to-issues`, `to-prd`, `triage`, `writing-great-skills` |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | 42 skills (origin: ECC in frontmatter) — `agent-self-evaluation`, `agent-sort`, `agentic-engineering`, `api-design`, `architecture-decision-records`, `backend-patterns`, `bun-runtime`, `coding-standards`, `context-budget`, `cost-aware-llm-pipeline`, `dart-flutter-patterns`, `database-migrations`, `deployment-patterns`, `docker-patterns`, `documentation-lookup`, `e2e-testing`, `error-handling`, `eval-harness`, `fastapi-patterns`, `flutter-dart-code-review`, `gateguard`, `github-ops`, `git-workflow`, `hexagonal-architecture`, `knowledge-ops`, `latency-critical-systems`, `mysql-patterns`, `postgres-patterns`, `production-audit`, `python-patterns`, `python-testing`, `react-patterns`, `react-performance`, `react-testing`, `redis-patterns`, `rust-patterns`, `rust-testing`, `safety-guard`, `search-first`, `security-review`, `strategic-compact`, `terminal-ops`, `verification-loop`; `agent-architecture-audit` (origin: oh-my-agent-check via ECC); 30 agents — `a11y-architect`, `architect`, `build-error-resolver`, `code-architect`, `code-explorer`, `code-reviewer`, `code-simplifier`, `comment-analyzer`, `dart-build-resolver`, `database-reviewer`, `docs-lookup`, `e2e-runner`, `fastapi-reviewer`, `flutter-reviewer`, `mle-reviewer`, `performance-optimizer`, `planner`, `pr-test-analyzer`, `python-reviewer`, `react-build-resolver`, `react-reviewer`, `refactor-cleaner`, `rust-build-resolver`, `rust-reviewer`, `security-reviewer`, `silent-failure-hunter`, `spec-miner`, `tdd-guide`, `type-design-analyzer`, `typescript-reviewer`; 33 commands — `aside`, `build-fix`, `checkpoint`, `code-review`, `fastapi-review`, `feature-dev`, `flutter-build`, `flutter-review`, `flutter-test`, `jira`, `learn`, `learn-eval`, `plan`, `plan-prd`, `pr`, `prp-commit`, `prp-implement`, `prp-plan`, `prp-pr`, `prp-prd`, `python-review`, `react-build`, `react-review`, `react-test`, `refactor-clean`, `resume-session`, `review-pr`, `rust-build`, `rust-review`, `rust-test`, `save-session`, `test-coverage`, `update-docs`; 3 contexts — `dev`, `research`, `review` |

kbg-native surfaces: skills `decide`, `thinking` (39 mental models vendored from [cc-thinking-skills](https://github.com/TJBoudreaux/cc-thinking-skills)); agent `agent-evaluator`; commands `epic-claim`, `epic-decompose`, `pm2`, `security-scan`.

---

## License

MIT — see [`LICENSE`](LICENSE).
