---
name: post-mortem
description: "Draft a post-mortem for a resolved bug (trigger/mechanism/patch/validation known). Use after /fix-bug; say 'เขียน post-mortem/บันทึกบั๊ก/incident report'. Don't use for in-progress or non-technical incidents."
argument-hint: Optional bug ID, Jira key, or summary
disable-model-invocation: true
disable-model-invocation-reason: writes a canonical doc (and optional tracker post) — user decides to record
---

# Post-Mortem

Draft the canonical engineering record of a fixed bug. This is the document that answers "what happened and why" for future engineers, reviewers, and incident retrospectives.

## Core Principles

- **Refuse to draft without 4 inputs.** Don't speculate — surface missing inputs rather than guessing. Mechanics (context-scan, partial-gap handling) live in Phase 1.
- **Blameless tone.** The goal is understanding, not blame. "The code assumed X" not "Alice forgot Y."
- **Code identifiers welcome.** Function names, file paths, commit SHAs — future readers need to grep for these.
- **No uncertain language.** "Appears to," "may have," "we believe" are banned. State what is known or explicitly mark what is still unknown.
- **Root cause over symptom.** The symptom is what users saw. The mechanism is why it happened. Distinguish the two clearly.

---

## Phase 1: Verify Inputs

**Goal**: Confirm the 4 required inputs are available before drafting.

**Actions**:
1. Check `$ARGUMENTS` for a bug identifier (JIRA key, GitHub issue, PR number, or short summary).
2. **Scan the conversation for each of the 4 inputs first** — an immediately-prior `/fix-bug` or `/incident` run in this session usually already established most of them. Treat anything genuinely established as satisfied; don't re-ask for it.
3. For whatever remains missing or unclear, ask the user explicitly:
   - **Reproducible trigger**: exact steps, environment, inputs that cause the failure. Can someone else make it happen?
   - **Known mechanism**: what code path, what invariant, what race, what assumption broke? One-paragraph explanation.
   - **Identified patch**: which commit(s) fix it? Commit SHA(s) + branch.
   - **Passing validation**: regression test name + status (passing CI, passing locally, both?). If no regression test exists, note that explicitly — it's a gap, not a blocker for drafting, but must be flagged.
4. If any input is still missing or unclear after the context scan → STOP. Ask the user to provide it. Do not proceed with gaps.
5. Capture the bug identifier as the post-mortem slug (e.g., `JIRA-12345`, `gh-456`).

**Anti-pattern**: drafting with "we think the cause is..." — that's an investigation, not a post-mortem.

---

## Phase 2: Gather Evidence

**Goal**: Collect artifacts that support each section of the template.

**Actions**: Harvest from context first — if this run follows `/fix-bug` in the same session, commit SHA, test name, and CI status are usually already known; fetch only what's still missing.
1. Fetch the fixing commit(s): `git show <sha>` — capture diff summary, author, date.
2. Fetch the regression test (if any): test file path, test name, assertion that would fail pre-fix.
3. Check CI status on the fix commit: `gh run list --commit <sha>` or `gh pr checks <pr>`.
4. If a previous fix attempt existed (common for regressions), note the SHA of the previous fix + why it was incomplete.
5. Check for related issues: `gh issue list --search <keyword>` (GitHub) or, for Jira, search via the **`jira-acli:acli`** skill — never a raw `acli`/MCP call. If `jira-acli` isn't installed, note it and skip (same fallback `review-pr`/`task-prep` use — an unresolved search never blocks the post-mortem).
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
Example: "Tada skipped a cross-stream sync on its single-stream fast-path; all 8+ GPU dumbModel fine-tuning runs hung at eval steps. Fixed by removing the shortcut (PR #5751)."

## 2. Symptom
What users / operators / tests saw. Observable failure mode only — no mechanism yet.
Example: "Fine-tuning on 8 GPUs hung every eval step — CPU idle, GPU 100% wait, no error, manual kill required."

## 3. Root Cause (Mechanism)
Why it happened. Code path, invariant, race, assumption — the actual technical cause.
Example: "`tadaLaunchPrepare`'s `numStreams == 1` fast-path skipped the `launchStream → deviceStream` sync; the kernel launched before `scratchBuf` writes were visible."

## 4. Symptom Linkage
How the mechanism produced the symptom. Connect cause → effect explicitly.
Example: "`scratchBuf` uninitialized at launch → kernel reads garbage → ring-flag spins forever — silent because the kernel is user-space, so the host just saw idle CPU / busy GPU."

## 5. Fix
What changed, at what commit(s). Link the patch.
Example: "Removed the fast-path, added `deviceStreamSync()` before launch. Commit `a1b2c3d` on `fix/tada-sync`."

## 6. Discovery Method
How the bug was found. Not the fix — the discovery.
Example: "Customer-reported hang, reproduced locally, bisected to `e5f6a7b`; instrumentation confirmed `scratchBuf == NULL` at kernel entry."

## 7. Escape Reason
How did this reach production? What check missed it?
Example: "Fast-path shipped in a perf sprint; unit tests covered multi-stream only, dumbModel wasn't in the CI workload matrix."

## 8. Validation Proof
How we know the fix works and won't regress.
Example: "`test_tada_single_stream_sync` fails pre-fix, passes post-fix; CI green; dumbModel eval-step benchmark now completes."

## 9. Follow-Ups
Tracked items to prevent recurrence. Each item needs an **individual owner** (not a team) and a **verifiable completion criterion** — vague ownership is the most-cited reason follow-ups rot. If genuinely unassigned, write "Unowned — needs assignment" rather than skip the field.
Example: "- [ ] Add dumbModel single-stream config to the CI workload matrix (owner: @priya, done when: it runs in CI nightly). - [ ] Audit all `numStreams` branches for the same assumption (owner: @jordan, done when: audit doc lists every branch + verdict). - [ ] Document fast-path policy: no sync skip without explicit safety proof (owner: Unowned — needs assignment)."
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
   - `GitHub issue comment (Recommended when tied to a specific GitHub issue/PR)` — post via `gh issue comment` / `gh pr comment` after user confirms "post it"
   - `JIRA comment (Recommended when tied to a specific Jira ticket)` — a post-mortem is a bespoke document, not one of `jira-acli:jira-content`'s 4 templated-comment shapes (status/QA/blocker/decision), so that skill is the wrong target. Convert it via `jira-acli:acli`'s own ADF plumbing instead: `md2adf.py <file>.md > note.json` then `acli jira workitem comment create --key <KEY> --body-file note.json`, after user confirms "post it". Never a raw `acli --body`/MCP call — that's the exact class of mistake that garbled a prior ticket (CLAUDE.md's Jira/Confluence routing rule). If `jira-acli` isn't installed, note it and hand the text to the user instead.
   - `Wiki / Confluence (Recommended for cross-team or non-technical audiences; best when the escape reason is process or policy)` — hand to user for manual posting
   - `Print-only (Recommended for sensitive or internal-only incidents)` — user copies it
4. Update any relevant runbooks, playbooks, or ADRs if the escape reason reveals a systemic gap.
5. If follow-ups were listed in Section 9, create tickets for them now — Jira tickets go through **`jira-acli:jira-content`** (Task/Bug creation is exactly its template fit, unlike the bespoke document above), GitHub via `gh issue create` — or flag to the user that they need creation.

---

## Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Decision-sizing triad) → Phase 1 verifies inputs before drafting. Rule 4 (verify-intent loop) → Section 8 requires regression test proof. Abort loud → Phase 1 aborts if 4 inputs missing.
- **Gate revisit trigger (Rule 1)**: the Phase 1 four-input refusal gate is unvalidated against any real run — no repo-committed post-mortem exists yet, and it's the most plausible reason a user would abandon the draft. If real usage shows people bouncing off the gate, loosen it first before adding more structure elsewhere.
- **Post-/fix-bug workflow**: `/fix-bug` Phase 7 produces a summary (what broke, root cause, fix shape, regression test, files touched). That summary IS the input to `/post-mortem` Phase 1. Run `/post-mortem` immediately after `/fix-bug` concludes, while context is warm.
- **Severity tier**: If the bug caused an incident (SLO breach, customer-visible outage), tag the post-mortem with the incident severity. Otherwise it's a standard engineering post-mortem.
- **Hooks active**: `hooks/gates/verifier-protect.sh` asks for approval on edits to the gate/audit verifier surfaces; it does not cover CLAUDE.md/METHODOLOGY.md directly.
- **Memory**: Write a `project` memory entry if the escape reason reveals a systemic gap (e.g., "CI matrix missing dumbModel" → `project_ci_gap_<date>.md`).

---

## Named Model

Section 7 "Escape Reason" (how did this reach production? what check missed it?) is the *pre-mortem* lens — not "what did we miss" but "what catastrophic-failure branch + detection + rollback" was missing pre-incident. Section 6 "Discovery Method" + section 8 "Validation Proof" together are *scientific-method* (repro → falsify → regression test). Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
