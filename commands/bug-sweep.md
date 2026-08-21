---
name: bug-sweep
description: "Sweep: N parallel agents (default 5) each hunt one small bug, report-only. Don't use for PR review (/review-pr) or session audit (/deep-audit)."
argument-hint: "[path] [count]"
model: inherit
effort: high
---

# Bug Sweep

Spawn parallel agents to hunt for small, concrete bugs across the codebase — report only, never auto-fix.

## Usage

`/bug-sweep [path] [count]`

- `path` (optional): scope the sweep to one directory or file. Defaults to the whole repo (respecting `.gitignore`).
- `count` (optional): number of parallel agents. Defaults to **5**.

## Procedure

1. **Partition the scope.** Split the target path into up to `count` distinct areas — separate top-level directories, or separate review lenses (correctness, security, silent-failure/error-handling, type-safety) if the target is too small to split by directory. Never let two agents cover the same files — that wastes a dispatch on a duplicate finding.
2. **Dispatch in one message.** Launch all agents as parallel Agent tool calls in a single response, not sequential. Reuse an existing specialized reviewer agent (e.g. `kbg:code-reviewer`, `kbg:security-reviewer`, `kbg:silent-failure-hunter`, or a language-specific reviewer) when its lens fits the assigned area; fall back to `general-purpose` otherwise.
3. **Constrain each agent's brief**, verbatim in the prompt:
   - Find **exactly one** small, concrete, verifiable bug in `<assigned area>` — not a style nit, not a hypothetical, not a "could be improved."
   - Report `file:line`, the concrete failure scenario (input/state → wrong output), and a minimal fix.
   - **If no real bug is found, say so explicitly.** Do not invent a finding just to have something to report.
4. **Consolidate.** Collect all reports. Drop empty ("none found") results — that's a true negative, not a merge decision. Directory-split agents can't overlap (Step 1 already guarantees disjoint files), but a lens split shares files across agents by design — when two lens agents describe the same underlying bug there, don't silently drop one: note the overlap explicitly ("N agents independently found this") — agreement across lenses is a confidence signal, not noise to blend away (same discipline as `review-pr` Phase 5: overlap is signal, dedupe would erase it). Don't inflate a minor nit into something bigger than the dispatched agent actually reported.
5. **Report, don't fix.** Present the surviving findings as a numbered list. If zero findings survive, say the sweep came up clean — that's a valid result, not a failure to report harder.

## Output Contract

```
N found (of <count> agents dispatched)
1. file:line — symptom — suggested fix
2. ...
```

If zero: `Sweep clean — no small bug found by any of the <count> agents.`

Suggested next step: to fix one directly, verify it yourself first — reproduce the failure,
don't just trust the dispatched agent's report — then apply the smallest change that addresses
it, then re-run whatever surfaced the bug to confirm it's actually gone. Route anything bigger
than a one-line fix through `/fix-bug` instead.

## Arguments

$ARGUMENTS:
- optional target path (defaults to repo root)
- optional agent count (defaults to 5)
