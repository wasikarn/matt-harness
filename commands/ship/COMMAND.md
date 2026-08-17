---
name: ship
description: "Land a code change end-to-end: classify, implement, test, review, fix-loop, merge. Say 'ship this/ทำงานใหม่'. Don't use for releases (/ship-release) or a PR already ready to merge (/ship-merge)."
argument-hint: Description of the task or change to ship
disable-model-invocation: true
disable-model-invocation-reason: irreversible external and spawns agents — full ship loop ending in merge
---

# Ship

One entry point for landing a code change, from a blank slate or an already-scoped request. Every phase gates the next. No autonomous loops — every fix iteration requires explicit re-invocation.

Merges the former `/ship-task` (blank-slate, 9-step) and `kbg:ship-change` (already-scoped, 5-phase) into a single command with one entry classification. Both were the same tail (implement → test → review → fix-loop → ship-merge) reached two different ways; keeping them as two surfaces the user had to choose between — with circular cross-references between them — was the actual problem, not the underlying distinction. See `CHANGELOG.md` for the record of this merge and why it supersedes the earlier "keep them separate" call.

## Phase Overview

| Phase | Path A (blank-slate) | Path B (already-scoped) |
|-------|----------------------|--------------------------|
| 0 | **Entry classification** — which path | **Entry classification** — which path |
| 1 | **Explore** — `Explore` agent, read-only recon | *skipped — scope already known* |
| 2 | **Clarify** — `kbg:decide`, 3-step scope gate | *skipped — escalate inline only if Phase 4 surfaces new ambiguity* |
| 3 | **Define done** — full checkable criteria list | **Define done** — 1-2 items, stated inline from the Phase 0 boundary |
| 4 | **Classify + Implement** — bug→`/fix-bug` · feature→inline TDD · refactor→`/refactor-clean` | same |
| 5 | **Test** — project test-suite + type-check | same |
| 6 | **Review** — `kbg:review-pr`, SCRUTINIZE-4 filter | same |
| 7 | **Fix loop** — `/address-review` → re-run Phase 6 until clean | same |
| 8 | **Ship** — `/ship-merge` | same |

Both paths converge at Phase 4 and share every phase after it verbatim.

---

## Phase 0: Entry Classification

**Goal**: route to the right amount of upfront discovery before anything is built.

**Actions**:
1. **Analyze**: does the request already name specific file(s), function(s), or an error message
   (concrete location signal → leans Already-scoped), or only a feature/outcome description with
   no located code (leans Blank-slate)? **Default when unclear**: Path A — blank-slate discovery
   is the safer over-ask (Failure Modes below).
2. **AskUserQuestion** single-select: "Is this a blank-slate task (need codebase recon + scope clarification first) or an already-scoped change (bug/feature/refactor with a known boundary)?"
   - `Blank slate (best when the codebase area, extension points, or full scope aren't known yet)` → Path A: runs Explore + Clarify (Phases 1-2) before implementation starts
   - `Already scoped (best when you know exactly what needs to change and where)` → Path B: skips straight to Phase 3's lightweight define-done, implementation starts sooner
3. **Shared scope gate** (applies to both paths): if the description spans multiple independent subsystems, STOP and propose decomposition. Each subsystem gets its own `/ship` run.

**Path A** → continue to Phase 1.
**Path B** → skip to Phase 3 (lightweight define-done), then Phase 4.

---

## Phase 1: Explore (Path A only)

**Goal**: Understand before touching. Read-only, clean context window.

**Actions**:
1. Identify the codebase area the task touches (auth, API, hooks, UI, data layer, etc.).
2. Spawn the `Explore` agent with a prompt like:
   > "Explore how [area] works across this codebase. Map the files involved, the data flow, and anything fragile. Don't change anything."
3. Wait for the agent's map.
4. From the map: identify load-bearing files, fragile spots, and the simplest implementation path.

**Gate**: recon must complete before Phase 2. If scope unclear after explore, narrow and re-explore.

---

## Phase 2: Clarify (Path A only)

**Goal**: Resolve unstated assumptions before designing.

**Actions**:
1. Invoke `kbg:decide` — it runs the 3-step (Analyze → Recommend → Ask) gate.
2. Answer its questions; redirect scope if needed.

**Gate**: all ambiguities resolved. Scope spanning independent subsystems → split into separate `/ship` runs.

---

## Phase 3: Define Done Criteria

**Path A — full procedure**:
1. List 1–N completion criteria, each checkable by a deterministic signal — a passing test name, a command exit code, a file presence, or a clean type-check. No prose-only criteria.
2. Confirm the list with the user.

**Path B — lightweight procedure**: state 1-2 checkable criteria inline, using the already-scoped boundary the user gave at Phase 0, rather than running a separate round-trip — an already-scoped change has a narrow enough boundary that a full criteria round-trip is ceremony, not rigor.

**Gate**: every criterion is checkable. A criterion you can't wire to a deterministic signal → rewrite it with a specific command/test before Phase 4.

---

## Phase 4: Classify + Implement

**Goal**: Build in small, reviewable pieces with TDD.

**Actions**:
1. **Classify**: run the shared sub-procedure in `commands/ship/references/classify.md` (bug fix / new feature / refactor). Written once so this can't drift between Path A and Path B — see the file for the full AskUserQuestion + routing logic.
2. **Bug fix** → `/fix-bug`. Wait for it to complete, then proceed to Phase 5.
3. **Refactor** → `/refactor-clean`. Wait for it to complete, then proceed to Phase 5.
4. **New feature** → continue inline:
   - **Discovery** — analyze `$ARGUMENTS`, identify ambiguities, and decompose if the request spans independent subsystems.
   - **Codebase exploration** — spawn 2–3 `Explore` agents in parallel (similar features, architecture, extension points) and read the key files they identify. (Path B skipped Phase 1's recon — this step covers feature-specific exploration even on the already-scoped path.)
   - **Clarifying questions** — present all underspecified aspects to the user and wait for answers before designing. If the scope changes materially, revise the Phase 3 criteria.
   - **Architecture design** — spawn 2–3 `code-architect` agents in parallel (minimal changes, clean architecture, pragmatic balance), self-review each surviving approach for placeholder/scope/ambiguity, then present all surviving approaches with their trade-offs and ask the user to pick — don't silently narrow to one before the user sees the field; name any dropped during self-review and why.
   - **Implementation** — wait for explicit approval, then default to TDD red → green → refactor unless one of the documented opt-out criteria applies (visual-only change, hard race with named tool, integration boundary with stated harness rejection, 1-line cosmetic).
   - **Quality review** — spawn conditional reviewers (code-reviewer always — covers type-design and test-coverage lenses; security-reviewer, silent-failure-hunter as needed), consolidate findings into Critical/Important/Minor — do NOT blend findings across agents; when two reviewers independently flag the same file:line, note the overlap explicitly rather than merging or dropping one — and ask the user how to proceed.
   - **Summary** — mark todos complete, document decisions, files modified, and next steps.

**Carve-out**: genuinely trivial work (a one-liner, a copy tweak) may skip the design-approval gate and implement directly, per METHODOLOGY Rule 1. Don't manufacture a design for a one-line change.

**Gate**: Phase 4 completes. The Phase 3 criteria must be passable.

---

## Phase 5: Test / Pre-Ship Verification

**Goal**: Prove the change works — the project's deterministic gates are green.

**Actions**:
1. **Run the test suite** — auto-detect the runner (`npm test` / `pnpm test` / `yarn test` / `pytest` / `go test ./...` / `cargo test`). If the project has no test runner, surface that and rely on the type-check + manual verification.
2. **Run the type-check** if the stack has one (`tsc --noEmit` / `vue-tsc` / `mypy .` / `go vet ./...` / `cargo check`).
3. **Cross-check the Phase 3 criteria** — each must pass. Emit a GREEN / AMBER / RED verdict:
   - **GREEN** (tests pass + type-check clean + every Phase 3 criterion met): proceed to Phase 6.
   - **AMBER** (tests + type-check pass, but a criterion needs manual verification — visual/UX, a manual runbook step): surface the manual item and ask the user to confirm before proceeding.
   - **RED** (any test fails or type-check errors): list the failures. STOP. Do NOT proceed to Phase 6. The user must fix and re-run Phase 5, or explicitly accept the risk.
4. **Audit trail.** Append a compact entry to `.scratch/<slug>/verification-log.jsonl` with the result.

Detailed test-runner auto-detect and the criteria cross-check are in `commands/ship/references/pre-ship-verify.md`.

---

## Phase 6: Review

**Goal**: Fresh-context multi-agent critic with no context contamination from the build.

**Actions**:
1. Invoke `kbg:review-pr`. For high-stakes surfaces (auth flows, payment, admin panels, file uploads, dependency manifests), run `kbg:security-auditor` first — the `security-reviewer` pass inside `kbg:review-pr` covers routine auth/secrets-touching diffs; don't run both.
2. SCRUTINIZE-4 gate in Phase 5 of that skill filters false positives.
3. Phase 7 of that skill writes `~/.claude/state/review-last.json`.

**Gate**: `review-last.json: clean: true`. If Critical findings → fix inline or return to Phase 4 for scope-narrowed fix → re-run Phase 6.

---

## Phase 7: Fix Loop

**Goal**: Iterate until the review comes back clean.

**Actions**:
1. If Phase 6 returned findings: fix them.
2. Re-run `kbg:review-pr` (Phase 6 of this command).
3. Repeat until `review-last.json` shows `clean: true` and `last_sha == HEAD`.

There is no autonomous loop. Each iteration requires explicit user re-invocation of Phase 6.

---

## Phase 8: Ship

**Goal**: Land the change with proof and clean review.

**Actions**:
1. **Check for an existing PR**: `gh pr view --json number -q .number 2>/dev/null`. If none
   exists yet, invoke `kbg:pr` to open one first — it runs its own templated preview/confirm
   gate before creating anything. Don't shortcut this with a raw `gh pr create`, which skips
   that gate. `/ship-merge`'s Phase 1 hard-requires a PR (`gh pr view`) and has no fallback of
   its own for a branch with none — Path B's ordinary first-push case would otherwise dead-end
   here after every prior phase already passed.
2. Tell the user to run `/ship-merge` — this command carries `disable-model-invocation: true`,
   so it cannot be invoked directly; hand the user the literal string, don't call it as a tool.
   Its own Phase 1 already runs the full Rule-14-scored review-state gate (Critical findings,
   CI status, review freshness, coverage) — don't duplicate that check here.

---

## Input Contract

- **Required**: task description and the codebase area to explore (Path A) or the known change boundary (Path B).
- **Optional**: existing repro steps (for bugs), rough acceptance criteria sketch.

## Failure Modes

- Phase 0 unclear which path → default to Path A; blank-slate discovery is the safer over-ask.
- Phase 1 unclear area → narrow scope, re-explore a smaller subsystem.
- Phase 3 non-machine-checkable criteria → rewrite criteria with a specific command.
- Phase 6 Critical findings → must fix before Phase 8. No exceptions.
- **Sensitive-path own-branch STOP at Phase 8**: if the diff touches a sensitive path — `ship-merge/COMMAND.md`'s automation-bias guard is the canonical definition (auth/secret/credential/payment/billing/token, or the harness's own verifier/gate paths per `hooks/gates/lib/_protected_paths.py`'s `is_gate_path()` — don't re-copy that list here), Phase 6's in-session review writes `review_mode: "own-branch"` — `/ship-merge`'s automation-bias guard won't trust that self-tiering and scores Critical findings 0, which STOPs the merge regardless of how clean the review looked. This isn't a bug in Phase 8; re-review via `kbg:review-pr`'s PR-by-number mode (isolated worktree) before retrying.
- `review-last.json` absent or stale → re-run `kbg:review-pr`.
- **Circular handoffs**: never tell the user to re-run `/ship` from within one of its own phases. Use the specific phase's underlying command instead.
- **Bloated command**: if you find yourself adding implementation detail (e.g., "how to write a test") beyond a pointer, it belongs in `/fix-bug` or `/refactor-clean`, not here.
- Autonomy invariant: fix loop (Phase 7) is manual — no unattended retry.
