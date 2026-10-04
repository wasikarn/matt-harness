# Post-Mortem Template

The 11-section template for `mh:post-mortem` step 3. Fill every section; an empty one reads
"None.", one under investigation reads "Unknown — tracked in <follow-up issue>". Records under
`docs/post-mortems/` with nine or ten sections are not retrofitted.

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

## 8. Failure class
One of: missing_context | bad_tool_contract | missing_guardrail | weak_verification
Each class maps to one fix: a clearer map or a memory entry (a lost decision is missing context), a better tool, a mechanical check (lint or audit rule, not a new deny gate), a new test. Name the fix.

## 9. Validation Proof
How we know the fix works and won't regress.
Example: "`test_tada_single_stream_sync` fails pre-fix, passes post-fix; CI green; dumbModel eval-step benchmark now completes."

## 10. Follow-Ups
Tracked items to prevent recurrence. Each item needs an **individual owner** (not a team) and a **verifiable completion criterion** — vague ownership is the most-cited reason follow-ups rot. If genuinely unassigned, write "Unowned — needs assignment" rather than skip the field.
Example: "- [ ] Add dumbModel single-stream config to the CI workload matrix (owner: @priya, done when: it runs in CI nightly). - [ ] Audit all `numStreams` branches for the same assumption (owner: @jordan, done when: audit doc lists every branch + verdict). - [ ] Document fast-path policy: no sync skip without explicit safety proof (owner: Unowned — needs assignment)."

## 11. Assumption Trace
The belief in force before the incident: what the team assumed was true, why that seemed reasonable at the time, and the specific evidence that proved it wrong. Distinct from Root Cause (the code mechanism) — this is the human belief-state that let the mechanism go unquestioned. Distinct from Escape Reason (which process/check missed it) — this is what was believed, not what should have caught it.
**Hindsight-bias risk**: this section is written after the root cause is already known, which biases recall toward a cleaner, more-reasonable-sounding belief than what was actually held at the time. Anchor to something said or written *before* the fix was found — a commit message, a chat line, an earlier hypothesis in the same investigation. If no such contemporaneous artifact exists, say so explicitly ("no record of the belief before the fix — reconstructed from memory, may be biased by knowing the outcome") rather than presenting a reconstructed belief as fact.
Example: "We assumed `numStreams == 1` meant single-GPU, so no sync was needed — reasonable, since every other fast-path in this file makes the same assumption. Proved wrong when tracing `deviceStreamSync()` showed a write still in flight on a supposedly single-stream launch. (Anchored to the investigation's own Slack thread, timestamped before the fix commit.)"
```
