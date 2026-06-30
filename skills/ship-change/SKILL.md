---
name: ship-change
description: "Orchestrate a scoped change — add, fix, change, refactor, or build-MVP — through classify → implement → review → address → merge. Use when a change is scoped and ready to sequence. Don't use for blank-slate discovery (use /ship-task) or one-line fixes. Thai: 'ship change', 'พร้อม merge', 'ขึ้น production'."
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
| 2 | Implement via `/fix-bug`, `/ship-task`, or `/refactor-clean` | → 3 |
| 3 | Self-review via `kbg:review-pr` (zero Critical findings gate) | → 4 |
| 4 | Address feedback via `/address-review` (all threads resolved gate) | → 3 or 5 |
| 5 | Merge via `/ship-merge` (CI green + approvals gate) | Done |

## Handoff Reference

| Phase | Command | When |
|---|---|---|
| 1 → 2 | `/fix-bug`, `/ship-task`, or `/refactor-clean` | After classification |
| 2 → 3 | `kbg:review-pr` | After implementation done |
| 3 → 4 | Open PR; `/address-review` if comments arrive | After zero Critical findings |
| 4 → 3 | `kbg:review-pr` again | After `/address-review` fixes |
| 4 → 5 | `/ship-merge` | After all threads resolved + CI green |

See `reference.md` for: full Phase 1–5 procedures, precondition gates, and failure modes to avoid.
