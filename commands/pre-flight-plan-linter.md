---
name: pre-flight-plan-linter
description: "Validate a /team-plan artifact before /team-build consumes it. Catches structural errors, missing validation commands, cyclic dependencies, overlapping file ownership, and F10 plan-approval risks. Use after /team-plan finishes and before /team-build starts. Don't use for: single-file work (no plan file needed), or plans you already started building (use /wave-status instead)."
argument-hint: "Path to plan markdown file"
disable-model-invocation: true
disable-model-invocation-reason: "workflow-step gate the user runs deliberately before /team-build"
---

# /pre-flight-plan-linter — Pre-flight plan validator

Run the plan linter on a `.claude/tasks/<slug>.md` file before `/team-build` consumes it. This is the machine gate that complements the lead's manual plan-approval filter (F10).

---

## Step 1 — Resolve plan file

1. Parse `$ARGUMENTS`:
   - Extract the first positional argument as `plan_file`
   - Detect `--strict` flag anywhere in `$ARGUMENTS`
   - Detect `--fix` flag anywhere in `$ARGUMENTS`
   - Detect `--json` flag anywhere in `$ARGUMENTS`
2. If no `plan_file` provided, default to `.claude/tasks/health-endpoint.md` (the canonical example from `/team-plan`).
3. Verify `plan_file` exists. If not, report the path and stop.

---

## Step 2 — Run linter

Invoke the linter script from the repo root:

```bash
python3 scripts/plan-linter.py <plan_file> [--strict] [--fix] [--json]
```

**Do not** run the linter from a subdirectory; `scripts/plan-linter.py` resolves relative to the repo root.

---

## Step 3 — Interpret results

### Exit 0 — Plan is flight-ready

Report:

> Plan is flight-ready ✅

Echo the linter's summary stats (sections, tasks, team members, acceptance criteria, validation commands). Proceed to `/team-build` when the user confirms.

### Exit 1 — Plan has structural errors

Report:

> Plan has errors ❌

List every error the linter emitted, one per line. For each error, provide a concrete fix suggestion:

- **Missing section** — add the `## Header` with placeholder content
- **Brain dump too short** — expand the brain dump to ≥ 50 characters of scope description
- **Q&A log < 10 entries** — return to `/team-plan` Step 2 and ask more clarifying questions
- **Team members outside 3-5** — merge or split roles; the F8 sweet spot is 3-5
- **Task ID or Description empty** — fill in the table cells; every task needs an ID and a description
- **Cyclic dependency** — break the loop by making one dependency indirect or introducing an intermediate task
- **Overlapping file ownership** — assign each file to exactly one task; cross-cutting edits belong to the orchestrator post-wave
- **Acceptance criteria < 3 or missing validation_command:** — add machine-checkable criteria and attach a runnable `validation_command:` to each
- **Validation commands < 3 or look like prose** — replace prose with runnable shell commands (e.g., `pytest tests/ -v`, not "Tests should pass")

**Gate:** do NOT proceed to `/team-build` until the user edits the plan and re-runs the linter.

### Exit 2 — Strict warnings (F10 risks)

Report:

> Plan is structurally valid but has F10 risks ⚠️

List each warning. Then ask the user:

- `Revise the plan` (recommended when F10 risks are real — e.g., no security-reviewer for auth work)
- `Proceed to /team-build anyway` (accept the risk; user overrides the F10 gate)

**Do not silently proceed.** The override must be explicit.

Common F10 warnings and what they mean:

- **Auth/secrets without security-reviewer** — a task touches passwords, tokens, hashing, or session logic, but no team member has a security role. Add a `security-reviewer` teammate or scope the auth work into a dedicated task.
- **Schema change without migration task** — a task mentions tables, columns, or schema changes, but there's no `.sql` migration file or explicit migration task. Add a `DB-N` migration task with a `.sql` file.
- **No integration validator for cross-component boundaries** — tasks depend on other tasks owned by different roles (e.g., `DB` → `API`), but there's no `INT-*` task. Add an integration validator task that blocks on all builders.
- **Overlapping directory ownership** — multiple tasks touch files in the same directory (≥ 3 files, different owners). Merge the tasks or split file ownership more granularly to avoid merge conflicts.

---

## Step 4 — Auto-fix mode (`--fix`)

If the user passed `--fix`:

1. Re-run the linter with `--fix`. The script will:
   - Append `validation_command: TBD_FIXME` to any acceptance criterion missing one
   - Insert missing table separator rows (`|---|---|`) in `## Team Members` or `## Step by Step Tasks`
   - Append placeholder sections for any missing required headers
2. Capture the fix summary from stdout.
3. Re-run the linter WITHOUT `--fix` to verify the fixes resolved the errors.
4. If errors remain, report the remaining issues and ask the user to fix them manually.
5. If only strict warnings remain, apply the Exit 2 flow from Step 3.

**Do not** treat `--fix` as a substitute for human review. It only handles trivial placeholders; criteria descriptions and command correctness still need author judgment.

---

## What this command does NOT do

- Does NOT execute the plan. That's `/team-build`.
- Does NOT revise the plan file itself (unless `--fix` is explicitly passed).
- Does NOT bypass the F10 gate. Warnings require explicit user override.
- Does NOT check the codebase. It validates the plan artifact's structure and contracts, not whether the implementation exists.

---

## Cross-references

- **F10 plan approval filter** — `commands/team-build.md` Step 5. The lead applies the same filter manually; this command is the machine pre-check.
- **Plan file structure** — `commands/team-plan.md` § Step 3. The linter enforces the table and list shapes defined there.
- **Linter script** — `scripts/plan-linter.py`. Contains the parsing logic, cycle detection, and F10 heuristics.
- **Validation chain** — `skills/orchestrate/SKILL.md` § Validation chain. Every acceptance criterion maps to a validation command; the linter checks that mapping exists.
