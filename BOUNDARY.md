# Boundary Map
_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: `bash <kbg-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md` where `<kbg-harness>` is the kbg-harness repo root and `<dotfiles>` is the target repo root (or from the plugin cache: `bash ~/.claude/plugins/cache/kobig/kbg/$(ls ~/.claude/plugins/cache/kobig/kbg/ | sort -V | tail -1)/skills/inventory/scripts/inventory-boundary.sh --repo-only`)._
_Schema version: v3 (adds Output styles table; Mutates column reflects Edit/Write/Bash grant)._
# Inventory
_Legend: ◇ plugin-delivered / project-local_

## Source: Personals/kbg-harness
_Personals/kbg-harness_

### Skills (137)
  ◇ acli                           Use when handling bulk Jira work-item operations and Confluence space/page/blog management from the terminal. Covers transitions, labels, assignments, comments, clones, archives, bulk-edit fields, JQL exports. Thai: 'ย้ายสถานะหลายตัว', 'แก้ label/assignee หลายรายการ', 'อัปเดตหลาย ticket', 'export JQL'. For creating a single Thai-format Bug or Story with guided AC, use kbg:create-jira-ticket instead. Don't use for single-ticket reads, JQL syntax help, install/config/auth, cheat sheets, GitHub/GitLab, or non-Atlassian trackers.
  ◇ adonisjs-patterns              AdonisJS v5 patterns: IoC container, Lucid ORM (ActiveRecord), Japa tests, VineJS validation, middleware, auth guards, and ace CLI commands.
  ◇ agent-architecture-audit       12-layer agent stack diagnostic. Audits wrapper regression, memory pollution, tool discipline failures, and repair loops. Produces severity-ranked findings.
  ◇ agent-eval                     Head-to-head comparison of coding agents (Claude Code, Aider, Codex, etc.) on custom tasks with pass rate, cost, time, and consistency metrics
  ◇ agent-harness-construction     Design and optimize AI agent action spaces, tool definitions, and observation formatting for higher completion rates.
  ◇ agent-self-evaluation          Self-evaluation after completing your own task: scores YOUR output on 5 axes (accuracy, completeness, clarity, actionability, conciseness), 1-5 scorecard + improvements. To evaluate ANOTHER agent's output use the agent-evaluator agent.
  ◇ agent-sort                     Sort ECC surfaces into DAILY vs LIBRARY buckets for a repo. Use to trim ECC to what a project actually needs.
  ◇ agentic-engineering            Operate as an agentic engineer using eval-first execution, decomposition, and cost-aware model routing.
  ◇ angular-developer              Angular code generation and architecture guidance. Covers signals, forms, DI, routing, SSR, accessibility, animations, and CLI tooling.
  ◇ api-design                     REST API design patterns including resource naming, status codes, pagination, filtering, error responses, versioning, and rate limiting for production APIs.
  ◇ architecture-decision-records  Capture architectural decisions as structured ADRs. Auto-detects decision moments, records context, alternatives, and rationale. Maintains an ADR log.
  ◇ ask-matt                       Ask which skill or flow fits your situation. A router over the user-invoked skills in this repo.
  ◇ autonomous-loops               Patterns and architectures for autonomous Claude Code loops — from simple sequential pipelines to RFC-driven multi-agent DAG systems.
  ◇ backend-patterns               Backend architecture patterns, API design, database optimization, and server-side best practices for Node.js, Express, and Next.js API routes.
  ◇ benchmark                      Use this skill to measure performance baselines, detect regressions before/after PRs, and compare stack alternatives.
  ◇ browser-qa                     Use this skill to automate visual testing and UI interaction verification using browser automation after deploying features.
  ◇ bun-runtime                    Bun as runtime, package manager, bundler, and test runner. When to choose Bun vs Node, migration notes, and Vercel support.
  ◇ clarify-first                  Ask the structured 3-step question (analyze, recommend, ask) BEFORE dispatching write-capable agents or starting multi-file changes where a wrong assumption wastes work. Trigger when a task is named but scope is unstated — 'fix the bug', 'refactor X', 'add Y', 'make it faster' with no file/metric/layer; or it spans subsystems with no clear boundary. Thai: 'clarify ก่อน', 'ถามก่อนเริ่ม', 'scope ยังไงดี', 'ยังไม่ชัดเจน'. Don't use for: explicit file paths, single-value changes, read-only requests, or rhetorical questions.
  ◇ code-tour                      Create CodeTour .tour files: persona-targeted walkthroughs with real file and line anchors. For onboarding, architecture, PR, and RCA tours.
  ◇ codebase-design                Deep-module design vocabulary. Use when designing interfaces, finding deepening opportunities, placing seams, or making code more testable.
  ◇ codebase-onboarding            Analyze an unfamiliar codebase and generate a structured onboarding guide with architecture map, key entry points, and conventions.
  ◇ coding-standards               Baseline cross-project coding conventions for naming, readability, immutability, and code-quality review. Use detailed frontend or backend skills for framework-specific patterns.
  ◇ context-budget                 Audits Claude Code context window consumption across agents, skills, MCP servers, and rules. Identifies bloat, redundant components, and produces prioritized token-savings recommendations.
  ◇ cost-aware-llm-pipeline        Cost optimization patterns for LLM API usage — model routing by task complexity, budget tracking, retry logic, and prompt caching.
  ◇ cpp-coding-standards           C++ coding standards based on the C++ Core Guidelines (isocpp.github.io). Use when writing, reviewing, or refactoring C++ code to enforce modern, safe, and idiomatic practices.
  ◇ cpp-testing                    Use only when writing/updating/fixing C++ tests, configuring GoogleTest/CTest, diagnosing failing or flaky tests, or adding coverage/sanitizers.
  ◇ create-jira-ticket             Create a single Jira Bug or Story using the team's Thai PO/QA-readable template. Use when the user says 'create bug'/'create story', 'report a bug', 'file a Jira bug', 'new Jira story', 'write a story', 'สร้างบั๊ก', 'แจ้งบั๊ก', 'เปิดบั๊ก', 'เปิดตั๋วบั๊ก', 'สร้าง story', 'เปิด story', 'เขียน story', 'ออก ticket bug', 'ออก story', or wants a structured Thai ticket. Don't use for: de-duping/triaging before filing (use atlassian:triage-issue), converting a spec/Confluence page to a backlog (use atlassian:spec-to-backlog), bulk creation (use acli), editing an existing ticket (use acli), technical tasks without PO-facing AC (use acli), security incidents (use kbg:incident), or non-Jira trackers.
  ◇ critical-eval                  Stress-test reasoning in arguments, PRs, ADRs, RFCs, incidents, decisions. Use when asked to critique, evaluate reasoning, check assumptions, stress-test arguments, review logic, verify it holds up, or when something feels off. Thai: 'ตรวจ reasoning', 'stress test ข้อโต้แย้ง', 'เช็คสมมติฐาน', 'ดู logic นี้'. Flag overconfident plans (definitely safe, zero downtime). Don't use for: adversarial review of error-handling/fallback code paths (defer to silent-failure-hunter), system dynamics/architecture trade-offs (kbg:backend-dev/code-architect), code review (kbg:review-pr), security audit (kbg:security-auditor), or research (/deep-dive).
  ◇ dart-flutter-patterns          Dart/Flutter production patterns: null safety, state management (BLoC, Riverpod, Provider), GoRouter, Dio, Freezed, and clean architecture.
  ◇ database-migrations            Database migration best practices for schema changes, data migrations, rollbacks, and zero-downtime deployments across PostgreSQL, MySQL, and common ORMs (Prisma, Drizzle, Kysely, Django, TypeORM, golang-migrate).
  ◇ decide                         Judgment Ladder decision support. Modes: probe (analyze before committing), decide (5-rung ladder), strategize (irreversible choices). Produces a decision record.
  ◇ deep-research                  Multi-source deep research: web search, synthesis, and cited reports with source attribution. Use when thorough research with evidence is needed.
  ◇ deployment-patterns            Deployment workflows, CI/CD pipeline patterns, Docker containerization, health checks, rollback strategies, and production readiness checklists for web applications.
  ◇ diagnosing-bugs                Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow.
  ◇ django-patterns                Django architecture patterns, REST API design with DRF, ORM best practices, caching, signals, middleware, and production-grade Django apps.
  ◇ django-security                Django security best practices, authentication, authorization, CSRF protection, SQL injection prevention, XSS prevention, and secure deployment configurations.
  ◇ django-tdd                     Django testing strategies with pytest-django, TDD methodology, factory_boy, mocking, coverage, and testing Django REST Framework APIs.
  ◇ docker-patterns                Docker and Docker Compose patterns for local development, container security, networking, volume strategies, and multi-service orchestration.
  ◇ documentation-lookup           Host-model skill for current library/framework docs via Context7 MCP: resolve-library-id → query-docs → answer. For a fresh-context isolated lookup spawn the docs-lookup agent instead.
  ◇ domain-modeling                Build and sharpen a project's domain model, ubiquitous language, and terminology. Use when pinning down domain concepts or maintaining the model.
  ◇ dotnet-patterns                Idiomatic C# and .NET patterns, conventions, dependency injection, async/await, and best practices for building robust, maintainable .NET applications.
  ◇ drizzle-patterns               Drizzle ORM patterns: schema definition, type inference, drizzle-kit migrations, query builder, relations, transactions, and prepared statements for PostgreSQL/SQLite.
  ◇ dynamic-workflow-mode          Design task-local harnesses, eval gates, and reusable skill extraction for Claude dynamic workflow mode and other adaptive agent harnesses.
  ◇ e2e-testing                    Playwright E2E testing patterns, Page Object Model, configuration, CI/CD integration, artifact management, and flaky test strategies.
  ◇ effect-ts-patterns             Effect-ts patterns: Effect<A,E,R> type, Effect.gen, Layer DI, Schema validation, fiber concurrency, and @effect/platform HTTP. For typed-effect-system codebases.
  ◇ error-handling                 Patterns for robust error handling across TypeScript, Python, and Go. Covers typed errors, error boundaries, retries, circuit breakers, and user-facing error messages.
  ◇ eval-harness                   Formal evaluation framework for Claude Code sessions implementing eval-driven development (EDD) principles
  ◇ fastapi-patterns               FastAPI best practices covering project structure, Pydantic v2 schemas, dependency injection, async handlers, authentication, authorization, transactional service layers, and testing with httpx and pytest.
  ◇ flutter-dart-code-review       Flutter/Dart review checklist: widget best practices, state management (BLoC, Riverpod, Provider, GetX, MobX, Signals), Dart idioms, and architecture.
  ◇ frontend-a11y                  Accessibility patterns for React and Next.js: semantic HTML, ARIA, form labeling, keyboard navigation, focus management, and screen reader support.
  ◇ frontend-patterns              Frontend development patterns for React, Next.js, state management, performance optimization, and UI best practices.
  ◇ gateguard                      Fact-forcing gate that blocks Edit/Write/Bash until concrete investigation of importers, schemas, and context is complete. +2.25 point quality lift.
  ◇ git-workflow                   Git workflow patterns including branching strategies, commit conventions, merge vs rebase, conflict resolution, and collaborative development best practices for teams of all sizes.
  ◇ github-ops                     GitHub operations via gh CLI: issue triage, PR management, CI/CD, releases, and security monitoring. Use for any GitHub task beyond git.
  ◇ goal-spec                      Before a multi-step loop: writes PROMPT.md goal spec (Goal, Done-when, Never-touch, Stop-if) to anchor agent behavior.
  ◇ golang-patterns                Idiomatic Go patterns, best practices, and conventions for building robust, efficient, and maintainable Go applications.
  ◇ golang-testing                 Go testing patterns including table-driven tests, subtests, benchmarks, fuzzing, and test coverage. Follows TDD methodology with idiomatic Go practices.
  ◇ grilling                       Relentless interview to stress-test a plan or design. Modes: basic (default, interview only) or with-docs (also produces ADRs + domain glossary).
  ◇ grpc-node-patterns             gRPC patterns for Node.js and Bun: proto definition, @grpc/grpc-js client and server, TypeScript codegen, streaming, error codes, and deadlines/metadata.
  ◇ handoff                        Compact the current conversation into a handoff document for another agent to pick up.
  ◇ harness-audit                  Single harness-state surface with three modes. Default mode runs a deterministic fleet/schema/structural audit across the kbg-harness plugin. --health mode queries the governance journal (formerly kbg:harness-health). --coverage mode renders the 2x2x3 (12-cell) decay grid (formerly kbg:harness-coverage). Use when running a harness audit, querying verdicts/sensors, or asking for the 12-cell coverage view. Thai: 'audit harness', 'ตรวจ harness', 'harness health', 'สุขภาพ harness', 'harness coverage', 'ตาราง 12 cell'. Don't use for: general repo lint or security audits (kbg:security-auditor).
  ◇ harness-nav                    L3 escape hatch for kbg-harness capability discovery. Use when no known skill, command, or agent clearly covers your task — teaches grep recipes to mine BOUNDARY.md, skills/, agents/, commands/ for the right capability. Returns the nearest match or confirms none exists. Thai: 'หา skill', 'navigate', 'skill ไหนเหมาะ', 'มีอะไรช่วยได้'. Don't use for: tasks where the right skill is already known (use it directly), or operational health queries (use kbg:harness-audit --health).
  ◇ hexagonal-architecture         Design, implement, and refactor Ports & Adapters systems with clear domain boundaries, dependency inversion, and testable use-case orchestration across TypeScript, Java, Kotlin, and Go services.
  ◇ hono-patterns                  Hono web framework patterns: typed routing, Zod validation, middleware, RPC client, context variables, and Bun/Node runtime adapters.
  ◇ implement                      Implement a piece of work based on a PRD or set of issues.
  ◇ improve-codebase-architecture  Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick.
  ◇ incident                       Manage a live production incident end-to-end, including the hotfix path when rollback/kill-switch is insufficient. Use when alerts fire, monitors show red, users report widespread issues, error rates spike, or the user asks for a hotfix / P0 fix. Thai: 'incident', 'เหตุฉุกเฉิน', 'production เสีย', 'ระบบล่ม', 'hotfix', 'แก้ด่วน', 'P0'. Do NOT use for: non-production bugs (use /fix-bug), planned maintenance, security incidents requiring special handling (STOP — redirect to security-reviewer first), or post-incident documentation (use /post-mortem after resolution).
  ◇ intent-driven-development      Clarify ambiguous requests into verifiable acceptance criteria before implementation. Targets security, data, migration, and integration changes. Skip for trivial edits or clear implementations.
  ◇ inventory                      Show what Claude Code skills, agents, commands, and hooks are loadable from the current project and global layers. Use when exploring available capabilities or verifying what the kbg@kobig plugin delivered. Thai: 'inventory', 'ดู skill ทั้งหมด', 'มี skill อะไรบ้าง'. Don't use for: a single-layer list (use /skills, /agents, or /hooks), capability routing when a skill is already known (use it directly), or governance health queries (kbg:harness-audit --health). Use inventory for the unified cross-layer view (project-local + global in one render) with plugin-delivered markers.
  ◇ java-coding-standards          Java coding standards for Spring Boot and Quarkus: naming, immutability, Optional, streams, exceptions, generics, CDI, and reactive patterns.
  ◇ knowledge-ops                  Knowledge base management across local files, MCP memory, vector stores, and Git repos. Use to save, sync, deduplicate, or search knowledge.
  ◇ kotlin-coroutines-flows        Kotlin Coroutines and Flow patterns for Android and KMP — structured concurrency, Flow operators, StateFlow, error handling, and testing.
  ◇ kotlin-exposed-patterns        JetBrains Exposed ORM patterns including DSL queries, DAO pattern, transactions, HikariCP connection pooling, Flyway migrations, and repository pattern.
  ◇ kotlin-ktor-patterns           Ktor server patterns including routing DSL, plugins, authentication, Koin DI, kotlinx.serialization, WebSockets, and testApplication testing.
  ◇ kotlin-patterns                Idiomatic Kotlin patterns, best practices, and conventions for building robust, efficient, and maintainable Kotlin applications with coroutines, null safety, and DSL builders.
  ◇ kotlin-testing                 Kotlin testing patterns with Kotest, MockK, coroutine testing, property-based testing, and Kover coverage. Follows TDD methodology with idiomatic Kotlin practices.
  ◇ kubernetes-patterns            Kubernetes workload patterns, resource management, RBAC, probes, autoscaling, ConfigMap/Secret handling, and kubectl debugging for production-grade deployments.
  ◇ langchain-langgraph-patterns   LangChain and LangGraph patterns: StateGraph agents, checkpointing, human-in-the-loop, tool calling, streaming, Pinecone RAG, and LangSmith tracing.
  ◇ latency-critical-systems       Use for latency-sensitive systems such as realtime dashboards, market data, streaming agents, execution gateways, queues, caches, or HFT-like infrastructure where freshness and p95 latency matter.
  ◇ learn                          Mine the current session for durable, reusable learnings — operator corrections, repeated workflows, stated preferences/conventions, decisions with rationale — and, ONLY after an AskUserQuestion approval gate, save the chosen ones as memory files. Use when the user explicitly asks to capture what was learned: 'learn from this session', 'remember how we did this', 'capture these learnings', 'save what you learned', or Thai 'จำไว้', 'เรียนจาก session นี้', 'บันทึกสิ่งที่เรียนรู้'. Don't use for: writing a single memory you already know (just write it directly), harness self-improvement (use kbg:recursive-improve), memory bookkeeping/lint (use kbg:memory-lint / kbg:memory-trim), or unprompted auto-*apply*. A default-ON SessionEnd hook (learn-capture; opt out with KBG_LEARN_CAPTURE=0) passively STAGES candidates to an out-of-repo queue, but nothing is written without your approval here.
  ◇ memory-lint                    Deterministic bookkeeping check for the memory store: catch dangling [[links]], orphaned facts, and index drift. Use after writing, editing, or removing memories. Thai: 'memory lint', 'ตรวจ memory', 'เช็คลิงก์ memory'. Don't use for: writing a memory (just write it), semantic content review, or harness ecosystem health (kbg:harness-audit).
  ◇ memory-trim                    Mechanically archive verbose or closed memory entries while keeping the memory store under its 200-line/25KB load cap. Uses reversible moves, never rm. Use when MEMORY.md is bloated or after a big session. Thai: 'memory trim', 'ย่อ memory', 'archive memory'. Don't use for: semantic memory review, deleting memory permanently, or harness-wide health checks (kbg:harness-audit).
  ◇ mysql-patterns                 MySQL and MariaDB schema, query, indexing, transaction, replication, and connection-pool patterns for production backends.
  ◇ nestjs-patterns                NestJS architecture patterns for modules, controllers, providers, DTO validation, guards, interceptors, config, and production-grade TypeScript backends.
  ◇ nuxt4-patterns                 Nuxt 4 app patterns for hydration safety, performance, route rules, lazy loading, and SSR-safe data fetching with useFetch and useAsyncData.
  ◇ orch-add-feature               Gated pipeline for a net-new capability: research → plan → TDD → review → commit. Delegates each phase to matching ECC agents.
  ◇ orch-build-mvp                 Turn a design or spec doc into a running MVP: slice → scaffold → TDD → review → gated commit.
  ◇ orch-change-feature            Change existing behavior: update tests to new spec, fix implementation to match, review, gated commit. Use when behavior is not broken but should be different.
  ◇ orch-fix-defect                Fix a bug: write a failing regression test, fix to green, review, gated commit. Use when existing behavior is broken.
  ◇ orch-pipeline                  Shared engine for the orch-* skill family: gated Research→Plan→TDD→Review→Commit pipeline, size classifier, agent map. Not invoked directly.
  ◇ orch-refine-code               Behavior-preserving refactor: confirm tests green, restructure, keep green, review, gated commit. Use when structure should improve but behavior must not change.
  ◇ orchestrate                    Prioritize competing tasks, then route each to inline / batch-parallel / pipeline-sequential / drop. Use when the user lists competing tasks, asks 'what should I work on' or 'what's the priority', plans a day/week/sprint, feels overwhelmed, spans independent sub-tasks or sequential phases, or says 'orchestrate', 'จัดสรรงาน', 'ประชุมจัดลำดับ', 'ลำดับความสำคัญ', or 'จัดpriority'. Don't use for: single-issue triage (triage), PR review (kbg:review-pr), one feature (/ship-task), or single-file coding (inline).
  ◇ parallel-execution-optimizer   Parallelize independent work into lanes: batched reads, concurrent agents, isolated worktrees, or verification passes — without write-surface conflicts.
  ◇ postgres-patterns              PostgreSQL database patterns for query optimization, schema design, indexing, and security. Based on Supabase best practices.
  ◇ production-audit               Local-evidence production readiness audit for pre-launch reviews, post-merge checks, and prod-failure questions. No external service.
  ◇ prompt-optimizer               Analyze a draft prompt, diagnose gaps, match ECC components, and output a ready-to-paste optimized prompt. Advisory only.
  ◇ prototype                      Build throwaway prototypes — terminal apps for logic questions, or radically different UI variations on one route.
  ◇ python-patterns                Pythonic idioms, PEP 8 standards, type hints, and best practices for building robust, efficient, and maintainable Python applications.
  ◇ python-testing                 Python testing strategies using pytest, TDD methodology, fixtures, mocking, parametrization, and coverage requirements.
  ◇ react-patterns                 React 18/19 patterns: hooks, server/client boundaries, Suspense, form actions, data fetching, state management, and accessibility. Use when writing or reviewing components.
  ◇ react-performance              React/Next.js performance patterns: 70+ rules across waterfalls, bundle size, server-side, re-render, and micro-perf. Use when optimizing React/Next.js code.
  ◇ react-testing                  React testing with RTL, Vitest/Jest, MSW, and axe. Covers component tests vs E2E decision boundary. Use when writing or fixing React tests.
  ◇ recursive-improve              Bounded human-gated harness-improvement loop. Use when the user explicitly asks to improve or audit the harness, or when verification posture reveals a concrete gap, including 'ปรับปรุง harness', 'recursive improve', 'แก้ harness'. Don't use for: single named bugs (use /fix-bug), new capabilities (use /ship-task), external tool research (use kbg:article-mine), or any self-launching / scheduled / unattended loop (every iteration is human-gated at an AskUserQuestion gate before any mutation).
  ◇ redis-patterns                 Redis data structure patterns, caching strategies, distributed locks, rate limiting, pub/sub, and connection management for production applications.
  ◇ repo-scan                      Cross-stack source code asset audit — classifies every file, detects embedded third-party libraries, and delivers actionable four-level verdicts per module with interactive HTML reports.
  ◇ resolving-merge-conflicts      Use when you need to resolve an in-progress git merge/rebase conflict.
  ◇ review-pr                      Run multi-agent PR review across code quality, tests, comments, errors, security, types, accessibility/UX, and simplification. Use when finishing changes before opening a PR, when a PR is ready, after addressing feedback, or when asked to review changes/aspects. Thai: 'review PR', 'ตรวจ PR', 'ดู PR นี้', 'รีวิว code'. Don't use for: a quick diff review (use /code-review, optionally --fix/--comment/ultra) or a single GitHub PR (use /review), single-file diffs (review inline), security-only audits (kbg:security-auditor), post-merge retrospectives, or invoking a single agent (use Agent tool).
  ◇ rules-distill                  Scan skills to extract cross-cutting principles and distill them into rules — append, revise, or create new rule files
  ◇ rust-patterns                  Idiomatic Rust patterns, ownership, error handling, traits, concurrency, and best practices for building safe, performant applications.
  ◇ rust-testing                   Rust testing patterns including unit tests, integration tests, async testing, property-based testing, mocking, and coverage. Follows TDD methodology.
  ◇ safety-guard                   Use this skill to prevent destructive operations when working on production systems or running agents autonomously.
  ◇ search-first                   Research-before-coding workflow. Search for existing tools, libraries, and patterns before writing custom code. Invokes the researcher agent.
  ◇ security-auditor               Standalone security audit — deep threat-model + remediation for auth, secrets, external input, file uploads, or dependencies. Covers injection, XSS/CSRF/SSRF, path traversal, broken access control, secret leaks, or vulnerable components. Use when PRs touch auth, APIs, admin panels, payments, or dep manifests. Thai: 'ตรวจ security', 'ช่องโหว่', 'security audit', 'เช็คความปลอดภัย'. The security-reviewer agent is the fast flag spawned inside kbg:review-pr — run one, not both. Don't use for: a quick branch-wide security check of pending changes (use /security-review), code review (kbg:review-pr), incidents (kbg:incident), or non-code security (infra, policy).
  ◇ security-review                In-flow security checklist while coding auth, user input, secrets, API endpoints, or payment features. Guides the current change. For a standalone full-codebase threat-model audit use kbg:security-auditor.
  ◇ setup-matt-pocock-skills       Configure this repo for Matt Pocock's engineering skills — issue tracker, triage labels, and doc layout. Run once before first use.
  ◇ ship-change                    Orchestrate an already-scoped change through classify → implement → review → address → merge. Use when the change is understood and needs guided sequencing through /fix-bug, /ship-task, kbg:review-pr, /address-review, and /ship-merge. Thai: 'ship change', 'พร้อม merge', 'ขึ้น production', 'deploy ตัวนี้'. Don't use for: a blank-slate task needing discovery first (use /ship-task), a change already mid-flight (jump straight to the relevant phase command, e.g. /fix-bug to continue or kbg:review-pr if ready for review), one-line fixes, or pure research/exploration.
  ◇ skill-scout                    Search existing local, marketplace, GitHub, and web skill sources before creating a new skill.
  ◇ skill-stocktake                Audit installed skills for quality; supports Quick Scan (changed only) and Full Stocktake modes.
  ◇ springboot-patterns            Spring Boot architecture patterns, REST API design, layered services, data access, caching, async processing, and logging. Use for Java Spring Boot backend work.
  ◇ springboot-security            Spring Security best practices for authn/authz, validation, CSRF, secrets, headers, rate limiting, and dependency security in Java Spring Boot services.
  ◇ springboot-tdd                 Test-driven development for Spring Boot using JUnit 5, Mockito, MockMvc, Testcontainers, and JaCoCo. Use when adding features, fixing bugs, or refactoring.
  ◇ strategic-compact              Suggests manual context compaction at logical intervals to preserve context through task phases rather than arbitrary auto-compaction.
  ◇ swift-concurrency-6-2          Swift 6.2 Approachable Concurrency — single-threaded by default, @concurrent for explicit background offloading, isolated conformances for main actor types.
  ◇ swiftui-patterns               SwiftUI architecture patterns, state management with @Observable, view composition, navigation, performance optimization, and modern iOS/macOS UI best practices.
  ◇ tauri-v2-patterns              Tauri v2 desktop app patterns: IPC commands, capabilities/permissions model, state management, events, plugins, and tauri.conf.json. Covers v2 breaking changes from v1.
  ◇ tdd                            Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests.
  ◇ teach                          Teach the user a new skill or concept, within this workspace.
  ◇ team-agent-orchestration       Run team-based orchestration for agent squads using work items, ownership, agent Kanban, merge gates, and control pane handoffs.
  ◇ terminal-ops                   Evidence-first repo execution. Use when running commands, checking CI failures, or pushing narrow fixes with proof of what was verified.
  ◇ thinking                       On-demand index of 39 mental models. Read before reasoning on any complex, ambiguous, or high-stakes problem to pick the right scaffold.
  ◇ to-issues                      Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices.
  ◇ to-prd                         Turn the current conversation into a PRD and publish it to the project issue tracker — no interview, just synthesis of what you've already discussed.
  ◇ token-budget-advisor           >-
  ◇ triage                         Move issues and external PRs through a state machine of triage roles — categorise, verify, grill if needed, and write agent-ready briefs.
  ◇ verification-loop              A comprehensive verification system for Claude Code sessions.
  ◇ vue-patterns                   Vue.js 3 Composition API, Pinia state, Vue Router, and Nuxt SSR patterns. Activates for Vue, Nuxt, Vite, or Pinia projects.
  ◇ writing-great-skills           Reference for writing and editing skills well — the vocabulary and principles that make a skill predictable.

### Commands (80)
  ◇ address-review                 Triage and respond to existing PR review comments — fetch threads via gh, classify (action/clarify/wontfix/out-of-scope), implement fixes (delegate to /fix-bug), reply per-thread with commit sha, re-request review. Use when a PR has open review threads, after kbg:review-pr returns findings, or user says 'address the review', or when the user says 'แก้ตามรีวิว', 'ตอบรีวิว', 'address review'. Don't use for: doing the review yourself (use kbg:review-pr), pre-PR cleanup, or merging post-approval (use /ship-merge).
  ◇ aside                          Answer a quick side question without interrupting or losing context from the current task. Resume work automatically after answering.
  ◇ build-fix                      Detect the project build system and incrementally fix build/type errors with minimal safe changes.
  ◇ checkpoint                     Create, verify, or list workflow checkpoints after running verification checks.
  ◇ code-review                    Inline code review — local uncommitted changes (no args) or GitHub PR by number/URL. Single-mode, no multi-agent stack. For specialized multi-agent PR review use /review-pr.
  ◇ cost-report                    Generate a local Claude Code cost report from the ECC cost-tracker metrics log.
  ◇ cpp-build                      Fix C++ build errors, CMake issues, and linker problems incrementally. Invokes the cpp-build-resolver agent for minimal, surgical fixes.
  ◇ cpp-review                     Comprehensive C++ code review for memory safety, modern C++ idioms, concurrency, and security. Invokes the cpp-reviewer agent.
  ◇ cpp-test                       Enforce TDD workflow for C++. Write GoogleTest tests first, then implement. Verify coverage with gcov/lcov.
  ◇ deep-dive                      Research a topic thoroughly across codebase, docs, and web, then synthesize findings into a concise actionable brief with sources. This is the single kbg research surface — both user-typed (/deep-dive) and auto-routed. Use when the user says 'research this', 'deep dive on X', 'compare Z approaches', 'how does Y work in this codebase', or any open-ended exploration. Thai: 'research', 'deep dive', 'วิจัย', 'สำรวจ', 'หาข้อมูล', 'compare วิธี', 'ศึกษา'. Don't use for: single-file lookups (just Read it), known answers (ask directly), implementation tasks (use /ship-task or /fix-bug), or security audits (use kbg:security-auditor).
  ◇ dismiss-stale                  Dismiss the sensor-staleness notification for 7 days (writes ~/.claude/state/kbg-staleness-dismissed.json with the current stale-set hash). Use when the user says 'dismiss', 'silence the staleness alert', 'mute the sensor warning', or after a SessionStart injection has been acknowledged. The dismissal is hash-gated: a new sensor going stale re-injects immediately, or when the user says 'ปิดแจ้งเตือน', 'dismiss stale', 'เงียบเซนเซอร์'. Don't use for: removing sensors (decay-cadence), silencing one specific sensor (edit hooks/sensors.json), or auditing why a sensor is stale (run /harness-audit).
  ◇ epic-claim                     Claim an epic issue, stamp coordination state, and sync local ownership.
  ◇ epic-decompose                 Break an epic into task children without creating task branches.
  ◇ epic-publish                   Publish a validated epic update back to the issue and local cache.
  ◇ epic-review                    Mark epic review requested, approved, or changes requested.
  ◇ epic-sync                      Sync epic issue bodies, labels, and local coordination snapshots from GitHub.
  ◇ epic-unblock                   Sweep blocked epic issues and reopen anything whose dependencies are closed.
  ◇ epic-validate                  Validate epic readiness, dependencies, and coordination policy.
  ◇ fastapi-review                 Review a FastAPI application for architecture, async correctness, dependency injection, Pydantic schemas, security, performance, and testability.
  ◇ feature-dev                    Guided feature development with codebase understanding and architecture focus
  ◇ fix-bug                        Guided 7-phase bug-fix workflow with diagnostic and test-first patterns built in. Use when fixing non-trivial bugs with non-obvious root causes, unclear blast radius, or need regression-test pinning, or when the user says 'แก้บั๊ก', 'fix bug', 'debug'. Don't use for: typos/one-line fixes (just fix it), known-cause bugs with obvious fixes (skip ceremony), diagnostic-only loops (use kbg:backend-dev), greenfield TDD (use kbg:backend-dev), or refactors not driven by a bug (spawn maintenance-engineer).
  ◇ flutter-build                  Fix Dart analyzer errors and Flutter build failures incrementally. Invokes the dart-build-resolver agent for minimal, surgical fixes.
  ◇ flutter-review                 Review Flutter/Dart code for idiomatic patterns, widget best practices, state management, performance, accessibility, and security. Invokes the flutter-reviewer agent.
  ◇ flutter-test                   Run Flutter/Dart tests, report failures, and incrementally fix test issues. Covers unit, widget, golden, and integration tests.
  ◇ frame                          Load a lightweight working-frame for the session — dev, review, or research. A posture-setter (how you work), lighter than running a full skill and distinct from output-styles (which set voice). Use when the user says 'dev mode', 'review mode', 'research mode', 'set context', 'switch frame', or 'โหมด dev', 'โหมด review', 'ตั้งโหมด'. Don't use for: running an actual workflow (use the matching skill — /deep-dive, kbg:review-pr, kbg:backend-dev) or changing voice register (use /output-style).
  ◇ go-build                       Fix Go build errors, go vet warnings, and linter issues incrementally. Invokes the go-build-resolver agent for minimal, surgical fixes.
  ◇ go-review                      Comprehensive Go code review for idiomatic patterns, concurrency safety, error handling, and security. Invokes the go-reviewer agent.
  ◇ go-test                        Enforce TDD workflow for Go. Write table-driven tests first, then implement. Verify 80%+ coverage with go test -cover.
  ◇ ideate-search                  Search past /ideate runs by query against the local qmd collection. Use when the user asks to find a previous ideate session, search ideate memory, or says 'ค้นหาไอเดีย', 'ideate search', 'หาไอเดีย'. or when the user says 'ค้นหาไอเดีย', 'ideate search', 'หาไอเดีย'. Don't use for: running a new ideation session (use /ideate), searching the codebase (use /deep-dive), or external web research (use /deep-dive).
  ◇ jira                           Retrieve a Jira ticket, analyze requirements, update status, or add comments. Uses the jira-integration skill and MCP or REST API.
  ◇ kbg-help                       Quick reference card for kbg-harness skills, commands, agents, validation pipeline, and context tiers. Use when the user asks 'help', 'what can you do', 'list skills', 'how do I use kbg', or 'kbg commands', or when the user says 'ช่วยเหลือ', 'มีอะไรบ้าง', 'ใช้ kbg ยังไง'. Don't use for: deep capability discovery (use kbg:harness-nav) or governance journal queries (use kbg:harness-audit --health). One-shot display, read-only.
  ◇ kotlin-build                   Fix Kotlin/Gradle build errors, compiler warnings, and dependency issues incrementally. Invokes the kotlin-build-resolver agent for minimal, surgical fixes.
  ◇ kotlin-review                  Comprehensive Kotlin code review for idiomatic patterns, null safety, coroutine safety, and security. Invokes the kotlin-reviewer agent.
  ◇ kotlin-test                    Enforce TDD workflow for Kotlin. Write Kotest tests first, then implement. Verify 80%+ coverage with Kover.
  ◇ learn-eval                     Extract reusable patterns from the session, self-evaluate quality before saving, and determine the right save location (Global vs Project).
  ◇ learn                          Extract reusable patterns from the current session and save them as candidate skills or guidance.
  ◇ model-route                    Recommend the best model tier for the current task based on complexity, risk, and budget.
  ◇ multi-backend                  Run a backend-focused multi-model workflow for APIs, algorithms, data, and business logic.
  ◇ multi-execute                  Execute a multi-model implementation plan while preserving Claude as the only filesystem writer.
  ◇ multi-frontend                 Run a frontend-focused multi-model workflow for components, layouts, animation, and UI polish.
  ◇ multi-plan                     Create a multi-model implementation plan without modifying production code.
  ◇ multi-workflow                 Run a full multi-model development workflow with research, planning, execution, optimization, and review.
  ◇ orch-add-feature               Orchestrate building a brand-new feature end to end — research, plan, TDD, review, gated commit. Wrapper that kicks off the orch-add-feature skill.
  ◇ orch-build-mvp                 Bootstrap an MVP from a design/spec doc: slice, scaffold, TDD, review, gated commit. Wrapper for the orch-build-mvp skill.
  ◇ orch-change-feature            Change an existing feature to new behavior: update tests, fix impl, review, gated commit. Wrapper for orch-change-feature.
  ◇ orch-fix-defect                Orchestrate fixing a bug — reproduce it as a failing regression test, fix to green, review, gated commit. Wrapper for the orch-fix-defect skill.
  ◇ orch-refine-code               Orchestrate a behavior-preserving refactor — confirm tests green, restructure without changing behavior, keep green, review, gated commit. Wrapper for the orch-refine-code skill.
  ◇ plan-prd                       Generate a lean, problem-first PRD and hand off to /plan for implementation planning.
  ◇ plan                           Restate requirements, assess risks, and create step-by-step implementation plan. WAIT for user CONFIRM before touching any code.
  ◇ pm2                            Analyze a project and generate PM2 service commands for detected frontend, backend, or database services.
  ◇ post-mortem                    Draft a canonical post-mortem for a resolved bug. Requires reproducible trigger, known mechanism, identified patch, and passing validation. Use after /fix-bug completes or when user says 'write post-mortem', 'document this bug', 'incident report', or when the user says 'เขียน post-mortem', 'บันทึกบั๊ก', 'incident report'. Don't use for: in-progress investigations (root cause must be known), hypothetical bugs (no validated fix), or non-technical incidents (use incident response template instead).
  ◇ pr                             Create a GitHub PR from current branch — general-purpose: validates, discovers templates, links PRDs/plans from multiple artifact paths, analyzes changes, pushes. For the PRP-workflow variant use /prp-pr.
  ◇ project-init                   Detect a project's stack and produce a dry-run ECC onboarding plan using the repository's install manifests and stack mappings.
  ◇ prp-commit                     Quick commit with natural language file targeting — describe what to commit in plain English
  ◇ prp-implement                  Execute an implementation plan with rigorous validation loops
  ◇ prp-plan                       Create comprehensive feature implementation plan with codebase analysis and pattern extraction
  ◇ prp-pr                         Create a GitHub PR in the PRPs-agentic-eng workflow: links `.claude/PRPs/` artifacts (reports/plans/prds), discovers templates, analyzes changes, pushes. Use after /prp-commit. For general PRs use /pr.
  ◇ prp-prd                        Interactive PRD generator - problem-first, hypothesis-driven product spec with back-and-forth questioning
  ◇ python-review                  Comprehensive Python code review for PEP 8 compliance, type hints, security, and Pythonic idioms. Invokes the python-reviewer agent.
  ◇ quality-gate                   Run the ECC formatter quality gate for a single file and report remediation steps.
  ◇ react-build                    Fix React build failures (Vite, webpack, Next.js, CRA, esbuild, Bun) — JSX errors, hydration mismatches, boundary failures. Invokes react-build-resolver agent.
  ◇ react-review                   React/JSX code review for hooks, performance, boundaries, accessibility, and security. Invokes react-reviewer (and typescript-reviewer on TSX changes).
  ◇ react-test                     Enforce TDD workflow for React. Write React Testing Library tests first (behavior-focused, accessibility-first), then implement components. Detects Vitest or Jest and verifies coverage targets.
  ◇ refactor-clean                 Safely identify and remove dead code with verification after each change.
  ◇ resume-session                 Load the most recent session file from ~/.claude/session-data/ and resume work with full context from where the last session ended.
  ◇ review-pr                      Multi-agent PR review: code quality, tests, comments, types. Usage: /review-pr [PR-number|URL] [--focus=code|tests|comments|types|errors|simplify]. Reviews current branch PR if no PR specified.
  ◇ rust-build                     Fix Rust build errors, borrow checker issues, and dependency problems incrementally. Invokes the rust-build-resolver agent for minimal, surgical fixes.
  ◇ rust-review                    Comprehensive Rust code review for ownership, lifetimes, error handling, unsafe usage, and idiomatic patterns. Invokes the rust-reviewer agent.
  ◇ rust-test                      Enforce TDD workflow for Rust. Write tests first, then implement. Verify 80%+ coverage with cargo-llvm-cov.
  ◇ save-session                   Save current session state to a dated file in ~/.claude/session-data/ so work can be resumed in a future session with full context.
  ◇ security-scan                  Run AgentShield against agent, hook, MCP, permission, and secret surfaces.
  ◇ ship-merge                     Merge an approved PR safely: validate state, execute server-side merge, clean up branch, monitor CI post-merge. Use when the user says 'merge this PR', 'ship it', or after /address-review or /ship-release reaches the merge gate, or when the user says 'merge PR', 'ship it', 'รวมโค้ด'. Do NOT use for: unapproved PRs (wait for approval), PRs with failing CI (fix first), or hotfixes that need direct push (use kbg:incident hotfix path).
  ◇ ship-release                   Cut a software release end-to-end: version bump → changelog → review gate → tag → merge → monitor. Use when the user says 'ship release', 'cut a release', 'prepare version X.Y.Z', or when a release branch is ready for tagging, or when the user says 'ปล่อยเวอร์ชัน', 'release', 'ship release'. Do NOT use for: one-off PR merges (use /ship-merge), hotfixes (use kbg:incident hotfix path), or when there is no release branch / tag strategy defined.
  ◇ skill-create                   Analyze local git history to extract coding patterns and generate SKILL.md files. Local version of the Skill Creator GitHub App.
  ◇ skill-health                   Show skill portfolio health dashboard with charts and analytics
  ◇ status-update                  Rewrite operator-supplied engineering content for leadership (VPs, directors, PMs) and shape for channel — JIRA, Slack, standup, email, or talking-points. Rewrites text you provide; does NOT fetch from Jira/Confluence. Use when user asks to write/rewrite for management/exec/VP/PM, asks for executive summary / leadership update, or wants a channel-specific version, or when the user says 'สรุปผู้บริหาร', 'status update', 'รายงานผู้บริหาร'. Don't use for: a report generated FROM Jira issues (use atlassian:generate-status-report), technical documentation (defer to technical-writer), tone humanization (use kbg:tech-humanize), or peer-level standup notes.
  ◇ test-coverage                  Analyze coverage, identify gaps, and generate missing tests toward the target threshold.
  ◇ update-codemaps                Scan project structure and generate token-lean architecture codemaps.
  ◇ update-docs                    Sync documentation from source-of-truth files such as scripts, schemas, routes, and exports.
  ◇ vue-review                     Vue.js code review: Composition API, reactivity, composable patterns, template security, accessibility, and performance. Invokes vue-reviewer and typescript-reviewer.

### Agents (55)
  ◇ a11y-architect                 WCAG 2.2 accessibility specialist. Use when designing UI components, establishing design systems, or auditing code for inclusive experiences.
  ◇ agent-evaluator                External evaluator: scores ANOTHER agent's output on 5-axis rubric (accuracy, completeness, clarity, actionability, conciseness), with evidence and VERDICT. For self-evaluation after your own task use kbg:agent-self-evaluation skill.
  ◇ architect                      Software architecture specialist for system design, scalability, and technical decision-making. Use PROACTIVELY when planning new features, refactoring large systems, or making architectural decisions.
  ◇ build-error-resolver           Build and TypeScript error resolver. Fixes build/type errors with minimal diffs when builds fail. No architectural edits — just green builds.
  ◇ chief-of-staff                 Personal communication chief of staff: triages email, Slack, LINE, and Messenger, classifies messages into 4 tiers, generates draft replies.
  ◇ code-architect                 Designs feature architectures by analyzing existing codebase patterns and conventions, then providing implementation blueprints with concrete files, interfaces, data flow, and build order.
  ◇ code-explorer                  Deeply analyzes existing codebase features by tracing execution paths, mapping architecture layers, and documenting dependencies to inform new development.
  ◇ code-reviewer                  Expert code reviewer. Reviews code for quality, security, and maintainability. Use after writing or modifying code.
  ◇ code-simplifier                Simplifies and refines code for clarity, consistency, and maintainability while preserving behavior. Focus on recently modified code unless instructed otherwise.
  ◇ comment-analyzer               Analyze code comments for accuracy, completeness, maintainability, and comment rot risk.
  ◇ conversation-analyzer          Use this agent when analyzing conversation transcripts to find behaviors worth preventing with hooks. Triggered by /hookify without arguments.
  ◇ cpp-build-resolver             C++ build, CMake, and compilation error resolution specialist. Fixes build errors, linker issues, and template errors with minimal changes. Use when C++ builds fail.
  ◇ cpp-reviewer                   Expert C++ reviewer: memory safety, modern idioms, concurrency, and performance. Use for all C++ code changes. MUST BE USED for C++ projects.
  ◇ dart-build-resolver            Dart/Flutter build and dependency error resolver. Fixes dart analyze errors, compilation failures, and pub conflicts with minimal changes. Use when builds fail.
  ◇ database-reviewer              PostgreSQL specialist for query optimization, schema design, security, and performance. Use when writing SQL, creating migrations, or troubleshooting. Includes Supabase best practices.
  ◇ django-build-resolver          Django/Python build and migration error resolver. Fixes pip/Poetry errors, migration conflicts, import errors, and configuration issues. Use when Django fails to start.
  ◇ django-reviewer                Expert Django reviewer: ORM correctness, DRF patterns, migration safety, security misconfigurations, and production-grade practices. MUST BE USED for Django projects.
  ◇ doc-updater                    Documentation and codemap specialist. Use PROACTIVELY for updating codemaps and documentation. Runs /update-codemaps and /update-docs, generates docs/CODEMAPS/*, updates READMEs and guides.
  ◇ docs-lookup                    Spawnable agent for current library/framework/API docs via Context7 MCP. Fresh context, locked tools — use when an isolated doc lookup is needed. For host-model guided lookup use kbg:documentation-lookup skill instead.
  ◇ e2e-runner                     End-to-end testing via Playwright. Generates and runs E2E tests, quarantines flaky tests, and uploads screenshots and traces.
  ◇ fastapi-reviewer               Reviews FastAPI applications for async correctness, dependency injection, Pydantic schemas, security, OpenAPI quality, testing, and production readiness.
  ◇ flutter-reviewer               Flutter/Dart code reviewer covering widget best practices, state management, Dart idioms, performance, accessibility, and architecture. Library-agnostic.
  ◇ go-build-resolver              Go build, vet, and compilation error resolution specialist. Fixes build errors, go vet issues, and linter warnings with minimal changes. Use when Go builds fail.
  ◇ go-reviewer                    Expert Go code reviewer: idiomatic Go, concurrency, error handling, and performance. Use for all Go code changes. MUST BE USED for Go projects.
  ◇ harness-optimizer              Analyze and improve the local agent harness configuration for reliability, cost, and throughput.
  ◇ healthcare-reviewer            Reviews healthcare application code for clinical safety, CDSS accuracy, PHI compliance, medical data integrity — EMR/EHR, clinical decision support, health information systems. Use when reviewing code touching patient data, clinical workflows, HL7/FHIR/DICOM, or HIPAA-relevant surfaces. Thai: 'review healthcare', 'PHI', 'HIPAA', 'EMR', 'ตรวจ healthcare', 'โค้ดการแพทย์', 'ข้อมูลผู้ป่วย'. Don't use for: non-healthcare code, general data privacy only (use compliance-engineer), or actual clinical/medical advice (this reviewer checks code, not clinical correctness). Read-only.
  ◇ ideate-critic                  Fresh-context critic for the /ideate command. Scores, clusters, and deepens divergent ideas produced by ideate Phase 1. Invoked by commands/ideate.md Phase 2 instead of running the critic pass on the host Claude, to reduce LLM-judge-circularity (CLAUDE.md §LLM-judge-circularity). Read-only: scores and reports, never blocks, never mutates the repo. Use when ideate needs a critic pass, or when the user says 'วิจารณ์ไอเดีย', 'critic', 'ตรวจไอเดีย'. Don't use for: code review (code-reviewer), structural diff judgment (inferential-structural-judge), or security audit (security-reviewer).
  ◇ incident-commander             Senior incident commander for production incident response, post-mortems, and error-budget governance. Use when an incident is active, coordinating responders, or when a service breaches its error budget, or when the user says 'incident', 'on-call', 'เหตุการณ์'. Don't use for: infrastructure deployment (defer to devops-engineer), bug fixes (defer to backend-engineer/frontend-engineer), or security breach response (defer to security-reviewer). Owns human coordination and decision timeline during incidents.
  ◇ inferential-structural-judge   Session-end inferential-FB sensor that scores a session's diff on over_engineering, arch_drift, test_pattern, and doctrine_conformance. Use when the SessionEnd hook fires and the session touched files, or when the user says 'ตัดสินโครงสร้าง', 'structural judge', 'verdict'. Journals an advisory verdict to governance-events.jsonl; never blocks or mutates code. Don't use for: deep PR review (use kbg:review-pr), security audit (defer to security-reviewer), test coverage (defer to pr-test-analyzer), or live diff review (defer to code-reviewer).
  ◇ java-build-resolver            Java/Maven/Gradle build error resolver for Spring Boot and Quarkus. Fixes build errors, compiler errors, and dependency issues. Use when Java builds fail.
  ◇ java-reviewer                  Expert Java reviewer for Spring Boot and Quarkus: layered architecture, JPA/Panache, MongoDB, security, and concurrency. MUST BE USED for all Java changes.
  ◇ kotlin-build-resolver          Kotlin/Gradle build, compilation, and dependency error resolution specialist. Fixes build errors, Kotlin compiler errors, and Gradle issues with minimal changes. Use when Kotlin builds fail.
  ◇ kotlin-reviewer                Kotlin and Android/KMP code reviewer. Reviews Kotlin code for idiomatic patterns, coroutine safety, Compose best practices, clean architecture violations, and common Android pitfalls.
  ◇ loop-operator                  Operate autonomous agent loops, monitor progress, and intervene safely when loops stall.
  ◇ mle-reviewer                   ML engineering reviewer for data contracts, feature pipelines, training reproducibility, model serving, and monitoring. Use when ML or MLOps code changes.
  ◇ network-architect              Designs enterprise or multi-site network architecture from requirements — read-only planner for campus/WAN/DC/hybrid topology, addressing, segmentation, capacity planning. Use when planning multi-site networks, choosing routing protocols, designing addressing schemes, or scoping network changes. Defers detail implementation to focused skills (kbg:cisco-ios-patterns, kbg:network-bgp-diagnostics, kbg:homelab-network-setup). Thai: 'ออกแบบ network', 'network architecture', 'campus network', 'WAN design'. Don't use for: BGP debugging (use kbg:network-bgp-diagnostics), Cisco-IOS specifics (use kbg:cisco-ios-patterns), homelab (use kbg:homelab-network-setup), troubleshooting (use network-troubleshooter), or live config changes. Read-only.
  ◇ network-troubleshooter         Diagnoses network connectivity, routing, DNS, interface, and policy symptoms with a read-only OSI-layer workflow and evidence-backed root cause summary. Use when troubleshooting connectivity loss, packet loss, routing loops, DNS resolution failures, ACL/firewall blocks, BGP neighbor issues, or interface flaps. Thai: 'แก้ network', 'troubleshoot network', 'BGP down', 'packet loss'. Don't use for: architecture design (use network-architect), live config changes (read-only), or host/application issues unrelated to network (use infra-engineer or backend-engineer). Never recommend temporarily removing ACLs, firewall rules, authentication, or management-plane restrictions. Read-only.
  ◇ performance-optimizer          Performance optimizer. Identifies bottlenecks, optimizes slow code, reduces bundle sizes, and fixes memory leaks and render issues.
  ◇ planner                        Expert planning specialist for complex features and refactoring. Use PROACTIVELY when users request feature implementation, architectural changes, or complex refactoring. Automatically activated for planning tasks.
  ◇ pr-test-analyzer               Review pull request test coverage quality and completeness, with emphasis on behavioral coverage and real bug prevention.
  ◇ python-reviewer                Expert Python reviewer: PEP 8, Pythonic idioms, type hints, security, and performance. Use for all Python code changes.
  ◇ react-build-resolver           Diagnose and fix React build failures across Vite, webpack, Next.js, CRA, and Bun. Handles compile errors, hydration mismatches, server/client boundary failures, and bundler configuration issues.
  ◇ react-reviewer                 React/JSX reviewer: hook correctness, render performance, server/client boundaries, accessibility, and React security. Use for .tsx/.jsx changes.
  ◇ refactor-cleaner               Dead code cleanup specialist. Uses knip, depcheck, and ts-prune to identify and remove unused code and duplicates.
  ◇ rust-build-resolver            Rust build error resolver. Fixes cargo errors, borrow checker issues, and Cargo.toml problems with minimal changes when builds fail.
  ◇ rust-reviewer                  Expert Rust reviewer: ownership, lifetimes, error handling, unsafe usage, and idiomatic patterns. Use for all Rust code changes.
  ◇ security-reviewer              Security vulnerability detector. Flags secrets, SSRF, injection, unsafe crypto, and OWASP Top 10. Use after writing code handling user input or auth.
  ◇ silent-failure-hunter          Review code for silent failures, swallowed errors, bad fallbacks, and missing error propagation.
  ◇ spec-miner                     Extracts behavioral specs from existing codebases. Produces Requirement and Invariant blocks with structured metadata. Use when onboarding a brownfield project to spec-driven development.
  ◇ swift-build-resolver           Swift/Xcode build and dependency error resolver. Fixes build errors, Xcode failures, SPM issues, and code signing problems. Use when Swift builds fail.
  ◇ swift-reviewer                 Expert Swift reviewer: protocol-oriented design, value semantics, ARC, Swift Concurrency, and idiomatic patterns. Use for all Swift code. MUST BE USED for Swift projects.
  ◇ tdd-guide                      Test-Driven Development specialist enforcing write-tests-first methodology. Use PROACTIVELY when writing new features, fixing bugs, or refactoring code. Ensures 80%+ test coverage.
  ◇ type-design-analyzer           Analyze type design for encapsulation, invariant expression, usefulness, and enforcement.
  ◇ typescript-reviewer            Expert TypeScript/JavaScript reviewer: type safety, async correctness, security, and idiomatic patterns. Use for all TS/JS code changes.
  ◇ vue-reviewer                   Expert Vue.js reviewer: Composition API, reactivity pitfalls, component architecture, template security, and performance. Use for Vue/Pinia/Nuxt changes. MUST BE USED for Vue projects.

### Hooks (1)
  ◇ hooks.json                     (no description)

## Agents — Repo
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| a11y-architect | WCAG 2.2 accessibility specialist. Use when designing UI components, establishing design systems, or auditing code for inclusive experiences. | ["Read", "Write", "Edit", "Grep", "Glob"] | yes |
| agent-evaluator | External evaluator: scores ANOTHER agent's output on 5-axis rubric (accuracy, completeness, clarity, actionability, conciseness), with evidence and VERDICT. For self-evaluation after your own task use kbg:agent-self-evaluation skill. | ["Read", "Grep", "Glob", "Bash"] | yes |
| architect | Software architecture specialist for system design, scalability, and technical decision-making. Use PROACTIVELY when planning new features, refactoring large systems, or making architectural decisions. | ["Read", "Grep", "Glob"] | no |
| build-error-resolver | Build and TypeScript error resolver. Fixes build/type errors with minimal diffs when builds fail. No architectural edits — just green builds. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| chief-of-staff | Personal communication chief of staff: triages email, Slack, LINE, and Messenger, classifies messages into 4 tiers, generates draft replies. | ["Read", "Grep", "Glob", "Bash", "Edit", "Write"] | yes |
| code-architect | Designs feature architectures by analyzing existing codebase patterns and conventions, then providing implementation blueprints with concrete files, interfaces, data flow, and build order. | [Read, Grep, Glob, Bash] | yes |
| code-explorer | Deeply analyzes existing codebase features by tracing execution paths, mapping architecture layers, and documenting dependencies to inform new development. | [Read, Grep, Glob] | no |
| code-reviewer | Expert code reviewer. Reviews code for quality, security, and maintainability. Use after writing or modifying code. | ["Read", "Grep", "Glob", "Bash"] | yes |
| code-simplifier | Simplifies and refines code for clarity, consistency, and maintainability while preserving behavior. Focus on recently modified code unless instructed otherwise. | [Read, Write, Edit, Bash, Grep, Glob] | yes |
| comment-analyzer | Analyze code comments for accuracy, completeness, maintainability, and comment rot risk. | [Read, Grep, Glob] | no |
| conversation-analyzer | Use this agent when analyzing conversation transcripts to find behaviors worth preventing with hooks. Triggered by /hookify without arguments. | [Read, Grep] | no |
| cpp-build-resolver | C++ build, CMake, and compilation error resolution specialist. Fixes build errors, linker issues, and template errors with minimal changes. Use when C++ builds fail. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| cpp-reviewer | Expert C++ reviewer: memory safety, modern idioms, concurrency, and performance. Use for all C++ code changes. MUST BE USED for C++ projects. | ["Read", "Grep", "Glob", "Bash"] | yes |
| dart-build-resolver | Dart/Flutter build and dependency error resolver. Fixes dart analyze errors, compilation failures, and pub conflicts with minimal changes. Use when builds fail. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| database-reviewer | PostgreSQL specialist for query optimization, schema design, security, and performance. Use when writing SQL, creating migrations, or troubleshooting. Includes Supabase best practices. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| django-build-resolver | Django/Python build and migration error resolver. Fixes pip/Poetry errors, migration conflicts, import errors, and configuration issues. Use when Django fails to start. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| django-reviewer | Expert Django reviewer: ORM correctness, DRF patterns, migration safety, security misconfigurations, and production-grade practices. MUST BE USED for Django projects. | ["Read", "Grep", "Glob", "Bash"] | yes |
| doc-updater | Documentation and codemap specialist. Use PROACTIVELY for updating codemaps and documentation. Runs /update-codemaps and /update-docs, generates docs/CODEMAPS/*, updates READMEs and guides. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| docs-lookup | Spawnable agent for current library/framework/API docs via Context7 MCP. Fresh context, locked tools — use when an isolated doc lookup is needed. For host-model guided lookup use kbg:documentation-lookup skill instead. | ["Read", "Grep", "mcp__context7__resolve-library-id", "mcp__context7__query-docs"] | no |
| e2e-runner | End-to-end testing via Playwright. Generates and runs E2E tests, quarantines flaky tests, and uploads screenshots and traces. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| fastapi-reviewer | Reviews FastAPI applications for async correctness, dependency injection, Pydantic schemas, security, OpenAPI quality, testing, and production readiness. | ["Read", "Grep", "Glob", "Bash"] | yes |
| flutter-reviewer | Flutter/Dart code reviewer covering widget best practices, state management, Dart idioms, performance, accessibility, and architecture. Library-agnostic. | ["Read", "Grep", "Glob", "Bash"] | yes |
| go-build-resolver | Go build, vet, and compilation error resolution specialist. Fixes build errors, go vet issues, and linter warnings with minimal changes. Use when Go builds fail. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| go-reviewer | Expert Go code reviewer: idiomatic Go, concurrency, error handling, and performance. Use for all Go code changes. MUST BE USED for Go projects. | ["Read", "Grep", "Glob", "Bash"] | yes |
| harness-optimizer | Analyze and improve the local agent harness configuration for reliability, cost, and throughput. | ["Read", "Grep", "Glob", "Bash", "Edit"] | yes |
| healthcare-reviewer | Reviews healthcare application code for clinical safety, CDSS accuracy, PHI compliance, medical data integrity — EMR/EHR, clinical decision support, health information systems. Use when reviewing code touching patient data, clinical workflows, HL7/FHIR/DICOM, or HIPAA-relevant surfaces. Thai: 'review healthcare', 'PHI', 'HIPAA', 'EMR', 'ตรวจ healthcare', 'โค้ดการแพทย์', 'ข้อมูลผู้ป่วย'. Don't use for: non-healthcare code, general data privacy only (use compliance-engineer), or actual clinical/medical advice (this reviewer checks code, not clinical correctness). Read-only. | Read, Grep, Glob | no |
| ideate-critic | Fresh-context critic for the /ideate command. Scores, clusters, and deepens divergent ideas produced by ideate Phase 1. Invoked by commands/ideate.md Phase 2 instead of running the critic pass on the host Claude, to reduce LLM-judge-circularity (CLAUDE.md §LLM-judge-circularity). Read-only: scores and reports, never blocks, never mutates the repo. Use when ideate needs a critic pass, or when the user says 'วิจารณ์ไอเดีย', 'critic', 'ตรวจไอเดีย'. Don't use for: code review (code-reviewer), structural diff judgment (inferential-structural-judge), or security audit (security-reviewer). | Read | no |
| incident-commander | Senior incident commander for production incident response, post-mortems, and error-budget governance. Use when an incident is active, coordinating responders, or when a service breaches its error budget, or when the user says 'incident', 'on-call', 'เหตุการณ์'. Don't use for: infrastructure deployment (defer to devops-engineer), bug fixes (defer to backend-engineer/frontend-engineer), or security breach response (defer to security-reviewer). Owns human coordination and decision timeline during incidents. | Read, Grep, Glob, Bash, WebSearch | yes |
| inferential-structural-judge | Session-end inferential-FB sensor that scores a session's diff on over_engineering, arch_drift, test_pattern, and doctrine_conformance. Use when the SessionEnd hook fires and the session touched files, or when the user says 'ตัดสินโครงสร้าง', 'structural judge', 'verdict'. Journals an advisory verdict to governance-events.jsonl; never blocks or mutates code. Don't use for: deep PR review (use kbg:review-pr), security audit (defer to security-reviewer), test coverage (defer to pr-test-analyzer), or live diff review (defer to code-reviewer). | Read, Grep, Bash | yes |
| java-build-resolver | Java/Maven/Gradle build error resolver for Spring Boot and Quarkus. Fixes build errors, compiler errors, and dependency issues. Use when Java builds fail. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| java-reviewer | Expert Java reviewer for Spring Boot and Quarkus: layered architecture, JPA/Panache, MongoDB, security, and concurrency. MUST BE USED for all Java changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| kotlin-build-resolver | Kotlin/Gradle build, compilation, and dependency error resolution specialist. Fixes build errors, Kotlin compiler errors, and Gradle issues with minimal changes. Use when Kotlin builds fail. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| kotlin-reviewer | Kotlin and Android/KMP code reviewer. Reviews Kotlin code for idiomatic patterns, coroutine safety, Compose best practices, clean architecture violations, and common Android pitfalls. | ["Read", "Grep", "Glob", "Bash"] | yes |
| loop-operator | Operate autonomous agent loops, monitor progress, and intervene safely when loops stall. | ["Read", "Grep", "Glob", "Bash", "Edit"] | yes |
| mle-reviewer | ML engineering reviewer for data contracts, feature pipelines, training reproducibility, model serving, and monitoring. Use when ML or MLOps code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| network-architect | Designs enterprise or multi-site network architecture from requirements — read-only planner for campus/WAN/DC/hybrid topology, addressing, segmentation, capacity planning. Use when planning multi-site networks, choosing routing protocols, designing addressing schemes, or scoping network changes. Defers detail implementation to focused skills (kbg:cisco-ios-patterns, kbg:network-bgp-diagnostics, kbg:homelab-network-setup). Thai: 'ออกแบบ network', 'network architecture', 'campus network', 'WAN design'. Don't use for: BGP debugging (use kbg:network-bgp-diagnostics), Cisco-IOS specifics (use kbg:cisco-ios-patterns), homelab (use kbg:homelab-network-setup), troubleshooting (use network-troubleshooter), or live config changes. Read-only. | Read, Grep | no |
| network-troubleshooter | Diagnoses network connectivity, routing, DNS, interface, and policy symptoms with a read-only OSI-layer workflow and evidence-backed root cause summary. Use when troubleshooting connectivity loss, packet loss, routing loops, DNS resolution failures, ACL/firewall blocks, BGP neighbor issues, or interface flaps. Thai: 'แก้ network', 'troubleshoot network', 'BGP down', 'packet loss'. Don't use for: architecture design (use network-architect), live config changes (read-only), or host/application issues unrelated to network (use infra-engineer or backend-engineer). Never recommend temporarily removing ACLs, firewall rules, authentication, or management-plane restrictions. Read-only. | Read, Bash, Grep | yes |
| performance-optimizer | Performance optimizer. Identifies bottlenecks, optimizes slow code, reduces bundle sizes, and fixes memory leaks and render issues. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| planner | Expert planning specialist for complex features and refactoring. Use PROACTIVELY when users request feature implementation, architectural changes, or complex refactoring. Automatically activated for planning tasks. | ["Read", "Grep", "Glob"] | no |
| pr-test-analyzer | Review pull request test coverage quality and completeness, with emphasis on behavioral coverage and real bug prevention. | [Read, Grep, Glob, Bash] | yes |
| python-reviewer | Expert Python reviewer: PEP 8, Pythonic idioms, type hints, security, and performance. Use for all Python code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| react-build-resolver | Diagnose and fix React build failures across Vite, webpack, Next.js, CRA, and Bun. Handles compile errors, hydration mismatches, server/client boundary failures, and bundler configuration issues. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| react-reviewer | React/JSX reviewer: hook correctness, render performance, server/client boundaries, accessibility, and React security. Use for .tsx/.jsx changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| refactor-cleaner | Dead code cleanup specialist. Uses knip, depcheck, and ts-prune to identify and remove unused code and duplicates. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| rust-build-resolver | Rust build error resolver. Fixes cargo errors, borrow checker issues, and Cargo.toml problems with minimal changes when builds fail. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| rust-reviewer | Expert Rust reviewer: ownership, lifetimes, error handling, unsafe usage, and idiomatic patterns. Use for all Rust code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| security-reviewer | Security vulnerability detector. Flags secrets, SSRF, injection, unsafe crypto, and OWASP Top 10. Use after writing code handling user input or auth. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| silent-failure-hunter | Review code for silent failures, swallowed errors, bad fallbacks, and missing error propagation. | [Read, Grep, Glob, Bash] | yes |
| spec-miner | Extracts behavioral specs from existing codebases. Produces Requirement and Invariant blocks with structured metadata. Use when onboarding a brownfield project to spec-driven development. | ["Read", "Grep", "Glob", "Bash", "Write"] | yes |
| swift-build-resolver | Swift/Xcode build and dependency error resolver. Fixes build errors, Xcode failures, SPM issues, and code signing problems. Use when Swift builds fail. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| swift-reviewer | Expert Swift reviewer: protocol-oriented design, value semantics, ARC, Swift Concurrency, and idiomatic patterns. Use for all Swift code. MUST BE USED for Swift projects. | ["Read", "Grep", "Glob", "Bash"] | yes |
| tdd-guide | Test-Driven Development specialist enforcing write-tests-first methodology. Use PROACTIVELY when writing new features, fixing bugs, or refactoring code. Ensures 80%+ test coverage. | ["Read", "Write", "Edit", "Bash", "Grep"] | yes |
| type-design-analyzer | Analyze type design for encapsulation, invariant expression, usefulness, and enforcement. | [Read, Grep, Glob] | no |
| typescript-reviewer | Expert TypeScript/JavaScript reviewer: type safety, async correctness, security, and idiomatic patterns. Use for all TS/JS code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| vue-reviewer | Expert Vue.js reviewer: Composition API, reactivity pitfalls, component architecture, template security, and performance. Use for Vue/Pinia/Nuxt changes. MUST BE USED for Vue projects. | ["Read", "Grep", "Glob", "Bash"] | yes |

## Skills — Repo
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| acli | Use when handling bulk Jira work-item operations and Confluence space/page/blog management from the terminal. Covers transitions, labels, assignments, comments, clones, archives, bulk-edit fields, JQL exports. Thai: 'ย้ายสถานะหลายตัว', 'แก้ label/assignee หลายรายการ', 'อัปเดตหลาย ticket', 'export JQL'. For creating a single Thai-format Bug or Story with guided AC, use kbg:create-jira-ticket instead. Don't use for single-ticket reads, JQL syntax help, install/config/auth, cheat sheets, GitHub/GitLab, or non-Atlassian trackers. | inline | auto |
| adonisjs-patterns | AdonisJS v5 patterns: IoC container, Lucid ORM (ActiveRecord), Japa tests, VineJS validation, middleware, auth guards, and ace CLI commands. | inline | auto |
| agent-architecture-audit | 12-layer agent stack diagnostic. Audits wrapper regression, memory pollution, tool discipline failures, and repair loops. Produces severity-ranked findings. | inline | auto |
| agent-eval | Head-to-head comparison of coding agents (Claude Code, Aider, Codex, etc.) on custom tasks with pass rate, cost, time, and consistency metrics | inline | auto |
| agent-harness-construction | Design and optimize AI agent action spaces, tool definitions, and observation formatting for higher completion rates. | inline | auto |
| agent-self-evaluation | Self-evaluation after completing your own task: scores YOUR output on 5 axes (accuracy, completeness, clarity, actionability, conciseness), 1-5 scorecard + improvements. To evaluate ANOTHER agent's output use the agent-evaluator agent. | inline | auto |
| agent-sort | Sort ECC surfaces into DAILY vs LIBRARY buckets for a repo. Use to trim ECC to what a project actually needs. | inline | auto |
| agentic-engineering | Operate as an agentic engineer using eval-first execution, decomposition, and cost-aware model routing. | inline | auto |
| angular-developer | Angular code generation and architecture guidance. Covers signals, forms, DI, routing, SSR, accessibility, animations, and CLI tooling. | inline | auto |
| api-design | REST API design patterns including resource naming, status codes, pagination, filtering, error responses, versioning, and rate limiting for production APIs. | inline | auto |
| architecture-decision-records | Capture architectural decisions as structured ADRs. Auto-detects decision moments, records context, alternatives, and rationale. Maintains an ADR log. | inline | auto |
| ask-matt | Ask which skill or flow fits your situation. A router over the user-invoked skills in this repo. | inline | manual |
| autonomous-loops | Patterns and architectures for autonomous Claude Code loops — from simple sequential pipelines to RFC-driven multi-agent DAG systems. | inline | auto |
| backend-patterns | Backend architecture patterns, API design, database optimization, and server-side best practices for Node.js, Express, and Next.js API routes. | inline | auto |
| benchmark | Use this skill to measure performance baselines, detect regressions before/after PRs, and compare stack alternatives. | inline | auto |
| browser-qa | Use this skill to automate visual testing and UI interaction verification using browser automation after deploying features. | inline | auto |
| bun-runtime | Bun as runtime, package manager, bundler, and test runner. When to choose Bun vs Node, migration notes, and Vercel support. | inline | auto |
| clarify-first | Ask the structured 3-step question (analyze, recommend, ask) BEFORE dispatching write-capable agents or starting multi-file changes where a wrong assumption wastes work. Trigger when a task is named but scope is unstated — 'fix the bug', 'refactor X', 'add Y', 'make it faster' with no file/metric/layer; or it spans subsystems with no clear boundary. Thai: 'clarify ก่อน', 'ถามก่อนเริ่ม', 'scope ยังไงดี', 'ยังไม่ชัดเจน'. Don't use for: explicit file paths, single-value changes, read-only requests, or rhetorical questions. | inline | auto |
| code-tour | Create CodeTour .tour files: persona-targeted walkthroughs with real file and line anchors. For onboarding, architecture, PR, and RCA tours. | inline | auto |
| codebase-design | Deep-module design vocabulary. Use when designing interfaces, finding deepening opportunities, placing seams, or making code more testable. | inline | auto |
| codebase-onboarding | Analyze an unfamiliar codebase and generate a structured onboarding guide with architecture map, key entry points, and conventions. | inline | auto |
| coding-standards | Baseline cross-project coding conventions for naming, readability, immutability, and code-quality review. Use detailed frontend or backend skills for framework-specific patterns. | inline | auto |
| context-budget | Audits Claude Code context window consumption across agents, skills, MCP servers, and rules. Identifies bloat, redundant components, and produces prioritized token-savings recommendations. | inline | auto |
| cost-aware-llm-pipeline | Cost optimization patterns for LLM API usage — model routing by task complexity, budget tracking, retry logic, and prompt caching. | inline | auto |
| cpp-coding-standards | C++ coding standards based on the C++ Core Guidelines (isocpp.github.io). Use when writing, reviewing, or refactoring C++ code to enforce modern, safe, and idiomatic practices. | inline | auto |
| cpp-testing | Use only when writing/updating/fixing C++ tests, configuring GoogleTest/CTest, diagnosing failing or flaky tests, or adding coverage/sanitizers. | inline | auto |
| create-jira-ticket | Create a single Jira Bug or Story using the team's Thai PO/QA-readable template. Use when the user says 'create bug'/'create story', 'report a bug', 'file a Jira bug', 'new Jira story', 'write a story', 'สร้างบั๊ก', 'แจ้งบั๊ก', 'เปิดบั๊ก', 'เปิดตั๋วบั๊ก', 'สร้าง story', 'เปิด story', 'เขียน story', 'ออก ticket bug', 'ออก story', or wants a structured Thai ticket. Don't use for: de-duping/triaging before filing (use atlassian:triage-issue), converting a spec/Confluence page to a backlog (use atlassian:spec-to-backlog), bulk creation (use acli), editing an existing ticket (use acli), technical tasks without PO-facing AC (use acli), security incidents (use kbg:incident), or non-Jira trackers. | inline | auto |
| critical-eval | Stress-test reasoning in arguments, PRs, ADRs, RFCs, incidents, decisions. Use when asked to critique, evaluate reasoning, check assumptions, stress-test arguments, review logic, verify it holds up, or when something feels off. Thai: 'ตรวจ reasoning', 'stress test ข้อโต้แย้ง', 'เช็คสมมติฐาน', 'ดู logic นี้'. Flag overconfident plans (definitely safe, zero downtime). Don't use for: adversarial review of error-handling/fallback code paths (defer to silent-failure-hunter), system dynamics/architecture trade-offs (kbg:backend-dev/code-architect), code review (kbg:review-pr), security audit (kbg:security-auditor), or research (/deep-dive). | inline | auto |
| dart-flutter-patterns | Dart/Flutter production patterns: null safety, state management (BLoC, Riverpod, Provider), GoRouter, Dio, Freezed, and clean architecture. | inline | auto |
| database-migrations | Database migration best practices for schema changes, data migrations, rollbacks, and zero-downtime deployments across PostgreSQL, MySQL, and common ORMs (Prisma, Drizzle, Kysely, Django, TypeORM, golang-migrate). | inline | auto |
| decide | Judgment Ladder decision support. Modes: probe (analyze before committing), decide (5-rung ladder), strategize (irreversible choices). Produces a decision record. | inline | auto |
| deep-research | Multi-source deep research: web search, synthesis, and cited reports with source attribution. Use when thorough research with evidence is needed. | inline | auto |
| deployment-patterns | Deployment workflows, CI/CD pipeline patterns, Docker containerization, health checks, rollback strategies, and production readiness checklists for web applications. | inline | auto |
| diagnosing-bugs | Diagnosis loop for hard bugs and performance regressions. Use when the user says "diagnose"/"debug this", or reports something broken/throwing/failing/slow. | inline | auto |
| django-patterns | Django architecture patterns, REST API design with DRF, ORM best practices, caching, signals, middleware, and production-grade Django apps. | inline | auto |
| django-security | Django security best practices, authentication, authorization, CSRF protection, SQL injection prevention, XSS prevention, and secure deployment configurations. | inline | auto |
| django-tdd | Django testing strategies with pytest-django, TDD methodology, factory_boy, mocking, coverage, and testing Django REST Framework APIs. | inline | auto |
| docker-patterns | Docker and Docker Compose patterns for local development, container security, networking, volume strategies, and multi-service orchestration. | inline | auto |
| documentation-lookup | Host-model skill for current library/framework docs via Context7 MCP: resolve-library-id → query-docs → answer. For a fresh-context isolated lookup spawn the docs-lookup agent instead. | inline | auto |
| domain-modeling | Build and sharpen a project's domain model, ubiquitous language, and terminology. Use when pinning down domain concepts or maintaining the model. | inline | auto |
| dotnet-patterns | Idiomatic C# and .NET patterns, conventions, dependency injection, async/await, and best practices for building robust, maintainable .NET applications. | inline | auto |
| drizzle-patterns | Drizzle ORM patterns: schema definition, type inference, drizzle-kit migrations, query builder, relations, transactions, and prepared statements for PostgreSQL/SQLite. | inline | auto |
| dynamic-workflow-mode | Design task-local harnesses, eval gates, and reusable skill extraction for Claude dynamic workflow mode and other adaptive agent harnesses. | inline | auto |
| e2e-testing | Playwright E2E testing patterns, Page Object Model, configuration, CI/CD integration, artifact management, and flaky test strategies. | inline | auto |
| effect-ts-patterns | Effect-ts patterns: Effect<A,E,R> type, Effect.gen, Layer DI, Schema validation, fiber concurrency, and @effect/platform HTTP. For typed-effect-system codebases. | inline | auto |
| error-handling | Patterns for robust error handling across TypeScript, Python, and Go. Covers typed errors, error boundaries, retries, circuit breakers, and user-facing error messages. | inline | auto |
| eval-harness | Formal evaluation framework for Claude Code sessions implementing eval-driven development (EDD) principles | inline | auto |
| fastapi-patterns | FastAPI best practices covering project structure, Pydantic v2 schemas, dependency injection, async handlers, authentication, authorization, transactional service layers, and testing with httpx and pytest. | inline | auto |
| flutter-dart-code-review | Flutter/Dart review checklist: widget best practices, state management (BLoC, Riverpod, Provider, GetX, MobX, Signals), Dart idioms, and architecture. | inline | auto |
| frontend-a11y | Accessibility patterns for React and Next.js: semantic HTML, ARIA, form labeling, keyboard navigation, focus management, and screen reader support. | inline | auto |
| frontend-patterns | Frontend development patterns for React, Next.js, state management, performance optimization, and UI best practices. | inline | auto |
| gateguard | Fact-forcing gate that blocks Edit/Write/Bash until concrete investigation of importers, schemas, and context is complete. +2.25 point quality lift. | inline | auto |
| git-workflow | Git workflow patterns including branching strategies, commit conventions, merge vs rebase, conflict resolution, and collaborative development best practices for teams of all sizes. | inline | auto |
| github-ops | GitHub operations via gh CLI: issue triage, PR management, CI/CD, releases, and security monitoring. Use for any GitHub task beyond git. | inline | auto |
| goal-spec | Before a multi-step loop: writes PROMPT.md goal spec (Goal, Done-when, Never-touch, Stop-if) to anchor agent behavior. | inline | auto |
| golang-patterns | Idiomatic Go patterns, best practices, and conventions for building robust, efficient, and maintainable Go applications. | inline | auto |
| golang-testing | Go testing patterns including table-driven tests, subtests, benchmarks, fuzzing, and test coverage. Follows TDD methodology with idiomatic Go practices. | inline | auto |
| grilling | Relentless interview to stress-test a plan or design. Modes: basic (default, interview only) or with-docs (also produces ADRs + domain glossary). | inline | auto |
| grpc-node-patterns | gRPC patterns for Node.js and Bun: proto definition, @grpc/grpc-js client and server, TypeScript codegen, streaming, error codes, and deadlines/metadata. | inline | auto |
| handoff | Compact the current conversation into a handoff document for another agent to pick up. | inline | manual |
| harness-audit | Single harness-state surface with three modes. Default mode runs a deterministic fleet/schema/structural audit across the kbg-harness plugin. --health mode queries the governance journal (formerly kbg:harness-health). --coverage mode renders the 2x2x3 (12-cell) decay grid (formerly kbg:harness-coverage). Use when running a harness audit, querying verdicts/sensors, or asking for the 12-cell coverage view. Thai: 'audit harness', 'ตรวจ harness', 'harness health', 'สุขภาพ harness', 'harness coverage', 'ตาราง 12 cell'. Don't use for: general repo lint or security audits (kbg:security-auditor). | inline | auto |
| harness-nav | L3 escape hatch for kbg-harness capability discovery. Use when no known skill, command, or agent clearly covers your task — teaches grep recipes to mine BOUNDARY.md, skills/, agents/, commands/ for the right capability. Returns the nearest match or confirms none exists. Thai: 'หา skill', 'navigate', 'skill ไหนเหมาะ', 'มีอะไรช่วยได้'. Don't use for: tasks where the right skill is already known (use it directly), or operational health queries (use kbg:harness-audit --health). | inline | auto |
| hexagonal-architecture | Design, implement, and refactor Ports & Adapters systems with clear domain boundaries, dependency inversion, and testable use-case orchestration across TypeScript, Java, Kotlin, and Go services. | inline | auto |
| hono-patterns | Hono web framework patterns: typed routing, Zod validation, middleware, RPC client, context variables, and Bun/Node runtime adapters. | inline | auto |
| implement | Implement a piece of work based on a PRD or set of issues. | inline | manual |
| improve-codebase-architecture | Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick. | inline | manual |
| incident | Manage a live production incident end-to-end, including the hotfix path when rollback/kill-switch is insufficient. Use when alerts fire, monitors show red, users report widespread issues, error rates spike, or the user asks for a hotfix / P0 fix. Thai: 'incident', 'เหตุฉุกเฉิน', 'production เสีย', 'ระบบล่ม', 'hotfix', 'แก้ด่วน', 'P0'. Do NOT use for: non-production bugs (use /fix-bug), planned maintenance, security incidents requiring special handling (STOP — redirect to security-reviewer first), or post-incident documentation (use /post-mortem after resolution). | inline | auto |
| intent-driven-development | Clarify ambiguous requests into verifiable acceptance criteria before implementation. Targets security, data, migration, and integration changes. Skip for trivial edits or clear implementations. | inline | auto |
| inventory | Show what Claude Code skills, agents, commands, and hooks are loadable from the current project and global layers. Use when exploring available capabilities or verifying what the kbg@kobig plugin delivered. Thai: 'inventory', 'ดู skill ทั้งหมด', 'มี skill อะไรบ้าง'. Don't use for: a single-layer list (use /skills, /agents, or /hooks), capability routing when a skill is already known (use it directly), or governance health queries (kbg:harness-audit --health). Use inventory for the unified cross-layer view (project-local + global in one render) with plugin-delivered markers. | inline | auto |
| java-coding-standards | Java coding standards for Spring Boot and Quarkus: naming, immutability, Optional, streams, exceptions, generics, CDI, and reactive patterns. | inline | auto |
| knowledge-ops | Knowledge base management across local files, MCP memory, vector stores, and Git repos. Use to save, sync, deduplicate, or search knowledge. | inline | auto |
| kotlin-coroutines-flows | Kotlin Coroutines and Flow patterns for Android and KMP — structured concurrency, Flow operators, StateFlow, error handling, and testing. | inline | auto |
| kotlin-exposed-patterns | JetBrains Exposed ORM patterns including DSL queries, DAO pattern, transactions, HikariCP connection pooling, Flyway migrations, and repository pattern. | inline | auto |
| kotlin-ktor-patterns | Ktor server patterns including routing DSL, plugins, authentication, Koin DI, kotlinx.serialization, WebSockets, and testApplication testing. | inline | auto |
| kotlin-patterns | Idiomatic Kotlin patterns, best practices, and conventions for building robust, efficient, and maintainable Kotlin applications with coroutines, null safety, and DSL builders. | inline | auto |
| kotlin-testing | Kotlin testing patterns with Kotest, MockK, coroutine testing, property-based testing, and Kover coverage. Follows TDD methodology with idiomatic Kotlin practices. | inline | auto |
| kubernetes-patterns | Kubernetes workload patterns, resource management, RBAC, probes, autoscaling, ConfigMap/Secret handling, and kubectl debugging for production-grade deployments. | inline | auto |
| langchain-langgraph-patterns | LangChain and LangGraph patterns: StateGraph agents, checkpointing, human-in-the-loop, tool calling, streaming, Pinecone RAG, and LangSmith tracing. | inline | auto |
| latency-critical-systems | Use for latency-sensitive systems such as realtime dashboards, market data, streaming agents, execution gateways, queues, caches, or HFT-like infrastructure where freshness and p95 latency matter. | inline | auto |
| learn | Mine the current session for durable, reusable learnings — operator corrections, repeated workflows, stated preferences/conventions, decisions with rationale — and, ONLY after an AskUserQuestion approval gate, save the chosen ones as memory files. Use when the user explicitly asks to capture what was learned: 'learn from this session', 'remember how we did this', 'capture these learnings', 'save what you learned', or Thai 'จำไว้', 'เรียนจาก session นี้', 'บันทึกสิ่งที่เรียนรู้'. Don't use for: writing a single memory you already know (just write it directly), harness self-improvement (use kbg:recursive-improve), memory bookkeeping/lint (use kbg:memory-lint / kbg:memory-trim), or unprompted auto-*apply*. A default-ON SessionEnd hook (learn-capture; opt out with KBG_LEARN_CAPTURE=0) passively STAGES candidates to an out-of-repo queue, but nothing is written without your approval here. | inline | auto |
| memory-lint | Deterministic bookkeeping check for the memory store: catch dangling [[links]], orphaned facts, and index drift. Use after writing, editing, or removing memories. Thai: 'memory lint', 'ตรวจ memory', 'เช็คลิงก์ memory'. Don't use for: writing a memory (just write it), semantic content review, or harness ecosystem health (kbg:harness-audit). | inline | auto |
| memory-trim | Mechanically archive verbose or closed memory entries while keeping the memory store under its 200-line/25KB load cap. Uses reversible moves, never rm. Use when MEMORY.md is bloated or after a big session. Thai: 'memory trim', 'ย่อ memory', 'archive memory'. Don't use for: semantic memory review, deleting memory permanently, or harness-wide health checks (kbg:harness-audit). | inline | auto |
| mysql-patterns | MySQL and MariaDB schema, query, indexing, transaction, replication, and connection-pool patterns for production backends. | inline | auto |
| nestjs-patterns | NestJS architecture patterns for modules, controllers, providers, DTO validation, guards, interceptors, config, and production-grade TypeScript backends. | inline | auto |
| nuxt4-patterns | Nuxt 4 app patterns for hydration safety, performance, route rules, lazy loading, and SSR-safe data fetching with useFetch and useAsyncData. | inline | auto |
| orch-add-feature | Gated pipeline for a net-new capability: research → plan → TDD → review → commit. Delegates each phase to matching ECC agents. | inline | auto |
| orch-build-mvp | Turn a design or spec doc into a running MVP: slice → scaffold → TDD → review → gated commit. | inline | auto |
| orch-change-feature | Change existing behavior: update tests to new spec, fix implementation to match, review, gated commit. Use when behavior is not broken but should be different. | inline | auto |
| orch-fix-defect | Fix a bug: write a failing regression test, fix to green, review, gated commit. Use when existing behavior is broken. | inline | auto |
| orch-pipeline | Shared engine for the orch-* skill family: gated Research→Plan→TDD→Review→Commit pipeline, size classifier, agent map. Not invoked directly. | inline | auto |
| orch-refine-code | Behavior-preserving refactor: confirm tests green, restructure, keep green, review, gated commit. Use when structure should improve but behavior must not change. | inline | auto |
| orchestrate | Prioritize competing tasks, then route each to inline / batch-parallel / pipeline-sequential / drop. Use when the user lists competing tasks, asks 'what should I work on' or 'what's the priority', plans a day/week/sprint, feels overwhelmed, spans independent sub-tasks or sequential phases, or says 'orchestrate', 'จัดสรรงาน', 'ประชุมจัดลำดับ', 'ลำดับความสำคัญ', or 'จัดpriority'. Don't use for: single-issue triage (triage), PR review (kbg:review-pr), one feature (/ship-task), or single-file coding (inline). | inline | auto |
| parallel-execution-optimizer | Parallelize independent work into lanes: batched reads, concurrent agents, isolated worktrees, or verification passes — without write-surface conflicts. | inline | auto |
| postgres-patterns | PostgreSQL database patterns for query optimization, schema design, indexing, and security. Based on Supabase best practices. | inline | auto |
| production-audit | Local-evidence production readiness audit for pre-launch reviews, post-merge checks, and prod-failure questions. No external service. | inline | auto |
| prompt-optimizer | Analyze a draft prompt, diagnose gaps, match ECC components, and output a ready-to-paste optimized prompt. Advisory only. | inline | auto |
| prototype | Build throwaway prototypes — terminal apps for logic questions, or radically different UI variations on one route. | inline | manual |
| python-patterns | Pythonic idioms, PEP 8 standards, type hints, and best practices for building robust, efficient, and maintainable Python applications. | inline | auto |
| python-testing | Python testing strategies using pytest, TDD methodology, fixtures, mocking, parametrization, and coverage requirements. | inline | auto |
| react-patterns | React 18/19 patterns: hooks, server/client boundaries, Suspense, form actions, data fetching, state management, and accessibility. Use when writing or reviewing components. | inline | auto |
| react-performance | React/Next.js performance patterns: 70+ rules across waterfalls, bundle size, server-side, re-render, and micro-perf. Use when optimizing React/Next.js code. | inline | auto |
| react-testing | React testing with RTL, Vitest/Jest, MSW, and axe. Covers component tests vs E2E decision boundary. Use when writing or fixing React tests. | inline | auto |
| recursive-improve | Bounded human-gated harness-improvement loop. Use when the user explicitly asks to improve or audit the harness, or when verification posture reveals a concrete gap, including 'ปรับปรุง harness', 'recursive improve', 'แก้ harness'. Don't use for: single named bugs (use /fix-bug), new capabilities (use /ship-task), external tool research (use kbg:article-mine), or any self-launching / scheduled / unattended loop (every iteration is human-gated at an AskUserQuestion gate before any mutation). | inline | manual |
| redis-patterns | Redis data structure patterns, caching strategies, distributed locks, rate limiting, pub/sub, and connection management for production applications. | inline | auto |
| repo-scan | Cross-stack source code asset audit — classifies every file, detects embedded third-party libraries, and delivers actionable four-level verdicts per module with interactive HTML reports. | inline | auto |
| resolving-merge-conflicts | Use when you need to resolve an in-progress git merge/rebase conflict. | inline | auto |
| review-pr | Run multi-agent PR review across code quality, tests, comments, errors, security, types, accessibility/UX, and simplification. Use when finishing changes before opening a PR, when a PR is ready, after addressing feedback, or when asked to review changes/aspects. Thai: 'review PR', 'ตรวจ PR', 'ดู PR นี้', 'รีวิว code'. Don't use for: a quick diff review (use /code-review, optionally --fix/--comment/ultra) or a single GitHub PR (use /review), single-file diffs (review inline), security-only audits (kbg:security-auditor), post-merge retrospectives, or invoking a single agent (use Agent tool). | inline | auto |
| rules-distill | Scan skills to extract cross-cutting principles and distill them into rules — append, revise, or create new rule files | inline | auto |
| rust-patterns | Idiomatic Rust patterns, ownership, error handling, traits, concurrency, and best practices for building safe, performant applications. | inline | auto |
| rust-testing | Rust testing patterns including unit tests, integration tests, async testing, property-based testing, mocking, and coverage. Follows TDD methodology. | inline | auto |
| safety-guard | Use this skill to prevent destructive operations when working on production systems or running agents autonomously. | inline | auto |
| search-first | Research-before-coding workflow. Search for existing tools, libraries, and patterns before writing custom code. Invokes the researcher agent. | inline | auto |
| security-auditor | Standalone security audit — deep threat-model + remediation for auth, secrets, external input, file uploads, or dependencies. Covers injection, XSS/CSRF/SSRF, path traversal, broken access control, secret leaks, or vulnerable components. Use when PRs touch auth, APIs, admin panels, payments, or dep manifests. Thai: 'ตรวจ security', 'ช่องโหว่', 'security audit', 'เช็คความปลอดภัย'. The security-reviewer agent is the fast flag spawned inside kbg:review-pr — run one, not both. Don't use for: a quick branch-wide security check of pending changes (use /security-review), code review (kbg:review-pr), incidents (kbg:incident), or non-code security (infra, policy). | inline | auto |
| security-review | In-flow security checklist while coding auth, user input, secrets, API endpoints, or payment features. Guides the current change. For a standalone full-codebase threat-model audit use kbg:security-auditor. | inline | auto |
| setup-matt-pocock-skills | Configure this repo for Matt Pocock's engineering skills — issue tracker, triage labels, and doc layout. Run once before first use. | inline | manual |
| ship-change | Orchestrate an already-scoped change through classify → implement → review → address → merge. Use when the change is understood and needs guided sequencing through /fix-bug, /ship-task, kbg:review-pr, /address-review, and /ship-merge. Thai: 'ship change', 'พร้อม merge', 'ขึ้น production', 'deploy ตัวนี้'. Don't use for: a blank-slate task needing discovery first (use /ship-task), a change already mid-flight (jump straight to the relevant phase command, e.g. /fix-bug to continue or kbg:review-pr if ready for review), one-line fixes, or pure research/exploration. | inline | auto |
| skill-scout | Search existing local, marketplace, GitHub, and web skill sources before creating a new skill. | inline | auto |
| skill-stocktake | Audit installed skills for quality; supports Quick Scan (changed only) and Full Stocktake modes. | inline | auto |
| springboot-patterns | Spring Boot architecture patterns, REST API design, layered services, data access, caching, async processing, and logging. Use for Java Spring Boot backend work. | inline | auto |
| springboot-security | Spring Security best practices for authn/authz, validation, CSRF, secrets, headers, rate limiting, and dependency security in Java Spring Boot services. | inline | auto |
| springboot-tdd | Test-driven development for Spring Boot using JUnit 5, Mockito, MockMvc, Testcontainers, and JaCoCo. Use when adding features, fixing bugs, or refactoring. | inline | auto |
| strategic-compact | Suggests manual context compaction at logical intervals to preserve context through task phases rather than arbitrary auto-compaction. | inline | auto |
| swift-concurrency-6-2 | Swift 6.2 Approachable Concurrency — single-threaded by default, @concurrent for explicit background offloading, isolated conformances for main actor types. | inline | auto |
| swiftui-patterns | SwiftUI architecture patterns, state management with @Observable, view composition, navigation, performance optimization, and modern iOS/macOS UI best practices. | inline | auto |
| tauri-v2-patterns | Tauri v2 desktop app patterns: IPC commands, capabilities/permissions model, state management, events, plugins, and tauri.conf.json. Covers v2 breaking changes from v1. | inline | auto |
| tdd | Test-driven development. Use when the user wants to build features or fix bugs test-first, mentions "red-green-refactor", or wants integration tests. | inline | auto |
| teach | Teach the user a new skill or concept, within this workspace. | inline | manual |
| team-agent-orchestration | Run team-based orchestration for agent squads using work items, ownership, agent Kanban, merge gates, and control pane handoffs. | inline | auto |
| terminal-ops | Evidence-first repo execution. Use when running commands, checking CI failures, or pushing narrow fixes with proof of what was verified. | inline | auto |
| thinking | On-demand index of 39 mental models. Read before reasoning on any complex, ambiguous, or high-stakes problem to pick the right scaffold. | inline | auto |
| to-issues | Break a plan, spec, or PRD into independently-grabbable issues on the project issue tracker using tracer-bullet vertical slices. | inline | manual |
| to-prd | Turn the current conversation into a PRD and publish it to the project issue tracker — no interview, just synthesis of what you've already discussed. | inline | manual |
| token-budget-advisor | Present depth options (25/50/75/100%) before answering when user wants
to control response length or token usage. | inline | auto |
| triage | Move issues and external PRs through a state machine of triage roles — categorise, verify, grill if needed, and write agent-ready briefs. | inline | manual |
| verification-loop | A comprehensive verification system for Claude Code sessions. | inline | auto |
| vue-patterns | Vue.js 3 Composition API, Pinia state, Vue Router, and Nuxt SSR patterns. Activates for Vue, Nuxt, Vite, or Pinia projects. | inline | auto |
| writing-great-skills | Reference for writing and editing skills well — the vocabulary and principles that make a skill predictable. | inline | manual |

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
_Generated: 2026-06-29T04:03:01Z_

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
| `code-explorer` | any file | Read-only trace |
| `code-reviewer` | any file | Read-only review |
| `comment-analyzer` | any file | Read-only comment audit |
| `compliance-engineer` | `docs/compliance/`, `policies/`, `data-retention/`, `gdpr/`, `hipaa/` | |
| `data-engineer` | `migrations/`, `etl/`, `analytics/`, `warehouse/`, `dbt/`, `spark/` | Beyond OLTP |
| `devops-engineer` | `.github/`, `docker/`, `k8s/`, `terraform/`, `helm/`, `ci/` | |
| `finops-engineer` | `infra/cost/`, `budgets/`, `docs/finops/` | Read-only + Bash for cost queries |
| `frontend-engineer` | `src/components/`, `src/pages/`, `styles/`, `public/`, `assets/`, `src/hooks/` | |
| `i18n-specialist` | `locales/`, `translations/`, `i18n/`, `src/i18n/`, `l10n/` | |
| `incident-commander` | `docs/incidents/`, `runbooks/`, `alerts/`, `oncall/` | Read-only + coordination |
| `maintenance-engineer` | any file | Refactor / deprecation scope |
| `ml-engineer` | `ml/`, `models/`, `features/`, `pipelines/`, `serving/`, `inference/` | |
| `mobile-engineer` | `ios/`, `android/`, `mobile/`, `react-native/`, `flutter/` | |
| `platform-engineer` | `platform/`, `proto/`, `gateway/`, `mesh/`, `grpc/`, `event-bus/` | |
| `pr-test-analyzer` | any file | Read-only test-coverage audit |
| `product-analyst` | `docs/requirements/`, `prd/`, `user-stories/` | Read-only + Bash |
| `researcher` | any file | Read-only research |
| `security-reviewer` | `auth/`, `secrets/`, `config/`, `security/`, `iam/`, `crypto/` | Read-only audit |
| `silent-failure-hunter` | any file | Read-only error-handling audit |
| `technical-writer` | `docs/`, `README*`, `CHANGELOG*`, `*.md`, `guides/`, `runbooks/` | |
| `test-engineer` | `tests/`, `*.test.*`, `*.spec.*`, `test_*.py`, `e2e/`, `integration/` | |
| `type-design-analyzer` | any file | Read-only type audit |
| `ux-reviewer` | `src/components/`, `src/pages/`, `e2e/ux/`, `a11y/` | Read-only UX audit |


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

