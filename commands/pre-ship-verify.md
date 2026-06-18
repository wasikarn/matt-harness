---
name: pre-ship-verify
description: "Run machine-checkable acceptance criteria for the current task before shipping. Use when a task has an ACCEPTANCE.md and you want deterministic verification before merge, release, or PR submission. Don't use for: tasks without an acceptance contract (no ground truth to verify), or when the user has already manually verified and explicitly says 'skip checks'."
argument-hint: "Optional slug (directory name under .scratch/) or auto-detect from latest .scratch entry"
disable-model-invocation: true
disable-model-invocation-reason: "operator-initiated ship checkpoint by preference — read-only (reports pass/fail, never merges/pushes/releases); user-only so verification is a deliberate pre-ship step"
---

# Pre-Ship Verify

Deterministic gate: run the acceptance contract and report pass/fail before any outward-facing action (merge, release, PR submit).

## Core Principles

- **Acceptance is the contract.** If criteria fail, the task is not done — regardless of how clean the code looks.
- **Machine-checkable first.** Commands, test exits, file states are verified automatically. Prose criteria are surfaced for human judgment, not silently skipped.
- **Never auto-ship.** This command reports; it does not merge, push, or release. The human (or `/ship-merge` gate) makes the final call.
- **One task at a time.** A single acceptance contract per invocation. Multiple tasks → run sequentially.

---

## Phase 1: Discover

**Goal**: Locate the acceptance contract for the task under verification.

**Actions**:
1. If user provided a slug argument (e.g., `phase-1-safety-fixes-2026-06-12`), use `.scratch/<slug>/ACCEPTANCE.md`.
2. If no slug provided, auto-detect:
   - List `.scratch/*/` directories by mtime (newest first).
   - Pick the first directory that contains `ACCEPTANCE.md`.
   - If multiple recent tasks exist, present the top 3 and ask user to confirm.
3. Verify the file exists. If absent → stop and tell user: "No ACCEPTANCE.md found. Run `kbg:accept-task` to lock a contract before shipping."
4. Read the contract metadata (`task`, `accepted`, `start-sha`) and surface them.

**Output**: confirmed slug, path to `ACCEPTANCE.md`, task name, acceptance date.

---

## Phase 2: Execute

**Goal**: Run `scripts/evals/run-acceptance.py` and capture structured results.

**Actions**:
1. Run:
   ```bash
   python3 "${KBG_PLUGIN_ROOT}/scripts/evals/run-acceptance.py" <slug> --verbose
   ```
   - Working directory: repo root.
   - Timeout: default (30s per criterion).
2. Read the generated `.scratch/<slug>/acceptance-results.json`.
3. Parse counts:
   - `passed`: criteria that exited 0.
   - `failed`: criteria that exited non-zero.
   - `skipped`: prose or manual criteria (not machine-checkable).
   - `blocked`: safety-denied commands (e.g., `git push`).

**Output**: raw results path, per-criterion status list (truncate to first 10 if >10 criteria, show "… and N more").

---

## Phase 3: Report + Gate

**Goal**: Present results and give a shipping recommendation.

**Actions**:
1. Summarize:
   ```markdown
   ## Pre-Ship Verification: <task-name>

   | Status | Count |
   |--------|-------|
   | ✅ Passed | N |
   | ❌ Failed | N |
   | ⏭️ Skipped (manual/prose) | N |
   | 🚫 Blocked (safety) | N |

   **Result**: [GREEN / AMBER / RED]
   - GREEN: all machine-checkable criteria passed (failed=0, blocked=0).
   - AMBER: some criteria skipped (manual only), no failures.
   - RED: any failed or blocked.
   ```
2. If **RED**:
   - List each failed/blocked criterion with its command and exit code.
   - Recommend: "Fix the failed criteria before shipping. After fixes, re-run `/pre-ship-verify`."
   - Do NOT proceed to merge/release.
3. If **AMBER**:
   - List skipped criteria and ask: "These criteria require manual verification. Confirm they are met before shipping?"
   - Options: `Verified manually — proceed` / `Re-run after manual checks` / `Stop and review`.
4. If **GREEN**:
   - State: "All machine-checkable criteria pass. The acceptance contract is satisfied."
   - Suggest next step per context:
     - If a PR exists → `/ship-merge`
     - If releasing → `/ship-release`
     - If just finished task → done; push if not already.

**Gate**: This command never auto-executes a ship. It only reports. The human (or a subsequent command's AskUserQuestion) decides.

---

## Phase 4: Audit Trail

**Goal**: Leave a machine-readable record of the verification run.

**Actions**:
1. Append a compact entry to `.scratch/<slug>/verification-log.jsonl`:
   ```json
   {"timestamp":"2026-06-12T14:23:00Z","command":"pre-ship-verify","slug":"<slug>","passed":N,"failed":N,"skipped":N,"blocked":N,"result":"green|amber|red"}
   ```
2. If the task's `ACCEPTANCE.md` was originally written by `kbg:accept-task`, update the task tracker (if any) with the verification result.

---

## Anti-Patterns

- **Running without a contract** — verifying nothing is worse than skipping verification, because it creates false confidence.
- **Ignoring blocked commands** — a blocked `git push` in acceptance criteria means the criterion is testing a guardrail. If it fails, the guardrail is broken.
- **Auto-proceeding on AMBER** — skipped manual criteria are still part of the contract. Confirm them explicitly.

## Integration Notes

- **Called from `/ship-merge` Phase 1** (optional): if the PR has an associated `ACCEPTANCE.md`, Phase 1 can suggest `/pre-ship-verify` before the merge gate.
- **Called from `kbg:review-pr` Phase 6**: the acceptance-contract check can invoke this command to replace prose cross-checking with deterministic execution.
- **CI integration**: `python3 "${KBG_PLUGIN_ROOT}/scripts/evals/run-acceptance.py" <slug> --gate` (non-zero exit on any failure) can run in GitHub Actions before merge.
- **Hook integration**: `verification-gate.sh` (advisory sensor) reads `acceptance-results.json` and logs; it does not block. Blocking is the user's decision via this command or `/ship-merge` gate.
