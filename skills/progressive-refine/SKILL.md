---
name: progressive-refine
description: "Run a multi-pass progressive refinement pipeline: rough draft → review → revise → polish. Use when the output quality matters more than speed (docs, complex algorithms, public APIs, architecture decisions). Don't use for: one-pass sufficient work (use inline or /feature-dev), or when the user explicitly says 'quick and dirty'."
---

# Progressive Refine

> **Subagent self-check:** If you were dispatched as a sub-agent for a specific refinement pass, **do not re-orchestrate.** Return your scoped output (a `done-when` artifact, a `Report:` block, or your done-criterion evidence) to the parent. The parent owns the prioritization + dispatch loop; you own one well-bounded deliverable. This preamble mirrors obra/superpowers' `<SUBAGENT-STOP>` convention.

Progressive refinement is not "do it again" — it is "do it with increasing constraint." Each pass adds a new quality lens to the artifact. The pattern distributes those passes across specialized agents so no single agent tries to handle all concerns at once.

This skill is the sequential-chain counterpart to `orchestrate`'s parallel fan-out. Where `orchestrate` dispatches independent domains side-by-side, `progressive-refine` chains dependent passes where Pass N consumes the output of Pass N-1.

---

## Core concept — five lenses

From article `agent-patterns`: each pass focuses on a different quality dimension. The draft agent prioritizes completeness. The next agent adds constraints. The next optimizes. The last polishes.

| Pass | Lens | Question | Typical agent |
|------|------|----------|-------------|
| 1 | **Coverage** | Does it handle all cases? | builder / drafter |
| 2 | **Correctness** | Are the edge cases right? | reviewer / editor |
| 3 | **Clarity** | Can a junior read this? | simplifier / reviewer |
| 4 | **Performance** | Does it meet latency/budget constraints? | perf engineer / validator |
| 5 | **Polish** | Docs, error messages, naming | polisher / technical-writer |

Not every artifact needs all five. The 3-pass code pattern (below) is the most common shape. The 5-pass doc pattern is used for public-facing prose.

**When to use progressive refinement vs single-pass**

Use progressive refinement when:
- The artifact is public-facing (docs, SDK, API contract)
- The artifact has >3 stakeholders
- The artifact has >5 edge cases or failure modes
- The cost of a defect is high (payments, auth, data integrity)

Use single-pass when:
- Internal tool or prototype
- The user said "quick" or "quick and dirty"
- The change is <30 lines and <2 edge cases
- Speed matters more than polish (spike, experiment, RFC draft)

**Never use >3 passes for the same file** — diminishing returns after Pass 3 for most code. Docs and specs can sustain 5 passes because prose defects are cheaper to catch in Pass 2-5 than in production. Code usually tops out at 3; add Pass 4 (performance) and Pass 5 (security/polish) only when the file is load-bearing or customer-facing.

---

## The 3-pass code pattern (most common)

The default pipeline for production code. It maps directly to the validation chain in `skills/orchestrate/SKILL.md` § Validation chain and to `/validate-and-fix` — but applied proactively as a planned pipeline rather than reactively after a single builder claims done.

### Pass 1 — Builder (`backend-engineer`)

Write the rough implementation. Scope is "make it work." Do not optimize, do not polish. The builder's job is coverage: all acceptance criteria must be exercisable.

**Done-when:** All acceptance criteria pass via `pytest` (or the project's test runner). The code may be verbose, may have TODOs, may lack docstrings — but every path is reachable by a test.

**F9 spawn prompt:**

```
# Task: Build <feature> rough implementation

## What
Write the initial implementation of <feature> that satisfies all acceptance criteria.
Do not optimize, do not refactor, do not add docstrings beyond what's needed to keep tests readable.

## Where
<directory or file paths>

## Focus
Coverage over elegance. Every acceptance criterion must have a test that exercises it.

## Deliverable
<source files> exist and `pytest <test path>` passes for all criteria.

## FILES YOU OWN
- <absolute path 1>
- <absolute path 2>
(Only files in this list. Anything else is out of scope — defer to the orchestrator.)

## UPSTREAM CONTRACTS
(Empty list — first pass.)

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <path> | exports <symbol> and passes criterion X | no new deps unless listed |

## Done-when
- [ ] All acceptance criteria have passing tests
- [ ] `pytest <path>` exits 0
- [ ] No edit to files outside FILES YOU OWN
```

Spawn **gated** — builder holds Edit/Write/Bash.

---

### Pass 2 — Simplifier (`code-simplifier`)

Refine the builder's output for clarity and brevity. Scope is "make it readable." The simplifier may extract helpers, reduce nesting, rename variables, inline trivial abstractions — but must not change behavior.

**Done-when:** Cyclomatic complexity <10 per function, no functions >50 lines, and all tests from Pass 1 still pass.

**F9 spawn prompt:**

```
# Task: Simplify <feature> implementation

## What
Refactor the Pass 1 implementation for clarity and brevity. Extract helpers, reduce nesting, rename for readability. Do NOT change behavior or public API.

## Where
<absolute paths from Pass 1 task["files"]>

## Focus
Clarity over cleverness. A junior engineer should read this without asking questions.

## Deliverable
The same source files, refactored, with all original tests still passing.

## FILES YOU OWN
- <absolute path 1>
- <absolute path 2>
(Only files in this list.)

## UPSTREAM CONTRACTS
- From task T1 (builder): <source files> — behavior is frozen; only structure changes

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <path> | cyclomatic complexity <10 per function | no behavior change |
| <path> | no function >50 lines | all T1 tests still pass |

## Done-when
- [ ] `pytest <path>` exits 0 (same test suite as T1)
- [ ] Every function is ≤50 lines
- [ ] Every function has cyclomatic complexity <10 (confirm with `radon cc` or equivalent)
- [ ] No edit to files outside FILES YOU OWN
```

Spawn **gated** — simplifier holds Edit/Write/Bash.

---

### Pass 3 — Validator (`code-reviewer` + `test-engineer`)

Verify correctness and coverage. The validator starts with fresh eyes — it does not share the builder's assumptions or blind spots. This is the adversarial verification step.

`code-reviewer` checks the code for edge-case gaps, invariant violations, and style. `test-engineer` checks coverage and writes missing tests.

**Done-when:** All tests pass, coverage >80%, no critical findings (P0/P1).

**F9 spawn prompt for `code-reviewer`:**

```
# Task: Review <feature> for correctness

## What
Review the post-simplification source for edge-case gaps, invariant violations, and correctness issues. Do NOT modify files.

## Where
<absolute paths from task["files"]>

## Focus
Correctness over speed. Flag any behavior that violates the acceptance criteria or introduces regressions.

## Deliverable
A structured verdict report at `.scratch/<feature>-review/verdict.md`:
- verdict: one of {pass, minor, reject}
- findings: list of file:line citations with severity (P0/P1/P2) and explanation
- coverage_gaps: list of untested branches or edge cases

## FILES YOU OWN (read-only)
- <absolute path 1>
- <absolute path 2>
(Only these files. Do not review out-of-scope files.)

## UPSTREAM CONTRACTS
- From task T2 (simplifier): final diff — behavior should be identical to T1

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <path> | no P0/P1 correctness findings | read-only |

## Done-when
- [ ] Verdict is exactly one of: pass, minor, reject
- [ ] Every finding includes a file:line citation
- [ ] coverage_gaps lists untested branches with line numbers
- [ ] No edit to any file
```

Spawn **ungated** — reviewer is read-only.

**F9 spawn prompt for `test-engineer`:**

```
# Task: Write missing tests for <feature>

## What
Write tests to close the coverage gaps identified by the code-reviewer (T3-reviewer). If T3-reviewer reported `pass`, write edge-case tests for the 3 most likely failure modes.

## Where
<test directory> + <source files>

## Focus
Behavioral coverage, not line coverage. Test what the code does, not how it's structured.

## Deliverable
New or updated test files that raise coverage to >80%.

## FILES YOU OWN
- <absolute test path 1>
(Only test files. Source files are read-only.)

## UPSTREAM CONTRACTS
- From task T3-reviewer: coverage_gaps list — reproduce each gap as a test case

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <test path> | covers every P0/P1 gap from T3-reviewer | no source-file edits |

## Done-when
- [ ] Coverage report shows >80% for <feature> module
- [ ] Every T3-reviewer gap has a corresponding test
- [ ] `pytest <test path>` exits 0
- [ ] No edit to source files outside test paths
```

Spawn **gated** — test-engineer holds Edit/Write.

---

## The 5-pass doc pattern

Used for public-facing documentation, runbooks, ADRs, and API specs where accuracy + accessibility + cross-link integrity matter.

### Pass 1 — Drafter (`technical-writer`)

Brain dump structure. Get every section on the page with at least bullet points.

**Done-when:** All planned sections have >=3 bullet points. Structure is complete; prose is allowed to be rough.

**F9 spawn prompt:**

```
# Task: Draft <doc> structure

## What
Write the initial draft of <doc>. Every planned section must have >=3 bullet points. Prose can be rough; completeness matters more than polish.

## Where
<doc file path>

## Focus
Coverage. Nothing is missing from the outline.

## Deliverable
<doc path> exists and every H2 section has >=3 bullet points.

## FILES YOU OWN
- <absolute doc path>

## UPSTREAM CONTRACTS
(Empty list — first pass.)

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <doc path> | every H2 has >=3 bullet points | no external links required yet |

## Done-when
- [ ] Every planned section is present with >=3 bullet points
- [ ] File passes `markdownlint` (or equivalent) for structure
- [ ] No edit to files outside FILES YOU OWN
```

Spawn **gated**.

---

### Pass 2 — Editor (`comment-analyzer`)

Fix accuracy and tone. Remove TODO markers. Add citations to every claim.

**Done-when:** No TODO markers remain; all claims have citations or are flagged as opinion.

**F9 spawn prompt:**

```
# Task: Edit <doc> for accuracy and tone

## What
Edit the Pass 1 draft for factual accuracy, tone consistency, and citation hygiene. Remove TODO markers. Add citations to every claim.

## Where
<absolute doc path>

## Focus
Accuracy over flair. A wrong claim in docs is worse than no docs.

## Deliverable
The same doc, edited, with zero TODO markers and every claim cited.

## FILES YOU OWN
- <absolute doc path>

## UPSTREAM CONTRACTS
- From task T1 (drafter): <doc path> — preserve structure; refine prose only

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <doc path> | zero TODO markers | structure unchanged |
| <doc path> | every claim has citation or [opinion] tag | no new sections |

## Done-when
- [ ] `grep -i "TODO\|FIXME\|XXX" <doc path>` returns empty
- [ ] Every claim links to a source or is tagged `[opinion]`
- [ ] `markdownlint` passes
- [ ] No edit to files outside FILES YOU OWN
```

Spawn **gated**.

---

### Pass 3 — Reviewer (`code-reviewer` adapted for prose)

Check completeness from a fresh-reader perspective.

**Done-when:** A new engineer can follow this doc without asking questions.

**F9 spawn prompt:**

```
# Task: Review <doc> for completeness

## What
Review the edited doc as if you are a new engineer joining the team. Flag any step that assumes unstated context, any term used before it's defined, and any missing prerequisite.

## Where
<absolute doc path>

## Focus
Completeness over style. The reader has never seen this codebase before.

## Deliverable
A structured review report at `.scratch/<doc>-review/completeness.md`:
- verdict: one of {pass, minor, reject}
- gaps: list of missing prerequisites or undefined terms with line numbers
- questions: list of questions a new reader would ask

## FILES YOU OWN (read-only)
- <absolute doc path>

## UPSTREAM CONTRACTS
- From task T2 (editor): final draft — verify claims are cited, then test readability

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <doc path> | no undefined terms before first use | read-only |
| <doc path> | every prerequisite is listed in a "Prerequisites" section | read-only |

## Done-when
- [ ] Verdict is exactly one of: pass, minor, reject
- [ ] gaps list cites line numbers
- [ ] No edit to any file
```

Spawn **ungated** — reviewer is read-only.

---

### Pass 4 — Validator (`ux-reviewer`)

Check accessibility and inclusivity.

**Done-when:** No gendered examples, all screenshots have alt text, reading level is appropriate.

**F9 spawn prompt:**

```
# Task: Validate <doc> accessibility and inclusivity

## What
Review the doc for inclusive language, accessible media, and appropriate reading level. Flag gendered examples, missing alt text, and jargon without explanation.

## Where
<absolute doc path>

## Focus
Accessibility over aesthetics. The doc must work for screen readers and non-native speakers.

## Deliverable
A structured report at `.scratch/<doc>-review/a11y.md`:
- verdict: one of {pass, minor, reject}
- a11y_findings: list of file:line issues with severity

## FILES YOU OWN (read-only)
- <absolute doc path>

## UPSTREAM CONTRACTS
- From task T3 (reviewer): completeness-verified draft — now check a11y

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <doc path> | no gendered examples | read-only |
| <doc path> | all images have alt text | read-only |
| <doc path> | jargon is defined on first use | read-only |

## Done-when
- [ ] Verdict is exactly one of: pass, minor, reject
- [ ] Every image reference has alt text
- [ ] No edit to any file
```

Spawn **ungated**.

---

### Pass 5 — Polisher (`technical-writer`)

Final formatting, cross-links, and lint.

**Done-when:** All internal links resolve, Markdown passes lint, doc is ready to publish.

**F9 spawn prompt:**

```
# Task: Polish <doc> for publication

## What
Final formatting pass: fix Markdown lint, resolve internal cross-links, standardize heading caps, add table of contents if absent.

## Where
<absolute doc path>

## Focus
Polish over substance. No content changes; only structure and formatting.

## Deliverable
The doc is publication-ready: lint-clean, all links resolve, consistent style.

## FILES YOU OWN
- <absolute doc path>

## UPSTREAM CONTRACTS
- From task T4 (ux-reviewer): a11y-verified draft — only formatting remains

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| <doc path> | all internal links resolve | no content changes |
| <doc path> | passes `markdownlint` | no section renames |

## Done-when
- [ ] `markdownlint` passes with zero errors
- [ ] `grep -oP '\[.*?\]\(.*?\)' <doc path> | xargs -I {} link-checker` resolves all internal links
- [ ] Table of contents is present and accurate (if doc >10 sections)
- [ ] No edit to files outside FILES YOU OWN
```

Spawn **gated**.

---

## Task board integration

Progressive refinement is a sequential chain. Each pass is a task in the board with `depends_on` the previous pass. The board makes the ordering observable and resumable across sessions.

Use `scripts/task_board_lib.sh` for all state transitions, per `skills/orchestrate/SKILL.md` § Task board integration.

### Chain structure

```
Pass 1 (builder)     →  Pass 2 (simplifier)  →  Pass 3a (code-reviewer)
   T1                       T2                       T3a
   depends_on: []           depends_on: [T1]         depends_on: [T2]
                                                      ↓
                                               Pass 3b (test-engineer)
                                                  T3b
                                                  depends_on: [T3a]
```

### Rejection handling

If any pass rejects (verdict != `pass`), the pipeline stops and the lead spawns a **fix task** that depends on the rejecting pass:

1. **Pass N rejects:** create fix task `T<N>-fix-1` with `depends_on = [T<N>]` and `status = "pending"`. Run `kbg_recompute_blocked` so it is unblocked once the rejecting pass is marked complete.
2. **Reset downstream:** set `status = "pending"` for all tasks that depend on T<N> (they were previously blocked; now they stay blocked until the fix task completes).
3. **Fixer completes:** mark `T<N>-fix-1` `completed`. Recompute blocked. The next pass unblocks and resumes.
4. **Re-validate after fix:** if the fixer edited source files, spawn a re-validator (same role as the original rejecting pass) with `depends_on = [T<N>-fix-1]` before allowing downstream to proceed.

**Shell pattern for rejection recovery:**

```bash
# T2 (simplifier) returned reject
updated=$(kbg_board_read "$PLAN_DIR" | jq '
  .tasks["T2-fix-1"] = {
    id: "T2-fix-1",
    status: "pending",
    depends_on: ["T2"],
    assigned_role: "backend-engineer",
    files: .tasks["T2"].files
  } |
  .tasks["T3a"].status = "pending"
')
kbg_board_write "$PLAN_DIR" "$updated"
kbg_recompute_blocked "$PLAN_DIR"
```

### Gating rules

| Pass role | Gated? | Why |
|-----------|--------|-----|
| Builder / Drafter (Pass 1) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Simplifier / Editor (Pass 2) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Reviewer / Validator (Pass 3+) | **No** | Read-only; no AskUserQuestion |
| Fixer (rejection recovery) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Polisher (Pass 5) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |

---

## Worked example: progressive refinement of a REST API endpoint

Concrete pipeline for implementing `GET /health`.

### Pass 1 — Builder: `backend-engineer` writes rough endpoint

```
# Task: Build GET /health rough implementation

## What
Add a health check endpoint that returns 200 with JSON body. Handle 200 and 500 cases only in this pass.

## Where
src/api/routes/health.py

## Focus
Coverage over elegance.

## Deliverable
src/api/routes/health.py exists and GET /health returns {"status":"ok"} with HTTP 200.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## UPSTREAM CONTRACTS
(Empty list — first pass.)

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/api/routes/health.py | exports GET /health handler | no new deps |

## Done-when
- [ ] GET /health returns HTTP 200 + {"status":"ok"}
- [ ] GET /health?fail=1 returns HTTP 500 (basic error path)
- [ ] pytest src/api/routes/test_health.py passes
- [ ] No edit to files outside FILES YOU OWN
```

### Pass 2 — Simplifier: `code-simplifier` refactors

```
# Task: Simplify GET /health implementation

## What
Refactor the health endpoint for clarity. Extract helper if needed, reduce nesting, rename for readability.

## Where
/Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## Focus
Clarity over cleverness.

## Deliverable
The same file, refactored, with all original tests still passing.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## UPSTREAM CONTRACTS
- From task T1: src/api/routes/health.py — behavior is frozen

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/api/routes/health.py | cyclomatic complexity <10 | no behavior change |
| src/api/routes/health.py | no function >50 lines | all T1 tests still pass |

## Done-when
- [ ] pytest src/api/routes/test_health.py exits 0
- [ ] Every function is ≤50 lines
- [ ] No edit to files outside FILES YOU OWN
```

### Pass 3a — Reviewer: `code-reviewer` finds missing 503 case

```
# Task: Review GET /health for correctness

## What
Review the simplified health endpoint for edge-case gaps and correctness.

## Where
/Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## Focus
Correctness over speed.

## Deliverable
Verdict report at .scratch/health-review/verdict.md.

## FILES YOU OWN (read-only)
- /Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## UPSTREAM CONTRACTS
- From task T2: final diff — behavior should be identical to T1

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/api/routes/health.py | no P0/P1 correctness findings | read-only |

## Done-when
- [ ] Verdict is one of: pass, minor, reject
- [ ] Every finding cites file:line
- [ ] No edit to any file
```

**Outcome:** reviewer rejects — missing 503 case and no timeout handling.

### Fix: spawn `backend-engineer` to add 503 + timeout

```
# Task: Fix GET /health review findings

## What
Address the T3a findings: add 503 response for degraded DB and add request timeout handling.

## Where
/Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## Focus
Precision over creativity — apply the fix exactly as described.

## Deliverable
The modified file passes all T3a findings.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## UPSTREAM CONTRACTS
- From T3a: missing 503 case and timeout handling — reproduce each in the fix commit message

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/api/routes/health.py | T3a findings resolved | no regression |

## Done-when
- [ ] Every T3a finding is either fixed or explicitly rejected with reason
- [ ] pytest src/api/routes/test_health.py exits 0
- [ ] No new files outside FILES YOU OWN
```

### Pass 3b — `test-engineer` writes tests for 200/500/503/timeout

```
# Task: Write missing tests for GET /health

## What
Write tests covering 200, 500, 503, and timeout paths.

## Where
src/api/routes/test_health.py

## Focus
Behavioral coverage.

## Deliverable
Test file with >80% coverage for health.py.

## FILES YOU OWN
- /Users/kobig/Codes/Personals/kbg-harness/src/api/routes/test_health.py

## UPSTREAM CONTRACTS
- From T3a: coverage gaps — 503 and timeout are untested

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| test_health.py | covers 200, 500, 503, timeout | no source-file edits |

## Done-when
- [ ] Coverage report shows >80% for health.py
- [ ] pytest src/api/routes/test_health.py exits 0
- [ ] No edit to source files
```

### Pass 4 (optional) — `security-reviewer` checks for information leakage

```
# Task: Security review of GET /health

## What
Check the final health endpoint for information leakage in error messages (stack traces, internal IPs, dependency versions).

## Where
/Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## Focus
Security correctness — no leakage.

## Deliverable
Security verdict at .scratch/health-review/security-verdict.md.

## FILES YOU OWN (read-only)
- /Users/kobig/Codes/Personals/kbg-harness/src/api/routes/health.py

## UPSTREAM CONTRACTS
- From T3-fix: final diff after 503+timeout fix

## Files + Criteria + Constraints
| File | Criterion | Constraint |
|------|-----------|------------|
| src/api/routes/health.py | no OWASP info-leak patterns | read-only |

## Done-when
- [ ] Security verdict is pass
- [ ] No edit to any file
```

This optional Pass 4 is gated by blast radius: if the endpoint is public-facing or customer-visible, run it. If it is an internal ops endpoint, skip.

---

## Cross-references

- **Validation chain `B → V1 → F → V2`** — `skills/orchestrate/SKILL.md` § Validation chain. The 3-pass code pattern is the proactive pipeline version of the same chain.
- **F9 spawn-prompt template** — `skills/orchestrate/SKILL.md` § Spawn-prompt template. Every pass above uses this template verbatim.
- **Task board integration (`depends_on`, `recompute_blocked`)** — `skills/orchestrate/SKILL.md` § Task board integration.
- **`/validate-and-fix`** — `commands/validate-and-fix.md`. Use this command to run the builder-validator-fix-revalidator chain reactively on a single already-completed task. Use `progressive-refine` when you want to plan the multi-pass pipeline upfront.
- **`code-simplifier`** — `skills/code-simplifier.md`. The Pass 2 agent for the 3-pass code pattern. If the skill file does not yet exist in the fleet, dispatch a simplification pass using the spawn prompt above with `backend-engineer` scoped to "refactor for clarity only."
- **`7-agent-pattern`** — `skills/7-agent-pattern/SKILL.md`. Catalog of agent roles including `technical-writer`, `comment-analyzer`, `ux-reviewer`, and `security-reviewer` used in the 5-pass doc pattern and optional Pass 4.
- **`recursive-improve`** — `skills/recursive-improve/SKILL.md`. Use `recursive-improve` when the harness itself needs improvement; use `progressive-refine` when a single artifact needs quality passes. The former is human-gated by design; the latter can be scripted once the plan is approved.
- **`backend-dev`** — `skills/backend-dev/SKILL.md`. The builder agent's own workflow (tests first, minimal implementation, architecture concerns). Pass 1 of the 3-pass pattern delegates to this skill.

## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
