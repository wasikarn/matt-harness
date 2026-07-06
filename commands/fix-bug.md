---
name: fix-bug
description: "Guided 7-phase bug-fix workflow. Use for non-trivial bugs needing root-cause or regression pinning. Say 'แก้บั๊ก/fix bug'. Don't use for typos, TDD (kbg:tdd), or refactors (/refactor-clean)."
argument-hint: Optional bug description or repro steps
disable-model-invocation: true
disable-model-invocation-reason: spawns agents and mutates — a fix the user commits to
metadata:
  origin: ECC
  ecc_commit: 2bc924faf2f8e893bfe0af86b1931283693c30ae
  ported: 2026-06-27
  kbg_extension: "kbg expanded the thin ECC orch-fix-defect wrapper into a full 7-phase discipline — added No-repro-no-fix gate, Root-cause-over-symptom principle, Surgical-by-default, Tests-encode-intent, TodoWrite tracking, Sequential ledger, and Hard Sequencing Rules (no hypothesis before deterministic repro; no fix before confirmed hypothesis; no cleanup before regression test passes). kbg body 187L vs ecc wrapper 38L — kbg is the substantive implementation, ecc delegates to orch-fix-defect skill."
---

# Fix Bug

You are helping a developer fix a bug. Follow the discipline: reproduce deterministically before hypothesizing, localize before fixing, write a regression test that would have caught it, and route the right reviewer agents to the fix.

## Core Principles

- **No repro, no fix.** **Analyze**: reproducibility signal strength — does the failure happen ≥2 times with the same inputs? Is the environment pinned (OS, runtime, branch)? **Recommend** STOP and ask when the repro is flaky or environment is unknown; proceed only when the failure is deterministic and the trigger is isolated. Don't fix imagined bugs — surface the uncertainty instead of guessing.
- **Root cause over symptom.** A fix that makes the symptom go away without explaining WHY is not a fix.
- **Surgical by default.** Smallest change near the bug beats refactoring nearby code. Refactor only if the bug exposes a structural weakness *and* the user agrees.
- **Tests encode intent.** The regression test must fail on the bug and pass on the fix. If you can't write a test that distinguishes the two, you haven't actually fixed the bug.
- **Use TodoWrite.** Track phases as todos so progress is visible.
- **Sequential ledger.** Every run of the repro, every instrumentation result, every hypothesis test is a data point. Record them in order — new ideas are weighed against the complete history, not against memory alone.

---

## Hard Sequencing Rules

These are non-negotiable ordering constraints derived from the debug-mantra discipline. Violating them is the #1 cause of fixing the wrong thing.

1. **No hypothesis before deterministic repro.** If the repro isn't reliable, STOP. Don't guess at causes when you can't prove the effect.
2. **No fix before confirmed hypothesis.** The fix targets the confirmed mechanism, not a ranked list of possibilities. If the top hypothesis turns out wrong after instrumentation, fall back and re-rank — don't patch on a hunch.
3. **No cleanup before regression test passes.** Strip instrumentation, run full suite, confirm green. Then clean up temporary files or debug branches.
4. **No commit before distinguishes-or-it-doesn't check.** Phase 6 must pass before the fix is considered complete. A green test that doesn't actually catch the bug is worse than no test — it provides false confidence.
5. **Record every run.** Each repro attempt, each instrumentation result, each hypothesis ranking is a ledger entry. If you're on the third hypothesis and still unsure, re-read the ledger — the pattern is in the data, not in your head.

---

## Phase 1: Reproduce + Minimise

**Goal**: Deterministic repro on the smallest failing case before any hypothesis. Mirrors `kbg:diagnosing-bugs`'s first two steps inline.

Initial report: $ARGUMENTS

**Actions**:
1. Create todo list with all phases.
2. Extract from the report: exact steps, inputs, environment (OS, runtime version, branch, last-known-good commit if mentioned).
3. Run the repro. Confirm it fails consistently (≥2 runs).
4. If you can't reproduce → STOP. Ask the user for missing pieces (logs, exact input, env diff). Do not proceed.
5. **Minimise**: strip the repro down. Remove non-essential setup, simplify inputs, narrow to the smallest sequence that still triggers the failure. Re-test after each removal — keep only what's load-bearing.
6. Capture the failure signal of the minimised repro (error, wrong output, stack trace, perf number). This is the verification target for Phase 5.
7. **Ledger entry**: append to running log — `YYYY-MM-DD HH:MM | Phase 1 | repro run #N | <environment> | <result: fail/pass>` — so later phases can reference what was already tried.

**Anti-patterns**: "I think this is the bug" without running anything · skipping straight to fix · keeping a 50-line repro when 5 lines reproduce it.

---

## Phase 2: Localize

**Goal**: Narrow the code surface involved.

**Actions**:
1. Use `code-review-graph` MCP for structural queries — callers, callees, impact radius from the failing function/symbol.
2. Use `git log -S '<symbol>'` or `git log -p <file>` to see when the behavior changed. The last commit to touch the failing code is often the suspect.
3. Read the suspect files end-to-end (not just grep snippets).
4. If the surface is wide (>3 files involved), spawn 1-2 `Explore` agents in parallel: each takes a different angle (call sites / data flow / similar past bugs).
5. Output: a short list of code locations + one-line explanation of each location's role in the failure.

---

## Phase 3: Hypothesize + Instrument

**Goal**: ONE *confirmed* hypothesis — not just a ranked list. Mirrors `kbg:diagnosing-bugs`'s hypothesise → instrument loop inline.

**Actions**:
1. List 2-3 candidate hypotheses based on Phase 2 findings.
2. For each, state: what would have to be true for this to be the cause, and what evidence would distinguish it from the others.
3. Rank by likelihood × cheapness-to-test. Pick the top one.
   - **Named bias guard — anchoring + confirmation.** Requiring ≥2 candidates before ranking guards against anchoring on the first plausible story; requiring distinguishing evidence per hypothesis guards against confirming the top pick without looking for what would disprove it. Full rung detail: `judgment-ladder.md` §"3. Gather and test assumptions" — read via Bash: `cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"`.
4. **Confirm via instrumentation if not already proven by Phase 1's repro**: add logging / asserts / breakpoints → re-run the minimised repro → observe whether the expected evidence appears. If it doesn't, fall back to the next-ranked hypothesis and repeat. Don't write the fix on an unconfirmed hypothesis.
   - **No-progress halts** (stagnation guards — NOT retry caps; don't borrow the retry-cap vocabulary, this is a different metric). Each routes to the step-7 gate's "Reject — need more investigation" branch, never to more unattended rounds:
     - **Stall** — two instrumentation rounds return the *same missing-evidence result for the same failure signal* → stop re-ranking and go to the gate. ("Same error twice in a row: you're guessing, not fixing.")
     - **Degrading** — confidence/progress goes *backwards* (each round contradicts the last), not just standing still → stop and go to the gate.
     - **Reachable-source skip** — don't exit "blocked" on an inference when a real source/log was reachable but unread; read it, or route the block to the gate. "Blocked" must mean a real wall, not an unchecked assumption.
5. **Ledger entry**: `YYYY-MM-DD HH:MM | Phase 3 | H1 tested | <instrumentation> | <evidence: found/missing> | fallback to H2? <yes/no>`.
6. **Analyze**: instrumentation evidence strength (did expected signal appear?), falsifiability (would evidence look different if hypothesis were wrong?), fallback count (how many times have we fallen back already?). **Recommend** proceed when evidence is strong and reproducible; recommend reject when evidence is weak or contradicted.
7. **AskUserQuestion** single-select: "Phase 3 confirmed: hypothesis '[H1 description]' is supported by [evidence summary]. Approve this hypothesis and proceed to fix strategy?"
   - `Approve hypothesis and proceed to Phase 4 (Recommended when instrumentation evidence is strong and reproducible; H1 is ranked highest by likelihood × cheapness-to-test)`
   - `Reject — need more investigation (Recommended when evidence is weak, contradicted, or a higher-ranked hypothesis was not tested yet)`
8. Strip instrumentation before Phase 5 — temporary scaffolding only, no permanent log spam.

**Anti-pattern**: "It could be X, Y, or Z" without ranking or testing — that's a list, not a hypothesis. Writing the fix without confirming the hypothesis = fixing the wrong thing.

---

## Phase 4: Fix Strategy

**Goal**: Pick approach. Default surgical.

**Actions**:
1. Two shapes:
   - **Surgical (default)** — minimal change exactly where the bug is. No nearby cleanup, no opportunistic refactor.
   - **Structural** — only if the bug is a symptom of a missing seam or wrong abstraction, AND the user agrees the refactor is in scope. For structural fixes, delegate to the `refactor-cleaner` agent (via `/refactor-clean`) instead of doing it inline.
2. Present chosen strategy to the user — surgical change at <file:line> doing X, OR structural change with refactor scope Y.
3. **Analyze**: scope of buggy code (single function vs cross-module), presence of missing seam/abstraction, regression-test feasibility. **Recommend** the shape with lowest blast radius that still fixes the root cause.
4. **AskUserQuestion** single-select: "Phase 4: the buggy code is at [file:line] — [scope description]. Which fix shape do you prefer?"
   - `Surgical fix (Recommended for localized logic errors in a single function; minimal blast radius, fastest to ship)` — proceed with minimal change at the identified location
   - `Structural fix (Recommended when the bug reveals a missing seam or wrong abstraction; higher blast radius but prevents recurrence)` — delegate to the `refactor-cleaner` agent (`/refactor-clean`) for cross-module refactor
   - `Reject — need more info (Recommended when the root cause is still unclear or the fix scope is ambiguous)`

---

## Phase 5: Implement (TDD by default — `kbg:tdd` pattern)

**Goal**: Make the minimised repro stop failing — with a regression test that fails on the pre-fix code.

**DO NOT START WITHOUT USER APPROVAL FROM PHASE 4.**

**Default: TDD red → green → refactor** (the `kbg:tdd` skill's pattern, inlined here):

1. **RED** — Write the regression test first. Assert the now-correct behavior. Run it → confirm it FAILS on the buggy code. If it doesn't fail, the test isn't catching the bug; rewrite the test before continuing.
2. **GREEN** — Write the minimal fix per Phase 4 strategy. Run the test → confirm it PASSES. Re-run the minimised repro from Phase 1 → confirm the original failure signal is gone.
3. **REFACTOR** — Clean up only if strictly required to keep the fix readable. No orthogonal cleanup.
4. Run the full test suite locally. Confirm no orthogonal regressions.

**Opt out of TDD** (only when the test framework can't encode the bug type — visual regression, hard race condition needing dedicated tooling, integration boundary with no test harness):
- Tell the user TDD is being skipped and why.
- Implement the fix directly. Re-run minimised repro to confirm it's gone. Run full suite.
- Phase 6 becomes the test-quality gate via revert-and-verify.

Update todos as you progress.

---

## Phase 6: Regression Test Verification

**Goal**: Prove the test is actually catching the bug, not passing for unrelated reasons.

**Actions**:
1. If TDD was used in Phase 5 (default path): the regression test exists and is green. Verify it via step 3 below — even TDD-authored tests can pass for the wrong reason after the fix.
2. If TDD was skipped (opt-out path): write the regression test now. Assert the now-correct behavior.
3. **Distinguishes-or-it-doesn't check** — the only proof the test is load-bearing:
   - Temporarily revert the fix.
   - Re-run the test → confirm it FAILS.
   - Re-apply the fix.
   - Re-run the test → confirm it PASSES.
   - If the test passes with the fix reverted, it isn't catching the bug. Rewrite it before continuing.
4. Name the test so the WHY is visible — e.g. `test_does_not_silently_swallow_null_user_id` not `test_user_id_handling`.
5. If the bug was a silent failure (no exception raised), the test must assert on side-effects or absence of state, not just "no exception thrown".

---

## Phase 7: Quality Review

**Goal**: Route domain-specific reviewer agents for a final quality pass.

**Actions**:
1. Conditional routing — launch in parallel based on what the fix touched:
   - **Error-handling** (new/modified try-catch, fallbacks, exception flow) → `silent-failure-hunter`
   - **Tests added/modified** → `code-reviewer` (behavioral test-coverage lens)
   - **Auth / secrets / external input** → `security-reviewer`
   - **Comments added/modified** → `code-reviewer` (comment-accuracy lens)
   - If the fix touched none of the above (rare for non-trivial bugs) → route to `code-reviewer` agent for a general correctness pass against Phase 4 strategy.
2. Consolidate findings into severity tiers + present to user. For each finding, assign a tier by asking *"if this ships as-is, what's the worst that could happen?"* — production breaks / a 2am page / silent data corruption / users see errors → **Critical**; a real but contained issue → **Important**; only "the code is slightly less clean" → **Minor**:
   - **Critical** — must fix before merge (security, data integrity, broken functionality)
   - **Important** — should fix before merge (real issues that don't block but shouldn't ship)
   - **Minor** — nice to have (style, optional refinements)
   - Ask per tier: fix now, defer, or proceed as-is.
3. Summarize: what broke, root cause (one sentence), fix shape, regression test name, files touched.
4. Suggest next step:
   - If not yet reviewed → invoke `kbg:review-pr`
   - If review addressed and approved → `/ship-merge`
   - If documenting the fix → `/post-mortem`
   - If fix touched auth/secrets → `kbg:security-auditor` for comprehensive audit before merge

---

## Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Think before coding) → Phases 1-3. Surgical changes → Phase 4 default. Model only for judgment → Phase 1 repro must be deterministic, not Claude-asserted. Tests verify intent → Phase 6 distinguishes-or-it-doesn't check. Fail loud → Phase 1 abort if no repro.
- **code-review-graph MCP**: Phase 2 for structural lookup; the orchestrating session (not the reviewer agents, which have no MCP grant) runs impact-radius queries in Phase 7 before spawning review — `code-reviewer` itself escalates blast-radius depth via grep.
- **`kbg:diagnosing-bugs` and `kbg:tdd` are built in as DEFAULTS, not alternatives**:
  - Phase 1 (Reproduce + Minimise) and Phase 3 (Hypothesize + Instrument) inline `kbg:diagnosing-bugs`'s core loop so the full workflow lives in one document. Don't separately invoke `kbg:diagnosing-bugs` from within `/fix-bug` — it's already running.
  - Phase 5 defaults to `kbg:tdd`'s red-green-refactor. Opt out only when the test framework can't encode the bug type (visual regression, hard race condition).
  - Use standalone `kbg:diagnosing-bugs` for understand-only loops (e.g. characterising a flaky test before deciding whether to fix it).
  - Use standalone `kbg:tdd` for greenfield TDD on new features, not bug fixes.
- **Hooks active**: `hooks/gates/irrecoverable.sh` (destructive Bash/git/SQL patterns) and `hooks/gates/path-hardcode.sh` (hardcoded `/Users/` paths) run automatically. Don't bypass.
- **Agent routing reference**: silent-failure-hunter (error-handling audit), code-reviewer (test-coverage + comment-accuracy lenses), security-reviewer (auth/secrets/OWASP).

---

## Named Model

The reproduce → hypothesize → instrument → falsify loop is the *scientific method*. Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
