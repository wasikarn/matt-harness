---
name: accept-task
description: "Lock a machine-checkable acceptance contract before any non-trivial task. Use when starting multi-file changes, schema migrations, or before dispatching write-capable agents; write `.scratch/<slug>/ACCEPTANCE.md` with criteria + start SHA. Use when user says 'lock acceptance', 'define acceptance criteria', or 'what does done look like'. Also fires on Thai contract requests like 'เขียน acceptance', 'เกณฑ์สำเร็จ', 'done คืออะไร'. Don't use for trivial single-file edits, read-only analysis, or existing contracts."
---

# Accept Task

Agents optimize for what looks done. Without a contract written **before** execution, "acceptance" becomes a post-hoc rationalization of whatever the agent produced — you read the diff and decide it's fine, which is hope, not verification. This skill locks the success criteria at task start, when you still have the clearest view of what "done" means, so a later review checks the work against a fixed target instead of against the work itself.

This is the **Acceptance** stage of the operation flow (`Task → Ritual → Acceptance → Execute → Verify → Evidence → Session → Retro`). It pairs with kbg:review-pr: accept-task writes the contract, `kbg:review-pr` Phase 6 verifies the work met it. The invariant: **every non-trivial task has acceptance, authored before execution.**

## When to use

Lock a contract when the task is non-trivial:
- multi-file change, schema/migration, or anything > ~30 min
- before dispatching write-capable agents (they execute against the contract)
- when scope is open-ended enough that "done" is debatable

Skip it (Rule 2 — no ceremony) for: trivial single-file edits, read-only analysis/research, or a task that already has a signed `ACCEPTANCE.md`.

## Contract format

Write `.scratch/<slug>/ACCEPTANCE.md`. `<slug>` is the feature/fix kebab-case name (same dir as `issue.md` if one exists — see `docs/agents/issue-tracker.md`).

```markdown
# Acceptance: <slug>
<!-- accept-task contract — LOCKED at task start. Do not edit criteria mid-task;
     if scope genuinely changes, note it under "Scope changes" with a reason. -->
- task: <slug>
- accepted: <ISO-8601 UTC>
- start-sha: <git rev-parse HEAD>
- executor: <agent name(s) / "claude inline" / "human">

## Criteria
- [ ] <machine-checkable criterion — a test, a command exit, a file:line state>
- [ ] <criterion 2>

## Out of scope
- <explicit non-goal — what this task will NOT touch>

## Scope changes
<!-- append-only: if a criterion must change after lock, log "<date> — <what> — <why>" -->
```

`.scratch/` is gitignored — this is a **working-tree contract** for the current task, not a permanent audit record. (Permanent rationale belongs in memory; cryptographic presence/absence proof belongs in kbg:assert-presence / kbg:decommission.)

## Workflow

1. **Determine the slug** — reuse the `.scratch/<slug>/` dir if `issue.md` exists; otherwise pick a kebab-case name and `mkdir -p .scratch/<slug>`.
2. **Source the criteria** — if `issue.md` has an `## Acceptance Criteria` section, pull from it. Otherwise draft 2–5 criteria with the user.
3. **Make each criterion machine-checkable** — rewrite vague criteria into falsifiable ones. "Works correctly" → "`npm test` exits 0 and `tests/auth.spec.ts` covers the null-token path". If a criterion can't be made checkable, mark it `(manual)` and say how it's judged.
4. **Capture the start point** — `git rev-parse HEAD` for `start-sha`, current UTC for `accepted`.
5. **Write `ACCEPTANCE.md` and `PROGRESS.md`** — fill the template. Name the executor (which agent[s] will do the work). Also create the mutable progress tracker:
   ```bash
   cat > ".scratch/<slug>/PROGRESS.md" <<'PROGRESS_EOF'
   # Progress: <slug>
   <!-- Mutable state file — update after each significant step. Read on session resume. -->
   - task: <slug>
   - accepted: <ISO-8601 UTC>

   ## Status
   <!-- in_progress | blocked | complete -->
   in_progress

   ## What was tried
   <!-- append-only log: "<date> — <what> — <outcome>" -->

   ## What passed
   <!-- criteria confirmed green (with evidence command) -->

   ## What's still open
   <!-- criteria not yet verified + open questions -->
   PROGRESS_EOF
   ```
   Downstream: on session resume, read `PROGRESS.md` before touching code (METHODOLOGY Rule 1 boot sequence).

   Then write the consequence report:
   ```bash
   mkdir -p "${ACCEPT_TASK_STATE_DIR:-$HOME/.claude/state}"
   printf '{"slug":"%s","path":"%s","criteria_count":%s,"ts":"%s"}\n' \
     "<slug>" ".scratch/<slug>/ACCEPTANCE.md" "<N>" \
     "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     > "${ACCEPT_TASK_STATE_DIR:-$HOME/.claude/state}/accept-last.json"
   ```
   Downstream: `ship-task` Phase 3 reads `accept-last.json` to machine-check that a contract was locked before execution starts.
6. **Proceed to execution** — the contract is now the target. At review time, `kbg:review-pr` Phase 6 reads it and flags findings that leave a locked criterion unmet as `[acceptance-gap]` (rework), distinct from beyond-contract improvements.

## Anti-patterns

- **Criteria that can't fail** — "code is clean", "handles errors well". A criterion that no realistic diff could violate is theater. Anchor to a test, a command, or a concrete file:line state.
- **Writing it after the work** — the whole point is *before*. A contract authored post-hoc just describes what happened. Sign at task start.
- **Editing criteria to match the result** — if the work fell short, that's an acceptance-gap, not a reason to soften the contract. Real scope changes go in the append-only `## Scope changes` log with a reason.
- **Locking trivia** — don't write a contract for a typo fix or a read-only investigation. Reserve it for tasks where "done" is genuinely debatable.
