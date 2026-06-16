---
name: ship-task
description: "9-step senior-engineer loop from scratch: explore → clarify → accept-task → implement → (auto-test hook) → review → fix-loop → ship. Use when starting a non-trivial task from a blank slate. Don't use for: tasks already mid-flight (use kbg:ship-change), one-line fixes, pure research/exploration."
disable-model-invocation: true
disable-model-invocation-reason: "irreversible external and spawns agents — full ship loop ending in merge"
---

# Ship Task — 9-Step Senior Engineer Loop

Sequential pipeline that encodes the full 9-step loop into one command. Each phase gates the next.
No phase is skipped. No autonomous loops — every fix iteration requires explicit re-invocation.

## Phase Overview

| Phase | Steps | Action | Gate |
|-------|-------|--------|------|
| 1 | 1 | **Explore** — `code-explorer` agent, read-only recon | Map returned |
| 2 | 2 | **Clarify** — `kbg:clarify-first`, 3-step scope gate | All Q answered |
| 3 | 3 | **Accept** — `kbg:accept-task`, lock ACCEPTANCE.md | Contract written |
| 4 | 4 | **Implement** — `/feature-dev` or `/fix-bug`, TDD discipline | Command done |
| 5 | 5+6 | **Test** — `post-edit-test` hook (auto) + `/pre-ship-verify` | GREEN or AMBER |
| 6 | 7 | **Review** — `kbg:review-pr`, SCRUTINIZE-4 filter | Zero Critical |
| 7 | 8 | **Fix loop** — `/address-review` → re-run Phase 6 until clean | `review-last.json: clean: true` |
| 8 | 9 | **Ship** — `/ship-merge` | CI green + review-state gate |

---

## Phase 1: Explore (Step 1 of 9)

**Goal**: Understand before touching. Read-only, clean context window.

**Actions**:
1. Identify the codebase area the task touches (auth, API, hooks, UI, data layer, etc.).
2. Spawn the `code-explorer` agent with a prompt like:
   > "Explore how [area] works across this codebase. Map the files involved, the data flow, and anything fragile. Don't change anything."
3. Wait for the agent's map.
4. From the map: identify load-bearing files, fragile spots, and the simplest implementation path.

**Gate**: recon must complete before Phase 2. If scope unclear after explore, narrow and re-explore.

---

## Phase 2: Clarify (Step 2 of 9)

**Goal**: Resolve unstated assumptions before designing.

**Actions**:
1. Invoke `kbg:clarify-first` — it runs the 3-step (Analyze → Recommend → Ask) gate.
2. Answer its questions; redirect scope if needed.

**Gate**: all ambiguities resolved. Scope spanning independent subsystems → split into separate `/ship-task` runs.

---

## Phase 3: Lock Acceptance (Step 3 of 9)

**Goal**: Machine-checkable "done" before a single line changes.

**Actions**:
1. Invoke `kbg:accept-task` — it writes `.scratch/<slug>/ACCEPTANCE.md`.
2. Verify: every criterion must be checkable (a command exit code, a file presence, a test assertion).

**Gate**: ACCEPTANCE.md written and `accept-last.json` present before Phase 4.
Machine check:
```bash
cat "${ACCEPT_TASK_STATE_DIR:-$HOME/.claude/state}/accept-last.json"
```
- File absent → STOP: "No `kbg:accept-task` run found. Lock the contract first."
- `slug` matches current task → proceed.
- `slug` mismatch → WARN: "Contract is for a different task. Re-run `kbg:accept-task`."

---

## Phase 4: Implement (Step 4 of 9)

**Goal**: Build in small, reviewable pieces with TDD.

**Actions**:
1. Classify: bug fix → `/fix-bug`; new feature or refactor → `/feature-dev`.
2. Run the command. It handles its own internal explore → design → TDD implement → self-check loop.
3. Stop after each phase within the command and verify before continuing.

**Gate**: command completes. ACCEPTANCE.md criteria must be passable.

---

## Phase 5: Test (Steps 5+6 of 9)

**Goal**: Prove the change works — automatic + explicit.

The `post-edit-test` hook fires asynchronously after every Edit/Write. If it logged failures, fix them before proceeding.

**Manual check**:
```bash
python3 scripts/evals/run-acceptance.py <slug>
```
Must exit GREEN (all machine criteria met) or AMBER (only prose criteria remain, confirm manually).

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
