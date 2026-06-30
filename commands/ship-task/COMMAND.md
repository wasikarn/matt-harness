---
name: ship-task
description: "9-step senior-engineer loop from scratch: explore → clarify → define-done → implement → test → review → fix-loop → ship. Use when starting a non-trivial task from a blank slate, or when the user says 'ทำงานใหม่', 'ship task', 'เริ่มต้นทำงาน'. Don't use for: tasks already mid-flight (use kbg:ship-change), one-line fixes, pure research/exploration."
disable-model-invocation: true
disable-model-invocation-reason: irreversible external and spawns agents — full ship loop ending in merge
---

# Ship Task — 9-Step Senior Engineer Loop

Sequential pipeline that encodes the full 9-step loop into one command. Each phase gates the next.
No phase is skipped. No autonomous loops — every fix iteration requires explicit re-invocation.

## Phase Overview

| Phase | Steps | Action | Gate |
|-------|-------|--------|------|
| 1 | 1 | **Explore** — `Explore` agent, read-only recon | Map returned |
| 2 | 2 | **Clarify** — `kbg:decide`, 3-step scope gate | All Q answered |
| 3 | 3 | **Define done** — checkable completion criteria | Criteria listed |
| 4 | 4 | **Implement** — inline feature work or `/fix-bug`, TDD discipline | Command done |
| 5 | 5+6 | **Test** — project test-suite + type-check | GREEN or AMBER |
| 6 | 7 | **Review** — `kbg:review-pr`, SCRUTINIZE-4 filter | Zero Critical |
| 7 | 8 | **Fix loop** — `/address-review` → re-run Phase 6 until clean | `review-last.json: clean: true` |
| 8 | 9 | **Ship** — `/ship-merge` | CI green + review-state gate |

---

## Phase 1: Explore (Step 1 of 9)

**Goal**: Understand before touching. Read-only, clean context window.

**Actions**:
1. Identify the codebase area the task touches (auth, API, hooks, UI, data layer, etc.).
2. Spawn the `Explore` agent with a prompt like:
   > "Explore how [area] works across this codebase. Map the files involved, the data flow, and anything fragile. Don't change anything."
3. Wait for the agent's map.
4. From the map: identify load-bearing files, fragile spots, and the simplest implementation path.

**Gate**: recon must complete before Phase 2. If scope unclear after explore, narrow and re-explore.

---

## Phase 2: Clarify (Step 2 of 9)

**Goal**: Resolve unstated assumptions before designing.

**Actions**:
1. Invoke `kbg:decide` — it runs the 3-step (Analyze → Recommend → Ask) gate.
2. Answer its questions; redirect scope if needed.

**Gate**: all ambiguities resolved. Scope spanning independent subsystems → split into separate `/ship-task` runs.

---

## Phase 3: Define Done Criteria (Step 3 of 9)

**Goal**: Machine-checkable "done" before a single line changes.

**Actions**:
1. List 1–N completion criteria, each checkable by a deterministic signal — a passing test name, a command exit code, a file presence, or a clean type-check. No prose-only criteria.
2. Confirm the list with the user.

**Gate**: every criterion is checkable. A criterion you can't wire to a deterministic signal → rewrite it with a specific command/test before Phase 4.

---

## Phase 4: Implement (Step 4 of 9)

**Goal**: Build in small, reviewable pieces with TDD. This phase inlines the former `/feature-dev` 7-phase feature workflow for new features and refactors; bug fixes still dispatch to `/fix-bug`.

**Actions**:
1. Classify: bug fix → `/fix-bug`; new feature or refactor → continue below.
2. **Discovery** — analyze `$ARGUMENTS`, identify ambiguities, and decompose if the request spans independent subsystems.
3. **Codebase exploration** — spawn 2–3 `Explore` agents in parallel (similar features, architecture, extension points) and read the key files they identify.
4. **Clarifying questions** — present all underspecified aspects to the user and wait for answers before designing. If the scope changes materially, revise the Phase 3 criteria.
5. **Architecture design** — spawn 2–3 `code-architect` agents in parallel (minimal changes, clean architecture, pragmatic balance), self-review the chosen approach for placeholder/scope/ambiguity, and ask the user to pick.
6. **Implementation** — wait for explicit approval, then default to TDD red → green → refactor unless one of the documented opt-out criteria applies (visual-only change, hard race with named tool, integration boundary with stated harness rejection, 1-line cosmetic).
7. **Quality review** — spawn conditional reviewers (code-reviewer always — covers type-design and test-coverage lenses; security-reviewer, silent-failure-hunter as needed), consolidate findings into Critical/Important/Minor, and ask the user how to proceed.
8. **Summary** — mark todos complete, document decisions, files modified, and next steps.

**Carve-out**: genuinely trivial work (a one-liner, a copy tweak) may skip the design-approval gate and implement directly, per METHODOLOGY Rule 1. Don't manufacture a design for a one-line change.

**Gate**: Phase 4 completes. The Phase 3 criteria must be passable.

---

## Phase 5: Test / Pre-Ship Verification (Steps 5+6 of 9)

**Goal**: Prove the change works — the project's deterministic gates are green.

**Actions**:
1. **Run the test suite** — auto-detect the runner (`npm test` / `pnpm test` / `yarn test` / `pytest` / `go test ./...` / `cargo test`). If the project has no test runner, surface that and rely on the type-check + manual verification.
2. **Run the type-check** if the stack has one (`tsc --noEmit` / `vue-tsc` / `mypy .` / `go vet ./...` / `cargo check`).
3. **Cross-check the Phase 3 criteria** — each must pass. Emit a GREEN / AMBER / RED verdict:
   - **GREEN** (tests pass + type-check clean + every Phase 3 criterion met): proceed to Phase 6.
   - **AMBER** (tests + type-check pass, but a criterion needs manual verification — visual/UX, a manual runbook step): surface the manual item and ask the user to confirm before proceeding.
   - **RED** (any test fails or type-check errors): list the failures. STOP. Do NOT proceed to Phase 6. The user must fix and re-run Phase 5, or explicitly accept the risk.
4. **Audit trail.** Append a compact entry to `.scratch/<slug>/verification-log.jsonl` with the result.

Detailed test-runner auto-detect and the criteria cross-check are in `commands/ship-task/references/pre-ship-verify.md`.

---

## Phase 6: Review (Step 7 of 9)

**Goal**: Fresh-context multi-agent critic with no context contamination from the build.

**Actions**:
1. Invoke `kbg:review-pr`.
2. SCRUTINIZE-4 gate in Phase 5 of that skill filters false positives.
3. Phase 7 of that skill writes `~/.claude/state/review-last.json`.

**Gate**: `review-last.json: clean: true`. If Critical findings → fix inline or return to Phase 4 for scope-narrowed fix → re-run Phase 6.

---

## Phase 7: Fix Loop (Step 8 of 9)

**Goal**: Iterate until the review comes back clean.

**Actions**:
1. If Phase 6 returned findings: fix them.
2. Re-run `kbg:review-pr` (Phase 6 of this command).
3. Repeat until `review-last.json` shows `clean: true` and `last_sha == HEAD`.

There is no autonomous loop. Each iteration requires explicit user re-invocation of Phase 6.

---

## Phase 8: Ship (Step 9 of 9)

**Goal**: Land the change with proof and clean review.

**Actions**:
1. Confirm review-state gate: `~/.claude/state/review-last.json` must have `clean: true` and `last_sha == git rev-parse HEAD`.
2. Invoke `/ship-merge`.

---

## Input Contract

- **Required**: task description and the codebase area to explore.
- **Optional**: existing repro steps (for bugs), rough acceptance criteria sketch.

## Failure Modes

- Phase 1 unclear area → narrow scope, re-explore a smaller subsystem.
- Phase 3 non-machine-checkable criteria → rewrite criteria with a specific command.
- Phase 6 Critical findings → must fix before Phase 8. No exceptions.
- `review-last.json` absent or stale → re-run `kbg:review-pr`.
- Autonomy invariant: fix loop (Phase 7) is manual — no unattended retry.
