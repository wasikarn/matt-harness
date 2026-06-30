# Boundary Map
_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: `bash <kbg-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md` where `<kbg-harness>` is the kbg-harness repo root and `<dotfiles>` is the target repo root (or from the plugin cache: `bash ~/.claude/plugins/cache/kobig/kbg/$(ls ~/.claude/plugins/cache/kobig/kbg/ | sort -V | tail -1)/skills/inventory/scripts/inventory-boundary.sh --repo-only`)._
_Schema version: v3 (adds Output styles table; Mutates column reflects Edit/Write/Bash grant)._
# Inventory
_Legend: ◇ plugin-delivered / project-local_

## Source: Personals/kbg-harness
_Personals/kbg-harness_

### Skills (47)
  ◇ acli                           Compact Jira/Confluence bulk ops + ADF→markdown (~80% token cut). Use when bulk-editing work-items/pages. Thai: 'ย้ายสถานะหลายตัว', 'export JQL'. Don't use for single-ticket reads/creates, config, non-Atlassian trackers.
  ◇ adonisjs-patterns              AdonisJS v5 patterns: IoC, Lucid ORM, Japa, VineJS, middleware, auth guards, ace CLI. Use when building an AdonisJS v5 backend. Don't use for non-AdonisJS frameworks.
  ◇ agent-architecture-audit       Scan 12-layer agent stacks, regression, memory pollution, tool discipline, repair loops. Use when debugging a misbehaving harness (stuck loops, rot). Don't use for code review.
  ◇ ask-matt                       Router over the matt-pocock flow: ask, grill, plan, slice, ship. Use when starting non-trivial work, unsure which skill fits. Don't use for known flows.
  ◇ backend-patterns               Backend architecture, API design, and DB optimization for Node.js/Express/Next.js — the kept TS/backend base. Use when building a Node/TS backend. Don't use for Python/Go/Rust backends.
  ◇ codebase-design                Deep-module design vocabulary. Use when designing interfaces, finding deepening opportunities, or placing seams. Don't use for framework patterns (see kbg:<framework>-patterns).
  ◇ codebase-onboarding            Catalogue unfamiliar codebases into an onboarding guide — architecture, entry points, conventions. Use when joining or taking over a project. Don't use for single-file lookups.
  ◇ context-budget                 Scan context-window consumption across agents/skills/MCP/rules; flag bloat + top savings. Use when context feels full or costs climb. Don't use for one-off response trimming.
  ◇ cost-aware-llm-pipeline        Compact LLM-pipeline cost: model routing, prompt caching, retry. Use when designing a multi-model pipeline where cost/latency matter. Don't use for single calls or prompting tips.
  ◇ create-jira-ticket             Build a single Jira Bug/Story from the Thai PO/QA template. Use when the user says 'สร้างบั๊ก'/'สร้าง story'. Don't use for triage, bulk, edits, or non-Jira.
  ◇ decide                         Doctrine-backed decision support, clarify scope, stress-test reasoning, pick among defensible options (probe/decide/strategize). Use when facing a non-trivial choice. Don't use for obvious or already-decided calls.
  ◇ diagnosing-bugs                Diagnosis loop for hard bugs and perf regressions. Use when the user says 'debug' or reports something not behaving. Don't use for trivial typos.
  ◇ domain-modeling                Build and sharpen a project's domain model and ubiquitous language. Use when pinning down domain concepts. Don't use for one-off vocabulary lookups.
  ◇ drizzle-patterns               Drizzle ORM patterns: schema, type inference, migrations, query builder, relations, transactions. Use when building Drizzle apps on PostgreSQL/SQLite. Don't use for Prisma or TypeORM.
  ◇ effect-ts-patterns             Effect-ts patterns: Effect<A,E,R>, Effect.gen, Layer DI, Schema validation, fiber concurrency, @effect/platform HTTP. Use when building/maintaining Effect-ts apps in TypeScript. Don't use for vanilla Promise/async codebases.
  ◇ eval-harness                   Eval-driven development (EDD) framework for Claude Code. Use when setting up EDD, building graders, or measuring AI-assisted workflow quality. Don't use for end-user feature work.
  ◇ fastapi-patterns               FastAPI patterns: structure, Pydantic v2, dependency injection, async handlers, auth, service layers. Use when building FastAPI apps. Don't use for non-FastAPI backends (Flask/Django).
  ◇ grilling                       Grill-me: walk the design tree one question at a time, each with a recommended answer. Use when stress-testing a plan. Don't use for implementation.
  ◇ grpc-node-patterns             gRPC patterns for Node/Bun: proto, @grpc/grpc-js client/server, TypeScript codegen, streaming, deadlines/metadata. Use when building gRPC services in Node/Bun. Don't use for REST/HTTP or non-Node gRPC.
  ◇ handoff                        Compact the current conversation into a handoff document for the next agent. Use when ending a session. Don't use for end-user updates.
  ◇ harness-audit                  Single harness-state surface with two modes. Default mode runs a deterministic fleet/schema/structural audit across the kbg-harness plugin. --health mode surfaces per-session token cost from the live cost ledger (formerly kbg:harness-health). Use when running a harness audit or querying session token cost. Thai: 'audit harness', 'ตรวจ harness', 'harness health', 'สุขภาพ harness'. Don't use for: general repo lint or security audits (kbg:security-auditor).
  ◇ hono-patterns                  Hono patterns: typed routing, Zod validation, middleware, RPC client, context vars. Use when building Hono services on Bun/Node. Don't use for Express, Fastify, or NestJS.
  ◇ improve-codebase-architecture  Scan a codebase for deepening opportunities and grill through one. Use when the user wants to prioritise architecture deepening. Don't use for routine features.
  ◇ incident                       Incident: run a production incident incl. hotfix. Use when alerts fire or user asks for hotfix. Thai: 'เหตุฉุกเฉิน'. Don't use for non-prod bugs or post-mortem.
  ◇ inventory                      Catalogue loadable skills/agents/commands/hooks + the escape hatch. Use when stuck on routing. Thai: 'หา skill ไหนเหมาะ'. Don't use for single-layer lists or governance health.
  ◇ langchain-langgraph-patterns   LangChain + LangGraph patterns: StateGraph agents, checkpointing, human-in-the-loop, tool calling, streaming, RAG, tracing. Use when building LangChain/LangGraph agents. Don't use for non-LangChain LLM frameworks.
  ◇ latency-critical-systems       Diagnosis + design for latency-sensitive systems, realtime dashboards, market data, streaming, queues, caches, HFT-like infra. Use when designing/reviewing/debugging them. Don't use for batch or offline.
  ◇ learn                          Catalogue durable session learnings; save as memory after an AskUserQuestion gate. Use when asked to capture learnings. Don't use for single known memories or self-improvement.
  ◇ memory-lint                    Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health.
  ◇ mysql-patterns                 MySQL/MariaDB schema, query, indexing, transaction, replication, and pool patterns. Use when designing or troubleshooting MySQL/MariaDB. Don't use for non-MySQL databases (see kbg:postgres-patterns).
  ◇ orchestrate                    Triage competing tasks and route each to inline/parallel/sequential/drop. Use when the user lists tasks or says 'จัดสรรงาน'. Don't use for single-issue triage or PR review.
  ◇ production-audit               Scan production readiness pre-launch. Use when asked whether an app is ready to ship. Don't use for in-flight feature work (use /ship-change).
  ◇ prototype                      Build throwaway terminal or UI prototypes to answer a question. Use when the user wants a quick prototype. Don't use for production code.
  ◇ python-patterns                Pythonic idioms, PEP 8, and type hints. Use when writing or reviewing Python for idiomatic style. Don't use for framework-specific Python (use kbg:fastapi-patterns).
  ◇ recursive-improve              Cage: human-gated, anti-unattended harness loop. Use when the user asks to improve or audit the harness. Don't use for bug fixes or new surfaces.
  ◇ review-pr                      Scan PRs across quality, tests, security, types, a11y via multi-agent review. Use when a PR is ready. Don't use for quick diffs or single PRs.
  ◇ score-decision                 Score pending decisions on weighted criteria: numeric verdict, pass/fail, confidence, trace. Use when a decision needs a verdict. Don't use for trivial or already-decided choices.
  ◇ security-auditor               Scan security vulnerabilities, threat-model + remediation (auth, secrets, injection, XSS, traversal). Use when PRs touch auth/APIs/payments/deps. Don't use for quick branch checks or code review.
  ◇ setup-matt-pocock-skills       Build the matt-pocock skill setup once: map to your project (tracker, labels, ADR format). Use when onboarding. Don't use for re-running on an already-configured repo.
  ◇ ship-change                    Slice a scoped change (add/fix/refactor/build-MVP) through classify→implement→review→merge. Use when a change is scoped and ready to sequence. Don't use for blank-slate discovery or one-line fixes.
  ◇ tauri-v2-patterns              Tauri v2 desktop app patterns: IPC, capabilities/permissions, state, events, plugins, tauri.conf.json. Use when building or upgrading a Tauri v2 app. Don't use for Tauri v1.
  ◇ tdd                            Test-driven development — write the failing test first. Use when the user mentions red-green-refactor or wants integration tests. Don't use for refactors without behaviour change.
  ◇ teach                          Teach the user a new skill over multiple sessions. Use when the user asks to learn a topic. Don't use for one-shot factual questions.
  ◇ to-issues                      Slice a plan into vertical slices through every layer. Use when a plan is ready to publish as ticket-size tasks. Don't use for status updates.
  ◇ to-prd                         Synthesise-seam: turn a prior discussion into a published PRD without re-interviewing. Use when the user asks for a PRD. Don't use for undecided scope.
  ◇ triage                         Triage state machine: categorise, verify, grill if needed, write agent briefs. Use when new issues/PRs arrive. Don't use for implementation or non-triage comments.
  ◇ writing-great-skills           Doctrine for writing skills — leading words, no-op test, completion criteria, two cuts. Use when authoring skill files. Don't use for writing application code.

### Commands (21)
  ◇ address-review                 Triage and respond to existing PR review comments — fetch threads via gh, classify (action/clarify/wontfix/out-of-scope), implement fixes (delegate to /fix-bug), reply per-thread with commit sha, re-request review. Use when a PR has open review threads, after kbg:review-pr returns findings, or user says 'address the review', or when the user says 'แก้ตามรีวิว', 'ตอบรีวิว', 'address review'. Don't use for: doing the review yourself (use kbg:review-pr), pre-PR cleanup, or merging post-approval (use /ship-merge).
  ◇ build-fix                      Detect the project build system and incrementally fix build/type errors with minimal safe changes.
  ◇ cost-report                    Generate a local Claude Code cost report from the ECC cost-tracker metrics log.
  ◇ deep-dive                      Research a topic thoroughly across codebase, docs, and web, then synthesize findings into a concise actionable brief with sources. This is the single kbg research surface — both user-typed (/deep-dive) and auto-routed. Use when the user says 'research this', 'deep dive on X', 'compare Z approaches', 'how does Y work in this codebase', or any open-ended exploration. Thai: 'research', 'deep dive', 'วิจัย', 'สำรวจ', 'หาข้อมูล', 'compare วิธี', 'ศึกษา'. Don't use for: single-file lookups (just Read it), known answers (ask directly), implementation tasks (use /ship-task or /fix-bug), or security audits (use kbg:security-auditor).
  ◇ fix-bug                        Guided 7-phase bug-fix workflow with diagnostic and test-first patterns built in. Use when fixing non-trivial bugs with non-obvious root causes, unclear blast radius, or need regression-test pinning, or when the user says 'แก้บั๊ก', 'fix bug', 'debug'. Don't use for: typos/one-line fixes (just fix it), known-cause bugs with obvious fixes (skip ceremony), diagnostic-only loops (use kbg:backend-dev), greenfield TDD (use kbg:backend-dev), or refactors not driven by a bug (use `/refactor-clean`).
  ◇ frame                          Load a lightweight working-frame for the session — dev, review, or research. A posture-setter (how you work), lighter than running a full skill and distinct from output-styles (which set voice). Use when the user says 'dev mode', 'review mode', 'research mode', 'set context', 'switch frame', or 'โหมด dev', 'โหมด review', 'ตั้งโหมด'. Don't use for: running an actual workflow (use the matching skill — /deep-dive, kbg:review-pr, kbg:backend-dev) or changing voice register (use /output-style).
  ◇ ideate-search                  Search past /ideate runs by query against the local qmd collection. Use when the user asks to find a previous ideate session, search ideate memory, or says 'ค้นหาไอเดีย', 'ideate search', 'หาไอเดีย'. Don't use for: running a new ideation session (use /ideate), searching the codebase (use /deep-dive), or external web research (use /deep-dive).
  ◇ kbg-help                       kbg-harness quick reference: skills, commands, agents, validation, context tiers. Use for 'help', 'what can you do', 'list skills', 'kbg commands', 'ช่วยเหลือ', 'มีอะไรบ้าง'.
  ◇ pm2                            Analyze a project and generate PM2 service commands for detected frontend, backend, or database services.
  ◇ post-mortem                    Draft a canonical post-mortem for a resolved bug. Requires reproducible trigger, known mechanism, identified patch, and passing validation. Use after /fix-bug completes or when user says 'write post-mortem', 'document this bug', 'incident report', or when the user says 'เขียน post-mortem', 'บันทึกบั๊ก', 'incident report'. Don't use for: in-progress investigations (root cause must be known), hypothetical bugs (no validated fix), or non-technical incidents (use incident response template instead).
  ◇ pr                             Create a GitHub PR from current branch — validates, discovers templates, links PRDs/plans, analyzes changes, pushes.
  ◇ prp-commit                     Quick commit with natural language file targeting — describe what to commit in plain English
  ◇ quality-gate                   Run the ECC formatter quality gate for a single file and report remediation steps.
  ◇ refactor-clean                 Safely identify and remove dead code (JS/TS, Python, Go, Rust) with test verification after each change. Delegates to the refactor-cleaner agent.
  ◇ save-session                   Save current session state to a dated file in ~/.claude/session-data/ so work can be resumed in a future session with full context.
  ◇ security-scan                  Run AgentShield against agent, hook, MCP, permission, and secret surfaces.
  ◇ ship-merge                     Merge an approved PR safely: validate state, execute server-side merge, clean up branch, monitor CI post-merge. Use when the user says 'merge this PR', 'ship it', or after /address-review or /ship-release reaches the merge gate, or when the user says 'merge PR', 'ship it', 'รวมโค้ด'. Do NOT use for: unapproved PRs (wait for approval), PRs with failing CI (fix first), or hotfixes that need direct push (use kbg:incident hotfix path).
  ◇ ship-release                   Cut a software release end-to-end: version bump → changelog → review gate → tag → merge → monitor. Use when the user says 'ship release', 'cut a release', 'prepare version X.Y.Z', or when a release branch is ready for tagging, or when the user says 'ปล่อยเวอร์ชัน', 'release', 'ship release'. Do NOT use for: one-off PR merges (use /ship-merge), hotfixes (use kbg:incident hotfix path), or when there is no release branch / tag strategy defined.
  ◇ test-coverage                  Analyze coverage, identify gaps, and generate missing tests toward the target threshold.
  ◇ update-codemaps                Scan project structure and generate token-lean architecture codemaps.
  ◇ update-docs                    Sync documentation from source-of-truth files such as scripts, schemas, routes, and exports.

### Agents (11)
  ◇ build-error-resolver           Build and TypeScript error resolver. Fixes build/type errors with minimal diffs when builds fail. No architectural edits — just green builds.
  ◇ code-architect                 Designs feature architectures by analyzing existing codebase patterns and conventions, then providing implementation blueprints with concrete files, interfaces, data flow, and build order.
  ◇ code-reviewer                  Expert code reviewer for quality, security, maintainability — plus comment-accuracy, type-design, and behavioral test-coverage lenses. Use after writing or modifying code.
  ◇ ideate-critic                  Fresh-context critic for the /ideate command. Scores, clusters, and deepens divergent ideas produced by ideate Phase 1. Invoked by commands/ideate.md Phase 2 instead of running the critic pass on the host Claude, to reduce LLM-judge-circularity (CLAUDE.md §LLM-judge-circularity). Read-only: scores and reports, never blocks, never mutates the repo. Use when ideate needs a critic pass, or when the user says 'วิจารณ์ไอเดีย', 'critic', 'ตรวจไอเดีย'. Don't use for: code review (code-reviewer) or security audit (security-reviewer).
  ◇ performance-optimizer          Performance optimizer. Identifies bottlenecks, optimizes slow code, reduces bundle sizes, and fixes memory leaks and render issues.
  ◇ python-reviewer                Expert Python reviewer: PEP 8, Pythonic idioms, type hints, security, and performance. Use for all Python code changes.
  ◇ refactor-cleaner               Dead code cleanup specialist across JS/TS, Python, Go, and Rust. Uses knip/depcheck/ts-prune (JS/TS), vulture (Python), deadcode (Go), and cargo-udeps (Rust) to identify and remove unused code and duplicates.
  ◇ security-reviewer              Security vulnerability detector. Flags secrets, SSRF, injection, unsafe crypto, and OWASP Top 10. Use after writing code handling user input or auth.
  ◇ silent-failure-hunter          Review code for silent failures, swallowed errors, bad fallbacks, and missing error propagation.
  ◇ spec-miner                     Extracts behavioral specs from existing codebases. Produces Requirement and Invariant blocks with structured metadata. Use when onboarding a brownfield project to spec-driven development.
  ◇ typescript-reviewer            Expert TypeScript/JavaScript reviewer: type safety, async correctness, security, and idiomatic patterns. Use for all TS/JS code changes.

### Hooks (1)
  ◇ hooks.json                     (no description)

## Agents — Repo
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| build-error-resolver | Build and TypeScript error resolver. Fixes build/type errors with minimal diffs when builds fail. No architectural edits — just green builds. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| code-architect | Designs feature architectures by analyzing existing codebase patterns and conventions, then providing implementation blueprints with concrete files, interfaces, data flow, and build order. | [Read, Grep, Glob, Bash] | yes |
| code-reviewer | Expert code reviewer for quality, security, maintainability — plus comment-accuracy, type-design, and behavioral test-coverage lenses. Use after writing or modifying code. | ["Read", "Grep", "Glob", "Bash"] | yes |
| ideate-critic | Fresh-context critic for the /ideate command. Scores, clusters, and deepens divergent ideas produced by ideate Phase 1. Invoked by commands/ideate.md Phase 2 instead of running the critic pass on the host Claude, to reduce LLM-judge-circularity (CLAUDE.md §LLM-judge-circularity). Read-only: scores and reports, never blocks, never mutates the repo. Use when ideate needs a critic pass, or when the user says 'วิจารณ์ไอเดีย', 'critic', 'ตรวจไอเดีย'. Don't use for: code review (code-reviewer) or security audit (security-reviewer). | Read | no |
| performance-optimizer | Performance optimizer. Identifies bottlenecks, optimizes slow code, reduces bundle sizes, and fixes memory leaks and render issues. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| python-reviewer | Expert Python reviewer: PEP 8, Pythonic idioms, type hints, security, and performance. Use for all Python code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| refactor-cleaner | Dead code cleanup specialist across JS/TS, Python, Go, and Rust. Uses knip/depcheck/ts-prune (JS/TS), vulture (Python), deadcode (Go), and cargo-udeps (Rust) to identify and remove unused code and duplicates. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| security-reviewer | Security vulnerability detector. Flags secrets, SSRF, injection, unsafe crypto, and OWASP Top 10. Use after writing code handling user input or auth. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| silent-failure-hunter | Review code for silent failures, swallowed errors, bad fallbacks, and missing error propagation. | [Read, Grep, Glob, Bash] | yes |
| spec-miner | Extracts behavioral specs from existing codebases. Produces Requirement and Invariant blocks with structured metadata. Use when onboarding a brownfield project to spec-driven development. | ["Read", "Grep", "Glob", "Bash", "Write"] | yes |
| typescript-reviewer | Expert TypeScript/JavaScript reviewer: type safety, async correctness, security, and idiomatic patterns. Use for all TS/JS code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |

## Skills — Repo
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| acli | Compact Jira/Confluence bulk ops + ADF→markdown (~80% token cut). Use when bulk-editing work-items/pages. Thai: 'ย้ายสถานะหลายตัว', 'export JQL'. Don't use for single-ticket reads/creates, config, non-Atlassian trackers. | inline | auto |
| adonisjs-patterns | AdonisJS v5 patterns: IoC, Lucid ORM, Japa, VineJS, middleware, auth guards, ace CLI. Use when building an AdonisJS v5 backend. Don't use for non-AdonisJS frameworks. | inline | auto |
| agent-architecture-audit | Scan 12-layer agent stacks, regression, memory pollution, tool discipline, repair loops. Use when debugging a misbehaving harness (stuck loops, rot). Don't use for code review. | inline | auto |
| ask-matt | Router over the matt-pocock flow: ask, grill, plan, slice, ship. Use when starting non-trivial work, unsure which skill fits. Don't use for known flows. | inline | manual |
| backend-patterns | Backend architecture, API design, and DB optimization for Node.js/Express/Next.js — the kept TS/backend base. Use when building a Node/TS backend. Don't use for Python/Go/Rust backends. | inline | auto |
| codebase-design | Deep-module design vocabulary. Use when designing interfaces, finding deepening opportunities, or placing seams. Don't use for framework patterns (see kbg:<framework>-patterns). | inline | auto |
| codebase-onboarding | Catalogue unfamiliar codebases into an onboarding guide — architecture, entry points, conventions. Use when joining or taking over a project. Don't use for single-file lookups. | inline | auto |
| context-budget | Scan context-window consumption across agents/skills/MCP/rules; flag bloat + top savings. Use when context feels full or costs climb. Don't use for one-off response trimming. | inline | auto |
| cost-aware-llm-pipeline | Compact LLM-pipeline cost: model routing, prompt caching, retry. Use when designing a multi-model pipeline where cost/latency matter. Don't use for single calls or prompting tips. | inline | auto |
| create-jira-ticket | Build a single Jira Bug/Story from the Thai PO/QA template. Use when the user says 'สร้างบั๊ก'/'สร้าง story'. Don't use for triage, bulk, edits, or non-Jira. | inline | auto |
| decide | Doctrine-backed decision support, clarify scope, stress-test reasoning, pick among defensible options (probe/decide/strategize). Use when facing a non-trivial choice. Don't use for obvious or already-decided calls. | inline | auto |
| diagnosing-bugs | Diagnosis loop for hard bugs and perf regressions. Use when the user says 'debug' or reports something not behaving. Don't use for trivial typos. | inline | auto |
| domain-modeling | Build and sharpen a project's domain model and ubiquitous language. Use when pinning down domain concepts. Don't use for one-off vocabulary lookups. | inline | auto |
| drizzle-patterns | Drizzle ORM patterns: schema, type inference, migrations, query builder, relations, transactions. Use when building Drizzle apps on PostgreSQL/SQLite. Don't use for Prisma or TypeORM. | inline | auto |
| effect-ts-patterns | Effect-ts patterns: Effect<A,E,R>, Effect.gen, Layer DI, Schema validation, fiber concurrency, @effect/platform HTTP. Use when building/maintaining Effect-ts apps in TypeScript. Don't use for vanilla Promise/async codebases. | inline | auto |
| eval-harness | Eval-driven development (EDD) framework for Claude Code. Use when setting up EDD, building graders, or measuring AI-assisted workflow quality. Don't use for end-user feature work. | inline | auto |
| fastapi-patterns | FastAPI patterns: structure, Pydantic v2, dependency injection, async handlers, auth, service layers. Use when building FastAPI apps. Don't use for non-FastAPI backends (Flask/Django). | inline | auto |
| grilling | Grill-me: walk the design tree one question at a time, each with a recommended answer. Use when stress-testing a plan. Don't use for implementation. | inline | auto |
| grpc-node-patterns | gRPC patterns for Node/Bun: proto, @grpc/grpc-js client/server, TypeScript codegen, streaming, deadlines/metadata. Use when building gRPC services in Node/Bun. Don't use for REST/HTTP or non-Node gRPC. | inline | auto |
| handoff | Compact the current conversation into a handoff document for the next agent. Use when ending a session. Don't use for end-user updates. | inline | manual |
| harness-audit | Single harness-state surface with two modes. Default mode runs a deterministic fleet/schema/structural audit across the kbg-harness plugin. --health mode surfaces per-session token cost from the live cost ledger (formerly kbg:harness-health). Use when running a harness audit or querying session token cost. Thai: 'audit harness', 'ตรวจ harness', 'harness health', 'สุขภาพ harness'. Don't use for: general repo lint or security audits (kbg:security-auditor). | inline | auto |
| hono-patterns | Hono patterns: typed routing, Zod validation, middleware, RPC client, context vars. Use when building Hono services on Bun/Node. Don't use for Express, Fastify, or NestJS. | inline | auto |
| improve-codebase-architecture | Scan a codebase for deepening opportunities and grill through one. Use when the user wants to prioritise architecture deepening. Don't use for routine features. | inline | manual |
| incident | Incident: run a production incident incl. hotfix. Use when alerts fire or user asks for hotfix. Thai: 'เหตุฉุกเฉิน'. Don't use for non-prod bugs or post-mortem. | inline | auto |
| inventory | Catalogue loadable skills/agents/commands/hooks + the escape hatch. Use when stuck on routing. Thai: 'หา skill ไหนเหมาะ'. Don't use for single-layer lists or governance health. | inline | auto |
| langchain-langgraph-patterns | LangChain + LangGraph patterns: StateGraph agents, checkpointing, human-in-the-loop, tool calling, streaming, RAG, tracing. Use when building LangChain/LangGraph agents. Don't use for non-LangChain LLM frameworks. | inline | auto |
| latency-critical-systems | Diagnosis + design for latency-sensitive systems, realtime dashboards, market data, streaming, queues, caches, HFT-like infra. Use when designing/reviewing/debugging them. Don't use for batch or offline. | inline | auto |
| learn | Catalogue durable session learnings; save as memory after an AskUserQuestion gate. Use when asked to capture learnings. Don't use for single known memories or self-improvement. | inline | auto |
| memory-lint | Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health. | inline | auto |
| mysql-patterns | MySQL/MariaDB schema, query, indexing, transaction, replication, and pool patterns. Use when designing or troubleshooting MySQL/MariaDB. Don't use for non-MySQL databases (see kbg:postgres-patterns). | inline | auto |
| orchestrate | Triage competing tasks and route each to inline/parallel/sequential/drop. Use when the user lists tasks or says 'จัดสรรงาน'. Don't use for single-issue triage or PR review. | inline | auto |
| production-audit | Scan production readiness pre-launch. Use when asked whether an app is ready to ship. Don't use for in-flight feature work (use /ship-change). | inline | auto |
| prototype | Build throwaway terminal or UI prototypes to answer a question. Use when the user wants a quick prototype. Don't use for production code. | inline | manual |
| python-patterns | Pythonic idioms, PEP 8, and type hints. Use when writing or reviewing Python for idiomatic style. Don't use for framework-specific Python (use kbg:fastapi-patterns). | inline | auto |
| recursive-improve | Cage: human-gated, anti-unattended harness loop. Use when the user asks to improve or audit the harness. Don't use for bug fixes or new surfaces. | inline | manual |
| review-pr | Scan PRs across quality, tests, security, types, a11y via multi-agent review. Use when a PR is ready. Don't use for quick diffs or single PRs. | inline | auto |
| score-decision | Score pending decisions on weighted criteria: numeric verdict, pass/fail, confidence, trace. Use when a decision needs a verdict. Don't use for trivial or already-decided choices. | inline | manual |
| security-auditor | Scan security vulnerabilities, threat-model + remediation (auth, secrets, injection, XSS, traversal). Use when PRs touch auth/APIs/payments/deps. Don't use for quick branch checks or code review. | inline | auto |
| setup-matt-pocock-skills | Build the matt-pocock skill setup once: map to your project (tracker, labels, ADR format). Use when onboarding. Don't use for re-running on an already-configured repo. | inline | manual |
| ship-change | Slice a scoped change (add/fix/refactor/build-MVP) through classify→implement→review→merge. Use when a change is scoped and ready to sequence. Don't use for blank-slate discovery or one-line fixes. | inline | auto |
| tauri-v2-patterns | Tauri v2 desktop app patterns: IPC, capabilities/permissions, state, events, plugins, tauri.conf.json. Use when building or upgrading a Tauri v2 app. Don't use for Tauri v1. | inline | auto |
| tdd | Test-driven development — write the failing test first. Use when the user mentions red-green-refactor or wants integration tests. Don't use for refactors without behaviour change. | inline | auto |
| teach | Teach the user a new skill over multiple sessions. Use when the user asks to learn a topic. Don't use for one-shot factual questions. | inline | manual |
| to-issues | Slice a plan into vertical slices through every layer. Use when a plan is ready to publish as ticket-size tasks. Don't use for status updates. | inline | manual |
| to-prd | Synthesise-seam: turn a prior discussion into a published PRD without re-interviewing. Use when the user asks for a PRD. Don't use for undecided scope. | inline | manual |
| triage | Triage state machine: categorise, verify, grill if needed, write agent briefs. Use when new issues/PRs arrive. Don't use for implementation or non-triage comments. | inline | manual |
| writing-great-skills | Doctrine for writing skills — leading words, no-op test, completion criteria, two cuts. Use when authoring skill files. Don't use for writing application code. | inline | manual |

## Hooks — Repo
| Hook | Purpose |
|---|---|
| hooks.json | — |

## Output styles — Repo
| Style | Description |
|---|---|
| senior-eng | Senior-engineering register for daily terminal work: friendly, direct, and always on-point. Lead with conclusions, state the strongest reason, prefer plain English, and use structure only when it carries information. Escalate to staff-eng when ownership, cross-team boundaries, or long-term consequences matter. |
| staff-eng | Organization-scale technical lead register for cross-boundary decisions and long-term consequences: decisive, systems-minded, and teaching-oriented. Lead with the decision plus the constraint that shaped it, name systems and owners, and leave the user with a reusable frame. Use via /style or when senior-eng escalates. |

---
_Generated: 2026-06-30T17:02:47Z_

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
- **Total waves:** 3-5. More = plan is too coarse; fewer = use `/ship-task` (single-agent) instead.
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

Canonical file patterns per agent. Assign each file to exactly one agent in an `orchestrate` dispatch plan to prevent silent overwrites.

| Agent | Canonical file patterns | Notes |
|---|---|---|
| `api-doc-specialist` | `openapi/`, `docs/api/`, `sdk/`, `swagger/` | |
| `backend-engineer` | `api/`, `middleware/`, `models/`, `routes/`, `services/`, `tests/` | |
| `code-architect` | `CLAUDE.md (doctrine home) `, `architecture/`, `*.md` (design docs) | Blueprints, not implementation |
| `Explore` | any file | Read-only trace |
| `code-reviewer` | any file | Read-only review (carries comment-accuracy / type-design / test-coverage / UX lenses) |
| `compliance-engineer` | `docs/compliance/`, `policies/`, `data-retention/`, `gdpr/`, `hipaa/` | |
| `data-engineer` | `migrations/`, `etl/`, `analytics/`, `warehouse/`, `dbt/`, `spark/` | Beyond OLTP |
| `devops-engineer` | `.github/`, `docker/`, `k8s/`, `terraform/`, `helm/`, `ci/` | |
| `finops-engineer` | `infra/cost/`, `budgets/`, `docs/finops/` | Read-only + Bash for cost queries |
| `frontend-engineer` | `src/components/`, `src/pages/`, `styles/`, `public/`, `assets/`, `src/hooks/` | |
| `i18n-specialist` | `locales/`, `translations/`, `i18n/`, `src/i18n/`, `l10n/` | |
| `refactor-cleaner` | any file | Refactor / deprecation scope |
| `ml-engineer` | `ml/`, `models/`, `features/`, `pipelines/`, `serving/`, `inference/` | |
| `mobile-engineer` | `ios/`, `android/`, `mobile/`, `react-native/`, `flutter/` | |
| `platform-engineer` | `platform/`, `proto/`, `gateway/`, `mesh/`, `grpc/`, `event-bus/` | |
| `product-analyst` | `docs/requirements/`, `prd/`, `user-stories/` | Read-only + Bash |
| `researcher` | any file | Read-only research |
| `security-reviewer` | `auth/`, `secrets/`, `config/`, `security/`, `iam/`, `crypto/` | Read-only audit |
| `silent-failure-hunter` | any file | Read-only error-handling audit |
| `technical-writer` | `docs/`, `README*`, `CHANGELOG*`, `*.md`, `guides/`, `runbooks/` | |
| `test-engineer` | `tests/`, `*.test.*`, `*.spec.*`, `test_*.py`, `e2e/`, `integration/` | |


---

## Cross-references

- **[Agent tool patterns: allowlist vs denylist](../../docs/agent-tool-patterns.md)** — kbg-harness convention is `tools:` (allowlist) for new agents; reserve `disallowedTools:` (denylist) for cases where the allowlist would exceed 6-7 tools or the team explicitly opts into implicit-inheritance. The `Mutates` column above reflects `Edit`/`Write`/`Bash` grants.
- **[@0xCodez 14-step harness roadmap](https://x.com/0xCodez/article/2066867539305459732)** — external framing (2026-06-16): harness → loop → self-improving system. Useful for onboarding; kbg keeps the 3-floor vocabulary but rejects the article's L3/L4 unattended-loop conclusion per the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model. Keep/discard analysis is in [[0xcodez-harness-roadmap]] memory.
- **[Sydney Runkle — The Art of Loop Engineering](https://x.com/sydneyrunkle/article/2066928783534289358)** — LangChain's 4-loop stack: agent loop, verification loop, event-driven loop, hill-climbing loop (2026-06-16). Good vocabulary for L1/L2 + human-in-the-loop; kbg rejects the L3/L4 unattended conclusion per the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model. Keep/discard analysis is in [[sydney-runkle-loop-engineering]] memory.

---

## Repo context

Module map + verification recipe for the harness. Inject these conventions when a freshly spawned subagent needs the same onboarding map the lead already holds.

### Module Boundaries
- `agents/` — 29 senior-specialist agents
- `skills/` — 28 workflow skills
- `commands/` — 13 slash commands
- `hooks/` — 49 hook scripts
- `output-styles/` — 2 output styles (senior-eng default, staff-eng opt-in)
- `themes/` — 0 themes (deliberate non-goal)
- `eval/` — dataset + regression gate

### Quick Context
- **Stack:** Bash + Python 3 + jq; kbg-harness is a Claude Code plugin (version in `.claude-plugin/plugin.json`)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** `bash "${KBG_PLUGIN_ROOT}/tests/hooks/runners/test-critical-hooks.sh"` (expect 0 failures)
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/kobig/kbg/<version>/` (rebuilt on `claude plugin update kbg@kobig`)

### Verification
- `bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" "${KBG_PLUGIN_ROOT}"` — 0C/0W expected (INFO findings are non-blocking)
- `claude plugin validate --strict "${KBG_PLUGIN_ROOT}"` — exit 0
- `bash "${KBG_PLUGIN_ROOT}/tests/hooks/runners/test-critical-hooks.sh"` — expect 0 failures
- `python3 "${KBG_PLUGIN_ROOT}/eval/run-eval.py" --dataset "${KBG_PLUGIN_ROOT}/eval/datasets/" --regression --gate` — exit 0

---

## Trigger phrases

Map user intent → harness dispatch. Use these trigger phrases in `commands/`, `skills/`, and agent `description:` frontmatter so the orchestrator nudge (`hooks/orchestrator-nudge.sh`) routes correctly.

### Decisions & debate
| User says | Dispatch | Why |
|---|---|---|
| "pros and cons", "which is better", "should we use X or Y" | `kbg:decide` debate mode | Advocate + Skeptic + Synthesizer debate |
| "what should I work on", "prioritize these", "plan this pile of work" | `kbg:orchestrate` skill | Prioritize + route to cheapest correct executor |

### Single-task workflows
| User says | Dispatch | Why |
|---|---|---|
| "build one feature", "implement X" | `/ship-task` | Single-agent ceremony |
| "fix this bug", "debug this" | `/fix-bug` | Bug ceremony |
| "address review feedback" | `/address-review` | PR review response |
| "ship it", "merge this" | `/ship-merge` | Pre-merge gate |
| "release now", "cut a release" | `/ship-release` | Release ceremony |

### Research & analysis
| User says | Dispatch | Why |
|---|---|---|
| "research this", "deep dive on X", "how does Y work" | `/deep-dive` | Brain dump + Q&A + plan |
| "review this PR", "check this code" | `kbg:review-pr` skill | Multi-lens PR review |
| "audit the harness", "check health" | `kbg:harness-audit` skill | Self-audit |

### Incident & post-mortem
| User says | Dispatch | Why |
|---|---|---|
| "incident", "alerts firing", "monitors red" | `kbg:incident` skill | Live incident response |
| "post-mortem", "writeup after incident" | `/post-mortem` | Incident documentation |
| "status update", "what did we ship" | `/status-update` | Status report |


---

## Reference docs

These files live in the plugin cache, not the project CWD. Read them via Bash with `KBG_PLUGIN_ROOT` (exported by `hooks/session/command-root-anchor.sh`), not as relative markdown links.

- **Reasoning-models catalog** — `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` — 39 vendored cc-thinking-skills mental models and the kbg surface that applies (or deliberately does not apply) each.
- **Vendored thinking-skills library** — `cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/README.md"` — verbatim upstream copies of the 39 mental-model SKILL.md files, kept under `docs/` so they are never auto-discovered as invokable skills.

