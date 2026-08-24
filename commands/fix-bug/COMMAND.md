---
name: fix-bug
description: "Guided 7-phase bug-fix workflow. Use for non-trivial bugs needing root-cause or regression pinning. Say 'แก้บั๊ก/fix bug'. Don't use for typos, TDD (tdd), or refactors (/refactor-clean)."
argument-hint: Optional bug description or repro steps
model: inherit
effort: high
---

# Fix Bug

You are helping a developer fix a bug: reproduce deterministically before hypothesizing, localize before fixing, write a regression test that would have caught it, and route the right reviewer agents.

*(Ported from ECC; provenance detail: `references/provenance.md`.)*

## Core Principles

- **No repro, no fix.** **Analyze**: reproducibility signal strength — does the failure happen ≥2 times with the same inputs? Is the environment pinned (OS, runtime, branch)? **Recommend** STOP and ask when the repro is flaky or environment is unknown; proceed only when the failure is deterministic and the trigger is isolated. Don't fix imagined bugs — surface the uncertainty instead of guessing.
- **Root cause over symptom.** A fix that makes the symptom go away without explaining WHY is not a fix.
- **Surgical by default.** Smallest change near the bug beats refactoring nearby code. Refactor only if the bug exposes a structural weakness *and* the user agrees.
- **Tests encode intent.** The regression test must fail on the bug and pass on the fix. If you can't write a test that distinguishes the two, you haven't actually fixed the bug.
- **Use TodoWrite.** Track phases as todos so progress is visible.
- **Sequential ledger.** Every run of the repro, every instrumentation result, every hypothesis test is a data point. Record them in order — new ideas are weighed against the complete history, not against memory alone.

---

## Hard Sequencing Rules

Non-negotiable — violating them is the #1 cause of fixing the wrong thing. Each is enforced by a real gate below; full rationale: `references/hard-sequencing-rules.md`.

1. **No hypothesis before deterministic repro** (Phase 1 gate).
2. **No fix before confirmed hypothesis** (Phase 3 step 7 gate).
3. **No cleanup before regression test passes** (Phase 5 REFACTOR step).
4. **No commit before the distinguishes-or-it-doesn't check** (Phase 6).
5. **Record every run** — each repro/instrumentation/ranking is a ledger entry.

---

## Phase 1: Reproduce + Minimise

**Goal**: Deterministic repro on the smallest failing case before any hypothesis. Mirrors `diagnosing-bugs`'s first two steps inline.

Initial report: $ARGUMENTS

**Actions**:
1. Create todo list with all phases.
2. Extract from the report: exact steps, inputs, environment (OS, runtime, branch, last-known-good commit if mentioned).
3. Run the repro. Confirm it fails consistently (≥2 runs).
4. Can't reproduce → STOP. Ask for missing pieces (logs, exact input, env diff); do not proceed.
5. **Minimise**: strip non-essential setup, simplify inputs, narrow to the smallest sequence that still triggers the failure — re-test after each removal, keep only what's load-bearing.
6. Capture the minimised repro's failure signal (error, wrong output, stack trace, perf number) — the verification target for Phase 5.
7. **Ledger entry**: append to running log — `YYYY-MM-DD HH:MM | Phase 1 | repro run #N | <environment> | <result: fail/pass>`.

**Anti-patterns**: "I think this is the bug" without running anything · skipping straight to fix · keeping a 50-line repro when 5 lines reproduce it.

---

## Phase 2: Localize

**Goal**: Narrow the code surface involved.

**Actions**:
1. Use `code-review-graph` MCP for structural queries — callers, callees, impact radius from the failing function/symbol. Check `mcp__code-review-graph__list_repos_tool` first; if the repo's graph isn't built, fall back to Grep.
2. `git log -S '<symbol>'` or `git log -p <file>` to see when the behavior changed — the last commit to touch it is often the suspect.
3. Read the suspect files end-to-end (not just grep snippets).
4. Wide surface (>3 files)? Spawn 1-2 `Explore` agents in parallel, each on a different angle (call sites / data flow / similar past bugs).
5. Output: a short list of code locations, each with a one-line note covering both its role in the failure and how it was found (code-review-graph query / `git log` hit / direct read / Explore agent) — Phase 3 reads this list to rank hypotheses without re-deriving it, so the provenance matters as much as the role.

---

## Phase 3: Hypothesize + Instrument

**Goal**: ONE *confirmed* hypothesis — not just a ranked list. Mirrors `diagnosing-bugs`'s hypothesise → instrument loop inline.

**Actions**:
1. List 2-3 candidate hypotheses based on Phase 2 findings.
2. For each: what would have to be true for it to be the cause, and what evidence would distinguish it from the others.
3. Rank by likelihood × cheapness-to-test. Pick the top one.
   - **Named bias guard — anchoring + confirmation** (≥2 candidates + distinguishing evidence per hypothesis, steps 1-2, is the mitigation). Full rationale: `judgment-ladder.md` §"3. Gather and test assumptions" — `cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"`.
4. **Confirm via instrumentation** (if not already proven by Phase 1's repro): add logging/asserts/breakpoints → re-run the minimised repro → observe whether the expected evidence appears; if not, fall back to the next-ranked hypothesis and repeat. Don't write the fix on an unconfirmed hypothesis.
   - **No-progress halts** (stagnation guards, not retry caps; full detail: `references/phase3-stagnation-guards.md`) — each routes to the step-7 "Reject" branch, never to more unattended rounds:
     - **Stall** — two rounds return the same missing-evidence result for the same failure signal.
     - **Degrading** — confidence goes backwards round over round, not just standing still.
     - **Reachable-source skip** — calling it "blocked" when a real source/log was reachable but unread; read it, or route to the gate.
5. **Ledger entry**: `YYYY-MM-DD HH:MM | Phase 3 | H1 tested | <instrumentation> | <evidence: found/missing> | fallback to H2? <yes/no>`.
6. **Analyze**: instrumentation evidence strength (expected signal appeared?), falsifiability (would evidence differ if hypothesis were wrong?), fallback count. **Recommend** proceed when evidence is strong/reproducible, reject when weak/contradicted.
7. **AskUserQuestion** single-select: "Phase 3 confirmed: hypothesis '[H1 description]' is supported by [evidence summary]. Approve this hypothesis and proceed to fix strategy?"
   - `Approve hypothesis and proceed to Phase 4 (best when instrumentation evidence is strong and reproducible; H1 is ranked highest by likelihood × cheapness-to-test)` — locks H1 as the fix target
   - `Reject — need more investigation (best when evidence is weak, contradicted, or a higher-ranked hypothesis was not tested yet)` — falls back to the next-ranked hypothesis (step 4), still subject to the Stall/Degrading halts
8. Strip instrumentation before Phase 5 — temporary scaffolding, no permanent log spam.

**Anti-pattern**: "It could be X, Y, or Z" without ranking or testing — that's a list, not a hypothesis; writing the fix without confirming it = fixing the wrong thing.

---

## Phase 4: Fix Strategy

**Goal**: Pick approach. Default surgical.

**Actions**:
1. Two shapes:
   - **Surgical (default)** — minimal change exactly where the bug is; no nearby cleanup or opportunistic refactor. **Exception — sibling instances of the same root defect**, not just workaround-siblings: every caller sharing the identical defect counts too — grep for every caller and fix them all in this change. Full rationale, finding-callers detail, and consequence of skipping one: `references/phase4-sibling-instances.md`.
   - **Structural** — only if the bug is a symptom of a missing seam or wrong abstraction AND the user agrees the refactor is in scope; delegate to `refactor-cleaner` (`/refactor-clean`).
2. Present the chosen strategy — surgical change at <file:line> doing X, or structural change with refactor scope Y.
3. **Analyze**: scope of buggy code (single function vs cross-module), presence of missing seam/abstraction, regression-test feasibility. **Recommend** lowest blast radius that still fixes root cause.
4. **AskUserQuestion** single-select: "Phase 4: the buggy code is at [file:line] — [scope description]. Which fix shape do you prefer?"
   - `Surgical fix (best for localized logic errors in a single function; minimal blast radius, fastest to ship)` — proceed at the identified location
   - `Structural fix (best when the bug reveals a missing seam or wrong abstraction; higher blast radius but prevents recurrence)` — delegate to `refactor-cleaner` (`/refactor-clean`)
   - `Reject — need more info (best when the root cause is still unclear or the fix scope is ambiguous)`
   - **Self-consistency**: if step 3 found the bug confined to a single function with no seam/abstraction issue, narrow the menu to Surgical/Reject — Structural isn't offered. The gate still fires; only the menu narrows, Phase 5's approval gate is never skipped.
5. **Revisit trigger**: if Phase 5 grows past the scope named in step 2 (touches files/call sites outside the identified location), stop and re-run step 4 rather than letting the fix silently outgrow its chosen scope.

---

## Phase 5: Implement (TDD by default)

**Goal**: Make the minimised repro stop failing — with a regression test that fails on the pre-fix code.

**DO NOT START WITHOUT USER APPROVAL FROM PHASE 4.**

**Default: TDD red → green → refactor** (the `tdd` pattern, inlined here):

1. **RED** — write the regression test first, asserting the now-correct behavior. Run it → confirm it FAILS on the buggy code; if it doesn't fail, rewrite the test before continuing.
2. **GREEN** — write the minimal fix per Phase 4 strategy. Run the test → confirm PASSES. Re-run the Phase 1 repro → confirm the original failure signal is gone.
3. **REFACTOR** — clean up only if strictly required for readability; no orthogonal cleanup.
4. Run the full suite locally, confirm no orthogonal regressions.

**Opt out of TDD** only when the test framework can't encode the bug type (visual regression, hard race condition, no test harness) — tell the user why, implement directly, re-run the repro, run full suite; Phase 6 becomes the test-quality gate. Full procedure: `references/phase5-tdd-optout.md`.

---

## Phase 6: Regression Test Verification

**Goal**: Prove the test catches the bug, not passing for unrelated reasons.

**Actions**:
1. TDD path (default): the regression test already exists (Phase 5's RED step) and is green — verify it below regardless, since a TDD-authored test can still pass for the wrong reason. Opt-out path: write the regression test now, asserting the now-correct behavior.
2. **Distinguishes-or-it-doesn't check** — the only proof the test is load-bearing:
   - Temporarily revert the fix.
   - Re-run the test → confirm it FAILS.
   - Re-apply the fix.
   - Re-run the test → confirm it PASSES.
   - If the test passes with the fix reverted, it isn't catching the bug. Rewrite it before continuing.
3. Name the test so the WHY is visible — e.g. `test_does_not_silently_swallow_null_user_id` not `test_user_id_handling`.
4. If the bug was a silent failure (no exception raised), the test must assert on side-effects or absence of state, not just "no exception thrown".

---

## Phase 7: Quality Review

**Goal**: Route domain-specific reviewer agents for a final quality pass.

**Actions**:
1. Conditional routing — launch in parallel based on what the fix touched (full trigger criteria: `references/phase7-agent-routing.md`):
   - Error-handling → `silent-failure-hunter`
   - Tests added/modified → the matching per-language reviewer (`typescript-reviewer`/`python-reviewer`)
   - Auth / secrets / external input → `security-reviewer`
   - Comments added/modified, or a shared function's behavior changed → the matching per-language reviewer
   - Performance-shaped root cause (algorithm/data-structure/query-pattern issue, not a plain logic error) → `performance-optimizer`
   - None of the above → `mattpocock-skills:code-review` (general correctness pass against Phase 4 strategy)
2. Consolidate findings into severity tiers, present to user. Do NOT blend findings across agents — if two reviewers flag the same file:line, note the overlap rather than merging or dropping one; agreement is a confidence signal, not noise to blend away. Assign each finding a tier by asking *"if this ships as-is, what's the worst that could happen?"*:
   - **Critical** (must fix before merge: security, data integrity, broken functionality) / **Important** (should fix: real but non-blocking) / **Minor** (nice to have: style, optional).
   - Ask per tier: fix now, defer, or proceed as-is.
3. Summarize: what broke, root cause, fix shape, regression test name, files touched. Root cause
   must name the causal mechanism (the "because X" from the confirmed hypothesis), not just the
   symptom — this text often lands verbatim in a commit/PR description read without this
   session's diagnosis context.
4. Suggest next step:
   - If not yet reviewed → invoke `mattpocock-skills:code-review`
   - If review addressed and approved → `/ship-merge`
   - If documenting the fix → `/post-mortem`
   - If fix touched auth/secrets → `kbg:security-auditor`

---

## Integration Notes

Project-specific cross-references (METHODOLOGY alignment, code-review-graph MCP usage,
`diagnosing-bugs`/`tdd` default-vs-standalone, active hooks, agent-routing summary):
`references/integration-notes.md`.

---

## Named Model

The reproduce → hypothesize → instrument → falsify loop is the *scientific method*. Catalog + honesty caveat: `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
