# Pre-ship acceptance verification

This is the detailed reference for the deterministic acceptance gate that `/ship-task` runs in Phase 5. It was formerly the standalone `/pre-ship-verify` command.

## When this runs

`/ship-task` Phase 5 invokes this gate after Phase 4 (Implement) completes and the `post-edit-test` hook has run. The gate reports GREEN / AMBER / RED; RED stops the pipeline before Phase 6.

## Core principles

- **Acceptance is the contract.** If criteria fail, the task is not done.
- **Machine-checkable first.** Commands, test exits, file states are verified automatically. Prose criteria are surfaced for human judgment.
- **Never auto-ship.** This gate reports; it does not merge, push, or release.
- **One task at a time.** A single acceptance contract per `/ship-task` invocation.

## Phase 1 — Discover the contract

1. If the user provided a slug argument, use `.scratch/<slug>/ACCEPTANCE.md`.
2. Otherwise, auto-detect:
   - List `.scratch/*/` directories by mtime (newest first).
   - Pick the first directory containing `ACCEPTANCE.md`.
   - If multiple recent tasks exist, present the top 3 and ask the user to confirm.
3. If no `ACCEPTANCE.md` exists → STOP: "Run `kbg:accept-task` to lock a contract before shipping."
4. Read contract metadata (`task`, `accepted`, `start-sha`) and surface them.

## Phase 2 — Execute

Run:

```bash
python3 "${KBG_PLUGIN_ROOT}/scripts/evals/run-acceptance.py" <slug> --verbose
```

- Working directory: repo root.
- Timeout: default (30s per criterion).

Read `.scratch/<slug>/acceptance-results.json`. Parse:

- `passed`: criteria that exited 0.
- `failed`: criteria that exited non-zero.
- `skipped`: prose or manual criteria.
- `blocked`: safety-denied commands (e.g., `git push`).

## Phase 3 — Report + gate

Summarize:

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

**RED:** list each failed/blocked criterion with command and exit code. Recommend fixing before re-running Phase 5. Do NOT proceed to Phase 6.

**AMBER:** list skipped criteria and ask the user to confirm manual verification.

**GREEN:** state the contract is satisfied. Suggest next step:
- PR exists → proceed to Phase 6 (`kbg:review-pr`).
- No PR yet → create or push branch before Phase 6.

## Phase 4 — Audit trail

Append to `.scratch/<slug>/verification-log.jsonl`:

```json
{"timestamp":"2026-06-12T14:23:00Z","command":"/ship-task Phase 5","slug":"<slug>","passed":N,"failed":N,"skipped":N,"blocked":N,"result":"green|amber|red"}
```

## Anti-patterns

- Running without a contract.
- Ignoring blocked commands (they test guardrails).
- Auto-proceeding on AMBER without manual confirmation.
