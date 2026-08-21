---
name: review-pr-finish
description: "Finish kbg:review-pr's tiered findings — decide submit/fix, write review state and loop verdict. Use when kbg:review-pr-tier hands off. Don't use for self-invoked or standalone review."
bucket: review
metadata:
  origin: kbg
model: inherit
effort: high
---

# Comprehensive PR Review — Present + Summary (Phases 6-7)

Final link in the `kbg:review-pr` → `kbg:review-pr-tier` → `kbg:review-pr-finish` chain — see
`kbg:review-pr-tier`'s own header for why this split exists (harness-audit's 20,000-char
threshold + auto-compaction re-attachment protection). Never invoked directly or standalone —
`kbg:review-pr-tier`'s Phase 5 calls `Skill(kbg:review-pr-finish)` as a mandatory next step once tiered.

**First action — read the checkpoint, before anything else**, same fail-closed discipline as
`kbg:review-pr-tier`:

```bash
CKPT_JSON=$(bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/read-review-checkpoint.sh" 5 "$HEAD_SHA" "${WT:-}")
```

Use the `$HEAD_SHA` you already hold — this script does not call `git` itself. **On any non-zero
exit: stop, name the exact `reason=` token, tell the human plainly** — don't guess or proceed on
partial/assumed values. On success, parse `base_sha`, `agent_findings`,
`dispatch_failures`, and `tier_list` out of `$CKPT_JSON`. **Derive, don't re-store**:
`CRITICAL_COUNT`/`IMPORTANT_COUNT`/`MINOR_COUNT` and `FINDING_FILES` come from counting/filtering
`tier_list` — they were never separately checkpointed.

---

## Phase 6: Present + User Decision

**Goal**: Show tier-grouped findings, then branch on the review target (set in Phase 1): **own current branch** → fix decision (fixes land in the working tree); **PR by number** → the submit decision. For a reviewer, choosing how to submit the review *is* acting on the findings — no "fix later", and in-place fixes in the throwaway worktree are discarded at Phase 7 cleanup unless pushed. This is the **single submit gate**; Phase 7 executes the choice without re-asking.

**This gate requires an actual answer from the user — not a formality to self-answer when no one's available to respond.** With no way to get a real answer (no interactive session, `AskUserQuestion` unavailable, unattended/headless), don't pick an action-taking option yourself — default to the non-mutating choice instead (`Fix later` on branch A, `Skip — I'll post manually` on branch B) and say plainly the decision was deferred, not made for the user. Confirmed failure mode: an unattended run picked "fix Critical + Important now" as its own default and actually committed the fixes, off a request that only asked for a review.

**Actions**:
1. **If `JIRA_KEY` was set, present the ticket-quality report first**, as its own section before
   the code findings, never blended into the tiers — template: `../review-pr/reference.md` §
   Requirement Analysis Presentation. **This section never feeds the posted review body, on
   either review target** (safety-load-bearing, repeated here) — Phase 7's review-body
   construction starts from the code findings below only; ticket content never lands in a public
   GitHub comment.

   Then present code findings — tier table, demoted-finding tags, zero-finding green-light
   variants, and the 1-line ledger trend — exact templates + rationale:
   `../review-pr/reference.md` § Phase 6 — Code Findings Presentation Templates.

   **Proof-verification check** (own-branch flow only — Rule 4, define done, loop until
   verified; doesn't apply to a PR-by-number review, whose throwaway worktree has no `.scratch/`
   of its own): look for `.scratch/<slug>/proofs/`. If absent and the task is non-trivial (≥2
   files changed or ≥1 test file touched), flag as **[verification-gap] must-fix** — independent
   proof is required before merge. If present, verify at least one artifact is non-empty (test
   output, type-check output, or adversarial review). Surface: `Proof: 2 artifacts (test +
   typecheck) ✅` or `Proof: missing — must-fix`.

2. **Branch on review target (from Phase 1):**

   **A. Reviewing the current branch (own working tree)** — fixes land directly, straight to the fix decision:
   - **Self-consistency**: skip this ask only when Critical/Important/Minor are all 0 **and** none of this file's own must-fix conditions are active — no `dispatch_failures`, re-hunt status isn't `incomplete`, proof-verification above doesn't flag `[verification-gap] must-fix`. All-zero tiers with any of those still active is not a clean pass — surface the gap, don't skip. Only when every condition clears: state "Clean pass, proceeding," record as `proceeded-as-is` (step 3), go straight to Phase 7.
   - **Auto-proceed on Minor-only** (`ACS:minor-only-auto-proceed`): also skip the ask (auto-proceed, defer) when **Critical == 0 AND Important == 0** — only Minor (cosmetic) findings remain — **and** the same must-fix conditions as Self-consistency above are clear. State: "Phase 6: 0 Critical, 0 Important, N Minor (cosmetic) — proceeding, Minor findings deferred as follow-up. Say 'fix all' to address them now." Record as `proceeded-as-is` with the deferred Minor findings as a follow-up, go straight to Phase 7. Why Important still gates, and why the counts aren't a self-report: `../review-pr/reference.md` § Phase 6 — Minor-only auto-proceed rationale.
   - **AskUserQuestion** single-select (only when at least one Critical **or** Important finding remains): "Phase 6: [N] Critical (must fix before merge), [N] Important (should fix before merge), [N] Minor (nice to have). My recommendation: [option]. How do you want to proceed?"
     - `Fix Critical issues now, proceed with Important/Minor later (best when Critical count is low and the user wants to keep momentum)`
     - `Fix Critical + Important now, Minor later (best when both tiers have real issues that shouldn't ship)`
     - `Fix all tiers now before proceeding (best when review surfaced significant problems across all tiers)`
     - `Proceed as-is — acknowledge risk (only when findings are false positives or truly cosmetic)` — revisit only if a later change at the same file:line proves the "cosmetic" call wrong

   **B. Reviewing a PR by number (isolated, throwaway worktree)** — the decision *is* what review to submit to the author. **First build the review payload** (`../review-pr/reference.md` § Build the Review Payload), then show the preview before asking **once**:
   - **Preview**: event type + review body (from that same payload-build procedure), plus:
     - Number of line-level comments to be posted
     - 2–3 sample comments (what the author will see)
   - **Prior-review check**: `gh pr view <#> --json reviews -q ".reviews[].author.login"` vs `gh api user -q .login`. Warn before asking if already reviewed — GitHub stacks new reviews (no update-in-place).
   - **AskUserQuestion** single-select: "Phase 6: reviewing PR #N — [N] line-level comments + [event type], previewed above. My recommendation: [option]. How do you want to act on these findings?"
     - `Post line-level review now (best when findings are concrete — the author sees each issue in context)` — batch via `gh api` (Phase 7)
     - `Post summary only (best when line-level comments would be noisy or the diff is trivial)` — single `gh pr review --body` (Phase 7)
     - `Fix + push to the PR branch (write access / own PR only — worktree fixes discard unless committed + pushed)` — apply fixes in `$WT`, commit, push before Phase 7 cleanup
     - `Skip — I'll post manually (best when the body needs rephrasing or the PR isn't ready for external review)` — nothing posted; revisit if unreviewed past this session (Phase 2's pinned window goes stale) — re-run `kbg:review-pr` rather than author from old findings
   - To tweak the top-level body first: pick a post option and say so (or answer Other), adjust, then proceed.

3. Record the decision; Phase 7 executes it:
   - **Fix now** (branch A) / **Fix + push** (branch B) — apply the fixes. For branch B, commit in `$WT` and push to the PR's head branch *before* Phase 7 cleanup removes the worktree.
   - **Fix later** (branch A) — capture as a follow-up.
   - **Post line-level / Post summary** (branch B) — Phase 7 runs the recorded submit (no second gate).
   - **Proceed as-is / Skip** — document the rationale; nothing posted.

---

## Phase 7: Summary

**Goal**: Record what was reviewed, what was addressed, suggested next step.

**Actions**:
1. Mark all todos complete. Write the review-state file so `/ship-merge`'s scored review gate can
   read it, via the bundled script — never hand-author the JSON:
   ```bash
   # File paths w/ Critical+Important findings this round — feeds the convergence
   # gate's finding-identity tracking. Sort+dedup for a stable set-diff.
   FINDING_FILES_TMP="${TMPDIR:-/tmp}/review-pr-findings-$$"
   printf '%s\n' "${FINDING_FILES[@]}" | sort -u > "$FINDING_FILES_TMP"
   bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/write-review-state.sh" \
     "${CRITICAL_COUNT:-0}" "${REHUNT_STATUS:-n/a}" "${DISPATCH_FAILURES:-}" "$HEAD_SHA" "${WT:-}" \
     "${IMPORTANT_COUNT:-0}" "${MINOR_COUNT:-0}" "$FINDING_FILES_TMP"

   # ADR 0009's bounded auto-loop decision, right after — same $HEAD_SHA/$WT as
   # the write above, confirming this reads back THIS round's write, not stale.
   if LOOP_DECISION=$(bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/should-continue-loop.sh" "$HEAD_SHA" "${WT:-}"); then
     LOOP_EXIT=0
   else
     LOOP_EXIT=$?
   fi
   LOOP_REASON=$(printf '%s\n' "$LOOP_DECISION" | sed -n 's/^reason=//p')
   ```
   `FINDING_FILES` = file paths from the tiered Critical + Important findings (derived from the
   checkpoint's `tier_list`, not separately tracked) — one bash-array entry per distinct file,
   **repo-relative**. Pass it via the temp file, every other value as a literal positional
   argument, not inherited env. Full rationale, stdout contract, non-zero-exit semantics:
   `../review-pr/reference.md` § write-review-state.sh — Field Contract & Amend Mode. Step 2's
   round-aware footer renders directly from that stdout — don't re-derive it by re-reading the
   state file back.

   **`should-continue-loop.sh`'s exit code (`$LOOP_EXIT` above) is what step 2 branches on to
   decide auto-continue** — never re-derive this from `round`/`stalled`/`force_human`/
   `convergence_state` yourself; that's the sync-seam this script exists to close. `0` = continue
   automatically; any non-zero = stop and hand back to a human, with `$LOOP_REASON` naming why.
   Full reason-token glossary + rendered stop messages: `../review-pr/reference.md` § Loop
   Reason Stop Messages. Full script: `../review-pr/scripts/should-continue-loop.sh`.
2. Summarize:
   - PR # and URL (if applicable)
   - Review window: `BASE_SHA..HEAD_SHA`
   - Jira ticket + verdict, if `JIRA_KEY` was set (e.g. "TP-871: ready-with-assumptions" or "TP-871: fetch failed, cross-check skipped")
   - Agents dispatched + their tier counts (e.g. "code-reviewer: 2 Critical / 3 Important / 0 Minor")
   - User decision (author flow: fixed-now / deferred / proceeded-as-is; reviewer flow: posted line-level / posted summary / fixed+pushed / skipped)
   - **Suggested next steps** (pick what applies):
     - Wants clarity polish after fixes → run the native `/simplify` (clarity-only, behavior-preserving) as follow-up (NOT part of kbg:review-pr itself)
     - At PR-ready → `/ship-merge` (or push for review)
     - Review needs another pass after fixes → **branch on `$LOOP_EXIT`/`$LOOP_REASON` from step
       1** (ADR 0009's bounded auto-loop, same no-re-derive rule as step 1) — this renders from it:
       - **`$LOOP_EXIT == 0` (continue):** render `Round {round} — Critical {prev}→{now}, Important
         {prev}→{now} → convergence: progressing, auto-continuing to round {round+1}.` then
         **actually re-invoke `kbg:review-pr` from Phase 1 on the same branch**, without waiting
         for a fresh human prompt — nothing else in the skill is bypassed (Phase 6 still asks the
         human; Phase 1's own dispatch-mode `AskUserQuestion` still fires on its normal triggers).
         `REVIEW_PR_ROUND_CEILING=1` disables auto-continue with no code change, as a rollback.
       - **`$LOOP_EXIT != 0` (stop):** drop the re-run suggestion; render the per-`$LOOP_REASON`
         message: `../review-pr/reference.md` § Loop Reason Stop Messages — interpolate
         `{round}`/`{prev}`/`{now}`/`{N}`/`{churn_files}` from step 1's stdout as that section
         specifies. Any non-`converged` reason that blocks a merge does so via `/ship-merge`'s
         Critical-findings/`force_human` scoring (0 → hits the 40 floor → STOP) — the human
         decision is required before merge, not optional.
     - Reviewer comments came back externally → `/address-review`
     - Reviewer flow (PR #N), review posted → done; ping the author / await their `/address-review`
3. **Submit the review to GitHub** (gated — never auto-submit; posting a review is outward-facing). Posts findings as line-level comments, not a bare summary.

   **Build the review payload** (event/body/comments-array construction), the two entry points
   (reviewer-flow vs. author-flow, each gated on user confirmation so the submit ask never fires
   twice), and the exact `gh api` JSON-build command: `../review-pr/reference.md` § Build the
   Review Payload.
4. **Clean up the worktree** if Phase 2 created one: `cd` back to the repo dir, then `git worktree remove "$WT" --force`.

---

**Reference tables** (aspect routing, agent descriptions, tips, workflow examples):
`../review-pr/reference.md`.

**Done when**: Phase 6's decision has been recorded, the review-state checkpoint and the
auto-loop verdict are written, the review payload (if any) has been submitted per the recorded
decision, and the worktree (if any) is cleaned up.
