# Ship — Classify Sub-Procedure

Shared by both entry paths of `/ship` (Path A calls this inside Phase 4 step 1; Path B calls this at Phase 0 before skipping ahead). Written once so classification logic can't drift between entry points — see `sync-seam-defect-class` in project memory for why that drift is a proven, recurring failure mode in this repo.

**Goal**: determine bug fix / new feature / refactor, and route to the tool built for each.

**Actions**:
1. Parse `$ARGUMENTS` — if the user already said "fix" or "bug", classify as bug; if "feature" or "add", classify as feature; if "refactor" or "clean up", classify as refactor.
2. **Analyze**: keywords in arguments, scope (single file vs subsystem), presence of repro steps or error symptoms. **Recommend** the classification that best fits, naming why the other two don't. If keywords conflict or none match, say the classification is uncertain rather than asserting a confident pick from weak evidence.
3. **Self-consistency**: skip the ask below when step 1's keyword match is unambiguous (no competing signal), step 2's evidence doesn't contradict it, **and the classification is Bug fix or New feature** — state the classification, proceed to step 5. Those two routes still confirm before any code changes: `/fix-bug`'s own Phase 3/4 gates and the feature path's Phase 4 approval gate (`ship/COMMAND.md`). **Refactor never skips this ask** — `/refactor-clean` (`agents/refactor-cleaner.md` §3) has no pre-edit confirmation gate of its own; it stages changes without committing, so the user's only touchpoint is reviewing the diff after it's already written to the working tree. This ask is the sole pre-mutation confirmation on that route. Also ask whenever keywords are absent, conflicting, or contradicted.
4. **AskUserQuestion** single-select (skip per step 3): "Classify: keywords = [...], scope = [single file / subsystem / multi-subsystem], repro steps = [present / absent]. My recommendation: [classification]. Confirm?"
   - `Bug fix (best when repro steps or error symptoms are present and the goal is to correct existing behavior)` — → `/fix-bug` (step 6)
   - `New feature (best when adding new behavior, UI, or capability that didn't exist before)` — → inline Phase 4 (step 6)
   - `Refactor (best when restructuring code without changing external behavior)` — → `/refactor-clean` (step 6)
5. **Scope check**: if the description spans multiple independent subsystems, STOP and propose decomposition — one `/ship` run per subsystem.
6. Route:
   - **Bug fix** → `/fix-bug $ARGUMENTS`. Wait for it to complete.
   - **New feature** → continue inline (the Implement steps in `commands/ship/COMMAND.md` Phase 4).
   - **Refactor** → `/refactor-clean`. Wait for it to complete.
7. Do NOT proceed past this classification until the routed command returns (bug/refactor) or the inline steps finish (feature).

**Precondition gate**: if implementation was abandoned or re-scoped mid-way, return to step 1.
