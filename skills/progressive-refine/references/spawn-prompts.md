# Progressive-refine — full F9 spawn prompts

The full F9 spawn-prompt fences for every pass of `progressive-refine`. The
canonical F9 template (file ownership + upstream contracts) lives in
`skills/orchestrate/SKILL.md` § Spawn-prompt template; the blocks below are that
template filled in per pass. `SKILL.md` keeps the per-pass *decision* content
(role, done-when, gated/ungated); copy the matching fence from here when you
actually spawn the agent.

- [3-pass code pattern](#3-pass-code-pattern) — Pass 1 builder, Pass 2 simplifier, Pass 3a reviewer, Pass 3b test-engineer
- [5-pass doc pattern](#5-pass-doc-pattern) — Pass 1 drafter → Pass 5 polisher
- [Worked example: GET /health](#worked-example-get-health) — end-to-end with a rejection + fix

---

## 3-pass code pattern

### Pass 1 — Builder (`backend-engineer`) — gated

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

### Pass 2 — Simplifier (`code-simplifier`) — gated

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

### Pass 3a — Reviewer (`code-reviewer`) — ungated (read-only)

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

### Pass 3b — Test-engineer (`test-engineer`) — gated

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

---

## 5-pass doc pattern

### Pass 1 — Drafter (`technical-writer`) — gated

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

### Pass 2 — Editor (`comment-analyzer`) — gated

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

### Pass 3 — Reviewer (`code-reviewer` adapted for prose) — ungated (read-only)

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

### Pass 4 — Validator (`ux-reviewer`) — ungated

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

### Pass 5 — Polisher (`technical-writer`) — gated

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

---

## Worked example: GET /health

Concrete pipeline for implementing `GET /health`, including a rejection at Pass 3a and the fix task that recovers from it.

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
- src/api/routes/health.py

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
src/api/routes/health.py

## Focus
Clarity over cleverness.

## Deliverable
The same file, refactored, with all original tests still passing.

## FILES YOU OWN
- src/api/routes/health.py

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
src/api/routes/health.py

## Focus
Correctness over speed.

## Deliverable
Verdict report at .scratch/health-review/verdict.md.

## FILES YOU OWN (read-only)
- src/api/routes/health.py

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
src/api/routes/health.py

## Focus
Precision over creativity — apply the fix exactly as described.

## Deliverable
The modified file passes all T3a findings.

## FILES YOU OWN
- src/api/routes/health.py

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
- src/api/routes/test_health.py

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

Gated by blast radius: if the endpoint is public-facing or customer-visible, run it. If it is an internal ops endpoint, skip.

```
# Task: Security review of GET /health

## What
Check the final health endpoint for information leakage in error messages (stack traces, internal IPs, dependency versions).

## Where
src/api/routes/health.py

## Focus
Security correctness — no leakage.

## Deliverable
Security verdict at .scratch/health-review/security-verdict.md.

## FILES YOU OWN (read-only)
- src/api/routes/health.py

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
