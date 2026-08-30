---
name: post-mortem
description: "Post-mortem: a writeup for a resolved bug (trigger/mechanism/patch/validation known). Use after mattpocock-skills:diagnosing-bugs; say 'เขียน post-mortem/บันทึกบั๊ก'. Don't use for in-progress incidents."
argument-hint: Optional bug ID, Jira key, or summary
disable-model-invocation: true
disable-model-invocation-reason: writes a canonical doc (and optional tracker post) — user decides to record
model: inherit
effort: high
---

# Post-Mortem

Draft the canonical engineering record of a fixed bug. This is the document that answers "what happened and why" for future engineers and reviewers.

## Core Principles

- **Refuse to draft without 4 inputs.** Don't speculate — surface missing inputs rather than guessing. Mechanics (context-scan, partial-gap handling) live in Phase 1.
- **Blameless tone.** The goal is understanding, not blame. "The code assumed X" not "Alice forgot Y."
- **Code identifiers welcome.** Function names, file paths, commit SHAs — future readers grep for these.
- **No uncertain language.** "Appears to," "may have," "we believe" are banned. State what is known or explicitly mark what's still unknown.
- **Root cause over symptom.** The symptom is what users saw. The mechanism is why it happened. Distinguish the two.

---

## Phase 1: Verify Inputs

**Goal**: Confirm the 4 required inputs are available before drafting.

**Actions**:
1. Check whether the user supplied a bug identifier (JIRA key, GitHub issue, PR number, or
   short summary) when invoking this skill.
2. **Scan the conversation for each of the 4 inputs first** — an immediately-prior `mattpocock-skills:diagnosing-bugs` or `mh:incident` run in this session usually already established most of them. Treat anything genuinely established as satisfied; don't re-ask for it.
3. For whatever remains missing or unclear, ask the user explicitly:
   - **Reproducible trigger**: exact steps, environment, inputs that cause the failure. Can someone else make it happen?
   - **Known mechanism**: what code path, what invariant, what race, what assumption broke? One-paragraph explanation.
   - **Identified patch**: which commit(s) fix it? Commit SHA(s) + branch.
   - **Passing validation**: regression test name + status (passing CI, passing locally, both?). If no regression test exists, note it explicitly — a gap, not a blocker for drafting, but must be flagged.
4. If any input is still missing after the context scan → STOP. Ask the user for it. Do not proceed with gaps.
5. Capture the bug identifier as the post-mortem slug (e.g., `JIRA-12345`, `gh-456`).

**Anti-pattern**: drafting with "we think the cause is..." — that's an investigation, not a post-mortem.

---

## Phase 2: Gather Evidence

**Goal**: Collect artifacts that support each section of the template.

**Actions**: Harvest from context first — if this run follows `mattpocock-skills:diagnosing-bugs` in the same session, commit SHA, test name, and CI status are usually already known; fetch only what's still missing.
1. Fetch the fixing commit(s): `git show <sha>` — capture diff summary, author, date.
2. Fetch the regression test (if any): test file path, test name, assertion that would fail pre-fix.
3. Check CI status on the fix commit: `gh run list --commit <sha>` or `gh pr checks <pr>`.
4. If a previous fix attempt existed (common for regressions), note the SHA of the previous fix + why it was incomplete.
5. Check for related issues: `gh issue list --search <keyword>` (GitHub) or, for Jira, search via the **`jira-acli:acli`** skill — never a raw `acli`/MCP call. If `jira-acli` isn't installed, note it and skip (an unresolved search never blocks this).
6. Check for customer / workload impact: any support tickets, SLO breaches, or error-rate spikes tied to this bug?

---

## Phase 3: Draft

**Goal**: Produce the post-mortem document using the 10-section template below.

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

## 10. Assumption Trace
The belief in force before the incident: what the team assumed was true, why that seemed reasonable at the time, and the specific evidence that proved it wrong. Distinct from Root Cause (the code mechanism) — this is the human belief-state that let the mechanism go unquestioned. Distinct from Escape Reason (which process/check missed it) — this is what was believed, not what should have caught it.
**Hindsight-bias risk**: this section is written after the root cause is already known, which biases recall toward a cleaner, more-reasonable-sounding belief than what was actually held at the time. Anchor to something said or written *before* the fix was found — a commit message, a chat line, an earlier hypothesis in the same investigation. If no such contemporaneous artifact exists, say so explicitly ("no record of the belief before the fix — reconstructed from memory, may be biased by knowing the outcome") rather than presenting a reconstructed belief as fact.
Example: "We assumed `numStreams == 1` meant single-GPU, so no sync was needed — reasonable, since every other fast-path in this file makes the same assumption. Proved wrong when tracing `deviceStreamSync()` showed a write still in flight on a supposedly single-stream launch. (Anchored to the investigation's own Slack thread, timestamped before the fix commit.)"
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
3. Verify every code identifier (function, file, SHA) exists: quick `git show <sha>` or `grep -r <function>` sanity check. Existence isn't accuracy — if the draft also claims what that identifier *does* or *covers* ("this check validates X," "no check catches this drift"), verify the claim itself, not just its existence. A check that exists but never runs against this repo's real paths, or validates a different file than claimed, is still a citation error. When the claim is that two mechanisms are *equivalent* or that no gap/asymmetry exists ("this filter covers the same scope as that matcher," "no asymmetry found"), read the full cited code path, not just the first matching line — a later check or guard can narrow, widen, or invalidate the equivalence.
4. Verify any claim stated as settled fact but resting on absence of evidence rather than a positive check (e.g., "no live server emits X," "this has never happened before"). Either back it with what was actually checked, or restate it as the narrower true claim ("no configured server does this, as far as a grep of Y confirms").
5. When declaring a broader concern "resolved," "closed," or "already addressed" — as opposed to verifying one specific identifier — grep the affected file(s) for every other occurrence of the relevant term before asserting closure. State what was actually checked ("all N occurrences of X in file Y reflect the fix") rather than a blanket "verified against the diff" implying coverage it didn't do.
6. Verify links (PR numbers, issue keys) are real.
7. Ensure Section 4 (Symptom Linkage) actually connects Section 3 → Section 2. If it doesn't, the mechanism isn't fully understood.
8. Check Section 10 (Assumption Trace) for hindsight-bias reconstruction: does the stated belief trace to something said or written before the fix was found, or is it a plausible-sounding story assembled after the fact? If no contemporaneous artifact exists, confirm the draft says so explicitly rather than presenting the reconstruction as fact.
9. Render this checklist explicitly in your response — one line per action above, noting what was checked and the result — before presenting the final draft. Don't fold Phase 4's verification into another section's prose (e.g., a stray Section 9 bullet); a visible checklist keeps the checks re-verifiable later instead of just asserted, and resists silently skipping a step under compression.

---

## Phase 5: Present + Archive

**Goal**: Deliver the post-mortem and record where it lives.

**Actions**:
1. Present the complete post-mortem to the user in a single markdown block.
2. **Analyze**: organization practice (repo-based vs issue-tracker based), whether the bug is public (open-source) or internal, whether runbooks/ADRs need updating from findings. **Recommend**: name the specific option below the analysis points to (e.g. "Repo markdown — the bug is public and this repo tracks issues in-repo"), not just "maximizes discoverability."
3. **AskUserQuestion** single-select: "Phase 5: the post-mortem is complete. Where should it live so future engineers can find it?" Render step 2's pick as the literal `(Recommended)` tag on that one option below (replacing its `(best when X)` clause — the menu is a template, not a fixed default), and name the runner-up option + the fact that would flip the pick to it.
   - `Repo markdown (best for team-accessible, long-lived records, especially when the bug is public or the fix affects core architecture)` — write to `docs/post-mortems/<slug>.md`, then **AskUserQuestion** yes/no: "Commit this post-mortem to the repo?"
   - `GitHub issue comment (best when tied to a specific GitHub issue/PR)` — post via `gh issue comment` / `gh pr comment` after user confirms "post it"
   - `JIRA comment (best when tied to a specific Jira ticket)` — a post-mortem is a bespoke document, not one of `jira-acli:jira-content`'s 4 templated-comment shapes (status/QA/blocker/decision), so that skill is the wrong target. Convert it via `jira-acli:acli`'s own ADF plumbing instead: `md2adf.py <file>.md > note.json` then `acli jira workitem comment create --key <KEY> --body-file note.json`, after user confirms "post it". Never a raw `acli --body`/MCP call — the mistake that garbled a prior ticket (CLAUDE.md's routing rule). If `jira-acli` isn't installed, hand the text to the user instead.
   - `Wiki / Confluence (best for cross-team or non-technical audiences, especially when the escape reason is process or policy)` — hand to user for manual posting
   - `Print-only (best for sensitive or internal-only incidents)` — user copies it
4. Update any relevant runbooks, playbooks, or ADRs if the escape reason reveals a systemic gap.
5. If follow-ups were listed in Section 9, create tickets for them now — Jira tickets go through **`jira-acli:jira-content`** (Task/Bug creation fits its template, unlike the bespoke document above), GitHub via `gh issue create` — or flag to the user that they need creation.

---

## Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Decision-sizing triad) → Phase 1 verifies inputs before drafting. Rule 4 (verify-intent loop) → Section 8 requires regression test proof. Abort loud → Phase 1 aborts if 4 inputs missing.
- **Gate revisit trigger (Rule 1)**: 3 repo-committed post-mortems now exist under `docs/post-mortems/` — re-check whether the Phase 1 four-input gate still causes abandonment, or drop this caveat. If usage shows people bouncing off it, loosen the gate before adding more structure elsewhere.
- **Post-diagnosing-bugs workflow**: `mattpocock-skills:diagnosing-bugs` Phase 6 (Cleanup) requires the confirmed hypothesis stated in the commit/PR message, plus the regression test from Phase 5 and the minimised repro from Phase 2 — together these cover the 4 required inputs (reproducible trigger, known mechanism, identified patch, passing validation). That output IS the input to `mh:post-mortem` Phase 1. Run `mh:post-mortem` immediately after `diagnosing-bugs` concludes, while context is warm.
- **Severity tier**: If the bug caused an incident (SLO breach, customer-visible outage), tag the post-mortem with the incident severity; otherwise it's standard.
- **Section 10 (Assumption Trace) origin**: added 2026-08-30 after an article audit found all 4 real post-mortems under `docs/post-mortems/` shared the same gap — none named the specific belief that made the bug's root cause go unquestioned. Distinct from Escape Reason (process gap) and Root Cause (code mechanism); applies going forward, not retrofitted onto the 4 existing records.
- **Hooks active**: `hooks/gates/verifier-protect.sh` asks for approval on edits to the gate/audit verifier surfaces, not CLAUDE.md/METHODOLOGY.md directly.
- **Memory**: Write a `project` memory entry if the escape reason reveals a systemic gap (e.g., "CI matrix missing dumbModel" → `project_ci_gap_<date>.md`).

---

## Named Model

Section 7 "Escape Reason" (how did this reach production? what check missed it?) is the *pre-mortem* lens — not "what did we miss" but "what catastrophic-failure branch + detection + rollback" was missing pre-incident. Section 6 "Discovery Method" + section 8 "Validation Proof" together are *scientific-method* (repro → falsify → regression test). Catalog + honesty caveat: read via Bash with `cat "${MH_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.
