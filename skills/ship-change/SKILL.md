---
name: ship-change
description: "Orchestrate the full change lifecycle from classify → implement → review → address → merge. Use when starting non-trivial changes needing guided sequencing through /fix-bug, /feature-dev, kbg:review-pr, /address-review, and /ship-merge. Don't use for: one-line fixes, changes already mid-flight, or pure research/exploration."
disable-model-invocation: true
disable-model-invocation-reason: "orchestrates the full lifecycle ending in merge (external) — sequences self-gating mutations"
---

# Ship Change

Guide the user through the complete change lifecycle. This is a meta-orchestrator: it owns sequencing, preconditions, and stop conditions — not the implementation details of individual phases.

## Core Principles

- **One phase at a time.** Don't skip ahead. Each phase gates the next.
- **No silent handoffs.** After each phase, explicitly tell the user which command to run next and why.
- **Context carries forward.** The same session persists across phases; use conversation history, not intermediate files.
- **Bail out early.** If a phase reveals the change is out of scope, too large, or needs decomposition, STOP and re-scope before continuing.
- **Fork timeout fallback.** Some phases invoke `context: fork` skills that spawn agents. If the agent hangs or stalls for >2 minutes, cancel it and invoke the phase's underlying command directly (e.g., `/fix-bug` instead of waiting on Phase 2 via `kbg:ship-change`).

---

## Phase Overview

| Phase | Goal | Next |
|-------|------|------|
| 1 | Classify (bug / feature / refactor) | → 2 |
| 2 | Implement via `/fix-bug`, `/feature-dev`, or `maintenance-engineer` | → 3 |
| 3 | Self-review via `kbg:review-pr` (zero Critical findings gate) | → 4 |
| 4 | Address feedback via `/address-review` (all threads resolved gate) | → 3 or 5 |
| 5 | Merge via `/ship-merge` (CI green + approvals gate) | Done |

## Handoff Reference

| Phase | Command | When |
|---|---|---|
| 1 → 2 | `/fix-bug`, `/feature-dev`, or spawn `maintenance-engineer` agent | After classification |
| 2 → 3 | `kbg:review-pr` | After implementation done |
| 3 → 4 | Open PR; `/address-review` if comments arrive | After zero Critical findings |
| 4 → 3 | `kbg:review-pr` again | After `/address-review` fixes |
| 4 → 5 | `/ship-merge` | After all threads resolved + CI green |

See [reference.md](reference.md) for: full Phase 1–5 procedures, precondition gates, and failure modes to avoid.

## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
