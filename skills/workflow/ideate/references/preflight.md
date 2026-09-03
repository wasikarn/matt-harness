# Pre-flight gate — Steps 0-2 (moved verbatim from `SKILL.md`)

Read before running the three self-judge questions in `SKILL.md`: Step 0 (budget/convergence
warning blocks), Step 1 (explicit invocation skips the self-judge entirely), Step 2 (when the
self-judge applies).

**Step 0. Cost + convergence warning check.**

If an `<ideate-budget status="warning">` or `<ideate-convergence status="warning">` block is
present in context, don't auto-fire from Step 2 — answer directly; on an explicit `mh:ideate`
(Step 1) still proceed, but surface the warning in the brief. No hook produces either block
today, so this step is usually a no-op.

**Step 1. Explicit invocation check.**

If the user typed `mh:ideate` or asked for "ideate mode"/"use the ideate skill"/"run ideate on
this"/"brainstorm", **skip the rest of this section and go straight to Phase 1** — they opted
in, don't second-guess.

**Step 2. Self-judge (only if Step 1 did not match).**
