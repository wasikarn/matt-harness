---
name: progressive-refine
description: "Sequential refinement chain: each pass adds a new quality lens (draft → constrain → optimize → polish). Use when an artifact needs staged improvement where pass N consumes pass N-1's output, or the user asks to harden/refine something in passes, including 'ปรับแต่งทีละขั้น', 'refine', 'harden'. Don't use for: parallel independent domains (use kbg:orchestrate), or one-shot edits."
---

# Progressive Refine

> **Subagent self-check:** If you were dispatched as a sub-agent for a specific refinement pass, **do not re-orchestrate.** Return your scoped output (a `done-when` artifact, a `Report:` block, or your done-criterion evidence) to the parent. The parent owns the prioritization + dispatch loop; you own one well-bounded deliverable. This preamble mirrors obra/superpowers' `<SUBAGENT-STOP>` convention.

Progressive refinement is not "do it again" — it is "do it with increasing constraint." Each pass adds a new quality lens to the artifact. The pattern distributes those passes across specialized agents so no single agent tries to handle all concerns at once.

This skill is the sequential-chain counterpart to `orchestrate`'s parallel fan-out. Where `orchestrate` dispatches independent domains side-by-side, `progressive-refine` chains dependent passes where Pass N consumes the output of Pass N-1.

> **Full F9 spawn prompts** for every pass below live in `references/spawn-prompts.md` (kept out of this file to stay under the SKILL.md size budget). Each pass here gives the role, done-when, and gating; copy the matching fence from the reference when you actually spawn the agent.

---

## Core concept — five lenses

From article `agent-patterns`: each pass focuses on a different quality dimension. The draft agent prioritizes completeness. The next agent adds constraints. The next optimizes. The last polishes.

| Pass | Lens | Question | Typical agent |
|------|------|----------|-------------|
| 1 | **Coverage** | Does it handle all cases? | builder / drafter |
| 2 | **Correctness** | Are the edge cases right? | reviewer / editor |
| 3 | **Clarity** | Can a junior read this? | simplifier / reviewer |
| 4 | **Performance** | Does it meet latency/budget constraints? | perf engineer / validator |
| 5 | **Polish** | Docs, error messages, naming | polisher / technical-writer |

Not every artifact needs all five. The 3-pass code pattern (below) is the most common shape. The 5-pass doc pattern is used for public-facing prose.

**When to use progressive refinement vs single-pass**

Use progressive refinement when:
- The artifact is public-facing (docs, SDK, API contract)
- The artifact has >3 stakeholders
- The artifact has >5 edge cases or failure modes
- The cost of a defect is high (payments, auth, data integrity)

Use single-pass when:
- Internal tool or prototype
- The user said "quick" or "quick and dirty"
- The change is <30 lines and <2 edge cases
- Speed matters more than polish (spike, experiment, RFC draft)

**Never use >3 passes for the same file** — diminishing returns after Pass 3 for most code. Docs and specs can sustain 5 passes because prose defects are cheaper to catch in Pass 2-5 than in production. Code usually tops out at 3; add Pass 4 (performance) and Pass 5 (security/polish) only when the file is load-bearing or customer-facing.

---

## The 3-pass code pattern (most common)

The default pipeline for production code. It maps directly to the validation chain in `skills/orchestrate/SKILL.md` § Validation chain (the inline builder→validator→fix→revalidator sequence a dispatch flow runs per task) — but applied proactively as a planned pipeline rather than reactively after a single builder claims done.

Full F9 prompts: `references/spawn-prompts.md` § [3-pass code pattern](references/spawn-prompts.md#3-pass-code-pattern).

### Pass 1 — Builder (`backend-engineer`)

Write the rough implementation. Scope is "make it work." Do not optimize, do not polish. The builder's job is coverage: all acceptance criteria must be exercisable.

**Done-when:** All acceptance criteria pass via `pytest` (or the project's test runner). The code may be verbose, may have TODOs, may lack docstrings — but every path is reachable by a test.

Spawn **gated** — builder holds Edit/Write/Bash.

### Pass 2 — Simplifier (`code-simplifier`)

Refine the builder's output for clarity and brevity. Scope is "make it readable." The simplifier may extract helpers, reduce nesting, rename variables, inline trivial abstractions — but must not change behavior.

**Done-when:** Cyclomatic complexity <10 per function, no functions >50 lines, and all tests from Pass 1 still pass.

Spawn **gated** — simplifier holds Edit/Write/Bash.

### Pass 3 — Validator (`code-reviewer` + `test-engineer`)

Verify correctness and coverage. The validator starts with fresh eyes — it does not share the builder's assumptions or blind spots. This is the adversarial verification step.

`code-reviewer` checks the code for edge-case gaps, invariant violations, and style. `test-engineer` checks coverage and writes missing tests.

**Done-when:** All tests pass, coverage >80%, no critical findings (P0/P1).

- `code-reviewer` — spawn **ungated** (read-only). Returns a verdict report with file:line findings + coverage gaps.
- `test-engineer` — spawn **gated** (holds Edit/Write). Reproduces each coverage gap from the reviewer as a test case.

---

## The 5-pass doc pattern

Used for public-facing documentation, runbooks, ADRs, and API specs where accuracy + accessibility + cross-link integrity matter.

Full F9 prompts: `references/spawn-prompts.md` § [5-pass doc pattern](references/spawn-prompts.md#5-pass-doc-pattern).

| Pass | Role (`agent`) | Done-when | Spawn |
|------|----------------|-----------|-------|
| 1 — Drafter (`technical-writer`) | Brain dump structure; every section on the page with bullets | Every planned section has >=3 bullet points; structure complete, prose rough | gated |
| 2 — Editor (`comment-analyzer`) | Fix accuracy and tone; remove TODOs; cite every claim | No TODO markers remain; all claims cited or tagged `[opinion]` | gated |
| 3 — Reviewer (`code-reviewer` for prose) | Check completeness from a fresh-reader perspective | A new engineer can follow the doc without asking questions | ungated |
| 4 — Validator (`ux-reviewer`) | Check accessibility and inclusivity | No gendered examples, all images have alt text, reading level appropriate | ungated |
| 5 — Polisher (`technical-writer`) | Final formatting, cross-links, lint | All internal links resolve, Markdown lint-clean, publication-ready | gated |

---

## Task board integration

Progressive refinement is a sequential chain. Each pass is a task in the board with `depends_on` the previous pass. The board makes the ordering observable and resumable across sessions.

Source `${CLAUDE_SKILL_DIR}/scripts/task-board-lib.sh` (a per-skill wrapper that resolves the plugin-wide library) for all state transitions, per `skills/orchestrate/SKILL.md` § Task board integration.

### Chain structure

```
Pass 1 (builder)     →  Pass 2 (simplifier)  →  Pass 3a (code-reviewer)
   T1                       T2                       T3a
   depends_on: []           depends_on: [T1]         depends_on: [T2]
                                                      ↓
                                               Pass 3b (test-engineer)
                                                  T3b
                                                  depends_on: [T3a]
```

### Rejection handling

If any pass rejects (verdict != `pass`), the pipeline stops and the lead spawns a **fix task** that depends on the rejecting pass:

1. **Pass N rejects:** create fix task `T<N>-fix-1` with `depends_on = [T<N>]` and `status = "pending"`. Run `kbg_recompute_blocked` so it is unblocked once the rejecting pass is marked complete.
2. **Reset downstream:** set `status = "pending"` for all tasks that depend on T<N> (they were previously blocked; now they stay blocked until the fix task completes).
3. **Fixer completes:** mark `T<N>-fix-1` `completed`. Recompute blocked. The next pass unblocks and resumes.
4. **Re-validate after fix:** if the fixer edited source files, spawn a re-validator (same role as the original rejecting pass) with `depends_on = [T<N>-fix-1]` before allowing downstream to proceed.

**Shell pattern for rejection recovery:**

```bash
# T2 (simplifier) returned reject
updated=$(kbg_board_read "$PLAN_DIR" | jq '
  .tasks["T2-fix-1"] = {
    id: "T2-fix-1",
    status: "pending",
    depends_on: ["T2"],
    assigned_role: "backend-engineer",
    files: .tasks["T2"].files
  } |
  .tasks["T3a"].status = "pending"
')
kbg_board_write "$PLAN_DIR" "$updated"
kbg_recompute_blocked "$PLAN_DIR"
```

### Gating rules

| Pass role | Gated? | Why |
|-----------|--------|-----|
| Builder / Drafter (Pass 1) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Simplifier / Editor (Pass 2) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Reviewer / Validator (Pass 3+) | **No** | Read-only; no AskUserQuestion |
| Fixer (rejection recovery) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |
| Polisher (Pass 5) | **Yes** — AskUserQuestion | Holds Edit/Write/Bash |

---

## Worked example

A full `GET /health` pipeline — builder → simplifier → reviewer (rejects: missing 503 + timeout) → fix → test-engineer → optional security review — with every F9 fence is in `references/spawn-prompts.md` § [Worked example: GET /health](references/spawn-prompts.md#worked-example-get-health). The optional Pass 4 security review is gated by blast radius: run it for public-facing/customer-visible endpoints, skip for internal ops endpoints.

---

## Cross-references

- **Full F9 spawn prompts (all passes + worked example)** — `references/spawn-prompts.md`. Copy the matching fence when spawning each pass.
- **Validation chain `B → V1 → F → V2`** — `skills/orchestrate/SKILL.md` § Validation chain. The 3-pass code pattern is the proactive pipeline version of the same chain.
- **F9 spawn-prompt template** — `skills/orchestrate/SKILL.md` § Spawn-prompt template. Every pass uses this template verbatim.
- **Task board integration (`depends_on`, `recompute_blocked`)** — `skills/orchestrate/SKILL.md` § Task board integration.
- **Per-task validation chain** — `skills/orchestrate/SKILL.md` § Validation chain (TaskCreate + addBlockedBy). Run the builder→validator→fix→revalidator chain reactively on a single already-completed task by dispatching that sequence inline via `kbg:orchestrate`. Use `progressive-refine` when you want to plan the multi-pass pipeline upfront.
- **`code-simplifier`** — `agents/code-simplifier.md`. The Pass 2 agent for the 3-pass code pattern. If the agent file does not yet exist in the fleet, dispatch a simplification pass using the spawn prompt above with `backend-engineer` scoped to "refactor for clarity only."
- **`recursive-improve`** — `skills/recursive-improve/SKILL.md`. Use `recursive-improve` when the harness itself needs improvement; use `progressive-refine` when a single artifact needs quality passes. The former is human-gated by design; the latter can be scripted once the plan is approved.
- **`backend-dev`** — `skills/backend-dev/SKILL.md`. The builder agent's own workflow (tests first, minimal implementation, architecture concerns). Pass 1 of the 3-pass pattern delegates to this skill.
