---
name: team-build
type: command
description: "Phase 2 of the agent-teams workflow: read .claude/tasks/<slug>.md, apply the plan approval filter (F10), spawn agents in waves using the F9 spawn-prompt template, then run post-build validation. Use after /team-plan completes, or when user says 'team build: <slug>', 'execute the plan'. Don't use for: features without a plan file (run /team-plan first), or single-agent work (use /feature-dev)."
argument-hint: "Path to plan file (e.g. .claude/tasks/health-endpoint.md)"
disable-model-invocation: true
---

# /team-build — Multi-agent feature execution

You are executing a plan produced by `/team-plan`. The plan file `.claude/tasks/<slug>.md` is the **session-resettable, lead-handoffable decoupling interface** (per D10): a fresh session, a different lead, or a partial resumption all work because the plan decouples state from session context. Read the plan first, then execute.

This is Step 4-7 of the article `agent-teams-workflow` 7-step pipeline. Steps 1-3 belong to `/team-plan`.

## Lead-coordinator contract (F8)

You are the lead. You are in **delegate mode + plan-mode** for the entire lifetime of this build. The four doctrine rules:

1. **You do not write code.** Teammates write code. You dispatch, validate, merge.
2. **Opus-lead + Sonnet-teammate cost split.** Teammate spawn prompts set `model: "sonnet"` (or the cheapest model that can do the task). You stay on Opus for synthesis + judgment.
3. **Plan-mode is fixed by the plan, not the session.** You do not drop plan-mode mid-build, even to answer a teammate's "faster-inline" question. Revise the plan, not the mode.
4. **3-5 teammates is the sweet spot.** If the plan is outside this range, refuse to build and ask the user to revise the plan at `/team-plan` time. "3-5" is **peak concurrent live teammates**, not total tasks/seats — a teammate takes multiple tasks, so a 7-seat feature (e.g. `7-agent-pattern`) is a ≤5-concurrent roster, not 7; don't refuse it for its seat count.

The full doctrine is in `skills/orchestrate/SKILL.md` § Lead-coordinator doctrine.

---

## Step 4 — Fresh context (soft-warn gate)

**Goal:** verify the lead is in a fresh session, or get explicit user consent to continue in the current session.

**Why:** the article recommends "Start a new Claude Code session with just the plan." Mid-session builds inherit the planning context, which can saturate the lead's budget by the time Wave 3+ dispatches.

**Actions:**
1. Detect: is this the first `/team-build` invocation in this session, or has the lead already been executing other work in the same session? (Heuristic: check the session transcript for `/team-plan` for the same `<slug>` earlier in the session, or any other write-capable dispatch.)
2. **If fresh context confirmed** (no `/team-plan` earlier this session, or `/team-plan` ran in a different session): proceed to Step 5.
3. **If mid-session detected**: surface `AskUserQuestion`:
   - `Start a fresh session and /exit first (Recommended)` — context cost: lead's full budget preserved for execution
   - `Continue in the current session` — accept the context cost; you explicitly waive the fresh-session recommendation
4. **If `AskUserQuestion` is denied** (headless `-p` mode, `dontAsk`, or other runtime refusal): **refuse to dispatch.** Log the refusal: "TASK-BUILD-GATE: /team-build refused — fresh-session gate denied in non-interactive mode. User must restart in a fresh session or override the gate explicitly." Stop. Do NOT silently fall through.

**This is a soft-warn gate, not a hard block.** The user CAN override; the override must be explicit, not a silent default.

---

## Step 5 — Read the plan + apply plan approval filter (F10)

**Goal:** read the plan file, verify it's complete, and apply the pre-execution gate.

**Actions:**
1. Read `.claude/tasks/<slug>.md` (the argument is the path; default to `.claude/tasks/health-endpoint.md` if no argument).
2. **Verify completeness:**
   - `## Brain dump` filled?
   - `## Q&A log` has ≥ 10 answered questions? (Hard requirement; refuse if < 10.)
   - `## Team Members` has 3-5 members? (Peak concurrent roster, not total tasks/seats. Refuse if outside the F8 sweet spot — but tell the user, don't silently revise.)
   - `## Step by Step Tasks` table complete with `Depends On` + `Files` + `Criteria` + `Constraints`?
   - `## Acceptance Criteria` machine-checkable?
   - `## Validation Commands` present and runnable?
3. **Apply plan approval filter (F10):** reject plans that violate pre-execution criteria from the initial prompt. The lead has the user's initial intent; the plan is the lead's first guess at implementation. Bad plans waste waves. **Common rejection reasons:**
   - Plan modifies schema without migration (data loss risk)
   - Plan touches auth/secrets without explicit security-reviewer chain
   - Plan assumes external service availability without a fallback path
   - Plan has overlapping file ownership between teammates (merge conflict guaranteed)
   - Plan has no integration validator (D8) for cross-component boundaries
4. **If rejected:** explain why, list the specific issues, refuse to build. The user can revise the plan (edit `.claude/tasks/<slug>.md`) and re-invoke `/team-build`.
5. **If approved:** derive the wave structure (tasks with `Depends On == "-"` are Wave 1; tasks whose `Depends On` are all in the same wave become Wave 2; etc.). List the waves in order.

**Optional `--spec` shortcut (P2.4):** the plan file's `## Step by Step Tasks` table is hand-written today, but a future spec-file shape is wired through `scripts/orchestrate-dispatch.py` (P2.4 / SYNTHESIS #49). If the user passes `--spec path/to/ship-merge.yml` as the first argument, `/team-build` can ask the dispatcher to render the wave plan JSON via `--emit-plan` and use it as the starting point for wave execution. v1 of `/team-build` still expects the hand-written plan file; the `--spec` flag is a future enhancement. The dispatcher does NOT auto-spawn agents — it renders the plan, the lead dispatches.

**This is distinct from F7's post-execution gate (in `hooks/task-lifecycle.sh`).** F10 catches bad plans BEFORE work; F7 catches bad completions AFTER work. Two different layers of the same quality pipeline.

---

## Step 6 — Wave execution

**Goal:** spawn teammates in waves, inject upstream contracts from previous waves, gate each task with `addBlockedBy`.

**⚠️ F8.5 — Clamp fan-out to 5 before spawning (advisory floor 3 — F8.4).** This is the enforcement point for the [[bounded-agent-spawning]] contract. A wave with >5 tasks MUST be split: spawn 5, queue the rest in `deferred-<date>.md`, dispatch the next wave after the first finishes. A wave with <3 agents is under-parallelized — fold it back or run inline (advisory, not a block). The clamp is on TOTAL spawned agents across the plan lifetime (worklist + audit + verify), not on the work-list size — see `skills/orchestrate/SKILL.md` § Bounded fan-out (F8.5).

**For each wave, in order:**

1. **Build the spawn prompt for each task in the wave using the F9 template** (in `skills/orchestrate/SKILL.md` § Spawn-prompt template):
   - `What` — from the task's `Description` column
   - `Where` — from the task's `Files` column
   - `Focus` — the implicit dimension (correctness / minimal-blast / API-stability / etc.) — make it explicit
   - `Deliverable` — from the task's `Criteria` column (a thing a reviewer can grep for)
   - `FILES YOU OWN` — the task's `Files` column, absolute paths
   - `UPSTREAM CONTRACTS` — for Wave 2+: each `Depends On` task that completed, with the file:line or schema field the downstream may rely on
   - `Files + Criteria + Constraints` — the table from the plan, expanded
   - `Done-when` — the validation commands that prove this task's acceptance criteria pass
2. **Spawn the teammate** with `Task` tool:
   - `subagent_type: <plan's "Assigned To" column>`
   - `model: "sonnet"` (per F8 cost split; override only if the task is Opus-shaped — security audit, cross-system synthesis)
   - `prompt: <the F9 template, fully filled>`
3. **Wait for the wave to complete.** The runtime enforces `addBlockedBy` chains; you don't need to poll.
4. **Verify the wave's outputs** against their acceptance criteria BEFORE starting the next wave:
   - For each task in the wave, run the corresponding `validation_command` from the plan
   - If a task fails, the wave is incomplete — fix or re-dispatch (do NOT start the next wave)
   - If a task succeeds, capture its output (file:line, commit sha, contract field) for the next wave's `UPSTREAM CONTRACTS` injection
5. **Integration validator (D8) at end-of-build:** the plan's `INT-N` task is a single `TaskUpdate addBlockedBy=[all-builders]`. It runs after ALL builders complete. It traces cross-component correctness (e.g. "does the API endpoint's response shape match what the frontend consumer expects"). Do not skip this — it's the seam check.

**Anti-patterns:**

- **Spawn all waves in parallel.** The whole point of waves is sequencing. Parallelizing all waves ignores upstream contracts.
- **Skip the per-wave verification.** Starting Wave 2 with a broken Wave 1 wastes the Wave 2 budget on a doomed task.
- **Inject an empty `UPSTREAM CONTRACTS` for Wave 2+.** That's the failure mode F9 was designed to prevent.
- **Override the F8 model split (Sonnet teammates) without explicit reason.** Opus-everywhere is the cost cliff the article warns about.

---

## Step 7 — Post-build validation

**Goal:** run all `## Validation Commands` from the plan, report pass/fail per acceptance criterion with evidence.

**Actions:**
1. **Run every command** in the plan's `## Validation Commands` section.
2. **For each acceptance criterion** in `## Acceptance Criteria`:
   - Pass: at least one validation command passes that exercises the criterion
   - Fail: no validation command passes, OR the command passes but the criterion isn't actually exercised (e.g. the command is `bash -n` but the criterion is "the API returns X")
3. **Report** to the user:
   - Wave-by-wave summary (which tasks passed, which failed, in which wave)
   - Per-criterion verdict with the exact command + output that proved it
   - The integration validator's verdict
   - Any leftover risks (e.g. "Wave 2 succeeded but the plan didn't include a regression test for the migration rollback path")
4. **Do NOT mark the build complete** if any criterion fails. The user decides whether to revise the plan, re-dispatch a failed wave, or accept the partial state with explicit acknowledgement.

**Logging:** each spawn, contract, and validation result is journaled via the existing `task-lifecycle.sh` pattern (TeammateIdle / TaskCreated / TaskCompleted hooks, see REPORT.md § 1.5 + § 2.10). F7's TaskCompleted test-claim gate (in `hooks/task-lifecycle.sh`) is the runtime enforcement: a teammate claiming "tests pass" without a `validation_command:` field in the event payload will be blocked from completing. This is the F7 half of the quality pipeline.

---

## Step 7 done-when (final)

The build is complete when:

- [ ] All `## Step by Step Tasks` rows are `status=completed` in the TaskList
- [ ] All `## Acceptance Criteria` items pass
- [ ] All `## Validation Commands` exit 0
- [ ] The integration validator (D8) passes
- [ ] The plan file's done-when checklist is checked
- [ ] The build is reported to the user with per-criterion evidence

---

## What this command does NOT do

- Does NOT plan. The plan exists at `.claude/tasks/<slug>.md`; if it's missing or incomplete, run `/team-plan` first.
- Does NOT silently fix a bad plan. The plan approval filter (F10) rejects; the user revises.
- Does NOT skip the F8 model split. Sonnet-teammate is the cost lever.
- Does NOT skip the F7 task-completion gate. A teammate claiming "tests pass" without a runnable `validation_command:` is blocked by the hook, not the lead.

---

## Cross-references

- **F9 spawn-prompt template** — `skills/orchestrate/SKILL.md` § Spawn-prompt template. The template is the rendering format; the plan file is the data source.
- **F8 lead doctrine** — `skills/orchestrate/SKILL.md` § Lead-coordinator doctrine. Four rules: delegate, model split, plan-mode, 3-5 sweet spot.
- **F10 plan approval filter** — this command's Step 5. Pre-execution gate, complements F7.
- **F7 TaskCompleted gate** — `hooks/task-lifecycle.sh`. Post-execution gate, complements F10. Uses exit 2 + stderr (NOT exit 0 + JSON like PreToolUse).
- **D8 integration validator** — this command's Step 6 final sub-step. Single `TaskUpdate addBlockedBy=[all]` after all builders.
- **D10 plan-file interface** — `.claude/tasks/<slug>.md` is the session-resettable, lead-handoffable interface. This command reads from it; a fresh session can resume from it.
- **Validation chain** — `skills/orchestrate/SKILL.md` § Validation chain. The DAG `B → V1 → F → V2` is the per-task quality pattern; this command's wave structure is the multi-task quality pattern.
- **METHODOLOGY:** Rule 1 (think before coding) — the plan approval filter is the runtime form of this rule. Rule 4 (goal-driven) — every validation command is observable. Rule 12 (fail loud) — bad plan rejected with reasons, not silently revised. Rule 13 (orchestrate) — this whole command IS the orchestration pattern.
