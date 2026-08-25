# Boundary Map
_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: `bash <matt-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md` where `<matt-harness>` is the matt-harness repo root and `<dotfiles>` is the target repo root (or from the plugin cache: `bash ~/.claude/plugins/cache/kobig/mh/$(ls ~/.claude/plugins/cache/kobig/mh/ | sort -V | tail -1)/skills/inventory/scripts/inventory-boundary.sh --repo-only`)._
_Schema version: v5 (Skills and Agents tables now grouped by `bucket:` frontmatter key under `### <bucket>` subheads, replacing the single flat table each; v4 added Commands table and dropped the redundant inventory.sh bulleted-list dump in --repo-only mode — tables are now the sole listing, matching skills/inventory/reference.md's documented "Boundary map" contract; Hooks Purpose column now a full comment paragraph via fm_hook_desc, not a truncated first line)._

## Agents — Repo
### analysis
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| ideate-critic | Fresh-context critic for /ideate Phase 2. Use when ideate needs a critic pass, or the user says 'วิจารณ์ไอเดีย', 'critic', 'ตรวจไอเดีย'. Don't use for: code review (mattpocock-skills:code-review) or security audit (security-reviewer). | Read | no |
| requirement-analyst | Senior-level, systematic requirement analysis from Jira tickets or other sources — ambiguities, missing acceptance criteria, edge cases, dependencies, risks, readiness verdict. Use before implementation starts. | ["Read", "Grep", "Glob"] | no |
| spec-miner | Extracts behavioral specs from existing codebases. Produces Requirement and Invariant blocks with structured metadata. Use when onboarding a brownfield project to spec-driven development. | ["Read", "Grep", "Glob", "Bash", "Write"] | yes |

### build
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| build-error-resolver | Build-error resolver across npm, Cargo, Maven, Gradle, Go, Python, and Dart/Flutter. Minimal diffs, no architecture changes. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| performance-optimizer | Performance optimizer. Identifies bottlenecks, optimizes slow code, reduces bundle sizes, and fixes memory leaks and render issues. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |
| refactor-cleaner | Dead code cleanup specialist across JS/TS, Python, Go, and Rust. Identifies and removes unused code and duplicates. | ["Read", "Write", "Edit", "Bash", "Grep", "Glob"] | yes |

### design
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| backend-architect | Backend systems architect — API contracts, service boundaries, data ownership, consistency, caching, reliability, scalability. Design-first, cross-language — defers framework/DB specifics to *-patterns skills. | [Read, Grep, Glob, Bash] | yes |
| code-architect | Designs feature architectures by analyzing existing codebase patterns and conventions, then providing implementation blueprints with concrete files, interfaces, data flow, and build order. | [Read, Grep, Glob, Bash] | yes |

### review
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| a11y-architect | Accessibility specialist, audits UI/design systems for WCAG 2.2 AA compliance. Use when building or reviewing web components. Not React architecture (mh:frontend-patterns). | ["Read", "Write", "Edit", "Grep", "Glob"] | yes |
| blind-spot-hunter | Post-review adversarial hunter for emergent/interaction defects that survived normal review — cross-file, framework-behavior, data-flow-asymmetry blind spots. Traces each to an earned severity. Use after code review. | [Read, Grep, Glob, Bash] | yes |
| nextjs-reviewer | Next.js App Router framework specialist: rendering/caching model, Server Actions, middleware, route handlers, metadata API, image/font optimization. Use for Next.js-specific changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| python-reviewer | Expert Python reviewer: PEP 8, Pythonic idioms, type hints, security, and performance. Use for all Python code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |
| security-reviewer | Security vulnerability detector. Flags secrets, SSRF, injection, unsafe crypto, and OWASP Top 10. Use after writing code handling user input or auth. | ["Read", "Bash", "Grep", "Glob"] | yes |
| silent-failure-hunter | Review code for silent failures, swallowed errors, bad fallbacks, and missing error propagation. Use when reviewing error handling — try/catch, fallbacks, or async error flow. | [Read, Grep, Glob, Bash] | yes |
| typescript-reviewer | Expert TypeScript/JavaScript reviewer: type safety, async correctness, security, and idiomatic patterns. Use for all TS/JS code changes. | ["Read", "Grep", "Glob", "Bash"] | yes |

### utility
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| summarizer | Summarizes any text, doc, or transcript into clear, filler-free output for any audience — BLUF structure, source-fidelity, information-density calibration. Use for condensing long content. | ["Read", "Grep", "Glob"] | no |

## Commands — Repo
| Command | Description |
|---|---|
| bug-sweep | Sweep: N parallel agents (default 5) each hunt one small bug, report-only. Don't use for PR review (mattpocock-skills:code-review) or session audit (/deep-audit). |
| build-fix | Detect the project build system and incrementally fix build/type errors with minimal safe changes. Delegates to the build-error-resolver agent. |
| deep-audit | Post-implementation adversarial audit: reconstruct session state, verify every claim against evidence, score before/after on a defined rubric, implement only evidence-backed fixes, re-score. Use after a significant implementation pass to check it actually improved something. Don't use for a first-pass code review — see mattpocock-skills:code-review. |
| frame | Load a working-frame: dev/review/research (posture-setter, not a workflow or voice change). Say 'dev mode/โหมด dev/ตั้งโหมด'. Don't use for skills or /config's output-style picker. |
| ideate-search | Search past /ideate runs via the local qmd collection. Say 'ideate search/ค้นหาไอเดีย/หาไอเดีย'. Don't use for a new session (/ideate) or code/web research (research). |
| post-mortem | Draft a post-mortem for a resolved bug (trigger/mechanism/patch/validation known). Use after mattpocock-skills:diagnosing-bugs; say 'เขียน post-mortem/บันทึกบั๊ก/incident report'. Don't use for in-progress or non-technical incidents. |
| refactor-clean | Safely identify and remove dead code (JS/TS, Python, Go, Rust) with test verification after each change. Delegates to the refactor-cleaner agent. |
| risk-check | Classify a PR's risk as LOW/MEDIUM/HIGH from diff size and sensitive-path signals. Advisory only — never gates a merge. See /mh:ship-merge for the decision. |
| security-scan | Run AgentShield against agent, hook, MCP, permission, and secret surfaces. Don't use for code-vulnerability review — use mh:security-auditor. |
| ship-release | Cut a release end-to-end: bump, changelog, review gate, tag, merge, monitor. Say 'ship release/ปล่อยเวอร์ชัน'. Don't use for PR merges (/ship-merge) or hotfixes (mh:incident). |
| summarize | Compress a document, transcript, or pasted text into a BLUF-structured summary. Delegates to the summarizer agent. |
| test-coverage | Analyze coverage, identify gaps, and generate missing tests toward the target threshold. |
| tiered-pipeline | Run a bounded task through the Fable→Sonnet→Opus maker/checker pipeline (capped fixes, bug-hunt, gated final review). Don't use for quick edits or PR review. |
| wiki-ingest | Ingest a source document into the llm-wiki vault from any project. Don't use for searching the vault (qmd MCP, collection llm-wiki) or kbg's own memory store (mh:learn). |
| address-review | Triage + respond to open PR review comments (fetch, classify, fix via mattpocock-skills:diagnosing-bugs, reply). Say 'address review/แก้ตามรีวิว'. Don't use to review (mattpocock-skills:code-review) or merge (/ship-merge). |
| cost-report | Generate a local Claude Code cost report from the cost-tracker metrics log. |
| ideate | Parallel divergent ideation (5 isolated agents, rotating frames, novelty/viability/fit scoring). Say 'brainstorm/ระดมความคิด/คิดไอเดีย'. Don't use for syntax, lookups, or closed-phrasing asks. |
| review-fixtures | Dispatch 2 independent staff-eng agents to adversarially review skill-creator-style fixture outputs (with_skill vs baseline) for a skill, agent, or command before deciding a fix. Use mid an improve+optimize loop once fixtures exist. Don't use for PR review (mattpocock-skills:code-review) or skill-creator's own quantitative grading/benchmark step. |
| ship-merge | Merge a PR safely: validate, server-side merge, cleanup, monitor CI. Say 'merge PR/รวมโค้ด'. Don't use for failing CI or hotfixes (mh:incident). |

## Skills — Repo
### agent-support
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| performance-optimizer-algorithms | Catalog of performance-optimizer's 14-row algorithmic-complexity pattern table. Auto-loads when performance-optimizer runs. Don't use for other agents. | inline | auto |
| requirement-analyst-format | Catalog of requirement-analyst's self-consistency checklist, Output Format template, and Anti-Patterns list. Auto-loads when requirement-analyst runs. Don't use for other reviewer agents or standalone requirement analysis. | inline | auto |
| spec-miner-anti-patterns | Catalog of spec-miner's 10 Anti-Patterns FAIL list. Auto-loads when spec-miner runs. Don't use for other agents or standalone spec authoring. | inline | auto |
| summarizer-format | Catalog of summarizer's Output Format templates, word-level compression BAD/GOOD table, and Anti-Patterns list. Auto-loads when summarizer runs. Don't use for other agents or standalone summarization. | inline | auto |

### design
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| design-system | Scan a design system for token/visual consistency and AI-slop detection, or generate one. Use when starting a project. Don't use for scraping other sites. | inline | auto |
| frontend-design-direction | Frontend-design-direction: typography, layout, tone, and motion. Use when building or restyling UI. Don't use for React architecture (mh:frontend-patterns) or HTML artifacts (plannotator-effective-html). | inline | auto |
| make-interfaces-feel-better | Catalog of UI-polish details — spacing, borders, shadows, motion, hit areas, text wrapping. Use when a UI feels flat. Don't use for direction choices (mh:frontend-design-direction). | inline | auto |
| tech-humanize | Humanize dev/tech writing (English/Thai) to sound natural, not AI-generated. Use when editing chat, standup/PR/commit, UI copy, or prose/ticket/spec/ADR, or say แก้ให้เป็นธรรมชาติ. Don't use for translation. | inline | auto |

### meta
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| agent-architecture-audit | Scan 12-layer agent stacks, regression, memory pollution, tool discipline, repair loops. Use when debugging a misbehaving harness (stuck loops, rot). Don't use for code review. | inline | auto |
| compress-docs | Compact a bloated markdown doc for tokens; verify-before-overwrite, grammar stays full. Use when over harness-audit's 20K threshold. Don't use for content grading or suggest-only scans. | inline | auto |
| context-budget | Scan context-window consumption across agents/skills/MCP/rules; flag bloat + top savings. Use when context feels full or costs climb. Don't use for one-off response trimming. | inline | auto |
| eval-harness | Eval-driven development (EDD) framework for Claude Code. Use when setting up EDD, building graders, or measuring AI-assisted workflow quality. Don't use for end-user feature work. | inline | auto |
| goal-craft | Compact a /goal completion condition: done-when check, one-way-door screen, turn bound. Use when drafting a /goal condition. Don't use for single-turn tasks (do it directly). | inline | auto |
| harness-audit | Harness-state surface, two modes: fleet/schema audit, --health for session token cost. Use for harness audits or cost checks. Don't use for repo lint/security (mh:security-auditor). | inline | auto |
| learn | Scan a session transcript for cross-turn patterns ambient auto-memory misses. Use when wrapping up a session; batch-gate via AskUserQuestion. Don't use for single known memories. | inline | auto |
| loop-design-check | Pre-flight gate + review checklist against loop failure modes — spinning, verifier-gaming, wrong-answer completion. Use when designing/reviewing an agent loop. Don't use for one-off tasks. | inline | auto |
| memory-lint | Scan memory store for dangling [[links]], orphans, index drift; --trim archives bloat. Use when MEMORY.md over cap. Don't use for semantic review or harness health. | inline | auto |
| recursive-improve | Cage: human-gated, anti-unattended harness loop. Use when the user asks to improve or audit the harness. Don't use for bug fixes or new surfaces. | inline | manual |
| score-decision | Score pending decisions on weighted criteria: numeric verdict, pass/fail, confidence, trace. Use when a decision needs a verdict. Don't use for trivial or already-decided choices. | inline | manual |
| wiki-scan | Scan llm-wiki vault health: orphans, frontmatter, citation integrity, stats. Use when checking vault integrity. Don't use for kbg's memory store (mh:memory-lint) or semantic search (qmd). | inline | auto |

### patterns
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| accessibility | WCAG 2.2 AA accessibility, ARIA patterns, React a11y fixes for forms/focus/keyboard nav. Use when building web UI. Don't use for React architecture (mh:frontend-patterns). | inline | auto |
| backend-patterns | Backend architecture, API design, and DB optimization for Node.js/Next.js. Use when building a Node/TS backend. Don't use for Python/Go/Rust backends, or the client half (mh:frontend-patterns). | inline | auto |
| cost-aware-llm-pipeline | Compact LLM-pipeline cost: model routing, prompt caching, retry. Use when designing a multi-model pipeline where cost/latency matter. Don't use for single calls or prompting tips. | inline | auto |
| drizzle-patterns | Drizzle ORM patterns: schema, type inference, migrations, query builder, relations, transactions. Use when building Drizzle apps on PostgreSQL/SQLite. Don't use for Prisma or TypeORM. | inline | auto |
| frontend-patterns | Frontend architecture, component design, and rendering optimization for React/TS. Use when building a React/TS frontend. Don't use for Vue/Svelte/Angular, backend (mh:backend-patterns), or WCAG/a11y audits (mh:accessibility). | inline | auto |
| grpc-node-patterns | gRPC patterns for Node/Bun: proto, @grpc/grpc-js client/server, TypeScript codegen, streaming, deadlines/metadata. Use when building gRPC services in Node/Bun. Don't use for REST/HTTP or non-Node gRPC. | inline | auto |
| latency-critical-systems | Diagnosis + design for latency-sensitive systems, realtime dashboards, market data, streaming, queues, caches, HFT-like infra. Use when designing/reviewing/debugging them. Don't use for batch or offline. | inline | auto |
| mysql-patterns | MySQL/MariaDB schema, query, indexing, transaction, replication, and pool patterns. Use when designing or troubleshooting MySQL/MariaDB. Don't use for non-MySQL databases. | inline | auto |
| typescript-patterns | TypeScript idioms: type-modeling and tsconfig choices, compatible across 5.9-7.x. Use when picking compiler options or type shapes. Don't use for routine edits or backend architecture. | inline | auto |

### review
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| blind-spot-hunter-shapes | Catalog of 7 highest-yield blind-spot shapes (cross-file, framework-behavior, data-flow-asymmetry, identity, scope-mismatch, emitted-string, vacuous-test). Auto-loads when blind-spot-hunter runs. Don't use for escalation/output-format or standalone hunting. | inline | auto |
| pr | PR the branch on GitHub, templated body previewed before submit. Trigger on 'open a PR/เปิด PR'. Don't use for merging (`/ship-merge`) or review replies (`/address-review`). | inline | auto |
| production-audit | Scan production readiness pre-launch. Use when asked whether an app is ready to ship. Don't use for in-flight feature work (use /mattpocock-skills:implement). | inline | auto |
| review-lens-nextjs-routing | Next.js App Router file-convention (error.tsx/loading.tsx/route.ts/parallel routes) and Middleware checklist. Auto-loads when nextjs-reviewer runs. Don't use for caching/Server Actions or standalone review. | inline | auto |
| security-auditor | Scan security vulnerabilities, threat-model + remediation (auth, secrets, injection, XSS, traversal). Use when PRs touch auth/APIs/payments/deps. Don't use for quick branch checks or code review. | inline | auto |
| security-reviewer-patterns | Catalog of security-reviewer's BAD/GOOD examples (SQLi, IDOR, JWT, mass assignment, SSRF, ReDoS). Auto-loads when security-reviewer runs. Don't use for the deep-audit workflow (security-auditor). | inline | auto |

### workflow
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| incident | Incident: run a production incident incl. hotfix. Use when alerts fire or user asks for hotfix. Thai: 'เหตุฉุกเฉิน'. Don't use for non-prod bugs or post-mortem. | inline | auto |
| orchestrate | Triage competing tasks and route each to inline/parallel/sequential/drop. Use when the user lists tasks or says 'จัดสรรงาน'. Don't use for single-issue triage or PR review. | inline | auto |

## Hooks — Repo
| Hook | Purpose |
|---|---|
| flow-nudge.sh | Advisory: when the user's prompt looks like non-trivial engineering work, nudge plan-first — enter plan mode (Shift+Tab / EnterPlanMode) before editing, with the heavyweight spec flow (mattpocock-skills:grilling, then the user types /mattpocock-skills:to-spec → /mattpocock-skills:to-tickets → /mattpocock-skills:implement; to-spec/to-tickets/implement are all disable-model-invocation upstream) as the branch for a feature to spec out. UserPromptSubmit hook. Output → plain stdout — docs: "added as context Claude can see and act on" (not the JSON hookSpecificOutput.additionalContext path, which is what's specifically documented as wrapped in a "system reminder"; this script uses plain stdout instead, a separately-documented mechanism with the same practical effect); never blocks, always exits 0. Errors are […] |
| jira-route-nudge.sh | Advisory: when the user's prompt mentions Jira/Confluence work, nudge routing through the jira-acli plugin's skills (jira-acli:acli, jira-acli:jira-content, jira-acli:confluence-content) before any direct mcp__*atlassian*/mcp__*Rovo* tool call or raw acli command. UserPromptSubmit hook. Output -> plain stdout — docs: "added as context Claude can see and act on" (not the JSON hookSpecificOutput.additionalContext path, which is what's specifically documented as wrapped in a "system reminder"); never blocks, always exits 0. Errors are silently swallowed. |
| learn-nudge.sh | Advisory: remind the operator that mh:learn exists when a session had enough activity to plausibly contain a durable learning worth capturing. SessionEnd hook. Never blocks (SessionEnd has no decision control at all), never writes memory, never judges WHAT the learnings are — that's mh:learn's job, gated by its own AskUserQuestion. This hook only decides whether to say "consider running it." |
| dispatch-pretooluse.py | PreToolUse dispatcher merge logic. Invoked by dispatch-pretooluse.sh with the tool-call JSON payload on stdin and two argv: the routing table path and the repo root (script paths in the table are repo-relative). |
| dispatch-pretooluse.sh | The single PreToolUse registration in hooks.json. Fans out (in parallel) to every gate whose matcher matches this tool call, via dispatch-pretooluse.py -- see that file for the merge rules, verified against Claude Code's own hooks documentation (2026-08-25, ticket #91), not invented. |
| dispatch-single.sh | Thin profile/kill-switch filter for every non-PreToolUse hook (SessionStart, UserPromptSubmit, Stop, SessionEnd, InstructionsLoaded). PreToolUse gates never route through here -- see dispatch-pretooluse.sh, which has no profile concept at all (every PreToolUse hook today is a deny-gate, always on by construction, not tiered). |
| atlassian-mcp-gate.sh | Gate: block a direct Atlassian/Jira/Confluence MCP call (any mcp__*atlassian*/ mcp__*rovo* tool -- both a locally-configured/plugin MCP server, e.g. mcp__plugin_atlassian_atlassian__*, and a claude.ai-hosted connector, e.g. mcp__claude_ai_Atlassian_Rovo__*) before a jira-acli:* skill has loaded this session. Escalates ~/.claude/CLAUDE.md's "route through jira-acli first" doctrine + the advisory/jira-route-nudge.sh UserPromptSubmit reminder from prose to a computational PreToolUse gate -- both proved insufficient in practice (2026-07-15: still routing straight to the Atlassian MCP). |
| credential-guard.sh | Gate: block Read/Grep access to credential-bearing file paths. #96. Resolves the target via realpath BEFORE matching, closing the bypass where a symlink with an innocuous name (e.g. notes.txt) points at a real credential file (e.g. ~/.ssh/id_rsa) -- a naive string match on the unresolved path would sail straight through. |
| db-write-gate.sh | Gate: ask on any MCP execute_sql-shaped call (mcp__<server>__execute_sql*) unless the statement is provably a simple read. Generic — matches any server, no config needed. |
| irrecoverable.sh | Gate: block irrecoverable Bash patterns before they execute. Reads the PreToolUse JSON payload from stdin; exits 2 to block. |
| _codeowners_match.py | Shared CODEOWNERS discovery + matching logic, used by commands/ship-merge/COMMAND.md's step 7 (CLI wrapper below, argv/stdout contract unchanged from the original embedded block). Its second caller, hooks/gates/convergence-merge-gate.sh, was retired 2026-08-24 (#82). |
| _hook_output.py | Shared hook-output JSON primitive. Used by hooks/gates/db-write-gate.sh and hooks/gates/verifier-protect.sh's embedded python3 -c blocks, both of which defined an identical emit_ask() before this extraction (2026-08-15) -- each gate still builds its own reason message inline (that part is legitimately gate-specific), only the JSON-shape emission is shared here. |
| _protected_paths.py | Shared gate/verifier-governance path classifier. Ported near-verbatim (2026-08-15) from hooks/gates/verifier-protect.sh's own is_verifier_path() -- the more complete of two prior copies. commands/risk-check.md's embedded is_gate_path() was the other, missing hooks/advisory/ coverage; both now call this one instead, closing that gap. |
| task-complete-separation.sh | Gate: a subagent may not mark its own task completed (maker≠checker). Reads the PreToolUse JSON payload from stdin; exits 2 to block. |
| verifier-protect.sh | Gate: prompt the human to approve any Write/Edit/MultiEdit — OR a Bash-mediated write (redirect, tee, sed -i, perl -i, cp, mv, rm, trash) — to the verifier surfaces: hooks/gates/**, hooks/advisory/**, hooks/hooks.json, the PreToolUse dispatcher's own routing (hooks/pretooluse-table.json, hooks/dispatch-pretooluse.py/.sh), AND the non-model audit verifier (skills/harness-audit/scripts/audit.sh + checks/**) — so the model cannot neuter the deny-gates, silently turn an advisory sensor into something that emits permissionDecision, repoint or delete a gate's table entry, OR weaken the audit checks that judge it without an in-session human approval (the tamper-resistance principle: the agent cannot edit the code that judges it). hooks/advisory/** added 2026-08-06: previously unprotected, meaning a sensor could be edited into a real gate with zero […] |
| worktree-guard-dispatch.sh | Shared early-exit prelude for gate:write:worktree-guard and gate:bash:worktree-guard. Both hooks.json entries pointed the same inline `bash -c` one-liner at worktree-guard.py -- extracted here so the two matchers (Write|Edit|NotebookEdit vs Bash) stay separate registrations with their own descriptions (redirect vs deny is a real behavioral difference, decided inside worktree-guard.py by tool_name), while the identical no-op-unless-guarded check isn't duplicated as a JSON string literal twice. |
| worktree-guard.py | ponytail: generic worktree guard (moved from dotfiles 2026-07-02). Redirects Edit/Write on a SUB-repo's main checkout so parallel terminals can't clobber one shared working tree. Branch alone can't fix this — one repo dir = one working tree regardless of branch; the worktree is the isolation. Auto-creates a session-scoped worktree under WT_ROOT and transparently redirects the edit there via PreToolUse updatedInput. ponytail: branch name is `wip/<session-id>` — session_id is the only stable identifier this hook has. Rename the branch to your ticket key before opening a PR. Base selection: MH_WORKTREE_BASE=<branch> fetches origin/<branch> and bases the auto-worktree there (hotfix sessions: MH_WORKTREE_BASE=main). Unset = current HEAD of the main checkout, which can lag origin; prefer an explicit worktree for hotfix work. Fetch failure falls back to HEAD — never blocks editing on network. Guarded workspace is opt-in and unset by default: MH_GUARDED_WORKSPACE has NO default, […] |
| command-root-anchor.sh | command-root-anchor.sh — matcher-less SessionStart hook |
| doctrine-bootstrap.sh | SessionStart: inject METHODOLOGY.md doctrine into the session context. Output goes to stdout → CC injects it as system context for the session. |
| instructions-loaded-journal.sh | InstructionsLoaded: journal every CLAUDE.md / `.claude/rules/*.md` load to ~/.local/share/kbg/metrics/instructions-loaded.jsonl. This event has no decision control — Claude Code discards any stdout/JSON output it produces and uses it for observability only — so a log file is the only useful side effect. Exists to answer "did this file load, when, and why" with a deterministic record instead of forensic reconstruction after the fact. |
| memory-health-nudge.sh | SessionStart: surface memory-lint findings (dangling links, orphans, index drift, near-budget) at session start. |
| precompact-state-flush.sh | PreCompact: flush a deterministic, non-LLM-summarized snapshot of the session's in-flight state (git status, HEAD, plugin manifest versions) to ~/.local/share/kbg/metrics/precompact-snapshots.jsonl before compaction runs (#92/T13). CLAUDE.md's own "Compact instructions" section already asks the compacting model to preserve exactly this class of fact in prose ("which files are staged/committed... the current plugin version state... any open plan-mode approval") — that's a prompt instruction, not a guarantee (this repo's own memory has repeated stale-count/stale-fact incidents from trusting a model's own summary). This hook is the computational backstop: the same class of fact, captured by a deterministic script instead of an LLM paraphrase, so a post- compaction turn can consult ground truth instead of trusting the summary […] |
| skill-usage-telemetry.sh | PostToolUse(Skill): journal every skill invocation to ~/.local/share/kbg/metrics/skill-usage.jsonl — usage evidence (not "feel") for the future matt-skill vs harness-skill overlap cull (#90/T11). This event has no decision control here — audit logging only, never a gate. |
| cost-tracker.sh | Stop: log cumulative per-model token usage to ~/.local/share/kbg/metrics/costs.jsonl |
| memory-audit-commit.sh | Stop: commit any dirty changes in the current project's memory store to its own git history. Restores a real audit trail / rollback path for the memory store, which previously had zero version control — see docs/research/agent-memory-engineering-2026-08-07.md proposal A4 (verified 2026-08-07: `git rev-parse --is-inside-work-tree` failed against the live store, confirmed, not assumed). |
| stale-task-nudge.sh | Stop: nudge the model when a task it created is still `in_progress` right as the turn ends, with nothing in this turn touching it — the exact shape of a real incident (2026-08-09): a task was marked in_progress, a final report delivered as the turn's last output, and TaskUpdate(completed) never called. Caught only because the user happened to ask "check tasks that are still open". |
| test-credential-guard.sh | Behavioral tests for hooks/gates/credential-guard.sh (#96). Covers the core deny cases, the realpath/symlink-indirection bypass this gate exists to close, and the false-positive cases a naive substring match would trip. Run standalone: bash tests/hooks/test-credential-guard.sh |
| test-dispatch-pretooluse.sh | Behavioral tests for hooks/dispatch-pretooluse.sh + dispatch-pretooluse.py (T12 #91). Two kinds of coverage: 1. PARITY: a real gate's output through the dispatcher must byte-match (or field-match) the same gate invoked directly, for the cases that matter most -- a denying gate, an asking gate, and an updatedInput redirect. This is the bar that actually matters: profile-filter and kill-switch tests alone would not have caught the systemMessage gap found live while building this (worktree-guard.py's redirect message was silently dropped by the merge on the first draft). 2. MERGE PRECEDENCE: synthetic fixture scripts (not real gates) exercise the deny > ask > allow ordering, the "blocking suppresses updatedInput" rule, the multi-updatedInput warning, and the […] |
| test-dispatch-single.sh | Behavioral tests for hooks/dispatch-single.sh (T12 #91) -- the profile-tier and kill-switch filter every non-PreToolUse hook now routes through. PreToolUse gates never use this wrapper (see dispatch-pretooluse.sh/.py and their own test file) -- there is no tiering concept for gates at all. Run standalone: bash tests/hooks/test-dispatch-single.sh |
| test-flow-nudge.sh | Flow-nudge unit tests: simulates UserPromptSubmit JSON payloads and asserts stdout output (nudge fired) vs silence (nudge skipped). The hook never blocks, so all tests expect exit 0. Run standalone: bash tests/hooks/test-flow-nudge.sh |
| test-gates.sh | Gate unit tests: simulates PreToolUse JSON payloads and asserts allow/deny/ask. Each test_deny call expects exit 2; test_allow expects exit 0 + empty stdout; test_ask expects exit 0 + a permissionDecision: ask JSON on stdout. Run standalone: bash tests/hooks/test-gates.sh |
| test-instructions-loaded-journal.sh | instructions-loaded-journal unit tests: simulates InstructionsLoaded JSON payloads and asserts one compact JSONL row lands per invocation, with the expected fields carried through. The hook has no decision control (its stdout is always empty/discarded), so every test checks the log file, not stdout, and every test expects exit 0. Run standalone: bash tests/hooks/test-instructions-loaded-journal.sh |
| test-jira-route-nudge.sh | jira-route-nudge unit tests: simulates UserPromptSubmit JSON payloads and asserts stdout output (nudge fired) vs silence (nudge skipped). The hook never blocks, so all tests expect exit 0. Run standalone: bash tests/hooks/test-jira-route-nudge.sh |
| test-learn-nudge.sh | learn-nudge unit tests: simulates SessionEnd JSON payloads pointing at a fixture transcript, asserts stderr output (nudge fired) vs silence (nudge skipped) and that stdout is ALWAYS empty (SessionEnd stdout is discarded — a hook that wrote a nudge there would be dead-at-birth). The hook never blocks (SessionEnd has no decision control), so all tests expect exit 0. Run standalone: bash tests/hooks/test-learn-nudge.sh |
| test-memory-health-nudge.sh | memory-health-nudge unit tests: focused on the --classify-unindexed wiring added on top of the pre-existing detector-findings nudge. Isolates a fake $HOME and a fake project cwd so real ~/.claude/projects state is never touched; the hook derives its memory dir from `pwd -P` (physical path, slashes -> dashes) the same way memory-lint.py's own memory_dir() does, so fixtures must be planted at that exact computed path. Run standalone: bash tests/hooks/test-memory-health-nudge.sh |
| test-precompact-state-flush.sh | precompact-state-flush unit tests (#92/T13): simulates PreCompact JSON payloads and asserts a deterministic snapshot (git HEAD, git status --porcelain, plugin/marketplace manifest versions) lands in ~/.local/share/kbg/metrics/precompact-snapshots.jsonl before compaction — the computational backstop for the same class of fact CLAUDE.md's own Compact-instructions section already asks the compacting model to preserve in prose. Pure flush: never emits permissionDecision, even though PreCompact supports one (verified against official docs before building this hook — deny would block compaction, which isn't this hook's job). Run standalone: bash tests/hooks/test-precompact-state-flush.sh |
| test-session-stop.sh | Session/Stop hook smoke tests: doctrine-bootstrap (SessionStart), command-root-anchor (SessionStart), memory-health-nudge (SessionStart), cost-tracker (Stop), memory-audit-commit (Stop). These hooks never block (no permissionDecision) — tests assert exit 0 + expected side effect (stdout injection / env-file append / metrics-file append), and that each fails safe (exit 0, no side effect) when its required env var is unset. Run standalone: bash tests/hooks/test-session-stop.sh |
| test-skill-usage-telemetry.sh | skill-usage-telemetry unit tests (#90/T11): simulates PostToolUse(Skill) payloads and asserts one compact JSONL row lands per invocation with {ts, session_id, skill, plugin} — no outcome/success field (see the hook's own header for why: no reliable success signal exists for a Skill call). Also covers harness-health.py's skill-usage panel: given a synthetic skill-usage.jsonl, does it render correct 7d/30d invocation counts split by plugin, and does it skip a malformed line without crashing. Run standalone: bash tests/hooks/test-skill-usage-telemetry.sh |
| test-verifier-protect.sh | Behavioral tests for verifier-protect.sh (always-on gate — no opt-in condition, unlike worktree-guard.py — fires on every Bash/Write/Edit call in every repo running this plugin). Had zero automated coverage before 2026-08-04: this file was added the same day as the round-3 port of worktree-guard.py's heredoc/ANSI-C/newline/$VAR/~ fixes into this gate's own embedded generator, specifically to close that gap. Run standalone: bash tests/hooks/test-verifier-protect.sh |
| test-worktree-guard.sh | Behavioral tests for the worktree-guard gate (opt-in, generic PreToolUse redirect). Uses the MH_GUARDED_WORKSPACE / MH_WORKTREE_ROOT env seams to run against throwaway repos — never touches any real workspace or ~/.worktrees. Run standalone: bash tests/hooks/test-worktree-guard.sh |

## Output styles — Repo
| Style | Description |
|---|---|
| staff-eng | Sole live-response register — self-calibrating: state the answer first for how-to/lookup/local changes, use decision+constraint+owner+revisit-trigger+verification-step framing only for genuine cross-boundary trade-offs or long-term consequences. Formal deliverables (PRs, docs, reports) switch to their own audience's register. |

---
_Generated: 2026-08-25T04:43:29Z_

---

## Task sizing guidance

Derived from the task-sizing guidance + article `agent-teams-best-practices`. Apply at `mh:orchestrate` plan time, before fan-out dispatch.

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
- **Total waves:** 3-5. More = plan is too coarse; fewer = use `/mattpocock-skills:implement` (single-agent) instead.
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

Canonical file patterns per agent. Assign each file to exactly one agent in an `orchestrate` dispatch plan to prevent silent overwrites. This table is a hand-maintained literal, not generated from `agents/*.md` — keep it in sync by hand when an agent is added or removed. Not covered by harness-audit check 12 (that check only verifies `skills/orchestrate/SKILL.md` + `reference.md`, not this table or `BOUNDARY.md`) — `inventory-boundary.sh` prints a stderr warning at regen time if this table and `agents/` disagree, but that's advisory, not a CI gate.

| Agent | Canonical file patterns | Mutates | Notes |
|---|---|---|---|
| `code-architect` | `architecture/`, `*.md` (design docs) | yes | Blueprints, not implementation — but `tools:` grants Bash (Bash can mutate) |
| `typescript-reviewer` | `*.ts`, `*.tsx`, `*.js`, `*.jsx` | yes | Read-only TS/JS review *by intent* — type safety, async correctness — `tools:` grants Bash (Bash can mutate) |
| `python-reviewer` | `*.py`, `pyproject.toml` | yes | Read-only Python review *by intent* — PEP 8, idioms, type hints — `tools:` grants Bash (Bash can mutate) |
| `security-reviewer` | `auth/`, `secrets/`, `config/`, `security/`, `iam/`, `crypto/` | yes | Vulnerability detection — `tools:` Read/Bash/Grep/Glob (Bash can mutate; no Edit/Write) |
| `silent-failure-hunter` | any file | yes | Read-only error-handling audit *by intent* — `tools:` grants Bash (Bash can mutate) |
| `spec-miner` | any file → `.scratch/specs/` | yes | Extracts behavioral specs (Write + Bash) |
| `refactor-cleaner` | any file | yes | Dead-code removal / deprecation scope (Edit/Bash) |
| `build-error-resolver` | any file with build/type errors | yes | Minimal-diff build/type fixes (Edit/Bash) |
| `performance-optimizer` | any file | yes | Bottleneck + bundle + memory fixes (Edit/Bash) |
| `ideate-critic` | none (read-only) | no | Fresh-context critic for `/ideate` Phase 2 (Read only — no Bash) |
| `a11y-architect` | components / design-system files (WCAG-relevant) | yes | Accessibility audits — `tools:` grants Write/Edit directly (no Bash) |
| `backend-architect` | `api/`, `services/` (design docs) | yes | API contracts, service boundaries — design-first — `tools:` grants Bash (Bash can mutate) |
| `blind-spot-hunter` | any file | yes | Read-only adversarial hunt for emergent defects *by intent*, post-review — `tools:` grants Bash (Bash can mutate) |
| `nextjs-reviewer` | Next.js App Router files (`app/`, `pages/`, middleware, route handlers) | yes | Read-only framework review *by intent* — `tools:` grants Bash (Bash can mutate) |
| `requirement-analyst` | none (read-only) | no | Requirement analysis from tickets/specs (Read/Glob/Grep only — no Bash) |
| `summarizer` | none (read-only) | no | Condenses text/docs/transcripts (Read/Glob/Grep only — no Bash) |


---

## Cross-references

- **[Agent tool patterns: allowlist vs denylist](docs/agent-tool-patterns.md)** — matt-harness convention is `tools:` (allowlist) for new agents; reserve `disallowedTools:` (denylist) for cases where the allowlist would exceed 6-7 tools or the team explicitly opts into implicit-inheritance. The `Mutates` column above reflects `Edit`/`Write`/`Bash` grants.
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
- **Stack:** Bash + Python 3 + jq; matt-harness is a Claude Code plugin (version in `.claude-plugin/plugin.json`)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** harness-audit (64 checks) + a 14-file hook behavioral suite, run in parallel by `scripts/run-gauntlet.sh` — see `CLAUDE.md`'s Validation section. The old critical-hooks suite + eval dataset gate were deleted, not rebuilt, in the 2026-06-27 reset (`c452102`). (Check/test counts here are hand-maintained — keep in sync with `ls skills/harness-audit/scripts/checks/*.sh | wc -l` and the test list in `scripts/run-gauntlet.sh`.)
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/kobig/mh/<version>/` (rebuilt on `claude plugin update mh@kobig`)

### Verification
- `bash "${MH_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" "${MH_PLUGIN_ROOT}"` — 0C/0W expected (INFO findings are non-blocking)
- `claude plugin validate --strict "${MH_PLUGIN_ROOT}"` — exit 0
- `bash "${MH_PLUGIN_ROOT}/scripts/run-gauntlet.sh"` — full parallel gauntlet (validate + lint + JSON + audit + 14-file hook suite)

---

## Trigger phrases

Map user intent → harness dispatch. Use these trigger phrases in `commands/`, `skills/`, and agent `description:` frontmatter so the flow nudge (`hooks/advisory/flow-nudge.sh`) routes correctly.

### Decisions & debate
| User says | Dispatch | Why |
|---|---|---|
| "what should I work on", "prioritize these", "plan this pile of work" | `mh:orchestrate` skill | Prioritize + route to cheapest correct executor |

### Single-task workflows
| User says | Dispatch | Why |
|---|---|---|
| "build one feature", "implement X", "scope this change" | `/mattpocock-skills:implement` | Implement a spec/tickets with TDD where possible → `mattpocock-skills:code-review` → commit |
| "fix this bug", "debug this" | `mattpocock-skills:diagnosing-bugs` | Feedback loop → hypothesize → instrument → fix + regression test |
| "address review feedback" | `/address-review` | PR review response |
| "ship it", "merge this" | `/ship-merge` | Pre-merge gate |
| "release now", "cut a release" | `/ship-release` | Release ceremony |

### Research & analysis
| User says | Dispatch | Why |
|---|---|---|
| "research this", "deep dive on X", "how does Y work" | `research` | Brain dump + Q&A + plan |
| "review this PR", "check this code" | `mattpocock-skills:code-review` skill | Standards + spec review since the kbg review pipeline retired (2026-08-24 #82) |
| "audit the harness", "check health" | `mh:harness-audit` skill | Self-audit |

### Incident & post-mortem
| User says | Dispatch | Why |
|---|---|---|
| "incident", "alerts firing", "monitors red" | `mh:incident` skill | Live incident response |
| "post-mortem", "writeup after incident" | `/post-mortem` | Incident documentation |
| "save my session", "hand off" | `handoff` | Session state capture |


---

## Reference docs

These files live in the plugin cache, not the project CWD. Read them via Bash with `MH_PLUGIN_ROOT` (exported by `hooks/session/command-root-anchor.sh`), not as relative markdown links.

- **Reasoning-models catalog** — `cat "${MH_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` — 39 named cc-thinking-skills mental models and the kbg surface that applies (or deliberately does not apply) each; points to the upstream repo for full write-ups.

