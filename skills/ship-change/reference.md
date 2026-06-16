# Ship Change Reference

On-demand detail for `ship-change` skill. Loaded when the agent needs full phase procedures or failure-mode checks.

---

## Phase 1: Classify (Full Procedure)

**Goal**: Determine if this is a bug fix, feature, refactor, or hybrid.

**Actions**:
1. Parse user arguments — if user already said "fix" or "bug", classify as bug; if "feature" or "add", classify as feature.
2. **Analyze**: keywords in arguments (`fix`, `bug`, `feature`, `add`, `refactor`), scope (single file vs subsystem), presence of existing repro steps. **Recommend** the classification that best fits the user's intent.
3. **AskUserQuestion** single-select: "Phase 1: keywords = [fix/bug/feature/add/refactor], scope = [single file / subsystem / multi-subsystem], repro steps = [present / absent]. My recommendation: [classification]. Confirm?"
   - `Bug fix (Recommended when repro steps or error symptoms are present and the goal is to correct existing behavior)`
   - `New feature (Recommended when adding new behavior, UI, or capability that didn't exist before)`
   - `Refactor (Recommended when restructuring code without changing external behavior)`
4. Scope check: if the description spans multiple independent subsystems, STOP and propose decomposition. Each subsystem gets its own `kbg:ship-change` run.
5. Output: classification + scope confirmation.

**Next**: Phase 2 (Implement).

---

## Phase 2: Implement (Full Procedure)

**Goal**: Execute the correct implementation command based on Phase 1 classification.

**Actions**:
1. **Bug fix** → tell user to run `/fix-bug <arguments>`. Wait for it to complete.
2. **New feature** → tell user to run `/feature-dev <arguments>`. Wait for it to complete.
3. **Refactor** → spawn `maintenance-engineer` agent. Wait for it to complete.
4. Do NOT proceed to Phase 3 until the implementation command returns.

**Precondition gate**: if implementation was abandoned or re-scoped, return to Phase 1.

**Next**: Phase 3 (Self-Review).

---

## Phase 3: Self-Review (Full Procedure)

**Goal**: Review your own diff before opening a PR.

**Actions**:
1. **Security check first**: For high-stakes surfaces (auth flows, payment, admin panels, file uploads, dependency manifests), tell user: "Run `kbg:security-auditor` for a comprehensive audit before `kbg:review-pr`." For a routine auth/secrets-touching diff, the `security-reviewer` pass inside `kbg:review-pr` is enough — don't run both (see `security-auditor` SKILL.md for the canonical agent-vs-skill rule).
2. Tell user: "Run `kbg:review-pr` to review the changes before opening a PR."
3. Wait for `kbg:review-pr` to complete.
4. If Critical findings were raised, fix them before proceeding (return to Phase 2 with a narrowed scope, or fix inline if trivial).

**Precondition gate**: `kbg:review-pr` must return zero Critical findings before proceeding.

**Next**: Phase 4 (Open PR / Address Feedback).

---

## Phase 4: Address Feedback (Full Procedure)

**Goal**: Respond to PR review comments.

**Actions**:
1. Tell user: "Open the PR. If external or automated review returns comments, return here and run `/address-review`."
2. If `/address-review` is run, wait for it to complete.
3. After `/address-review` finishes, return to Phase 3 (re-run `kbg:review-pr` on the updated diff) before declaring done.

**Precondition gate**: all review threads must be addressed (zero open actionable threads).

**Next**: Phase 5 (Merge).

---

## Phase 5: Verify + Merge (Full Procedure)

**Goal**: Collect independent proof, verify the acceptance contract, then land the change.

**Actions**:
0. **Review-state gate** (read before merge — machine-enforceable precondition):
   ```bash
   REVIEW_STATE="${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}/review-last.json"
   ```
   - **File absent** → STOP. "No `kbg:review-pr` run found. Run it now before merging."
   - **`clean: false`** → STOP. "Last review returned Critical findings. Re-run `kbg:review-pr` after fixes."
   - **`last_sha != HEAD`** → WARN. "Review ran on an earlier commit (last: `last_sha`, HEAD: `$(git rev-parse HEAD)`). Re-run `kbg:review-pr` or confirm the delta is trivial." (AskUserQuestion required — advisory, not a hard stop.)
   - **`clean: true` and `last_sha == HEAD`** → proceed.
1. **Collect proof artifacts** (at least one required per METHODOLOGY Rule 4 sub-rule):
   - Run tests and capture output: `npm test`, `pytest`, `go test`, etc. Save output to `.scratch/<slug>/proofs/test-output.txt`.
   - Run type-checker / linter: `tsc --noEmit`, `flake8`, `cargo check`. Save output to `.scratch/<slug>/proofs/typecheck.txt`.
   - Run deterministic acceptance: `python3 scripts/evals/run-acceptance.py <slug>`. Save `acceptance-results.json` to `.scratch/<slug>/proofs/`.
   - Fresh-context adversarial review: spawn `code-reviewer` or `security-reviewer` with no prior context, capture findings to `.scratch/<slug>/proofs/adversarial-review.md`.
   - **Gate**: if NONE of the above are available → STOP. Tell user: "Proof missing. Run at least one verification step before merge."
2. **Verify acceptance contract** (if the task locked one via `kbg:accept-task`):
   - Run `/pre-ship-verify <slug>`.
   - If RED → fix before merge.
   - If AMBER → confirm manual criteria are met.
   - If GREEN → proceed.
3. Tell user: "Run `/ship-merge` when CI is green and approvals are in."
4. Wait for `/ship-merge` to complete.
5. Summarize: what changed, files touched, key decisions, proof artifacts collected, and any follow-up items.

**Done.**

---

## Failure Modes to Avoid

- **Circular handoffs**: never tell the user to re-run `kbg:ship-change` from within a phase. Use the specific phase command instead.
- **Skipping review**: Phase 3 is non-negotiable. No PR opens without `kbg:review-pr` first.
- **Silent merges**: Phase 5 requires explicit `/ship-merge` invocation — don't imply the user should merge manually.
- **Bloated orchestrator**: if you find yourself adding implementation detail (e.g., "how to write a test"), that belongs in `/fix-bug` or `/feature-dev`, not here.
