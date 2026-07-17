---
description: Implement a scoped feature or change — detects the stack, loads the matching kbg:*-patterns skill, writes the smallest-scope highest-rigor diff, adversarially self-reviews. Delegates to the code-implementer agent.
name: implement
agent: code-implementer
subtask: true
---

# Implement

Implement a specific, scoped change end to end. Delegates to the `code-implementer` agent, which owns the detect-stack → load-matching-skill → explore → implement → verify → adversarial-self-review procedure.

## Usage

`/implement <task description>`

- `<task description>` (required): what to build or change. Be as specific as the task allows — expected files/area, acceptance criteria, constraints. A vague description ("improve the API") produces a vague diff; a scoped one ("add a rate-limit middleware to the Hono app in src/middleware, 100 req/15min per IP") produces a reviewable one.

## Output Contract

The agent returns:

1. Changes made, with `file:line` references.
2. Skill loaded (or "none — no stack match").
3. Verification: build/test command run + fresh output.
4. Adversarial self-review: what it tried to break, what it fixed, residual concerns named honestly.
5. Status: `DONE` (provisional) | `DONE_WITH_CONCERNS` | `BLOCKED` | `NEEDS_CONTEXT`.
6. Suggested next step: `DONE`/`DONE_WITH_CONCERNS` → `kbg:review-pr` (or dispatch `code-reviewer`/the matching language reviewer directly) — this agent's DONE is provisional, the reviewer + gauntlet render the authoritative verdict, never the implementer itself. `BLOCKED`/`NEEDS_CONTEXT` → resolve the named gap (missing decision, missing context, repeated failure), then re-dispatch.

## Arguments

$ARGUMENTS:
- required task description
