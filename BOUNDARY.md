# Boundary Map
_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: `bash <kbg-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md` where `<kbg-harness>` is the kbg-harness repo root and `<dotfiles>` is the target repo root (or from the plugin cache: `bash ~/.claude/plugins/cache/kobig/kbg/$(ls ~/.claude/plugins/cache/kobig/kbg/ | sort -V | tail -1)/skills/inventory/scripts/inventory-boundary.sh --repo-only`)._
_Schema version: v3 (adds Output styles table; Mutates column reflects Edit/Write/Bash grant)._
# Inventory
_Legend: ◇ plugin-delivered / project-local_

## Source: Personals/kbg-harness
_Personals/kbg-harness_

### Skills (33)
  ◇ adonisjs-patterns              AdonisJS v5 patterns: IoC, Lucid ORM, Japa, VineJS, middleware, auth guards, ace CLI. Use when building an AdonisJS v5 backend. Don't use for non-AdonisJS frameworks.
  ◇ agent-architecture-audit       Scan 12-layer agent stacks, regression, memory pollution, tool discipline, repair loops. Use when debugging a misbehaving harness (stuck loops, rot). Don't use for code review.
  ◇ backend-patterns               Backend architecture, API design, and DB optimization for Node.js/Express/Next.js — the kept TS/backend base. Use when building a Node/TS backend. Don't use for Python/Go/Rust backends.
  ◇ codebase-onboarding            Catalogue unfamiliar codebases into an onboarding guide — architecture, entry points, conventions. Use when joining or taking over a project. Don't use for single-file lookups.
  ◇ context-budget                 Scan context-window consumption across agents/skills/MCP/rules; flag bloat + top savings. Use when context feels full or costs climb. Don't use for one-off response trimming.
  ◇ cost-aware-llm-pipeline        Compact LLM-pipeline cost: model routing, prompt caching, retry. Use when designing a multi-model pipeline where cost/latency matter. Don't use for single calls or prompting tips.
  ◇ dart-flutter-patterns          Dart/Flutter production patterns: null safety, state management (BLoC/Riverpod/Provider), GoRouter, Dio, Freezed, clean architecture. Use when building or reviewing Dart/Flutter apps. Don't use for web-only frontend.
  ◇ decide                         Doctrine-backed decision support for genuinely hard, contested-diagnosis choices — when advisor()-level pressure-testing isn't enough. Use when the user says 'stuck between', 'torn between', 'hard call', 'high-stakes decision', or Thai 'ตัดสินใจยาก'/'เลือกไม่ลง'/'ชั่งใจไม่ได้'. Don't use for routine decisions — default is triad + advisor().
  ◇ drizzle-patterns               Drizzle ORM patterns: schema, type inference, migrations, query builder, relations, transactions. Use when building Drizzle apps on PostgreSQL/SQLite. Don't use for Prisma or TypeORM.
  ◇ effect-ts-patterns             Effect-ts patterns: Effect<A,E,R>, Effect.gen, Layer DI, Schema validation, fiber concurrency, @effect/platform HTTP. Use when building/maintaining Effect-ts apps in TypeScript. Don't use for vanilla Promise/async codebases.
  ◇ eval-harness                   Eval-driven development (EDD) framework for Claude Code. Use when setting up EDD, building graders, or measuring AI-assisted workflow quality. Don't use for end-user feature work.
  ◇ fastapi-patterns               FastAPI patterns: structure, Pydantic v2, dependency injection, async handlers, auth, service layers. Use when building FastAPI apps. Don't use for non-FastAPI backends (Flask/Django).
  ◇ goal-craft                     Compact a /goal completion condition: done-when check, one-way-door screen, turn bound. Use when drafting a /goal condition. Don't use for single-turn tasks (do it directly).
  ◇ grpc-node-patterns             gRPC patterns for Node/Bun: proto, @grpc/grpc-js client/server, TypeScript codegen, streaming, deadlines/metadata. Use when building gRPC services in Node/Bun. Don't use for REST/HTTP or non-Node gRPC.
  ◇ harness-audit                  Single harness-state surface, two modes: default fleet/schema audit, --health for session token cost. Use for harness audits or cost checks; not repo lint/security (kbg:security-auditor).
  ◇ hono-patterns                  Hono patterns: typed routing, Zod validation, middleware, RPC client, context vars. Use when building Hono services on Bun/Node. Don't use for Express, Fastify, or NestJS.
  ◇ incident                       Incident: run a production incident incl. hotfix. Use when alerts fire or user asks for hotfix. Thai: 'เหตุฉุกเฉิน'. Don't use for non-prod bugs or post-mortem.
  ◇ inventory                      Catalogue loadable skills/agents/commands/hooks + the escape hatch. Use when stuck on routing. Thai: 'หา skill ไหนเหมาะ'. Don't use for single-layer lists or governance health.
  ◇ langchain-langgraph-patterns   LangChain + LangGraph patterns: StateGraph agents, checkpointing, human-in-the-loop, tool calling, streaming, RAG, tracing. Use when building LangChain/LangGraph agents. Don't use for non-LangChain LLM frameworks.
  ◇ latency-critical-systems       Diagnosis + design for latency-sensitive systems, realtime dashboards, market data, streaming, queues, caches, HFT-like infra. Use when designing/reviewing/debugging them. Don't use for batch or offline.
  ◇ learn                          Catalogue durable session learnings; save as memory after an AskUserQuestion gate. Use when asked to capture learnings. Don't use for single known memories or self-improvement.
  ◇ memory-lint                    Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health.
  ◇ mysql-patterns                 MySQL/MariaDB schema, query, indexing, transaction, replication, and pool patterns. Use when designing or troubleshooting MySQL/MariaDB. Don't use for non-MySQL databases.
  ◇ orchestrate                    Triage competing tasks and route each to inline/parallel/sequential/drop. Use when the user lists tasks or says 'จัดสรรงาน'. Don't use for single-issue triage or PR review.
  ◇ pr                             Create a GitHub PR from the current branch — templated body, previewed for confirmation. Use when asked to create/open/raise a PR. Don't use for merging or review replies.
  ◇ production-audit               Scan production readiness pre-launch. Use when asked whether an app is ready to ship. Don't use for in-flight feature work (use /ship).
  ◇ recursive-improve              Cage: human-gated, anti-unattended harness loop. Use when the user asks to improve or audit the harness. Don't use for bug fixes or new surfaces.
  ◇ review-pr                      Scan a PR review (quality/tests/security/types/db) via multiple agents. Use when a PR is ready, by number/branch. Don't use for quick diffs. Thai: 'รีวิว PR'.
  ◇ score-decision                 Score pending decisions on weighted criteria: numeric verdict, pass/fail, confidence, trace. Use when a decision needs a verdict. Don't use for trivial or already-decided choices.
  ◇ security-auditor               Scan security vulnerabilities, threat-model + remediation (auth, secrets, injection, XSS, traversal). Use when PRs touch auth/APIs/payments/deps. Don't use for quick branch checks or code review.
  ◇ task-prep                      Prep-map a draft task against the handoff template; fill gaps; verify fresh-context; emit paste-ready. Use when tackling non-trivial tasks; don't use for ideas or one-liners.
  ◇ tauri-v2-patterns              Tauri v2 desktop app patterns: IPC, capabilities/permissions, state, events, plugins, tauri.conf.json. Use when building or upgrading a Tauri v2 app. Don't use for Tauri v1.
  ◇ tech-humanize                  Humanize dev/tech writing (English/Thai) to sound natural, not AI-generated. Use when editing standups, PRs, commits, ADRs, UI copy, or say แก้ให้เป็นธรรมชาติ. Don't use for translation.

### Commands (16)
  ◇ address-review                 Triage + respond to open PR review comments (fetch, classify, fix via /fix-bug, reply). Say 'address review/แก้ตามรีวิว'. Don't use to review (kbg:review-pr) or merge (/ship-merge).
  ◇ build-fix                      Detect the project build system and incrementally fix build/type errors with minimal safe changes. Delegates to the build-error-resolver agent.
  ◇ cost-report                    Generate a local Claude Code cost report from the ECC cost-tracker metrics log.
  ◇ fix-bug                        Guided 7-phase bug-fix workflow. Use for non-trivial bugs needing root-cause or regression pinning. Say 'แก้บั๊ก/fix bug'. Don't use for typos, TDD (tdd), or refactors (/refactor-clean).
  ◇ frame                          Load a working-frame: dev/review/research (posture-setter, not a workflow or voice change). Say 'dev mode/โหมด dev/ตั้งโหมด'. Don't use for skills or /output-style.
  ◇ ideate-search                  Search past /ideate runs via the local qmd collection. Say 'ideate search/ค้นหาไอเดีย/หาไอเดีย'. Don't use for a new session (/ideate) or code/web research (research).
  ◇ implementation-compliance-audit Audit a completed implementation against its approved plan via fresh-context verifiers — plan-conformance, not code quality. Use after finishing a multi-phase plan, before declaring it done. Don't use for reviewing an unplanned diff (kbg:review-pr) or prod-readiness (kbg:production-audit).
  ◇ kbg-help                       kbg-harness quick reference: skills, commands, agents, validation, context tiers. Use for 'help', 'what can you do', 'list skills', 'kbg commands', 'ช่วยเหลือ', 'มีอะไรบ้าง'.
  ◇ post-mortem                    Draft a post-mortem for a resolved bug (trigger/mechanism/patch/validation known). Use after /fix-bug; say 'เขียน post-mortem/บันทึกบั๊ก/incident report'. Don't use for in-progress or non-technical incidents.
  ◇ refactor-clean                 Safely identify and remove dead code (JS/TS, Python, Go, Rust) with test verification after each change. Delegates to the refactor-cleaner agent.
  ◇ security-scan                  Run AgentShield against agent, hook, MCP, permission, and secret surfaces. Don't use for code-vulnerability review — use kbg:security-auditor.
  ◇ ship-merge                     Merge an approved PR safely: validate, server-side merge, cleanup, monitor CI. Say 'merge PR/รวมโค้ด'. Don't use for unapproved PRs, failing CI, or hotfixes (kbg:incident).
  ◇ ship-release                   Cut a release end-to-end: bump, changelog, review gate, tag, merge, monitor. Say 'ship release/ปล่อยเวอร์ชัน'. Don't use for PR merges (/ship-merge) or hotfixes (kbg:incident).
  ◇ test-coverage                  Analyze coverage, identify gaps, and generate missing tests toward the target threshold.
  ◇ COMMAND                        Parallel divergent ideation (5 isolated agents, rotating frames, novelty/viability/fit scoring). Say 'brainstorm/ระดมความคิด/คิดไอเดีย'. Don't use for syntax, lookups, or closed-phrasing asks.
  ◇ COMMAND                        Land a code change end-to-end: classify, implement, test, review, fix-loop, merge. Say 'ship this/ทำงานใหม่'. Don't use for releases (/ship-release) or approved PRs (/ship-merge).

### Agents (13)
  ◇ build-error-resolver           Build-error resolver across npm, Cargo, Maven, Gradle, Go, Python, and Dart/Flutter. Minimal diffs, no architecture changes.
  ◇ code-architect                 Designs feature architectures by analyzing existing codebase patterns and conventions, then providing implementation blueprints with concrete files, interfaces, data flow, and build order.
  ◇ code-reviewer                  Expert code reviewer for quality, security, maintainability — plus comment-accuracy, type-design, behavioral test-coverage, and DB/SQL query-safety lenses. Use after writing or modifying code.
  ◇ flutter-reviewer               Flutter/Dart code reviewer covering widget best practices, state management, Dart idioms, performance, accessibility, and architecture. Library-agnostic.
  ◇ ideate-critic                  Fresh-context critic for /ideate Phase 2. Use when ideate needs a critic pass, or the user says 'วิจารณ์ไอเดีย', 'critic', 'ตรวจไอเดีย'. Don't use for: code review (code-reviewer) or security audit (security-reviewer).
  ◇ performance-optimizer          Performance optimizer. Identifies bottlenecks, optimizes slow code, reduces bundle sizes, and fixes memory leaks and render issues.
  ◇ python-reviewer                Expert Python reviewer: PEP 8, Pythonic idioms, type hints, security, and performance. Use for all Python code changes.
  ◇ refactor-cleaner               Dead code cleanup specialist across JS/TS, Python, Go, and Rust. Identifies and removes unused code and duplicates.
  ◇ security-reviewer              Security vulnerability detector. Flags secrets, SSRF, injection, unsafe crypto, and OWASP Top 10. Use after writing code handling user input or auth.
  ◇ silent-failure-hunter          Review code for silent failures, swallowed errors, bad fallbacks, and missing error propagation.
  ◇ spec-miner                     Extracts behavioral specs from existing codebases. Produces Requirement and Invariant blocks with structured metadata. Use when onboarding a brownfield project to spec-driven development.
  ◇ task-prep-checker              Fresh-context verifier for a task-prep prompt. Runs the golden-rule colleague test against the 9-field handoff template; returns a structured gap list. Read-only — never edits, never invents.
  ◇ typescript-reviewer            Expert TypeScript/JavaScript reviewer: type safety, async correctness, security, and idiomatic patterns. Use for all TS/JS code changes.

### Hooks (18)
  ◇ flow-nudge.sh                  Advisory: when the user's prompt looks like non-trivial engineering work,
  ◇ jira-route-nudge.sh            Advisory: when the user's prompt mentions Jira/Confluence work, nudge
  ◇ learn-nudge.sh                 Advisory: remind the operator that kbg:learn exists when a session had
  ◇ db-write-gate.sh               Gate: ask on non-SELECT tathep-db MCP calls (mcp__tathep-db__execute_sql_*).
  ◇ irrecoverable.sh               Gate: block irrecoverable Bash patterns before they execute.
  ◇ task-complete-separation.sh    Gate: a subagent may not mark its own task completed (maker≠checker).
  ◇ verifier-protect.sh            Gate: prompt the human to approve any Write/Edit/MultiEdit — OR a Bash-mediated
  ◇ worktree-create-block.sh       Gate: enforce kbg single-branch doctrine (no new non-develop branches via worktree).
  ◇ command-root-anchor.sh         command-root-anchor.sh — matcher-less SessionStart hook
  ◇ doctrine-bootstrap.sh          SessionStart: inject METHODOLOGY.md doctrine into the session context.
  ◇ cost-tracker.sh                Stop: log cumulative session token usage to ~/.local/share/kbg/metrics/costs.jsonl
  ◇ test-flow-nudge.sh             shellcheck disable=SC2016  # literal \$ in payload strings is intentional
  ◇ test-gates.sh                  shellcheck disable=SC2016  # literal \$ in test payload strings is intentional
  ◇ test-jira-route-nudge.sh       shellcheck disable=SC2016  # literal \$ in payload strings is intentional
  ◇ test-learn-nudge.sh            learn-nudge unit tests: simulates SessionEnd JSON payloads pointing at a
  ◇ test-session-stop.sh           Session/Stop hook smoke tests: doctrine-bootstrap (SessionStart),
  ◇ test-worktree-create.sh        shellcheck disable=SC2016  # literal $ in test payload strings is intentional
  ◇ test-worktree-guard.sh         Behavioral tests for the worktree-guard gate (tathep-scoped PreToolUse redirect).

## Agents — Repo
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| build-error-resolver | Build-error resolver across npm, Cargo, Maven, Gradle, Go, Python, and Dart/Flutter. Minimal diffs, no architecture changes. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| code-architect | Designs feature architectures by analyzing existing codebase patterns and conventions, then providing implementation blueprints with concrete files, interfaces, data flow, and build order. | [Read, Grep, Glob, Bash] | yes |
| code-reviewer | Expert code reviewer for quality, security, maintainability — plus comment-accuracy, type-design, behavioral test-coverage, and DB/SQL query-safety lenses. Use after writing or modifying code. | ["Read", "Grep", "Glob", "Bash"] | yes |
| flutter-reviewer | Flutter/Dart code reviewer covering widget best practices, state management, Dart idioms, performance, accessibility, and architecture. Library-agnostic. | ["Read", "Grep", "Glob", "Bash"] | yes |
| ideate-critic | Fresh-context critic for /ideate Phase 2. Use when ideate needs a critic pass, or the user says 'วิจารณ์ไอเดีย', 'critic', 'ตรวจไอเดีย'. Don't use for: code review (code-reviewer) or security audit (security-reviewer). | Read | no |
| performance-optimizer | Performance optimizer. Identifies bottlenecks, optimizes slow code, reduces bundle sizes, and fixes memory leaks and render issues. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| python-reviewer | Expert Python reviewer: PEP 8, Pythonic idioms, type hints, security, and performance. Use for all Python code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| refactor-cleaner | Dead code cleanup specialist across JS/TS, Python, Go, and Rust. Identifies and removes unused code and duplicates. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| security-reviewer | Security vulnerability detector. Flags secrets, SSRF, injection, unsafe crypto, and OWASP Top 10. Use after writing code handling user input or auth. | ["Read", "Bash", "Grep", "Glob"] | yes |
| silent-failure-hunter | Review code for silent failures, swallowed errors, bad fallbacks, and missing error propagation. | [Read, Grep, Glob, Bash] | yes |
| spec-miner | Extracts behavioral specs from existing codebases. Produces Requirement and Invariant blocks with structured metadata. Use when onboarding a brownfield project to spec-driven development. | ["Read", "Grep", "Glob", "Bash", "Write"] | yes |
| task-prep-checker | Fresh-context verifier for a task-prep prompt. Runs the golden-rule colleague test against the 9-field handoff template; returns a structured gap list. Read-only — never edits, never invents. | ["Read", "Glob", "Grep"] | no |
| typescript-reviewer | Expert TypeScript/JavaScript reviewer: type safety, async correctness, security, and idiomatic patterns. Use for all TS/JS code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |

## Skills — Repo
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| adonisjs-patterns | AdonisJS v5 patterns: IoC, Lucid ORM, Japa, VineJS, middleware, auth guards, ace CLI. Use when building an AdonisJS v5 backend. Don't use for non-AdonisJS frameworks. | inline | auto |
| agent-architecture-audit | Scan 12-layer agent stacks, regression, memory pollution, tool discipline, repair loops. Use when debugging a misbehaving harness (stuck loops, rot). Don't use for code review. | inline | auto |
| backend-patterns | Backend architecture, API design, and DB optimization for Node.js/Express/Next.js — the kept TS/backend base. Use when building a Node/TS backend. Don't use for Python/Go/Rust backends. | inline | auto |
| codebase-onboarding | Catalogue unfamiliar codebases into an onboarding guide — architecture, entry points, conventions. Use when joining or taking over a project. Don't use for single-file lookups. | inline | auto |
| context-budget | Scan context-window consumption across agents/skills/MCP/rules; flag bloat + top savings. Use when context feels full or costs climb. Don't use for one-off response trimming. | inline | auto |
| cost-aware-llm-pipeline | Compact LLM-pipeline cost: model routing, prompt caching, retry. Use when designing a multi-model pipeline where cost/latency matter. Don't use for single calls or prompting tips. | inline | auto |
| dart-flutter-patterns | Dart/Flutter production patterns: null safety, state management (BLoC/Riverpod/Provider), GoRouter, Dio, Freezed, clean architecture. Use when building or reviewing Dart/Flutter apps. Don't use for web-only frontend. | inline | auto |
| decide | Doctrine-backed decision support for genuinely hard, contested-diagnosis choices — when advisor()-level pressure-testing isn't enough. Use when the user says 'stuck between', 'torn between', 'hard call', 'high-stakes decision', or Thai 'ตัดสินใจยาก'/'เลือกไม่ลง'/'ชั่งใจไม่ได้'. Don't use for routine decisions — default is triad + advisor(). | inline | auto |
| drizzle-patterns | Drizzle ORM patterns: schema, type inference, migrations, query builder, relations, transactions. Use when building Drizzle apps on PostgreSQL/SQLite. Don't use for Prisma or TypeORM. | inline | auto |
| effect-ts-patterns | Effect-ts patterns: Effect<A,E,R>, Effect.gen, Layer DI, Schema validation, fiber concurrency, @effect/platform HTTP. Use when building/maintaining Effect-ts apps in TypeScript. Don't use for vanilla Promise/async codebases. | inline | auto |
| eval-harness | Eval-driven development (EDD) framework for Claude Code. Use when setting up EDD, building graders, or measuring AI-assisted workflow quality. Don't use for end-user feature work. | inline | auto |
| fastapi-patterns | FastAPI patterns: structure, Pydantic v2, dependency injection, async handlers, auth, service layers. Use when building FastAPI apps. Don't use for non-FastAPI backends (Flask/Django). | inline | auto |
| goal-craft | Compact a /goal completion condition: done-when check, one-way-door screen, turn bound. Use when drafting a /goal condition. Don't use for single-turn tasks (do it directly). | inline | auto |
| grpc-node-patterns | gRPC patterns for Node/Bun: proto, @grpc/grpc-js client/server, TypeScript codegen, streaming, deadlines/metadata. Use when building gRPC services in Node/Bun. Don't use for REST/HTTP or non-Node gRPC. | inline | auto |
| harness-audit | Single harness-state surface, two modes: default fleet/schema audit, --health for session token cost. Use for harness audits or cost checks; not repo lint/security (kbg:security-auditor). | inline | auto |
| hono-patterns | Hono patterns: typed routing, Zod validation, middleware, RPC client, context vars. Use when building Hono services on Bun/Node. Don't use for Express, Fastify, or NestJS. | inline | auto |
| incident | Incident: run a production incident incl. hotfix. Use when alerts fire or user asks for hotfix. Thai: 'เหตุฉุกเฉิน'. Don't use for non-prod bugs or post-mortem. | inline | auto |
| inventory | Catalogue loadable skills/agents/commands/hooks + the escape hatch. Use when stuck on routing. Thai: 'หา skill ไหนเหมาะ'. Don't use for single-layer lists or governance health. | inline | auto |
| langchain-langgraph-patterns | LangChain + LangGraph patterns: StateGraph agents, checkpointing, human-in-the-loop, tool calling, streaming, RAG, tracing. Use when building LangChain/LangGraph agents. Don't use for non-LangChain LLM frameworks. | inline | auto |
| latency-critical-systems | Diagnosis + design for latency-sensitive systems, realtime dashboards, market data, streaming, queues, caches, HFT-like infra. Use when designing/reviewing/debugging them. Don't use for batch or offline. | inline | auto |
| learn | Catalogue durable session learnings; save as memory after an AskUserQuestion gate. Use when asked to capture learnings. Don't use for single known memories or self-improvement. | inline | auto |
| memory-lint | Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health. | inline | auto |
| mysql-patterns | MySQL/MariaDB schema, query, indexing, transaction, replication, and pool patterns. Use when designing or troubleshooting MySQL/MariaDB. Don't use for non-MySQL databases. | inline | auto |
| orchestrate | Triage competing tasks and route each to inline/parallel/sequential/drop. Use when the user lists tasks or says 'จัดสรรงาน'. Don't use for single-issue triage or PR review. | inline | auto |
| pr | Create a GitHub PR from the current branch — templated body, previewed for confirmation. Use when asked to create/open/raise a PR. Don't use for merging or review replies. | inline | auto |
| production-audit | Scan production readiness pre-launch. Use when asked whether an app is ready to ship. Don't use for in-flight feature work (use /ship). | inline | auto |
| recursive-improve | Cage: human-gated, anti-unattended harness loop. Use when the user asks to improve or audit the harness. Don't use for bug fixes or new surfaces. | inline | manual |
| review-pr | Scan a PR review (quality/tests/security/types/db) via multiple agents. Use when a PR is ready, by number/branch. Don't use for quick diffs. Thai: 'รีวิว PR'. | inline | auto |
| score-decision | Score pending decisions on weighted criteria: numeric verdict, pass/fail, confidence, trace. Use when a decision needs a verdict. Don't use for trivial or already-decided choices. | inline | manual |
| security-auditor | Scan security vulnerabilities, threat-model + remediation (auth, secrets, injection, XSS, traversal). Use when PRs touch auth/APIs/payments/deps. Don't use for quick branch checks or code review. | inline | auto |
| task-prep | Prep-map a draft task against the handoff template; fill gaps; verify fresh-context; emit paste-ready. Use when tackling non-trivial tasks; don't use for ideas or one-liners. | inline | auto |
| tauri-v2-patterns | Tauri v2 desktop app patterns: IPC, capabilities/permissions, state, events, plugins, tauri.conf.json. Use when building or upgrading a Tauri v2 app. Don't use for Tauri v1. | inline | auto |
| tech-humanize | Humanize dev/tech writing (English/Thai) to sound natural, not AI-generated. Use when editing standups, PRs, commits, ADRs, UI copy, or say แก้ให้เป็นธรรมชาติ. Don't use for translation. | inline | auto |

## Hooks — Repo
| Hook | Purpose |
|---|---|
| flow-nudge.sh | Advisory: when the user's prompt looks like non-trivial engineering work, |
| jira-route-nudge.sh | Advisory: when the user's prompt mentions Jira/Confluence work, nudge |
| learn-nudge.sh | Advisory: remind the operator that kbg:learn exists when a session had |
| db-write-gate.sh | Gate: ask on non-SELECT tathep-db MCP calls (mcp__tathep-db__execute_sql_*). |
| irrecoverable.sh | Gate: block irrecoverable Bash patterns before they execute. |
| task-complete-separation.sh | Gate: a subagent may not mark its own task completed (maker≠checker). |
| verifier-protect.sh | Gate: prompt the human to approve any Write/Edit/MultiEdit — OR a Bash-mediated |
| worktree-create-block.sh | Gate: enforce kbg single-branch doctrine (no new non-develop branches via worktree). |
| command-root-anchor.sh | command-root-anchor.sh — matcher-less SessionStart hook |
| doctrine-bootstrap.sh | SessionStart: inject METHODOLOGY.md doctrine into the session context. |
| cost-tracker.sh | Stop: log cumulative session token usage to ~/.local/share/kbg/metrics/costs.jsonl |
| test-flow-nudge.sh | shellcheck disable=SC2016  # literal \$ in payload strings is intentional |
| test-gates.sh | shellcheck disable=SC2016  # literal \$ in test payload strings is intentional |
| test-jira-route-nudge.sh | shellcheck disable=SC2016  # literal \$ in payload strings is intentional |
| test-learn-nudge.sh | learn-nudge unit tests: simulates SessionEnd JSON payloads pointing at a |
| test-session-stop.sh | Session/Stop hook smoke tests: doctrine-bootstrap (SessionStart), |
| test-worktree-create.sh | shellcheck disable=SC2016  # literal $ in test payload strings is intentional |
| test-worktree-guard.sh | Behavioral tests for the worktree-guard gate (tathep-scoped PreToolUse redirect). |

## Output styles — Repo
| Style | Description |
|---|---|
| staff-eng | Sole live-response register — self-calibrating: state the answer first for how-to/lookup/local changes, use decision+constraint+owner framing only for genuine cross-boundary trade-offs or long-term consequences. Formal deliverables (PRs, docs, reports) switch to their own audience's register. |

---
_Generated: 2026-07-10T08:18:19Z_

---

## Task sizing guidance

Derived from the task-sizing guidance + article `agent-teams-best-practices`. Apply at `kbg:orchestrate` plan time, before fan-out dispatch.

### The 5-6 rule
5-6 tasks per agent is the sweet spot. < 3 = under-utilization; > 8 = context thrashing. This is per-agent, not per-plan.

### Size heuristics
| Dimension | Too small | Too big | Just right |
|-----------|-----------|---------|------------|
| Description | < 30 chars, or "just run X" | Vague novel | 1 concrete sentence |
| Files | No files assigned | > 3 files owned | 1-2 files |
| Criteria | None listed | > 2 criteria | 1-2 criteria |
| Dependencies | 0 (island task) | > 2 upstream tasks | 1 max |
| Estimate | < 15 min | > 4 hours | 2-4 hours |

### Wave balancing
- **Wave 1:** 3-5 tasks (foundational setup — schemas, contracts, migrations).
- **Wave 2+:** 2-4 tasks each (implementation layers that consume prior contracts).
- **Total waves:** 3-5. More = plan is too coarse; fewer = use `/ship` (single-agent) instead.
- **F8.5 hard cap:** > 5 tasks in any wave → split or merge. Clamp in code, not prose.

### Splitting oversized tasks
1. **Interface-first split:** extract API contract / type definition as Wave 1.
2. **Layer split:** backend → frontend → integration → tests (one task per layer).
3. **File split:** one task per file when files are independent. Never split a single file across two agents.

### Merging undersized tasks
1. Same file + same owner → merge.
2. "Update docs after X" → merge into X's task.
3. No files + no criteria → drop or merge.

---

## File ownership boundary table

Canonical file patterns per agent. Assign each file to exactly one agent in an `orchestrate` dispatch plan to prevent silent overwrites. This table lists the live 13-agent fleet — keep it in sync with `agents/` (harness-audit check 12 verifies orchestrate references every agent).

| Agent | Canonical file patterns | Mutates | Notes |
|---|---|---|---|
| `code-architect` | `architecture/`, `*.md` (design docs) | yes | Blueprints, not implementation — but `tools:` grants Bash (Bash can mutate) |
| `code-reviewer` | any file | yes | Read-only review *by intent* (comment-accuracy / type-design / test-coverage lenses) — `tools:` grants Bash (Bash can mutate) |
| `typescript-reviewer` | `*.ts`, `*.tsx`, `*.js`, `*.jsx` | yes | Read-only TS/JS review *by intent* — type safety, async correctness — `tools:` grants Bash (Bash can mutate) |
| `python-reviewer` | `*.py`, `pyproject.toml` | yes | Read-only Python review *by intent* — PEP 8, idioms, type hints — `tools:` grants Bash (Bash can mutate) |
| `flutter-reviewer` | `*.dart`, `lib/`, `pubspec.yaml` | yes | Read-only Dart/Flutter review *by intent* — widgets, state mgmt, Dart idioms — `tools:` grants Bash (Bash can mutate) |
| `security-reviewer` | `auth/`, `secrets/`, `config/`, `security/`, `iam/`, `crypto/` | yes | Vulnerability detection — `tools:` Read/Bash/Grep/Glob (Bash can mutate; no Edit/Write) |
| `silent-failure-hunter` | any file | yes | Read-only error-handling audit *by intent* — `tools:` grants Bash (Bash can mutate) |
| `spec-miner` | any file → `.scratch/specs/` | yes | Extracts behavioral specs (Write + Bash) |
| `refactor-cleaner` | any file | yes | Dead-code removal / deprecation scope (Edit/Bash) |
| `build-error-resolver` | any file with build/type errors | yes | Minimal-diff build/type fixes (Edit/Bash) |
| `performance-optimizer` | any file | yes | Bottleneck + bundle + memory fixes (Edit/Bash) |
| `ideate-critic` | none (read-only) | no | Fresh-context critic for `/ideate` Phase 2 (Read only — no Bash) |
| `task-prep-checker` | none (read-only) | no | Fresh-context verifier for a task-prep prompt (Read/Glob/Grep only — no Bash) |


---

## Cross-references

- **[Agent tool patterns: allowlist vs denylist](docs/agent-tool-patterns.md)** — kbg-harness convention is `tools:` (allowlist) for new agents; reserve `disallowedTools:` (denylist) for cases where the allowlist would exceed 6-7 tools or the team explicitly opts into implicit-inheritance. The `Mutates` column above reflects `Edit`/`Write`/`Bash` grants.
- **[@0xCodez 14-step harness roadmap](https://x.com/0xCodez/article/2066867539305459732)** — external framing (2026-06-16): harness → loop → self-improving system. Useful for onboarding; kbg keeps the 3-floor vocabulary but rejects the article's L3/L4 unattended-loop conclusion per the no-model-self-start rule (CLAUDE.md's Operating model under §Architecture). Keep/discard analysis is in [[0xcodez-harness-roadmap]] memory.
- **[Sydney Runkle — The Art of Loop Engineering](https://x.com/sydneyrunkle/article/2066928783534289358)** — LangChain's 4-loop stack: agent loop, verification loop, event-driven loop, hill-climbing loop (2026-06-16). Good vocabulary for L1/L2 + human-in-the-loop; kbg rejects the L3/L4 unattended conclusion per the no-model-self-start rule (CLAUDE.md's Operating model under §Architecture). Keep/discard analysis is in [[sydney-runkle-loop-engineering]] memory.

---

## Repo context

Module map + verification recipe for the harness. Inject these conventions when a freshly spawned subagent needs the same onboarding map the lead already holds.

### Module Boundaries
For live per-layer counts, read the auto-generated inventory header at the top of this file (regenerated by `inventory-boundary.sh`) — it is the single source of truth; do not hardcode counts here (they drift).
- `agents/` — specialist subagents (.md each)
- `skills/` — workflow skills (SKILL.md per directory; `_lib` is a shared shell library, not an invokable skill)
- `commands/` — slash commands
- `hooks/` — gates/ (deny) · advisory/ (journal) · session/ (inject) · stop/ (cost)
- `output-styles/` — staff-eng (sole live-response register)
- `themes/` — catppuccin-mocha

### Quick Context
- **Stack:** Bash + Python 3 + jq; kbg-harness is a Claude Code plugin (version in `.claude-plugin/plugin.json`)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** critical-hooks behavioral suite and eval gate are pending rebuild (removed in the v0.6.0 reset) — see `CLAUDE.md`'s Validation section
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/kobig/kbg/<version>/` (rebuilt on `claude plugin update kbg@kobig`)

### Verification
- `bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" "${KBG_PLUGIN_ROOT}"` — 0C/0W expected (INFO findings are non-blocking)
- `claude plugin validate --strict "${KBG_PLUGIN_ROOT}"` — exit 0
- critical-hooks behavioral suite + eval gate: pending rebuild, not currently runnable

---

## Trigger phrases

Map user intent → harness dispatch. Use these trigger phrases in `commands/`, `skills/`, and agent `description:` frontmatter so the flow nudge (`hooks/advisory/flow-nudge.sh`) routes correctly.

### Decisions & debate
| User says | Dispatch | Why |
|---|---|---|
| "pros and cons", "which is better", "should we use X or Y" | `kbg:decide` critique mode | Skeptic + Steel-man + Synthesis stress-test |
| "what should I work on", "prioritize these", "plan this pile of work" | `kbg:orchestrate` skill | Prioritize + route to cheapest correct executor |

### Single-task workflows
| User says | Dispatch | Why |
|---|---|---|
| "build one feature", "implement X", "scope this change" | `/ship` | Classify → implement → review → merge |
| "fix this bug", "debug this" | `/fix-bug` | Bug ceremony |
| "address review feedback" | `/address-review` | PR review response |
| "ship it", "merge this" | `/ship-merge` | Pre-merge gate |
| "release now", "cut a release" | `/ship-release` | Release ceremony |

### Research & analysis
| User says | Dispatch | Why |
|---|---|---|
| "research this", "deep dive on X", "how does Y work" | `research` | Brain dump + Q&A + plan |
| "review this PR", "check this code" | `kbg:review-pr` skill | Multi-lens PR review |
| "audit the harness", "check health" | `kbg:harness-audit` skill | Self-audit |

### Incident & post-mortem
| User says | Dispatch | Why |
|---|---|---|
| "incident", "alerts firing", "monitors red" | `kbg:incident` skill | Live incident response |
| "post-mortem", "writeup after incident" | `/post-mortem` | Incident documentation |
| "save my session", "hand off" | `handoff` | Session state capture |


---

## Reference docs

These files live in the plugin cache, not the project CWD. Read them via Bash with `KBG_PLUGIN_ROOT` (exported by `hooks/session/command-root-anchor.sh`), not as relative markdown links.

- **Reasoning-models catalog** — `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` — 39 vendored cc-thinking-skills mental models and the kbg surface that applies (or deliberately does not apply) each.
- **Vendored thinking-skills library** — `cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/README.md"` — verbatim upstream copies of the 39 mental-model SKILL.md files, kept under `docs/` so they are never auto-discovered as invokable skills.

