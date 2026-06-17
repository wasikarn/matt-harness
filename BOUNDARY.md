# Boundary Map
_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: `bash <kbg-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md` where `<kbg-harness>` is the kbg-harness repo root and `<dotfiles>` is the target repo root (or from the plugin cache: `bash ~/.claude/plugins/cache/kobig/kbg/$(ls ~/.claude/plugins/cache/kobig/kbg/ | sort -V | tail -1)/skills/inventory/scripts/inventory-boundary.sh --repo-only`)._
_Schema version: v3 (adds Output styles table; Mutates column reflects Edit/Write/Bash grant)._
# Inventory
_Legend: ◇ plugin-delivered / project-local_

## Source: Personals/kbg-harness
_Personals/kbg-harness_

### Skills (39)
  ◇ 7-agent-pattern                7-agent-pattern
  ◇ accept-task                    Lock a machine-checkable acceptance contract before any non-trivial task. Use when starting multi-file changes, schema migrations, or before dispatching write-capable agents; write `.scratch/<slug>/ACCEPTANCE.md` with criteria + start SHA. Use when user says 'lock acceptance', 'define acceptance criteria', or 'what does done look like'. Don't use for trivial single-file edits, read-only analysis, or existing contracts.
  ◇ acli                           Use when handling bulk Jira work-item operations and Confluence space/page/blog management from the terminal. Covers transitions, labels, assignments, comments, clones, archives, bulk-edit fields, JQL exports, and running acli commands. For creating a single Thai-format Bug or Story with guided AC, use kbg:create-jira-bug or kbg:create-jira-story instead. Don't use for single-ticket reads, JQL syntax help, install/config/auth, cheat sheets, GitHub/GitLab, or non-Atlassian trackers.
  ◇ adr                            adr
  ◇ article-mine                   Mine an article / repo / RFC / doc for doctrine via 5-agent fan-out, then ship in-session. Use when the user pastes a URL / file / text and says 'mine this', 'analyze this article', 'extract lessons', 'read this and apply', or 'what can we take from this' — to harvest doctrine for the harness. Don't use for: pure Q&A (kbg:research-brief), reasoning review (kbg:critical-eval), security (kbg:security-auditor), or PR review (kbg:review-pr).
  ◇ assert-presence                assert-presence
  ◇ backend-dev                    Backend implementation skill for API endpoints, DB migrations, webhooks, background jobs, rate limiters, error middleware, and schema design. Runs TDD + terminal-ops + architecture + diagnose. Use when the user asks for FastAPI/Flask/Django endpoints, SQL migrations, or Redis services. Don't use for: frontend UI/CSS, security-only audits (kbg:security-auditor), research (kbg:research-brief), infra deployment (devops-engineer), or frontend tests.
  ◇ clarify-first                  Ask the structured 3-step question (analyze, recommend, ask) BEFORE dispatching write-capable agents or starting multi-file changes where a wrong assumption wastes work. Trigger when a task is named but scope is unstated — 'fix the bug', 'refactor X', 'add Y', 'make it faster' with no file/metric/layer; or it spans subsystems with no clear boundary. Don't use for: explicit file paths, single-value changes, read-only requests, or rhetorical questions.
  ◇ create-jira-bug                Create a single Jira Bug using the team's Thai PO/QA-readable template. Tries acli first, falls back to Atlassian MCP when acli is unavailable or cannot set a required field. Use when the user says 'create bug', 'report a bug', 'file a Jira bug', or wants a structured Thai bug ticket with reproduction steps, impact, and Given/When/Then AC. Don't use for: bulk bug creation (use acli), editing an existing bug (use acli), security incidents (use kbg:incident/kbg:hotfix), or non-Jira trackers.
  ◇ create-jira-story              Create a single Jira Story using the team's Thai PO/QA-readable template. Tries acli first, falls back to Atlassian MCP when acli is unavailable or cannot set a required field. Use when the user says 'create story', 'new Jira story', 'write a story', or wants a structured Thai Story with business reason, scope, and Given/When/Then AC. Don't use for: bugs (use create-jira-bug), bulk story creation (use acli), editing an existing story (use acli), or technical tasks without PO-facing AC.
  ◇ critical-eval                  Stress-test reasoning in arguments, PRs, ADRs, RFCs, incidents, decisions. Use when asked to critique, evaluate reasoning, check assumptions, stress-test arguments, review logic, verify it holds up, or when something feels off. Flag overconfident plans (definitely safe, zero downtime). Don't use for: system dynamics/architecture trade-offs (kbg:backend-dev/code-architect), code review (kbg:review-pr), security audit (kbg:security-auditor), or research (kbg:research-brief).
  ◇ decommission                   decommission
  ◇ harness-audit                  harness-audit
  ◇ harness-coverage               Read-only harness-coverage report: renders the 2x2x3 (12-cell) grid from `hooks/sensors.json` and the governance journal, with a 60% decay threshold and the intentional-gap cell `inf-fb-behaviour` flagged. Use when the operator wants to know which cells are populated, stale, or empty, wants a quarter-end decay measurement, or a 12-row table view of the journal. Don't use for: per-session drill-down or a verdict stream (use `kbg:harness-health`), or per-sensor fire-rate (read the journal).
  ◇ harness-health                 Read-only query surface over the governance journal. Surfaces structural-judge verdicts (accept/flag/escalate) and sensor staleness from `hooks/sensors.json`, with per-sensor fire counts so silent sensors stay visible. Use when the user asks 'what's the harness health', 'last 10 verdicts', 'verdicts > 7 in 30 days', or 'silent-sensor count'. Don't use for: deep PR review (kbg:review-pr), security posture (kbg:security-auditor), fleet audit (kbg:harness-audit), or running the scoring engine.
  ◇ harness-nav                    L3 escape hatch for kbg-harness capability discovery. Use when no known skill, command, or agent clearly covers your task — teaches grep recipes to mine BOUNDARY.md, skills/, agents/, commands/ for the right capability. Returns the nearest match or confirms none exists. Don't use for: tasks where the right skill is already known (use it directly), or operational health queries (use kbg:harness-health). Reach for it only when the skill-nudge hook didn't surface the match.
  ◇ hotfix                         Use this skill for emergency production fixes requiring immediate code change. Trigger when user says 'production is down', 'critical bug', 'hotfix', 'emergency patch', 'P0', 'outage', or any production-wide incident. Rollback-first, severity-gated SLA, timeboxed execution. Do NOT use for: non-urgent bugs (use /fix-bug), subset-affecting issues, new features, or when rollback/kill-switch suffices.
  ◇ ideate                         Parallel divergent ideation. Use when prompts are open-ended (design, architecture, naming, API/SDK, fuzzy-debug) AND high-stakes AND open phrasing — spawns 5 isolated agent calls under different cognitive frames (regulator, 10-year-old, ant-colony, speedrunner, 3am, biology), scores on novelty/viability/fit, prunes traps, deepens top 3. Also fires on /ideate, brainstorm/ideate intents. Don't use for syntax, lookups, known-root-cause bugs, or closed phrasing ('quick', 'standard', 'canonical', 'textbook'). Pre-flight gate in body.
  ◇ incident                       Manage a live production incident end-to-end — detect, assess, mitigate, communicate, resolve, and handoff. Use when alerts fire, monitors show red, users report widespread issues, or error rates spike. Do NOT use for: non-production bugs (use /fix-bug), planned maintenance, security incidents requiring special handling (use security-reviewer first), or post-incident documentation (use /post-mortem after resolution).
  ◇ inventory                      inventory
  ◇ kbg-help                       Detailed reference card for kbg-harness: context tiers (L1/L2/L3), skill/command index, validation pipeline, plugin cache-invalidation, and load-bearing invariants. Use when the user asks for help, 'what can kbg do', 'how do I use the harness', or 'explain kbg'. Don't use for: deep capability discovery (use kbg:harness-nav) or governance journal queries (use kbg:harness-health). One-shot display, read-only.
  ◇ memory-lint                    memory-lint
  ◇ memory-trim                    memory-trim
  ◇ migrate                        Deprecate and migrate legacy code, APIs, or dependencies safely. Use when the user says 'migrate to v2', 'upgrade from X to Y', 'deprecate this API', 'extract this module', or when retiring systems, upgrading major versions, or migrating databases. Don't use for: new features (/feature-dev), hot bug fixes (/fix-bug, kbg:hotfix), refactors without a deprecation target, or when rollback is impossible.
  ◇ orchestrate                    Prioritize competing tasks, then route each to inline / batch-parallel / pipeline-sequential / drop. Use when the user lists competing tasks, asks 'what should I work on' or 'what's the priority', plans a day/week/sprint, feels overwhelmed, or spans independent sub-tasks or sequential phases. Don't use for: single-issue triage (triage), PR review (kbg:review-pr), one feature (/feature-dev), or single-file coding (inline).
  ◇ perf                           Performance regressions and bottlenecks. Trigger on latency spikes, throughput drops, memory leaks/growth, CPU saturation, slow queries, cache misses/CI, cold starts, resolver/ETL timeouts, or reported slowness. Don't use for: production outages (kbg:incident/kbg:hotfix), functional bugs without perf symptoms (/fix-bug), architectural redesigns (/deep-dive, code-architect), or capacity planning.
  ◇ probe                          probe
  ◇ progressive-refine             progressive-refine
  ◇ recursive-improve              recursive-improve
  ◇ research-brief                 Research brief with search-first + diagnose preloaded. Use when user says 'research this', 'deep dive on X', 'how does Y work in this codebase', 'compare Z approaches', or any open-ended exploration spanning files, docs, and external sources. Don't use for: implementation work (use /feature-dev or kbg:backend-dev), bug fixes (use /fix-bug), or security audits (use kbg:security-auditor).
  ◇ review-pr                      Run multi-agent PR review across code quality, tests, comments, errors, security, types, accessibility/UX, and simplification. Use when finishing changes before opening a PR, when a PR is ready, after addressing feedback, or when asked to review changes/aspects. Don't use for: single-file diffs (review inline), security-only audits (kbg:security-auditor), post-merge retrospectives, or invoking a single agent (use Agent tool).
  ◇ security-auditor               Use when auditing or reviewing security flaws in auth, secrets, external input, file uploads, or dependencies. Covers injection, XSS/CSRF/SSRF, path traversal, broken access control, secret leaks, or vulnerable components. Use when PRs touch auth, APIs, admin panels, payments, or dep manifests. Don't use for: code review (kbg:review-pr), incidents (kbg:hotfix/kbg:incident), or non-code security (infra, policy).
  ◇ semantic-code                  semantic-code
  ◇ ship-change                    Orchestrate the full change lifecycle from classify → implement → review → address → merge. Use when starting non-trivial changes needing guided sequencing through /fix-bug, /feature-dev, kbg:review-pr, /address-review, and /ship-merge. Don't use for: one-line fixes, changes already mid-flight, or pure research/exploration.
  ◇ task-sizing                    task-sizing
  ◇ tech-humanize                  Humanize dev/tech writing in English and/or Thai to sound natural, not AI-generated. Use when editing standup reports, PR descriptions, commit messages, ADRs, UI copy, or 'fix this to read less AI'. Covers English, Thai, and Thai↔English code-switching. Use when user says humanize, แก้ให้เป็นธรรมชาติ, เขียนให้ฟังดูเป็นคน, ปรับ tone, or 'less like ChatGPT'. Don't use for translation, detection-only analysis, or code identifiers.
  ◇ triage                         Single-issue triage: classify a bug, feature request, or task by severity, scope, and owner. Use when the user dumps a single issue and you need to decide whether to route it to /feature-dev, /fix-bug, /deep-dive, or kbg:orchestrate. Don't use for: prioritizing a batch (use kbg:orchestrate), or building a feature (use /feature-dev).
  ◇ types-first                    types-first
  ◇ usage-monitor                  Read-only cost and subagent usage summary for the current session. Use when the user asks about session cost, token burn, cost breakdown by agent, or suspects nested-team token amplification. Reads the SessionEnd capture at `~/.claude/usage/<slug>.jsonl`; L2 read-only, no gates. Don't use for: real-time cost gating (none exists), cross-session aggregation, or OTEL/OTLP export (not implemented).

### Commands (19)
  ◇ address-review                 Triage and respond to existing PR review comments — fetch threads via gh, classify (action/clarify/wontfix/out-of-scope), implement fixes (delegate to /fix-bug), reply per-thread with commit sha, re-request review. Use when a PR has open review threads, after kbg:review-pr returns findings, or user says 'address the review'. Don't use for: doing the review yourself (use kbg:review-pr), pre-PR cleanup, or merging post-approval (use /ship-merge).
  ◇ debug-debate                   Resolve a technical disagreement by spawning parallel debate agents: Advocate, Skeptic, and Synthesizer debate the topic in isolation, then the lead produces a consensus matrix with ranked risks. Use when the user asks 'which is better', 'should we use X or Y', or when teammates disagree on architecture. Don't use for: implementation work (use /feature-dev), research (use /deep-dive), or prioritization (use kbg:orchestrate).
  ◇ deep-dive                      Research a topic thoroughly across codebase, docs, and web, then synthesize findings into a concise actionable brief with sources. Use when user says 'research this', 'deep dive on X', 'compare Z approaches', or any open-ended exploration. Do NOT use for: single-file lookups (just Read it), known answers (ask directly), implementation tasks (use /feature-dev or /fix-bug), or structural system analysis (spawn code-architect).
  ◇ dismiss-stale                  Dismiss the sensor-staleness notification for 7 days (writes ~/.claude/state/kbg-staleness-dismissed.json with the current stale-set hash). Use when the user says 'dismiss', 'silence the staleness alert', 'mute the sensor warning', or after a SessionStart injection has been acknowledged. The dismissal is hash-gated: a new sensor going stale re-injects immediately. Don't use for: removing sensors (decay-cadence), silencing one specific sensor (edit hooks/sensors.json), or auditing why a sensor is stale (run /harness-audit).
  ◇ feature-dev                    Guided 7-phase feature development workflow (discover → explore codebase → ask clarifying questions → design architecture → implement → review → summarize). Use when starting a non-trivial new feature where deep codebase understanding and architectural choices matter. Don't use for: bug fixes (use /fix-bug), refactors (spawn `maintenance-engineer` agent), one-line changes (just do it), or quick prototypes (just do it inline).
  ◇ fix-bug                        Guided 7-phase bug-fix workflow with diagnostic and test-first patterns built in. Use when fixing non-trivial bugs with non-obvious root causes, unclear blast radius, or need regression-test pinning. Don't use for: typos/one-line fixes (just fix it), known-cause bugs with obvious fixes (skip ceremony), diagnostic-only loops (use kbg:backend-dev), greenfield TDD (use kbg:backend-dev), or refactors not driven by a bug (spawn maintenance-engineer).
  ◇ kbg-help                       Quick reference card for kbg-harness skills, commands, validation pipeline, and context tiers. Use when the user asks 'help', 'what can you do', 'list skills', 'how do I use kbg', or 'kbg commands'. Don't use for: deep capability discovery (use kbg:harness-nav) or governance journal queries (use kbg:harness-health). One-shot display, read-only.
  ◇ post-mortem                    Draft a canonical post-mortem for a resolved bug. Requires reproducible trigger, known mechanism, identified patch, and passing validation. Use after /fix-bug completes or when user says 'write post-mortem', 'document this bug', 'incident report'. Don't use for: in-progress investigations (root cause must be known), hypothetical bugs (no validated fix), or non-technical incidents (use incident response template instead).
  ◇ pre-flight-plan-linter         Validate a /team-plan artifact before /team-build consumes it. Catches structural errors, missing validation commands, cyclic dependencies, overlapping file ownership, and F10 plan-approval risks. Use after /team-plan finishes and before /team-build starts. Don't use for: single-file work (no plan file needed), or plans you already started building (use /wave-status instead).
  ◇ pre-ship-verify                Run machine-checkable acceptance criteria for the current task before shipping. Use when a task has an ACCEPTANCE.md and you want deterministic verification before merge, release, or PR submission. Don't use for: tasks without an acceptance contract (no ground truth to verify), or when the user has already manually verified and explicitly says 'skip checks'.
  ◇ ship-merge                     Merge an approved PR safely: validate state, execute server-side merge, clean up branch, monitor CI post-merge. Use when the user says 'merge this PR', 'ship it', or after /address-review or /ship-release reaches the merge gate. Do NOT use for: unapproved PRs (wait for approval), PRs with failing CI (fix first), or hotfixes that need direct push (use `hotfix` skill).
  ◇ ship-release                   Cut a software release end-to-end: version bump → changelog → review gate → tag → merge → monitor. Use when the user says 'ship release', 'cut a release', 'prepare version X.Y.Z', or when a release branch is ready for tagging. Do NOT use for: one-off PR merges (use /ship-merge), hotfixes (use `hotfix` skill), or when there is no release branch / tag strategy defined.
  ◇ ship-task                      9-step senior-engineer loop from scratch: explore → clarify → accept-task → implement → (auto-test hook) → review → fix-loop → ship. Use when starting a non-trivial task from a blank slate. Don't use for: tasks already mid-flight (use kbg:ship-change), one-line fixes, pure research/exploration.
  ◇ status-update                  Rewrite engineering content for leadership (VPs, directors, PMs) and shape for channel — JIRA, Slack, standup, email, or talking-points. Trigger when user asks to write/rewrite for management/exec/VP/PM, asks for 'executive summary / leadership update', or wants a channel-specific version. Don't use for: technical documentation (defer to technical-writer), tone humanization (use kbg:tech-humanize), or peer-level standup notes.
  ◇ team-build                     Phase 2 of the agent-teams workflow: read .claude/tasks/<slug>.md, apply the plan approval filter (F10), spawn agents in waves using the F9 spawn-prompt template, then run post-build validation. Use after /team-plan completes, or when user says 'team build: <slug>', 'execute the plan'. Don't use for: features without a plan file (run /team-plan first), or single-agent work (use /feature-dev).
  ◇ team-cleanup                   Clean up stale agent-team artifacts: old locks, dead heartbeats, orphaned board entries, archived completed plans, and expired mailbox messages. Use after a /team-build finishes, when the user says 'clean up the team', 'remove old plans', or when disk space in ~/.claude/tasks/ grows. Don't use for: active builds (use /wave-status first to verify completion), or plans you intend to resume (the archive is reversible for 30 days).
  ◇ team-plan                      Phase 1 of the agent-teams workflow: brain-dump the feature, research codebase, ask clarifying questions, then write a structured plan to .claude/tasks/<slug>.md with team members, dependency chains, file ownership, acceptance criteria, and validation commands. Use when starting non-trivial features for multi-agent parallel implementation, or when user says 'team plan: X'. Don't use for: single-file changes (use /feature-dev), trivial features (do inline), or research-only tasks (use /deep-dive).
  ◇ validate-and-fix               Run the builder-validator-fix-revalidator quality chain on a single completed task. Use after a teammate claims a task is done but you want independent validation before merging. Don't use for: pre-execution plan validation (use /team-build's F10 gate), post-build whole-project validation (use /pre-ship-verify), or tasks without a plan file (use /feature-dev for single-file work).
  ◇ wave-status                    Report real-time status of a multi-agent build: current wave, task progress, stale heartbeats, active locks, and ETA. Use during /team-build execution to check progress, or when the user asks 'where are we', 'status of the build', 'is the team done'. Don't use for: single-file work (use /status-update), or before a plan exists (use /team-plan first).

### Agents (29)
  ◇ api-doc-specialist             Senior API documentation specialist for OpenAPI specs, SDK references, and developer-portal content. Spawn when generating or updating API contract docs, designing endpoint naming, or building integration guides. Don't use for: user-facing product docs (defer to technical-writer), frontend component docs (defer to frontend-engineer), or internal runbooks (defer to technical-writer). Owns the contract between your API and its consumers.
  ◇ backend-engineer               Senior backend engineer for API design, data integrity, server-side implementation, and schema/migration work. Spawn when implementing or reviewing backend code, database changes, or service-side refactoring. Don't use for: auth/secrets (defer to security-reviewer), UI rendering (defer to frontend-engineer), infrastructure/CI/CD (defer to devops-engineer), or test strategy (defer to test-engineer). Owns backend-side data integrity and contract stability.
  ◇ code-architect                 Senior architect for actionable blueprints. Spawn when designing non-trivial features needing committed architecture — analyzes existing patterns, picks one approach with file paths, interfaces, data flows, and phased build sequence. Don't use for: refactoring existing architecture (defer to backend-engineer), task breakdown without depth (use kbg:orchestrate), or single-file changes.
  ◇ code-explorer                  Senior codebase tracer for end-to-end feature understanding. Spawn before modifying or extending existing features — follows execution paths, maps abstraction layers, identifies dependencies. Don't use for: finding files by name (spawn Explore subagent), researching external packages (use kbg:research-brief), or designing new architecture (use code-architect). Returns file:line references + essential files to read.
  ◇ code-reviewer                  Senior code-quality reviewer for bugs and guideline compliance. Spawn after writing/modifying code, before commit or PR — reviews unstaged git diff by default. Don't use for: security (defer to security-reviewer), test coverage (defer to pr-test-analyzer), error-handling (defer to silent-failure-hunter), or comment accuracy (defer to comment-analyzer). Owns general bug + convention review.
  ◇ code-simplifier                Senior post-implementation code simplifier for clarity and conventions without changing behavior. Spawn after coding tasks land when code works but is verbose or hard to read. Don't use for: bug review (use code-reviewer), architecture design (use code-architect), or whole-codebase refactoring (defer to maintenance-engineer). Owns clarity-preserving simplification.
  ◇ comment-analyzer               Senior comment & docstring auditor for accuracy and value. Spawn after adding/modifying documentation comments, before PR finalization, or when checking comment accuracy. Don't use for: general code review (defer to code-reviewer), or stripping comments wholesale (this agent assesses value, doesn't delete). Owns comment accuracy + maintainability.
  ◇ compliance-engineer            Senior compliance/privacy engineer for GDPR, SOC2, HIPAA, and audit-readiness. Spawn when designing data retention, mapping controls to frameworks, or preparing audit evidence. Don't use for: threat modeling or vulnerability scanning (defer to security-reviewer), production code implementation (defer to backend/frontend-engineer), or infrastructure deployment (defer to devops-engineer).
  ◇ data-engineer                  Senior data engineer for ETL pipelines, data models, streaming ingestion, batch transforms, and analytics schemas beyond relational OLTP. Spawn when building pipelines, designing warehouse schemas, or optimizing analytical query performance. Don't use for: OLTP API design (defer to backend-engineer), frontend dashboards (defer to frontend-engineer), ML training (defer to ml-engineer), or generic scripting (defer to backend-engineer).
  ◇ devops-engineer                Senior devops/SRE engineer for CI/CD, deployment, observability, and infrastructure as code. Spawn when changing build pipelines, deploy configs, monitoring, or infrastructure. Don't use for: application logic (defer to backend-engineer), security policy/vulnerability review (defer to security-reviewer), or auth/secrets handling (defer to security-reviewer). Owns runtime and deploy concerns.
  ◇ finops-engineer                Senior FinOps engineer for cloud cost optimization, reserved-instance planning, and spend governance. Spawn when cloud bills spike unexpectedly, when rightsizing instances, or when designing cost-aware architecture. Don't use for: general infrastructure provisioning (defer to devops-engineer), application performance tuning (defer to backend-engineer), or security audit (defer to security-reviewer).
  ◇ frontend-engineer              Senior frontend engineer for UI components, accessibility, state management, and design integration. Spawn when implementing or reviewing frontend code, design implementations, or client-side state. Don't use for: backend API design (defer to backend-engineer), threat-model review (defer to security-reviewer), deploy/build changes (defer to devops-engineer), or mobile apps (defer to mobile-engineer).
  ◇ i18n-specialist                Senior internationalization and localization engineer for multi-locale software. Spawn when adding new language support, designing translation pipelines, or fixing RTL layout and locale-specific formatting. Don't use for: general frontend feature implementation (defer to frontend-engineer), UX heuristic evaluation (defer to ux-reviewer), or backend API design (defer to backend-engineer). Owns the full i18n/l10n stack from key extraction to regional deployment.
  ◇ ideate-critic                  Fresh-context critic for the ideate skill. Scores, clusters, and deepens divergent ideas produced by ideate Phase 1. Invoked by skills/ideate/SKILL.md Phase 2 instead of running the critic pass on the host Claude, to reduce LLM-judge-circularity (CLAUDE.md §LLM-judge-circularity). Read-only: scores and reports, never blocks, never mutates the repo. Use when ideate needs a critic pass. Don't use for: code review (code-reviewer), structural diff judgment (inferential-structural-judge), or security audit (security-reviewer).
  ◇ incident-commander             Senior incident commander for production incident response, post-mortems, and error-budget governance. Spawn when an incident is active, coordinating responders, or when a service breaches its error budget. Don't use for: infrastructure deployment (defer to devops-engineer), bug fixes (defer to backend-engineer/frontend-engineer), or security breach response (defer to security-reviewer). Owns human coordination and decision timeline during incidents.
  ◇ inferential-structural-judge   Inferential-FB sensor that judges the session's diff against 4 structural dimensions: over_engineering, arch_drift, test_pattern, doctrine_conformance. Invoked by the SessionEnd hook (HOOK-1) once per session; journals a verdict to ~/.claude/governance-events.jsonl with event=inferential_structural_verdict per docs/research/inferential-structural-judge-design.md §3. Advisory only — journal-only verdict, never blocks, never mutates code (autonomy invariant, ADR 0002 §L115). Score 1-3 = silent accept; 4-6 = flag (surfaces in kbg:harness-health); 7-10 = escalate (mirrors to next SessionStart additionalContext). Cost ceiling: ~4k tokens/session; if session is already at ≥ 25k tokens, the hook skips and journals skipped:budget. Hard cap of 50 files in the diff (truncated=true beyond). Use when: SessionEnd lifecycle fires and the session touched ≥ 1 file. Don't use for: deep PR review (use kbg:review-pr), security audit (defer to security-reviewer), test coverage (defer to pr-test-analyzer), or live diff review (defer to code-reviewer).
  ◇ maintenance-engineer           Senior legacy and technical-debt engineer for refactoring, deprecation, framework upgrades, and modernization. Spawn when removing dead code, upgrading dependencies, migrating architecture, or quantifying technical debt. Don't use for: new features (defer to backend-engineer/frontend-engineer), greenfield architecture (defer to code-architect), or CI/CD changes (defer to devops-engineer). Owns post-delivery code health.
  ◇ ml-engineer                    Senior ML engineer for model serving, feature stores, ML pipelines, and MLOps infrastructure. Spawn when building inference APIs, designing feature pipelines, or operationalizing ML systems beyond training. Don't use for: pure data ETL (defer to data-engineer), frontend dashboards (defer to frontend-engineer), or security audit of model inputs (defer to security-reviewer). Owns ML systems in production: serving, monitoring, and feature management.
  ◇ mobile-engineer                Senior mobile engineer for iOS, Android, and React Native development. Spawn when building native or cross-platform mobile features, handling app store submissions, or optimizing mobile-specific performance. Don't use for: web-only frontend work (defer to frontend-engineer), backend API design (defer to backend-engineer), or pure data pipeline work (defer to data-engineer). Owns the mobile application layer and platform-specific concerns.
  ◇ platform-engineer              Senior platform engineer for microservices, service mesh, API gateways, event-driven architecture, and DX tooling. Spawn when designing inter-service communication, circuit breakers, sagas, gRPC contracts, or platform abstractions. Don't use for: application business logic (defer to backend-engineer), CI/CD configuration (defer to devops-engineer), or frontend components (defer to frontend-engineer).
  ◇ pr-test-analyzer               Senior PR test-coverage analyzer. Spawn after PR open/update or before ready-for-review to surface untested critical paths. Don't use for: writing tests (defer to test-engineer), or chasing line-coverage % (rates by behavioral criticality 1–10, not coverage %). Owns regression-risk visibility before merge.
  ◇ product-analyst                Senior product analyst for requirements elicitation, user-story decomposition, scope definition, and acceptance-criteria design. Spawn when translating vague ideas into engineering specs or user value is unclear. Don't use for: technical implementation (defer to backend/frontend-engineer), architecture blueprints (defer to code-architect), or code-level tracing (defer to code-explorer).
  ◇ researcher                     Senior research specialist for libraries, approaches, and external docs. Spawn when exploring unfamiliar technology, comparing options, or onboarding to a new module. Don't use for: tracing internal code (defer to code-explorer), implementing code (defer to backend-engineer/frontend-engineer), or fast symbol lookups (spawn Explore subagent).
  ◇ security-reviewer              Senior cross-cutting security reviewer for auth, secrets, input validation, OWASP Top 10, and supply chain. Spawn before merge on changes touching auth/secrets/external input, or on active credential leaks. Flags with severity + OWASP; defers fixes to backend/frontend/devops-engineer. Don't use for: general code-quality review (defer to code-reviewer) or non-security implementation (defer to backend/frontend-engineer).
  ◇ silent-failure-hunter          Senior error-handling auditor + adversarial plan reviewer. Spawn after error-handling changes (new catches, modified blocks, fallback logic) or after multi-role merges needing a skeptic against the plan. Don't use for: writing error handling from scratch (defer to backend-engineer/frontend-engineer), or general code review (defer to code-reviewer).
  ◇ technical-writer               Senior technical writer for READMEs, ADRs, runbooks, API docs, onboarding guides, and changelog prose. Spawn when creating docs from scratch, rewriting stale docs, or turning tribal knowledge into reference material. Don't use for: code review (defer to code-reviewer), security audit docs (defer to security-reviewer), or one-line inline comments (defer to the engineer who wrote the code).
  ◇ test-engineer                  Senior test-discipline owner for coverage design, edge cases, contract testing, and integration boundaries. Spawn when writing tests for new features or designing test strategy. Don't use for: reviewing PR test-coverage gaps (defer to pr-test-analyzer), implementing production code — write tests that drive the implementation, defer fixes to backend-engineer or frontend-engineer. Tests must encode WHY behavior matters, not just WHAT it does.
  ◇ type-design-analyzer           Senior type-design reviewer for encapsulation, invariants, and API contracts. Spawn after writing/modifying types, interfaces, DTOs, models, or schemas crossing module boundaries or public APIs. Grades encapsulation on 1–10. Don't use for: general code review (defer to code-reviewer), security (defer to security-reviewer), performance (defer to kbg:perf), or runtime verification (defer to test-engineer).
  ◇ ux-reviewer                    Senior UX and interaction reviewer for user journeys, accessibility, cognitive load, and form/task flow. Spawn when evaluating UI/UX implementations, reviewing from the user's perspective, or auditing accessibility gaps. Don't use for: visual design polish (defer to frontend-engineer), frontend component code review (defer to frontend-engineer), or performance optimization (defer to backend-engineer/frontend-engineer). Owns the UX layer between design and code.

### Hooks (6)
  ◇ _lib.py                        Pinned — JOURNAL-SCHEMA.md § "source" enum. Do NOT change to a per-language
  ◇ _lib.sh                        _lib.sh — shared protocol for Claude Code hooks (PreToolUse / UserPromptSubmit / etc).
  ◇ hooks.json                     (no description)
  ◇ hooks.json.test.bak            (no description)
  ◇ JOURNAL-SCHEMA.md              Governance Evidence Journal — Schema Contract
  ◇ sensors.json                   (no description)

## Agents — Repo
| Agent | Domain | Tools | Mutates |
|---|---|---|---|
| api-doc-specialist | Senior API documentation specialist for OpenAPI specs, SDK references, and developer-portal content. Spawn when generating or updating API contract docs, designing endpoint naming, or building integration guides. Don't use for: user-facing product docs (defer to technical-writer), frontend component docs (defer to frontend-engineer), or internal runbooks (defer to technical-writer). Owns the contract between your API and its consumers. | Read, Grep, Glob, Edit, Write, Bash | yes |
| backend-engineer | Senior backend engineer for API design, data integrity, server-side implementation, and schema/migration work. Spawn when implementing or reviewing backend code, database changes, or service-side refactoring. Don't use for: auth/secrets (defer to security-reviewer), UI rendering (defer to frontend-engineer), infrastructure/CI/CD (defer to devops-engineer), or test strategy (defer to test-engineer). Owns backend-side data integrity and contract stability. | Read, Grep, Glob, Edit, Write, Bash | yes |
| code-architect | Senior architect for actionable blueprints. Spawn when designing non-trivial features needing committed architecture — analyzes existing patterns, picks one approach with file paths, interfaces, data flows, and phased build sequence. Don't use for: refactoring existing architecture (defer to backend-engineer), task breakdown without depth (use kbg:orchestrate), or single-file changes. | Glob, Grep, Read, WebFetch, WebSearch, Bash | yes |
| code-explorer | Senior codebase tracer for end-to-end feature understanding. Spawn before modifying or extending existing features — follows execution paths, maps abstraction layers, identifies dependencies. Don't use for: finding files by name (spawn Explore subagent), researching external packages (use kbg:research-brief), or designing new architecture (use code-architect). Returns file:line references + essential files to read. | Glob, Grep, Read, WebFetch, WebSearch, Bash | yes |
| code-reviewer | Senior code-quality reviewer for bugs and guideline compliance. Spawn after writing/modifying code, before commit or PR — reviews unstaged git diff by default. Don't use for: security (defer to security-reviewer), test coverage (defer to pr-test-analyzer), error-handling (defer to silent-failure-hunter), or comment accuracy (defer to comment-analyzer). Owns general bug + convention review. | Glob, Grep, Read, WebFetch, WebSearch, Bash | yes |
| code-simplifier | Senior post-implementation code simplifier for clarity and conventions without changing behavior. Spawn after coding tasks land when code works but is verbose or hard to read. Don't use for: bug review (use code-reviewer), architecture design (use code-architect), or whole-codebase refactoring (defer to maintenance-engineer). Owns clarity-preserving simplification. | Read, Grep, Glob, Edit, Write, Bash | yes |
| comment-analyzer | Senior comment & docstring auditor for accuracy and value. Spawn after adding/modifying documentation comments, before PR finalization, or when checking comment accuracy. Don't use for: general code review (defer to code-reviewer), or stripping comments wholesale (this agent assesses value, doesn't delete). Owns comment accuracy + maintainability. | Read, Grep, Glob, Bash | yes |
| compliance-engineer | Senior compliance/privacy engineer for GDPR, SOC2, HIPAA, and audit-readiness. Spawn when designing data retention, mapping controls to frameworks, or preparing audit evidence. Don't use for: threat modeling or vulnerability scanning (defer to security-reviewer), production code implementation (defer to backend/frontend-engineer), or infrastructure deployment (defer to devops-engineer). | Read, Grep, Glob, Edit, Write, Bash | yes |
| data-engineer | Senior data engineer for ETL pipelines, data models, streaming ingestion, batch transforms, and analytics schemas beyond relational OLTP. Spawn when building pipelines, designing warehouse schemas, or optimizing analytical query performance. Don't use for: OLTP API design (defer to backend-engineer), frontend dashboards (defer to frontend-engineer), ML training (defer to ml-engineer), or generic scripting (defer to backend-engineer). | Read, Grep, Glob, Edit, Write, Bash | yes |
| devops-engineer | Senior devops/SRE engineer for CI/CD, deployment, observability, and infrastructure as code. Spawn when changing build pipelines, deploy configs, monitoring, or infrastructure. Don't use for: application logic (defer to backend-engineer), security policy/vulnerability review (defer to security-reviewer), or auth/secrets handling (defer to security-reviewer). Owns runtime and deploy concerns. | Read, Grep, Glob, Edit, Write, Bash | yes |
| finops-engineer | Senior FinOps engineer for cloud cost optimization, reserved-instance planning, and spend governance. Spawn when cloud bills spike unexpectedly, when rightsizing instances, or when designing cost-aware architecture. Don't use for: general infrastructure provisioning (defer to devops-engineer), application performance tuning (defer to backend-engineer), or security audit (defer to security-reviewer). | Read, Grep, Glob, Bash, WebSearch | yes |
| frontend-engineer | Senior frontend engineer for UI components, accessibility, state management, and design integration. Spawn when implementing or reviewing frontend code, design implementations, or client-side state. Don't use for: backend API design (defer to backend-engineer), threat-model review (defer to security-reviewer), deploy/build changes (defer to devops-engineer), or mobile apps (defer to mobile-engineer). | Read, Grep, Glob, Edit, Write, Bash | yes |
| i18n-specialist | Senior internationalization and localization engineer for multi-locale software. Spawn when adding new language support, designing translation pipelines, or fixing RTL layout and locale-specific formatting. Don't use for: general frontend feature implementation (defer to frontend-engineer), UX heuristic evaluation (defer to ux-reviewer), or backend API design (defer to backend-engineer). Owns the full i18n/l10n stack from key extraction to regional deployment. | Read, Grep, Glob, Edit, Write, Bash | yes |
| ideate-critic | Fresh-context critic for the ideate skill. Scores, clusters, and deepens divergent ideas produced by ideate Phase 1. Invoked by skills/ideate/SKILL.md Phase 2 instead of running the critic pass on the host Claude, to reduce LLM-judge-circularity (CLAUDE.md §LLM-judge-circularity). Read-only: scores and reports, never blocks, never mutates the repo. Use when ideate needs a critic pass. Don't use for: code review (code-reviewer), structural diff judgment (inferential-structural-judge), or security audit (security-reviewer). | inherit-all | no |
| incident-commander | Senior incident commander for production incident response, post-mortems, and error-budget governance. Spawn when an incident is active, coordinating responders, or when a service breaches its error budget. Don't use for: infrastructure deployment (defer to devops-engineer), bug fixes (defer to backend-engineer/frontend-engineer), or security breach response (defer to security-reviewer). Owns human coordination and decision timeline during incidents. | Read, Grep, Glob, Bash, WebSearch | yes |
| inferential-structural-judge | Inferential-FB sensor that judges the session's diff against 4 structural dimensions: over_engineering, arch_drift, test_pattern, doctrine_conformance. Invoked by the SessionEnd hook (HOOK-1) once per session; journals a verdict to ~/.claude/governance-events.jsonl with event=inferential_structural_verdict per docs/research/inferential-structural-judge-design.md §3. Advisory only — journal-only verdict, never blocks, never mutates code (autonomy invariant, ADR 0002 §L115). Score 1-3 = silent accept; 4-6 = flag (surfaces in kbg:harness-health); 7-10 = escalate (mirrors to next SessionStart additionalContext). Cost ceiling: ~4k tokens/session; if session is already at ≥ 25k tokens, the hook skips and journals skipped:budget. Hard cap of 50 files in the diff (truncated=true beyond). Use when: SessionEnd lifecycle fires and the session touched ≥ 1 file. Don't use for: deep PR review (use kbg:review-pr), security audit (defer to security-reviewer), test coverage (defer to pr-test-analyzer), or live diff review (defer to code-reviewer). | inherit-all | no |
| maintenance-engineer | Senior legacy and technical-debt engineer for refactoring, deprecation, framework upgrades, and modernization. Spawn when removing dead code, upgrading dependencies, migrating architecture, or quantifying technical debt. Don't use for: new features (defer to backend-engineer/frontend-engineer), greenfield architecture (defer to code-architect), or CI/CD changes (defer to devops-engineer). Owns post-delivery code health. | Read, Grep, Glob, Edit, Write, Bash | yes |
| ml-engineer | Senior ML engineer for model serving, feature stores, ML pipelines, and MLOps infrastructure. Spawn when building inference APIs, designing feature pipelines, or operationalizing ML systems beyond training. Don't use for: pure data ETL (defer to data-engineer), frontend dashboards (defer to frontend-engineer), or security audit of model inputs (defer to security-reviewer). Owns ML systems in production: serving, monitoring, and feature management. | Read, Grep, Glob, Edit, Write, Bash | yes |
| mobile-engineer | Senior mobile engineer for iOS, Android, and React Native development. Spawn when building native or cross-platform mobile features, handling app store submissions, or optimizing mobile-specific performance. Don't use for: web-only frontend work (defer to frontend-engineer), backend API design (defer to backend-engineer), or pure data pipeline work (defer to data-engineer). Owns the mobile application layer and platform-specific concerns. | Read, Grep, Glob, Edit, Write, Bash | yes |
| platform-engineer | Senior platform engineer for microservices, service mesh, API gateways, event-driven architecture, and DX tooling. Spawn when designing inter-service communication, circuit breakers, sagas, gRPC contracts, or platform abstractions. Don't use for: application business logic (defer to backend-engineer), CI/CD configuration (defer to devops-engineer), or frontend components (defer to frontend-engineer). | Read, Grep, Glob, Edit, Write, Bash | yes |
| pr-test-analyzer | Senior PR test-coverage analyzer. Spawn after PR open/update or before ready-for-review to surface untested critical paths. Don't use for: writing tests (defer to test-engineer), or chasing line-coverage % (rates by behavioral criticality 1–10, not coverage %). Owns regression-risk visibility before merge. | Read, Grep, Glob, Bash | yes |
| product-analyst | Senior product analyst for requirements elicitation, user-story decomposition, scope definition, and acceptance-criteria design. Spawn when translating vague ideas into engineering specs or user value is unclear. Don't use for: technical implementation (defer to backend/frontend-engineer), architecture blueprints (defer to code-architect), or code-level tracing (defer to code-explorer). | Read, Grep, Glob, Bash | yes |
| researcher | Senior research specialist for libraries, approaches, and external docs. Spawn when exploring unfamiliar technology, comparing options, or onboarding to a new module. Don't use for: tracing internal code (defer to code-explorer), implementing code (defer to backend-engineer/frontend-engineer), or fast symbol lookups (spawn Explore subagent). | Read, Grep, Glob, Bash, WebSearch | yes |
| security-reviewer | Senior cross-cutting security reviewer for auth, secrets, input validation, OWASP Top 10, and supply chain. Spawn before merge on changes touching auth/secrets/external input, or on active credential leaks. Flags with severity + OWASP; defers fixes to backend/frontend/devops-engineer. Don't use for: general code-quality review (defer to code-reviewer) or non-security implementation (defer to backend/frontend-engineer). | Read, Grep, Glob, Bash, WebSearch, WebFetch | yes |
| silent-failure-hunter | Senior error-handling auditor + adversarial plan reviewer. Spawn after error-handling changes (new catches, modified blocks, fallback logic) or after multi-role merges needing a skeptic against the plan. Don't use for: writing error handling from scratch (defer to backend-engineer/frontend-engineer), or general code review (defer to code-reviewer). | Read, Grep, Glob, Bash | yes |
| technical-writer | Senior technical writer for READMEs, ADRs, runbooks, API docs, onboarding guides, and changelog prose. Spawn when creating docs from scratch, rewriting stale docs, or turning tribal knowledge into reference material. Don't use for: code review (defer to code-reviewer), security audit docs (defer to security-reviewer), or one-line inline comments (defer to the engineer who wrote the code). | Read, Grep, Glob, Edit, Write, Bash | yes |
| test-engineer | Senior test-discipline owner for coverage design, edge cases, contract testing, and integration boundaries. Spawn when writing tests for new features or designing test strategy. Don't use for: reviewing PR test-coverage gaps (defer to pr-test-analyzer), implementing production code — write tests that drive the implementation, defer fixes to backend-engineer or frontend-engineer. Tests must encode WHY behavior matters, not just WHAT it does. | Read, Grep, Glob, Edit, Write, Bash | yes |
| type-design-analyzer | Senior type-design reviewer for encapsulation, invariants, and API contracts. Spawn after writing/modifying types, interfaces, DTOs, models, or schemas crossing module boundaries or public APIs. Grades encapsulation on 1–10. Don't use for: general code review (defer to code-reviewer), security (defer to security-reviewer), performance (defer to kbg:perf), or runtime verification (defer to test-engineer). | Read, Grep, Glob, Bash, WebFetch, WebSearch | yes |
| ux-reviewer | Senior UX and interaction reviewer for user journeys, accessibility, cognitive load, and form/task flow. Spawn when evaluating UI/UX implementations, reviewing from the user's perspective, or auditing accessibility gaps. Don't use for: visual design polish (defer to frontend-engineer), frontend component code review (defer to frontend-engineer), or performance optimization (defer to backend-engineer/frontend-engineer). Owns the UX layer between design and code. | Read, Grep, Glob, Bash | yes |

## Skills — Repo
| Skill | Description | Agent | Invoke |
|---|---|---|---|
| 7-agent-pattern | 7-agent-pattern | inline | auto |
| accept-task | Lock a machine-checkable acceptance contract before any non-trivial task. Use when starting multi-file changes, schema migrations, or before dispatching write-capable agents; write `.scratch/<slug>/ACCEPTANCE.md` with criteria + start SHA. Use when user says 'lock acceptance', 'define acceptance criteria', or 'what does done look like'. Don't use for trivial single-file edits, read-only analysis, or existing contracts. | inline | auto |
| acli | Use when handling bulk Jira work-item operations and Confluence space/page/blog management from the terminal. Covers transitions, labels, assignments, comments, clones, archives, bulk-edit fields, JQL exports, and running acli commands. For creating a single Thai-format Bug or Story with guided AC, use kbg:create-jira-bug or kbg:create-jira-story instead. Don't use for single-ticket reads, JQL syntax help, install/config/auth, cheat sheets, GitHub/GitLab, or non-Atlassian trackers. | inline | auto |
| adr | adr | inline | manual |
| article-mine | Mine an article / repo / RFC / doc for doctrine via 5-agent fan-out, then ship in-session. Use when the user pastes a URL / file / text and says 'mine this', 'analyze this article', 'extract lessons', 'read this and apply', or 'what can we take from this' — to harvest doctrine for the harness. Don't use for: pure Q&A (kbg:research-brief), reasoning review (kbg:critical-eval), security (kbg:security-auditor), or PR review (kbg:review-pr). | inline | manual |
| assert-presence | assert-presence | inline | manual |
| backend-dev | Backend implementation skill for API endpoints, DB migrations, webhooks, background jobs, rate limiters, error middleware, and schema design. Runs TDD + terminal-ops + architecture + diagnose. Use when the user asks for FastAPI/Flask/Django endpoints, SQL migrations, or Redis services. Don't use for: frontend UI/CSS, security-only audits (kbg:security-auditor), research (kbg:research-brief), infra deployment (devops-engineer), or frontend tests. | backend-engineer | auto |
| clarify-first | Ask the structured 3-step question (analyze, recommend, ask) BEFORE dispatching write-capable agents or starting multi-file changes where a wrong assumption wastes work. Trigger when a task is named but scope is unstated — 'fix the bug', 'refactor X', 'add Y', 'make it faster' with no file/metric/layer; or it spans subsystems with no clear boundary. Don't use for: explicit file paths, single-value changes, read-only requests, or rhetorical questions. | inline | auto |
| create-jira-bug | Create a single Jira Bug using the team's Thai PO/QA-readable template. Tries acli first, falls back to Atlassian MCP when acli is unavailable or cannot set a required field. Use when the user says 'create bug', 'report a bug', 'file a Jira bug', or wants a structured Thai bug ticket with reproduction steps, impact, and Given/When/Then AC. Don't use for: bulk bug creation (use acli), editing an existing bug (use acli), security incidents (use kbg:incident/kbg:hotfix), or non-Jira trackers. | inline | manual |
| create-jira-story | Create a single Jira Story using the team's Thai PO/QA-readable template. Tries acli first, falls back to Atlassian MCP when acli is unavailable or cannot set a required field. Use when the user says 'create story', 'new Jira story', 'write a story', or wants a structured Thai Story with business reason, scope, and Given/When/Then AC. Don't use for: bugs (use create-jira-bug), bulk story creation (use acli), editing an existing story (use acli), or technical tasks without PO-facing AC. | inline | manual |
| critical-eval | Stress-test reasoning in arguments, PRs, ADRs, RFCs, incidents, decisions. Use when asked to critique, evaluate reasoning, check assumptions, stress-test arguments, review logic, verify it holds up, or when something feels off. Flag overconfident plans (definitely safe, zero downtime). Don't use for: system dynamics/architecture trade-offs (kbg:backend-dev/code-architect), code review (kbg:review-pr), security audit (kbg:security-auditor), or research (kbg:research-brief). | inline | auto |
| decommission | decommission | inline | manual |
| harness-audit | harness-audit | inline | auto |
| harness-coverage | Read-only harness-coverage report: renders the 2x2x3 (12-cell) grid from `hooks/sensors.json` and the governance journal, with a 60% decay threshold and the intentional-gap cell `inf-fb-behaviour` flagged. Use when the operator wants to know which cells are populated, stale, or empty, wants a quarter-end decay measurement, or a 12-row table view of the journal. Don't use for: per-session drill-down or a verdict stream (use `kbg:harness-health`), or per-sensor fire-rate (read the journal). | inline | auto |
| harness-health | Read-only query surface over the governance journal. Surfaces structural-judge verdicts (accept/flag/escalate) and sensor staleness from `hooks/sensors.json`, with per-sensor fire counts so silent sensors stay visible. Use when the user asks 'what's the harness health', 'last 10 verdicts', 'verdicts > 7 in 30 days', or 'silent-sensor count'. Don't use for: deep PR review (kbg:review-pr), security posture (kbg:security-auditor), fleet audit (kbg:harness-audit), or running the scoring engine. | inline | auto |
| harness-nav | L3 escape hatch for kbg-harness capability discovery. Use when no known skill, command, or agent clearly covers your task — teaches grep recipes to mine BOUNDARY.md, skills/, agents/, commands/ for the right capability. Returns the nearest match or confirms none exists. Don't use for: tasks where the right skill is already known (use it directly), or operational health queries (use kbg:harness-health). Reach for it only when the skill-nudge hook didn't surface the match. | inline | auto |
| hotfix | Use this skill for emergency production fixes requiring immediate code change. Trigger when user says 'production is down', 'critical bug', 'hotfix', 'emergency patch', 'P0', 'outage', or any production-wide incident. Rollback-first, severity-gated SLA, timeboxed execution. Do NOT use for: non-urgent bugs (use /fix-bug), subset-affecting issues, new features, or when rollback/kill-switch suffices. | inline | auto |
| ideate | Parallel divergent ideation. Use when prompts are open-ended (design, architecture, naming, API/SDK, fuzzy-debug) AND high-stakes AND open phrasing — spawns 5 isolated agent calls under different cognitive frames (regulator, 10-year-old, ant-colony, speedrunner, 3am, biology), scores on novelty/viability/fit, prunes traps, deepens top 3. Also fires on /ideate, brainstorm/ideate intents. Don't use for syntax, lookups, known-root-cause bugs, or closed phrasing ('quick', 'standard', 'canonical', 'textbook'). Pre-flight gate in body. | inline | manual |
| incident | Manage a live production incident end-to-end — detect, assess, mitigate, communicate, resolve, and handoff. Use when alerts fire, monitors show red, users report widespread issues, or error rates spike. Do NOT use for: non-production bugs (use /fix-bug), planned maintenance, security incidents requiring special handling (use security-reviewer first), or post-incident documentation (use /post-mortem after resolution). | inline | auto |
| inventory | inventory | inline | auto |
| kbg-help | Detailed reference card for kbg-harness: context tiers (L1/L2/L3), skill/command index, validation pipeline, plugin cache-invalidation, and load-bearing invariants. Use when the user asks for help, 'what can kbg do', 'how do I use the harness', or 'explain kbg'. Don't use for: deep capability discovery (use kbg:harness-nav) or governance journal queries (use kbg:harness-health). One-shot display, read-only. | inline | auto |
| memory-lint | memory-lint | inline | auto |
| memory-trim | memory-trim | inline | auto |
| migrate | Deprecate and migrate legacy code, APIs, or dependencies safely. Use when the user says 'migrate to v2', 'upgrade from X to Y', 'deprecate this API', 'extract this module', or when retiring systems, upgrading major versions, or migrating databases. Don't use for: new features (/feature-dev), hot bug fixes (/fix-bug, kbg:hotfix), refactors without a deprecation target, or when rollback is impossible. | inline | manual |
| orchestrate | Prioritize competing tasks, then route each to inline / batch-parallel / pipeline-sequential / drop. Use when the user lists competing tasks, asks 'what should I work on' or 'what's the priority', plans a day/week/sprint, feels overwhelmed, or spans independent sub-tasks or sequential phases. Don't use for: single-issue triage (triage), PR review (kbg:review-pr), one feature (/feature-dev), or single-file coding (inline). | inline | auto |
| perf | Performance regressions and bottlenecks. Trigger on latency spikes, throughput drops, memory leaks/growth, CPU saturation, slow queries, cache misses/CI, cold starts, resolver/ETL timeouts, or reported slowness. Don't use for: production outages (kbg:incident/kbg:hotfix), functional bugs without perf symptoms (/fix-bug), architectural redesigns (/deep-dive, code-architect), or capacity planning. | inline | auto |
| probe | probe | inline | auto |
| progressive-refine | progressive-refine | inline | auto |
| recursive-improve | recursive-improve | inline | manual |
| research-brief | Research brief with search-first + diagnose preloaded. Use when user says 'research this', 'deep dive on X', 'how does Y work in this codebase', 'compare Z approaches', or any open-ended exploration spanning files, docs, and external sources. Don't use for: implementation work (use /feature-dev or kbg:backend-dev), bug fixes (use /fix-bug), or security audits (use kbg:security-auditor). | researcher | auto |
| review-pr | Run multi-agent PR review across code quality, tests, comments, errors, security, types, accessibility/UX, and simplification. Use when finishing changes before opening a PR, when a PR is ready, after addressing feedback, or when asked to review changes/aspects. Don't use for: single-file diffs (review inline), security-only audits (kbg:security-auditor), post-merge retrospectives, or invoking a single agent (use Agent tool). | inline | auto |
| security-auditor | Use when auditing or reviewing security flaws in auth, secrets, external input, file uploads, or dependencies. Covers injection, XSS/CSRF/SSRF, path traversal, broken access control, secret leaks, or vulnerable components. Use when PRs touch auth, APIs, admin panels, payments, or dep manifests. Don't use for: code review (kbg:review-pr), incidents (kbg:hotfix/kbg:incident), or non-code security (infra, policy). | inline | auto |
| semantic-code | semantic-code | inline | auto |
| ship-change | Orchestrate the full change lifecycle from classify → implement → review → address → merge. Use when starting non-trivial changes needing guided sequencing through /fix-bug, /feature-dev, kbg:review-pr, /address-review, and /ship-merge. Don't use for: one-line fixes, changes already mid-flight, or pure research/exploration. | inline | manual |
| task-sizing | task-sizing | inline | auto |
| tech-humanize | Humanize dev/tech writing in English and/or Thai to sound natural, not AI-generated. Use when editing standup reports, PR descriptions, commit messages, ADRs, UI copy, or 'fix this to read less AI'. Covers English, Thai, and Thai↔English code-switching. Use when user says humanize, แก้ให้เป็นธรรมชาติ, เขียนให้ฟังดูเป็นคน, ปรับ tone, or 'less like ChatGPT'. Don't use for translation, detection-only analysis, or code identifiers. | inline | auto |
| triage | Single-issue triage: classify a bug, feature request, or task by severity, scope, and owner. Use when the user dumps a single issue and you need to decide whether to route it to /feature-dev, /fix-bug, /deep-dive, or kbg:orchestrate. Don't use for: prioritizing a batch (use kbg:orchestrate), or building a feature (use /feature-dev). | inline | auto |
| types-first | types-first | inline | auto |
| usage-monitor | Read-only cost and subagent usage summary for the current session. Use when the user asks about session cost, token burn, cost breakdown by agent, or suspects nested-team token amplification. Reads the SessionEnd capture at `~/.claude/usage/<slug>.jsonl`; L2 read-only, no gates. Don't use for: real-time cost gating (none exists), cross-session aggregation, or OTEL/OTLP export (not implemented). | inline | auto |

## Hooks — Repo
| Hook | Purpose |
|---|---|
| _lib.py | Pinned — JOURNAL-SCHEMA.md § "source" enum. Do NOT change to a per-language |
| _lib.sh | _lib.sh — shared protocol for Claude Code hooks (PreToolUse / UserPromptSubmit / etc). |
| hooks.json | — |
| hooks.json.test.bak | — |
| JOURNAL-SCHEMA.md | Governance Evidence Journal — Schema Contract |
| sensors.json | — |

## Output styles — Repo
| Style | Description |
|---|---|
| TECH-LEAD-THAI | Senior engineering lead execution style — direct, opinionated, Thai code-switched register |

---
_Generated: 2026-06-17T04:10:33Z_

---

## Task sizing guidance

Derived from `skills/task-sizing/SKILL.md` and article `agent-teams-best-practices`. Apply at `/team-plan` time, before `/team-build` dispatch.

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
- **Total waves:** 3-5. More = plan is too coarse; fewer = use `/feature-dev` instead.
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

Canonical file patterns per agent. Assign each file to exactly one agent in a `/team-build` plan to prevent silent overwrites.

| Agent | Canonical file patterns | Notes |
|---|---|---|
| `api-doc-specialist` | `openapi/`, `docs/api/`, `sdk/`, `swagger/` | |
| `backend-engineer` | `api/`, `middleware/`, `models/`, `routes/`, `services/`, `tests/` | |
| `code-architect` | `docs/adr/`, `architecture/`, `*.md` (design docs) | Blueprints, not implementation |
| `code-explorer` | any file | Read-only trace |
| `code-reviewer` | any file | Read-only review |
| `code-simplifier` | any file | Post-impl refinement; Edit/Write/Bash |
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

---

## Team-ready blocks

When spawning a teammate (via `/team-build` or any agent-team dispatch), inject these shared conventions so teammates load the same module map + verification recipe.

### Module Boundaries
- `agents/` — 27 senior-specialist agents
- `skills/` — 28 workflow skills
- `commands/` — 11 slash commands
- `hooks/` — 38 hook scripts
- `output-styles/` — 1 TECH-LEAD-THAI
- `eval/` — dataset + regression + CI gate (Phase 1)

### Quick Context
- **Stack:** Bash + Python 3 + jq; kbg-harness is a Claude Code plugin (plugin.json v0.1.3)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** `bash hooks/tests/test-critical-hooks.sh` (201/0 expected)
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/kobig/kbg/<version>/` (rebuilt on `claude plugin update kbg@kobig`)

### Verification
- `bash skills/harness-audit/scripts/audit.sh .` — 0C/0W expected (26 I = schema-rot INFO, non-blocking)
- `claude plugin validate --strict .` — exit 0
- `bash hooks/tests/test-critical-hooks.sh` — 201/0 expected
- `python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate` — exit 0

---

## Agent Teams

Opt-in via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Plugin does NOT auto-enable experimental features.

**What it unlocks:**
- `/team-plan <feature>` — Steps 1-3: brain dump + research + ≥10 Q&A → `.claude/tasks/<slug>.md`
- `/team-build <plan-file>` — Steps 4-7: contract chain + wave execution + post-build validation
- TaskCompleted test-claim gate (`hooks/task-lifecycle.sh`, exit 2 + stderr per vendor spec)
- F9 spawn-prompt template in `skills/orchestrate/SKILL.md` (the "what/where/focus/deliverable" quad + FILES YOU OWN / UPSTREAM CONTRACTS schema)

---

## Trigger phrases

Map user intent → harness dispatch. Use these trigger phrases in `commands/`, `skills/`, and agent `description:` frontmatter so the orchestrator nudge (`hooks/orchestrator-nudge.sh`) routes correctly.

### Planning & execution
| User says | Dispatch | Why |
|---|---|---|
| "plan this for the team", "multi-agent plan", "team plan: X" | `/team-plan` | Steps 1-3: brain dump + Q&A + structured plan |
| "build the plan", "execute the plan", "ship the team plan" | `/team-build` | Steps 4-7: contract chain + wave execution |
| "where are we", "status of the build", "is the team done" | `/wave-status` | Reads task board, reports wave progress |
| "clean up the team", "remove old plans", "stale tasks" | `/team-cleanup` | Reaps locks, heartbeats, archives old boards |
| "validate this task", "did the teammate do it right" | `/validate-and-fix` | B→V1→F→V2 validation chain on one task |
| "lint the plan", "is this plan ready" | `/pre-flight-plan-linter` | Structural validation before `/team-build` |
| "pros and cons", "which is better", "should we use X or Y" | `/debug-debate` | Advocate + Skeptic + Synthesizer debate |

### Single-task workflows
| User says | Dispatch | Why |
|---|---|---|
| "build one feature", "implement X" | `/feature-dev` | Single-agent ceremony |
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
| "what should I work on", "prioritize these" | `kbg:orchestrate` skill | Prioritize + route |

### Incident & post-mortem
| User says | Dispatch | Why |
|---|---|---|
| "incident", "alerts firing", "monitors red" | `kbg:incident` skill | Live incident response |
| "post-mortem", "writeup after incident" | `/post-mortem` | Incident documentation |
| "status update", "what did we ship" | `/status-update` | Status report |

### Agent-team troubleshooting
| User says | Dispatch | Why |
|---|---|---|
| "agent went idle", "teammate stopped" | `/wave-status` → `/team-build` re-dispatch | Heartbeat check + re-claim |
| "merge conflict", "two agents touched same file" | `scripts/plan-linter.py` + `/team-plan` revision | Ownership violation |
| "validation failed but it says done" | `/validate-and-fix` | F7 gate + re-validator |
| "context exhausted", "out of tokens" | `/team-build` fresh-session gate | Context budget preservation |

