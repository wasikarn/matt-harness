---
name: ship-classify
description: "Classify a change as bug fix, feature, or refactor and route to the right /ship sub-command."
---

# Ship — Classify Sub-Procedure

Shared by both entry paths of `/ship` (Path A calls this inside Phase 4 step 1; Path B calls this at Phase 0 before skipping ahead). Written once so classification logic can't drift between entry points — see `sync-seam-defect-class` in project memory for why that drift is a proven, recurring failure mode in this repo.

**Goal**: determine bug fix / new feature / refactor, and route to the tool built for each.

**Actions**:
1. Parse `$ARGUMENTS` — if the user already said "fix" or "bug", classify as bug; if "feature" or "add", classify as feature; if "refactor" or "clean up", classify as refactor.
2. **Analyze**: keywords in arguments (`fix`, `bug`, `feature`, `add`, `refactor`), scope (single file vs subsystem), presence of existing repro steps or error symptoms. **Recommend** the classification that best fits.
3. **AskUserQuestion** single-select: "Classify: keywords = [...], scope = [single file / subsystem / multi-subsystem], repro steps = [present / absent]. My recommendation: [classification]. Confirm?"
   - `Bug fix (Recommended when repro steps or error symptoms are present and the goal is to correct existing behavior)`
   - `New feature (Recommended when adding new behavior, UI, or capability that didn't exist before)`
   - `Refactor (Recommended when restructuring code without changing external behavior)`
4. **Scope check**: if the description spans multiple independent subsystems, STOP and propose decomposition — one `/ship` run per subsystem.
5. Route:
   - **Bug fix** → `/fix-bug $ARGUMENTS`. Wait for it to complete.
   - **New feature** → continue inline (the Implement steps in `commands/ship/COMMAND.md` Phase 4).
   - **Refactor** → `/refactor-clean`. Wait for it to complete.
6. Do NOT proceed past this classification until the routed command returns (bug/refactor) or the inline steps finish (feature).

**Precondition gate**: if implementation was abandoned or re-scoped mid-way, return to step 1.
