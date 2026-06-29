---
name: post-mortem
description: "Draft a canonical post-mortem for a resolved bug. Requires reproducible trigger, known mechanism, identified patch, and passing validation. Use after /fix-bug completes or when user says 'write post-mortem', 'document this bug', 'incident report', or when the user says 'เขียน post-mortem', 'บันทึกบั๊ก', 'incident report'. Don't use for: in-progress investigations (root cause must be known), hypothetical bugs (no validated fix), or non-technical incidents (use incident response template instead)."
argument-hint: Optional bug ID, Jira key, or summary
disable-model-invocation: true
disable-model-invocation-reason: writes a canonical doc (and optional tracker post) — user decides to record
---

# Post-Mortem

Draft the canonical engineering record of a fixed bug. This is the document that answers "what happened and why" for future engineers, reviewers, and incident retrospectives.

## Core Principles

- **Refuse to draft without 4 inputs.** **Analyze**: which of the 4 inputs are present in the conversation context vs. which are missing. **Recommend** STOP and ask only for the missing pieces; if 3/4 are present, ask for the remaining 1 rather than demanding all 4. Don't speculate (METHODOLOGY Rule 12 — Fail loud).
- **Blameless tone.** The goal is understanding, not blame. "The code assumed X" not "Alice forgot Y."
- **Code identifiers welcome.** Function names, file paths, commit SHAs — future readers need to grep for these.
- **No uncertain language.** "Appears to," "may have," "we believe" are banned. State what is known or explicitly mark what is still unknown.
- **Root cause over symptom.** The symptom is what users saw. The mechanism is why it happened. Distinguish the two clearly.

---

## Phase 1: Verify Inputs

**Goal**: Confirm the 4 required inputs are available before drafting.

**Actions**:
1. Check `$ARGUMENTS` for a bug identifier (JIRA key, GitHub issue, PR number, or short summary).
2. Verify the 4 inputs with the user. Ask explicitly if any are unclear:
   - **Reproducible trigger**: exact steps, environment, inputs that cause the failure. Can someone else make it happen?
   - **Known mechanism**: what code path, what invariant, what race, what assumption broke? One-paragraph explanation.
   - **Identified patch**: which commit(s) fix it? Commit SHA(s) + branch.
   - **Passing validation**: regression test name + status (passing CI, passing locally, both?). If no regression test exists, note that explicitly — it's a gap, not a blocker for drafting, but must be flagged.
3. If any input is missing or unclear → STOP. Ask the user to provide it. Do not proceed with gaps.
4. Capture the bug identifier as the post-mortem slug (e.g., `JIRA-12345`, `gh-456`).

**Anti-pattern**: drafting with "we think the cause is..." — that's an investigation, not a post-mortem.

---

## Phase 2: Gather Evidence

**Goal**: Collect artifacts that support each section of the template.

**Actions**:
1. Fetch the fixing commit(s): `git show <sha>` — capture diff summary, author, date.
2. Fetch the regression test (if any): test file path, test name, assertion that would fail pre-fix.
3. Check CI status on the fix commit: `gh run list --commit <sha>` or `gh pr checks <pr>`.
4. If a previous fix attempt existed (common for regressions), note the SHA of the previous fix + why it was incomplete.
5. Check for related issues: `gh issue list --search <keyword>` or JIRA search for duplicates / similar bugs.
6. Check for customer / workload impact: any support tickets, SLO breaches, or error-rate spikes tied to this bug?

---

## Phase 3: Draft

**Goal**: Produce the post-mortem document using the 9-section template below.

**Tone check before writing**: re-read the Core Principles section above. Blameless, concrete, no hedging.

### Template

```markdown
# Post-Mortem: <Bug Title> (<slug>)

## 1. Summary
One paragraph. What broke, who was affected, and the final outcome.
Example: "GPU communication library Tada skipped a cross-stream sync under a single-stream fast-path gate that dumbModel triggered. All Llama-2-70B fine-tuning runs on 8+ GPUs hung at eval steps. Fixed by removing the unsafe shortcut and tightening the device-side safety check (PR #5751)."

## 2. Symptom
What users / operators / tests saw. Observable failure mode only — no mechanism yet.
Example: "LLM-7B fine-tuning on 8 GPUs hung every eval step. CPU utilization dropped to zero; GPU kernels showed 100% wait. No error message. Manual kill required."

## 3. Root Cause (Mechanism)
Why it happened. Code path, invariant, race, assumption — the actual technical cause.
Example: "In `tadaLaunchPrepare`, the fast-path for `numStreams == 1 && !persistent` skipped the `launchStream → deviceStream` cross-event. dumbModel hit this gate. Kernel launched before `scratchBuf` writes were visible → `scratchBuf == NULL` in kernel → ring ready-flag read from garbage → infinite spin."

## 4. Symptom Linkage
How the mechanism produced the symptom. Connect cause → effect explicitly.
Example: "Skipped sync → `scratchBuf` uninitialized at kernel launch → kernel dereferences null pointer → ring-flag read from garbage → spin-forever. The hang had no error message because the GPU kernel was user-space; the host saw idle CPUs and busy GPUs."

## 5. Fix
What changed, at what commit(s). Link the patch.
Example: "Removed the `numStreams == 1` fast-path entirely. Added `deviceStreamSync()` before kernel launch. Commit `a1b2c3d` on `fix/tada-sync`."

## 6. Discovery Method
How the bug was found. Not the fix — the discovery.
Example: "Customer reported hangs during dumbModel training. Reproduced locally with their config. Bisected to commit `e5f6a7b` (added fast-path 3 months ago). Instrumentation confirmed `scratchBuf == NULL` at kernel entry."

## 7. Escape Reason
How did this reach production? What check missed it?
Example: "Fast-path was added during a perf sprint. Unit tests covered multi-stream paths but not the single-stream gate. dumbModel was not in CI workload matrix at the time."

## 8. Validation Proof
How we know the fix works and won't regress.
Example: "Regression test `test_tada_single_stream_sync` reproduces the hang on pre-fix code and passes on fix. CI green on `a1b2c3d`. dumbModel 7B eval-step benchmark runs to completion (was hanging 100% of the time)."

## 9. Follow-Ups
Tracked items to prevent recurrence. Explicit owners and deadlines if known.
Example: "- [ ] Expand CI workload matrix to include dumbModel single-stream config (owner: CI team, target: next sprint). - [ ] Audit all `numStreams` branches for similar assumptions (owner: Tada team). - [ ] Document fast-path policy: no sync skip without explicit safety proof."
```

**Actions**:
1. Fill each section. Use the user's answers from Phase 1 + evidence from Phase 2.
2. If a section genuinely has no content (e.g., no customer impact), write "None." — don't skip the section.
3. If a section is unknown (e.g., escape reason is still being investigated), write "Unknown — tracked in <follow-up issue>."
4. Do NOT invent facts to make the narrative cleaner. If the mechanism is partially understood, state what IS known and mark the rest unknown.

---

## Phase 4: Review

**Goal**: Quality-check the draft before presenting.

**Actions**:
1. Check for banned phrases: "appears to," "may have," "we believe," "probably," "likely caused by." Replace with facts or explicit unknowns.
2. Check for blame: "Alice forgot," "the team missed," "reviewer approved." Replace with system-focused language: "the check was missing," "the test matrix didn't cover," "the policy was undocumented."
3. Verify every code identifier (function, file, SHA) exists: quick `git show <sha>` or `grep -r <function>` sanity check.
4. Verify links (PR numbers, issue keys) are real.
5. Ensure Section 4 (Symptom Linkage) actually connects Section 3 → Section 2. If it doesn't, the mechanism isn't fully understood.

---

## Phase 5: Present + Archive

**Goal**: Deliver the post-mortem and record where it lives.

**Actions**:
1. Present the complete post-mortem to the user in a single markdown block.
2. **Analyze**: organization practice (repo-based vs issue-tracker based), whether the bug is public (open-source) or internal, whether runbooks/ADRs need updating from findings. **Recommend** the destination that maximizes discoverability for future engineers.
3. **AskUserQuestion** single-select: "Phase 5: the post-mortem is complete. Where should it live so future engineers can find it?"
   - `Repo markdown (Recommended for team-accessible, long-lived records; best when the bug is public or the fix affects core architecture)` — write to `docs/post-mortems/<slug>.md`, then **AskUserQuestion** yes/no: "Commit this post-mortem to the repo?"
   - `JIRA / GitHub issue comment (Recommended when tied to a specific ticket; best for sprint or incident-ticket context)` — post as comment after user confirms "post it"
   - `Wiki / Confluence (Recommended for cross-team or non-technical audiences; best when the escape reason is process or policy)` — hand to user for manual posting
   - `Print-only (Recommended for sensitive or internal-only incidents)` — user copies it
4. Update any relevant runbooks, playbooks, or ADRs if the escape reason reveals a systemic gap.
5. If follow-ups were listed in Section 9, create tickets for them now (or flag to the user that they need creation).

---

## Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Think before coding) → Phase 1 verifies inputs before drafting. Rule 9 (Tests verify intent) → Section 8 requires regression test proof. Rule 12 (Fail loud) → Phase 1 aborts if 4 inputs missing.
- **Post-/fix-bug workflow**: `/fix-bug` Phase 7 produces a summary (what broke, root cause, fix shape, regression test, files touched). That summary IS the input to `/post-mortem` Phase 1. Run `/post-mortem` immediately after `/fix-bug` concludes, while context is warm.
- **Severity tier**: If the bug caused an incident (SLO breach, customer-visible outage), tag the post-mortem with the incident severity. Otherwise it's a standard engineering post-mortem.
- **Hooks active**: doctrine-edit-gate protects CLAUDE.md/METHODOLOGY.md if archiving involves editing those.
- **Memory**: Write a `project` memory entry if the escape reason reveals a systemic gap (e.g., "CI matrix missing dumbModel" → `project_ci_gap_<date>.md`).
