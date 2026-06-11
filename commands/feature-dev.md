---
description: "Guided 7-phase feature development workflow (discover → explore codebase → ask clarifying questions → design architecture → implement → review → summarize). Use when starting a non-trivial new feature where deep codebase understanding and architectural choices matter. Don't use for: bug fixes (use /fix-bug), refactors (spawn `maintenance-engineer` agent), one-line changes (just do it), or quick prototypes (just do it inline)."
argument-hint: Optional feature description
disable-model-invocation: true
---

# Feature Development

You are helping a developer implement a new feature. Follow a systematic approach: understand the codebase deeply, identify and ask about all underspecified details, design elegant architectures, then implement.

## Core Principles

- **Ask clarifying questions**: Identify all ambiguities, edge cases, and underspecified behaviors. Ask specific, concrete questions rather than making assumptions. Wait for user answers before proceeding with implementation. Ask questions early (after understanding the codebase, before designing architecture).
- **Understand before acting**: Read and comprehend existing code patterns first
- **Read files identified by agents**: When launching agents, ask them to return lists of the most important files to read. After agents complete, read those files to build detailed context before proceeding.
- **Simple and elegant**: Prioritize readable, maintainable, architecturally sound code
- **Use TodoWrite**: Track all progress throughout
- **No "too simple to design"**: Every feature goes through Phases 1-4 before Phase 5. The design can be short (a few sentences for trivial work), but it MUST be presented and approved. "Simple" features are where unexamined assumptions cause the most wasted work (per obra/superpowers brainstorming discipline).

---

## Phase 1: Discovery

**Goal**: Understand what needs to be built

Initial request: $ARGUMENTS

**Actions**:
1. Create todo list with all phases
2. **Analyze**: `$ARGUMENTS` ambiguity — is there a concrete user story, acceptance criteria, or just a concept? **Recommend** asking targeted clarifying questions only when the gap blocks Phase 3 architecture; if the request is "build X" with no acceptance criteria, that's a gap.
3. If feature unclear, ask user for:
   - What problem are they solving?
   - What should the feature do?
   - Any constraints or requirements?
4. **Scope check** — if the feature description spans multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), STOP and propose decomposition. Don't refine details of a project that needs to be broken into sub-projects first; each sub-project gets its own `/feature-dev` run. For appropriately-scoped features, continue.
5. **Analyze**: scope clarity (single subsystem vs spanning multiple), requirement completeness (edge cases defined?), constraint awareness (performance, backward compatibility). **Recommend** proceed when scope is tight and requirements are complete; recommend revise when assumptions remain.
6. **AskUserQuestion** single-select: "Phase 1: feature scope = [single subsystem / multi-subsystem]. Requirements = [complete / incomplete]. Edge cases = [defined / undefined]. My recommendation: [proceed / revise]. Do you agree?"
   - `Proceed to Phase 2 (Recommended when scope is tight, requirements are complete, and edge cases are defined)`
   - `Revise understanding — tell me what's wrong (Recommended when scope, requirements, or edge cases need clarification before design)`

---

## Phase 2: Codebase Exploration

**Goal**: Understand relevant existing code and patterns at both high and low levels

**Actions**:
1. Launch 2-3 code-explorer agents in parallel. Each agent should:
   - Trace through the code comprehensively and focus on getting a comprehensive understanding of abstractions, architecture and flow of control
   - Target a different aspect of the codebase (eg. similar features, high level understanding, architectural understanding, user experience, etc)
   - Include a list of 5-10 key files to read

   **Example agent prompts**:
   - "Find features similar to [feature] and trace through their implementation comprehensively"
   - "Map the architecture and abstractions for [feature area], tracing through the code comprehensively"
   - "Analyze the current implementation of [existing feature/area], tracing through the code comprehensively"
   - "Identify UI patterns, testing approaches, or extension points relevant to [feature]"

2. Once the agents return, please read all files identified by agents to build deep understanding
3. Present comprehensive summary of findings and patterns discovered

---

## Phase 3: Clarifying Questions

**Goal**: Fill in gaps and resolve all ambiguities before designing

**CRITICAL**: This is one of the most important phases. DO NOT SKIP.

**Actions**:
1. Review the codebase findings and original feature request
2. Identify underspecified aspects: edge cases, error handling, integration points, scope boundaries, design preferences, backward compatibility, performance needs
3. **Present all questions to the user in a clear, organized list**
4. **Wait for answers before proceeding to architecture design**
5. **Lock the acceptance contract before Phase 4.** For non-trivial scope, invoke `/accept-task` to write `.scratch/<slug>/ACCEPTANCE.md` (machine-checkable success criteria) before architecture design begins — it is the producer that the review's acceptance-gap check consumes downstream. `/accept-task` self-gates triviality, so trivial work passes straight through; don't restate the threshold here. Cross-reference (don't duplicate) the informal acceptance criteria from Phase 1 discovery.

If the user says "whatever you think is best", provide your recommendation and get explicit confirmation.

---

## Phase 4: Architecture Design

**Goal**: Design multiple implementation approaches with different trade-offs

**Quality criterion** — for each component the architect proposes, ensure you can answer 3 questions: (1) what does it do, (2) how do you use it (interface / API), (3) what does it depend on. If a component fails any of these, the boundaries need work — flag it before approving (per obra/superpowers brainstorming's design-for-isolation check).

**Actions**:
1. Choose the right tool based on the task type:
   - **New feature or major addition** → Launch 2-3 `code-architect` agents in parallel with different focuses: minimal changes (smallest change, maximum reuse), clean architecture (maintainability, elegant abstractions), or pragmatic balance (speed + quality)
   - **Refactoring existing architecture** → Spawn `maintenance-engineer` agent. This is a single-session deepening workflow that surfaces shallowness and proposes seams. Do not spawn multiple architects for refactors.
2. Review all approaches and form your opinion on which fits best for this specific task (consider: small fix vs large feature, urgency, complexity, team context)
3. **Self-review** the chosen approach before presenting (per obra/superpowers brainstorming spec-self-review):
   - **Placeholder scan** — any "TBD" / "TODO" / vague handwave (e.g., "we'll figure out auth later")? Specify or call out as explicitly deferred.
   - **Internal consistency** — do the components / data flow / error handling sections agree? No section contradicts another.
   - **Scope check** — is this focused enough for one implementation pass, or did Phase 1's decomposition miss something?
   - **Ambiguity check** — could any requirement be read two ways? Pick one and make it explicit.
   Fix issues inline. No re-review loop.
4. Present to user: brief summary of each approach, trade-offs comparison, **your recommendation with reasoning**, concrete implementation differences
5. **AskUserQuestion** single-select: "Phase 4: 3 approaches evaluated. [Minimal changes] = [blast radius description, e.g. 2 files, 1 new function]. [Clean architecture] = [blast radius, e.g. new module + interface, 6 files]. [Pragmatic balance] = [blast radius, e.g. 4 files, moderate abstraction]. My recommendation: [approach] because [reason]. Which do you prefer?"
   - `Minimal changes (Recommended when the feature is a small extension and maximum reuse of existing code matters most)`
   - `Clean architecture (Recommended when the feature is large or long-lived and maintainability / testability matter most)`
   - `Pragmatic balance (Recommended when speed matters but the feature still needs to survive the next 2 years)` — my recommendation if I provided one
   - `Request a 4th option — tell me what's missing (Recommended when none of the above fit the constraints or the tradeoff table is incomplete)`

---

## Phase 5: Implementation

**Goal**: Build the feature

**DO NOT START WITHOUT USER APPROVAL**

**Actions**:
1. Wait for explicit user approval
2. Read all relevant files identified in previous phases
3. **Analyze**: complexity (new module vs extension), testability (can public interface be exercised?), coupling (does it touch auth/data/schema?). The cost of a wrong implementation is almost always higher than the cost of writing the test first — default to TDD unless one of the opt-out criteria below applies.
4. **Default: TDD red → green → refactor** (the `/tdd` skill's pattern, inlined here — mirrors `/fix-bug.md` Phase 5):
   1. **RED** — Write one failing test for the smallest slice of the chosen public interface. Run it → confirm it FAILS for the right reason.
   2. **GREEN** — Implement the minimal code to pass. Hardcode, duplicate, ugly — all allowed. Just make it pass.
   3. **REFACTOR** — Clean up only if strictly required to keep the code readable. No orthogonal cleanup (METHODOLOGY Rule 3).
   4. **Next behavior** — Repeat for the next vertical slice. Tests verify behavior through public interfaces, not internal helpers.
   5. **Document** — Write a `SUMMARY.md` or inline `Cycle N` comments showing red → green → refactor progression. This is the evidence TDD happened.
   6. Run full test suite locally. Confirm no orthogonal regressions.
5. **Opt out of TDD** (only when the test framework can't encode the change type — each criterion requires a 1-sentence justification captured in `.scratch/<feature>/optout-reason.md`):
   - **Pure visual regression** (no behavior to assert on) — must enumerate the public API of the changed component (props in / events out / state). If any event handler, state transition, or async fetch is in the diff, this criterion does not apply.
   - **Hard race condition** needing dedicated timing/property-based tooling — must name the tool (e.g. `tla+`, `loom`, `fast-check`, `jepsen`, custom) and the property under test. Block on empty.
   - **Integration boundary with no test harness available** — must state what test-harness setup was tried and rejected (harness X, blocker Y). Permanent opt-out, but each invocation re-justifies.
   - **1-line cosmetic change** (typo, comment, formatting) — `git diff --stat` must show ≤ 1 changed line touching only whitespace / comments / doc strings. If the diff is larger, the criterion does not apply.
   When opting out: tell the user TDD is being skipped and which criterion applies, write `.scratch/<feature>/optout-reason.md` with criterion + 1-sentence justification, and proceed. Phase 6 reads the ledger file as the test-quality gate.
6. **AskUserQuestion** single-select: "Phase 5: complexity = [new module vs extension], testability = [public interface available / not yet], coupling = [touches auth/data/schema / isolated]. My recommendation: TDD (default). Confirm?"
   - `TDD — red/green/refactor (Recommended by default — the cost of a wrong implementation is higher than the cost of writing the test first)`
   - `Skip TDD (Recommended ONLY for: visual-only UI change with no behavioral handlers, hard race condition with named tool, integration boundary with stated harness rejection, or 1-line cosmetic with diff ≤ 1 line — state your criterion and write .scratch/<feature>/optout-reason.md)`
7. Implement following chosen architecture
8. Follow codebase conventions strictly
9. Write clean, well-documented code
10. Update todos as you progress

---

## Phase 6: Quality Review

**Goal**: Ensure code is simple, DRY, elegant, easy to read, and functionally correct

**Actions**:
1. Launch review agents based on what the code touches. Most changes fire 1–2 conditionals; if more than 3 agents match, prioritize by risk (security → type/data-integrity → error-handling → ux) and run the rest in a follow-up pass to respect METHODOLOGY Rule 6 (30K session budget):
   - **Always**: `code-reviewer` agent (simplicity/DRY/elegance, bugs/functional correctness, project conventions/abstractions)
   - **If changes touch auth/secrets/external input** → Add `security-reviewer` agent (OWASP patterns, secret handling, auth flows)
   - **If changes add/modify try-catch or fallback logic** → Add `silent-failure-hunter` agent (error suppression, broad catches, inadequate error messages)
   - **If changes add/modify types/interfaces/DTOs/schemas crossing module boundaries** → Add `type-design-analyzer` agent (encapsulation, invariants, API-contract honesty)
   - **If changes add/modify user-facing UI/components/flows** → Add `ux-reviewer` agent (task completion, cognitive load, WCAG 2.1 AA)
   - **If Phase 5 TDD was skipped** → Add `pr-test-analyzer` agent (does NOT count toward the 3-agent cap — on the opt-out path it is the test-quality gate that replaces red-green provenance, so it is dropped last, not first. If 4 other agents qualify, drop the lowest-priority non-`pr-test-analyzer` one instead.)
2. Consolidate findings into severity tiers. For each finding, assign a tier by asking *"if this ships as-is, what's the worst that could happen?"* — production breaks / a 2am page / silent data corruption / users see errors → **Critical**; a real but contained issue → **Important**; only "the code is slightly less clean" → **Minor**:
   - **Critical** — must fix before merge (security, data integrity, broken functionality)
   - **Important** — should fix before merge (real issues that don't block but shouldn't ship)
   - **Minor** — nice to have (style, optional refinements)
3. **AskUserQuestion** single-select: "Phase 6: [N] Critical (security/data/functionality), [N] Important (real issues that shouldn't ship), [N] Minor (style/optional). My recommendation: [option]. How do you want to proceed?"
   - `Fix Critical issues now, proceed with Important/Minor later (Recommended when Critical count is low and the user wants to keep momentum)`
   - `Fix Critical + Important now, Minor later (Recommended when both tiers have real issues that shouldn't ship)`
   - `Fix all tiers now before proceeding (Recommended when review surfaced significant problems across all tiers)`
   - `Proceed as-is — acknowledge risk (Recommended only when findings are false positives or truly cosmetic)`
4. Address issues based on user decision

---

## Phase 7: Summary

**Goal**: Document what was accomplished

**Actions**:
1. Mark all todos complete
2. Summarize:
   - What was built
   - Key decisions made
   - Files modified
   - Suggested next steps:
     - If TDD was skipped in Phase 5 → confirm `.scratch/<feature>/optout-reason.md` exists with criterion + 1-sentence justification; if missing, write it before `review-pr`
     - If not yet reviewed → invoke `review-pr` skill
     - If review addressed and approved → `/ship-merge`
     - If status update needed → `/status-update [channel] [summary]`
     - If this was backend work → `/backend-dev` can preload TDD + architecture skills for the next iteration

---

## Integration Notes (Project-Specific)

- **METHODOLOGY alignment**:
  - Rule 1 (Think before coding) → Phases 1-4 (discover → explore → clarify → design before implement)
  - Rule 2 (Simplicity first) → Phase 4 minimal-changes architect option + "No too-simple-to-design" Core Principle
  - Rule 3 (Surgical changes) → Phase 4 routing (refactor → spawn `maintenance-engineer` agent; don't bundle new-feature with refactor)
  - Rule 8 (Read before write) → Phase 2 Codebase Exploration is non-negotiable before any Phase 5 implementation
  - Rule 11 (Match codebase conventions) → Phase 4 Quality criterion (3-question isolation test) + "Follow existing patterns" in agent prompts
  - Rule 12 (Fail loud) → Phase 5 "DO NOT START WITHOUT USER APPROVAL" + Phase 6 user-decision gate per finding
- **Agent teams**: Use only when 30+ min latency acceptable. For focused tasks, spawn Explore or Plan directly.
- **Token budget**: Each phase fits 4K task / 30K session budget. Phase 2 + Phase 4 + Phase 6 combined can launch 5-8 agents (~20-35K tokens). Cap Phase 6 at 3 agents max — except `pr-test-analyzer` on the TDD-opt-out path, which does NOT count toward the cap (it is the test-quality gate that replaces red-green provenance, so it is dropped last, not first). `/compact` at natural boundaries if needed.
- **code-review-graph MCP**: Use for structural queries (callers, callees, impact radius) during Phase 2 and Phase 5.
- **TDD skill**: Phase 5 defaults to `/tdd` red-green-refactor (mirrors `/fix-bug.md` Phase 5). Invoke `/tdd` skill unless user opts out for a stated reason (visual regression with enumerated public API, race condition with named tool, integration boundary with stated harness rejection, cosmetic 1-liner with `git diff --stat` ≤ 1). Opt-out requires writing `.scratch/<feature>/optout-reason.md` with criterion + 1-sentence justification. Tests verify behavior through public interfaces, not internal helpers. Phase 6 runs `pr-test-analyzer` on the opt-out path; it is the test-quality gate that replaces red-green provenance and does NOT count toward the 3-agent cap.
- **Hooks active**: secret-scan, block-dangerous-git, doctrine-edit-gate run automatically during this workflow.
- **Agent routing**: Phase 2 → 2-3 `code-explorer` in parallel (different angles); Phase 4 → 2-3 `code-architect` in parallel (different focuses) OR spawn `maintenance-engineer` agent for refactors; Phase 6 → 3 `code-reviewer` in parallel (simplicity / correctness / conventions) + conditional `security-reviewer` (auth/secrets/external input) + conditional `silent-failure-hunter` (try-catch/fallbacks) + conditional `type-design-analyzer` (types/DTOs/schemas crossing boundaries) + conditional `ux-reviewer` (user-facing UI/flows) + conditional `pr-test-analyzer` (TDD-opt-out path, exempt from 3-agent cap).
