---
name: review-pr-finish
description: "Present kbg:review-pr's tiered findings, decide submit/fix, write review state and loop verdict. Use when kbg:review-pr-tier hands off. Don't use for self-invoked or standalone review."
metadata:
  origin: kbg
---

# Comprehensive PR Review — Present + Summary (Phases 6-7)

Final link in the `kbg:review-pr` → `kbg:review-pr-tier` → `kbg:review-pr-finish` chain — see
`kbg:review-pr-tier`'s own header for why this split exists (harness-audit's 20,000-char
threshold + auto-compaction re-attachment protection). Never invoked directly by a user or
standalone — `kbg:review-pr-tier`'s Phase 5 calls `Skill(kbg:review-pr-finish)` as a mandatory
next step once findings are tiered.

**First action — read the checkpoint, before anything else**, same fail-closed discipline as
`kbg:review-pr-tier`:

```bash
CKPT_JSON=$(bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/read-review-checkpoint.sh" 5 "$HEAD_SHA" "${WT:-}")
```

Use the `$HEAD_SHA` you already hold from the hand-off — this script does not call `git` itself.
**On any non-zero exit: stop, name the exact `reason=` token, tell the human plainly** — do not
guess or proceed on partial/assumed values. On success, parse `base_sha`, `agent_findings`,
`dispatch_failures`, and `tier_list` out of `$CKPT_JSON`. **Derive, don't re-store**:
`CRITICAL_COUNT`/`IMPORTANT_COUNT`/`MINOR_COUNT` and `FINDING_FILES` come from counting/filtering
`tier_list` — they were never separately checkpointed.

---

## Phase 6: Present + User Decision

**Goal**: Show tier-grouped findings, then branch on the review target (set in Phase 1): **own current branch** → fix decision (fixes land in the working tree); **PR by number** → the submit decision. For a reviewer, choosing how to submit the review *is* acting on the findings — there is no "fix later", and in-place fixes in the throwaway worktree are discarded at Phase 7 cleanup unless pushed. This is the **single submit gate**; Phase 7 executes the choice, it does not re-ask.

**This gate requires an actual answer from the user — it is not a formality to self-answer when no one is available to respond.** If there is no way to get a real answer (no interactive session, `AskUserQuestion` genuinely unavailable, unattended/headless invocation), do not pick an action-taking option yourself and let Phase 7 execute it on the user's behalf. Default to the non-mutating choice for the active branch instead — `Fix later` on branch A, `Skip — I'll post manually` on branch B — and say plainly that the decision was deferred for lack of confirmation, not made for the user. Confirmed failure mode: an unattended run picked "fix Critical + Important now" as its own default and then actually committed the fixes, off a request that only asked for a review.

**Actions**:
1. **If `JIRA_KEY` was set, present the ticket-quality report first**, as its own section before
   the code findings, never blended into the tiers — template and the terminal-only constraint
   (safety-load-bearing, repeated here rather than only in the reference file):
   `../review-pr/reference.md` § Requirement Analysis Presentation. **This section never feeds
   the posted review body, on either review target** — Phase 7's review-body construction starts
   from the code findings below only; ticket content never lands in a public GitHub comment.

   Then present code findings in this format:

   ```markdown
   # PR Review Summary

   ## Critical (X found) — must fix before merge
   - [agent-name]: Issue description [file:line]

   ## Important (X found) — should fix before merge
   - [agent-name]: Issue description [file:line]

   ## Minor (X found) — nice to have
   - [agent-name]: Suggestion [file:line]
   ```

   A finding demoted by `kbg:review-pr-tier`'s Phase 5 step 3.5 verifier carries its tag into whichever tier it landed in: `- [code-reviewer] [verifier-refuted, confidence: 0.85]: Issue description [file:line]` — still visible, just at a lower tier, never silently dropped.

   For tiers with zero findings, list as `Critical: 0 ✅` (explicit green light — agents are issues-only by frontmatter, so empty tier = clean signal, not "we forgot to check"). **Carry step 3.6's provenance onto the green light so the user stamps the code, not the summary** — a bare `Critical: 0 ✅` is exactly the rubber-stamp the verifier-separation principle warns about. Append the re-hunt outcome: `Critical: 0 ✅ · adversarial re-hunt ran clean` (non-trivial diff, hunter found nothing), `Critical: 0 ✅ · re-hunt skipped — trivial diff` (single non-test file), or `Critical: 0 — re-hunt did not return, verdict incomplete` (hunter errored/timed out; do not print an all-clean verdict). **If the checkpoint recorded any `dispatch_failures`, list them first and do not print an all-clean verdict** — `Dispatch: security-reviewer did not return — verdict incomplete, do not treat as clean` — a non-returning agent blocks the green light regardless of what the other agents found.

   After the tier table, surface a **1-line ledger trend** (read `../review-pr/ledger.md` § Aggregation — rolling 10 sessions, computed by the awk helper in `../review-pr/policy.md`):
   ```markdown
   **Trend (last 10 sessions)**: Q1: 12% (was 8%) — stable · Q2: 18% (was 22%) — improving · Q3: 67% (was 45%) — WORSENING · Q4: 8% (was 6%) — stable
   ```
   A `WORSENING` flag means the policy is *eligible* to tighten the Q this session (see `kbg:review-pr-tier`'s Phase 5 step 5). The user already saw the tightening note there; the trend line here is the *delta* since the last session. If fewer than 5 sessions of history exist, surface `insufficient data` instead of percentages.

   **Proof-verification check** (own-branch flow only — Rule 4, define done, loop until verified): a PR-by-number review runs in a throwaway worktree with no `.scratch/` of its own, so this check does not apply there. On your own branch, look for `.scratch/<slug>/proofs/`. If absent and the task is non-trivial (≥2 files changed or ≥1 test file touched), flag as **[verification-gap] must-fix** — independent proof is required before merge. If present, verify at least one artifact is non-empty (test output, type-check output, or adversarial review). Surface: `Proof: 2 artifacts (test + typecheck) ✅` or `Proof: missing — must-fix`.

2. **Branch on review target (from Phase 1):**

   **A. Reviewing the current branch (your own working tree)** — fixes land directly, so go straight to the fix decision:
   - **Self-consistency**: skip this ask only when Critical/Important/Minor are all 0 **and** none of this file's own must-fix conditions are active — no `dispatch_failures`, re-hunt status isn't `incomplete`, and the proof-verification check above doesn't flag `[verification-gap] must-fix`. All-zero tiers with any of those still active is not a clean pass — surface the gap, don't skip the ask. Only when every condition clears: state "Clean pass, proceeding," record the decision as `proceeded-as-is` (step 3), and go straight to Phase 7.
   - **Auto-proceed on Minor-only** (`ACS:minor-only-auto-proceed`): also skip the ask (auto-proceed, defer) when **Critical == 0 AND Important == 0** — only Minor (cosmetic) findings remain — **and** none of the must-fix conditions above are active (no `dispatch_failures`, re-hunt not `incomplete`, no `[verification-gap] must-fix`). State: "Phase 6: 0 Critical, 0 Important, N Minor (cosmetic) — proceeding, Minor findings deferred as follow-up. Say 'fix all' to address them now." Record the decision as `proceeded-as-is` with the deferred Minor findings captured as a follow-up, and go straight to Phase 7. This is the non-mutating default the header above names for the unattended case — taken without asking only where the deterministic tier-count fully covers the decision. Important findings stay human-gated: Important = "should fix before merge" (a real but contained issue where fix-now-vs-defer is a judgment call the deterministic score does NOT vouch — `harness-decay-cadence.md:102`: "Automate past the point where you can still vouch for the output and you ship agent slop"). The Critical/Important tier counts this rests on are already independently verified by `kbg:review-pr-tier`'s Phase 5 step 3.5 fresh-agent verifier, so they are not the maker's self-report.
   - **AskUserQuestion** single-select (only when at least one Critical **or** Important finding remains): "Phase 6: [N] Critical (must fix before merge), [N] Important (should fix before merge), [N] Minor (nice to have). My recommendation: [option]. How do you want to proceed?"
     - `Fix Critical issues now, proceed with Important/Minor later (best when Critical count is low and the user wants to keep momentum)`
     - `Fix Critical + Important now, Minor later (best when both tiers have real issues that shouldn't ship)`
     - `Fix all tiers now before proceeding (best when review surfaced significant problems across all tiers)`
     - `Proceed as-is — acknowledge risk (only when findings are false positives or truly cosmetic)` — revisit if a later change touches the same file:line and the "cosmetic" call turns out wrong; don't re-litigate otherwise

   **B. Reviewing a PR by number (isolated, throwaway worktree)** — the decision *is* what review to submit to the author. **First build the review payload** (per `../review-pr/reference.md`'s "Build the Review Payload" procedure) and show the preview, then ask **once** — Phase 7 executes the choice without re-asking:
   - **Preview** (show before the question):
     - Event type — `REQUEST_CHANGES` if any Critical, `COMMENT` if only Important/Minor, `APPROVE` if zero findings
     - Number of line-level comments to be posted
     - 2–3 sample comments (what the author will see)
     - Review body (the tier table + trend + proof-check from step 1 — **not** the Requirement Analysis section, which is terminal-only per step 1 and never posted)
   - **Prior-review check**: `gh pr view <#> --json reviews -q ".reviews[].author.login"` vs `gh api user -q .login`. If you already reviewed this PR, warn that GitHub stacks new reviews (no update-in-place) before asking.
   - **AskUserQuestion** single-select: "Phase 6: reviewing PR #N — [N] line-level comments + [event type], previewed above. My recommendation: [option]. How do you want to act on these findings?"
     - `Post line-level review now (best when findings are concrete — the author sees each issue in context)` — batch via `gh api` (Phase 7)
     - `Post summary only (best when line-level comments would be noisy or the diff is trivial)` — single `gh pr review --body` (Phase 7)
     - `Fix + push to the PR branch (only if you have write access / it's your own PR — worktree fixes are discarded unless committed + pushed)` — apply fixes in `$WT`, commit, push before Phase 7 cleanup
     - `Skip — I'll post manually (best when the body needs rephrasing or the PR isn't ready for external review)` — nothing posted; revisit if the PR sits unreviewed past this session — Phase 2's pinned window goes stale, and a fresh `kbg:review-pr` re-run is cheaper than manually authoring from old findings
   - To tweak the top-level body first, pick a post option and say so (or answer Other) — adjust the body, then proceed.

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
   # Collect the file paths holding Critical+Important findings this round —
   # feeds the cross-pass convergence gate's file-level finding-identity tracking.
   # Sort + dedup so the set-diff against last round is stable.
   FINDING_FILES_TMP="${TMPDIR:-/tmp}/review-pr-findings-$$"
   printf '%s\n' "${FINDING_FILES[@]}" | sort -u > "$FINDING_FILES_TMP"
   bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/write-review-state.sh" \
     "${CRITICAL_COUNT:-0}" "${REHUNT_STATUS:-n/a}" "${DISPATCH_FAILURES:-}" "$HEAD_SHA" "${WT:-}" \
     "${IMPORTANT_COUNT:-0}" "${MINOR_COUNT:-0}" "$FINDING_FILES_TMP"

   # Immediately after: the bounded auto-loop's continue/stop decision (ADR
   # 0009). Same $HEAD_SHA/$WT this round's write above just used — confirms
   # the state file this reads back is THIS round's write, not stale.
   if LOOP_DECISION=$(bash "${KBG_PLUGIN_ROOT}/skills/review-pr/scripts/should-continue-loop.sh" "$HEAD_SHA" "${WT:-}"); then
     LOOP_EXIT=0
   else
     LOOP_EXIT=$?
   fi
   LOOP_REASON=$(printf '%s\n' "$LOOP_DECISION" | sed -n 's/^reason=//p')
   ```
   `FINDING_FILES` = the set of file paths from the tiered Critical + Important findings (the files
   that actually hold a must-fix this round — derived from the checkpoint's `tier_list`, not
   separately tracked). Build it as a bash array as you read `tier_list`, one entry per distinct
   file with a Critical or Important finding. Pass it through the temp file (not an env var) for
   the same positional-arg reason as the counts below. **Entries must be repo-relative** (matching
   Phase 7 step 3's `comments[].path` convention below) — the same file reported as `$WT`-absolute
   in one round and repo-relative in another reads as two different identities to both `regressed`
   and the churn-streak tracker (both are exact-string set comparisons). The script normalizes a
   leading `/` defensively, but don't rely on that — report repo-relative at the source.
   Positional, not inherited env, on purpose: pass the actual values you're holding at this point
   in the phase (`CRITICAL_COUNT`/`IMPORTANT_COUNT`/`MINOR_COUNT` derived from `tier_list`,
   `REHUNT_STATUS` from `kbg:review-pr-tier`'s step 3.6, `DISPATCH_FAILURES` from the checkpoint,
   `HEAD_SHA`/`WT` from the checkpoint) as literal arguments — an inherited-but-unexported shell
   variable fails silently across the nested bash invocation this script call is.
   **stdout contract, and what a non-zero exit does/doesn't mean about whether anything was
   written:** `../review-pr/reference.md` § write-review-state.sh — Field Contract & Amend Mode.
   Step 2's round-aware footer renders directly from that stdout — don't re-derive it by
   re-reading the state file back.

   **`should-continue-loop.sh`'s exit code (`$LOOP_EXIT` above) is what step 2 branches on to
   decide auto-continue** — never re-derive this from `round`/`stalled`/`force_human`/
   `convergence_state` yourself; that re-derivation is exactly the sync-seam this script exists to
   close. `0` = continue automatically; any non-zero = stop and hand back to a human, with
   `$LOOP_REASON` naming why (`converged`/`regressed`/`churning`/`stalled`/`ceiling` mirror
   `convergence_state`; `missing-state`/`malformed-state`/`stale-sha`/`malformed-round`/
   `malformed-force-human`/`malformed-convergence-state`/`malformed-finding-files`/
   `no-findings-nonclean` are fail-closed integrity stops; `reviewer-flow` means this is a
   PR-by-number review — auto-continue is `own-branch`-only, since a reviewer can't act on
   someone else's diff). Full script: `../review-pr/scripts/should-continue-loop.sh`.

   **Field contract, `amend` mode for correcting a wrong value after the write already happened
   (with the production incidents behind each guard), and the `CRITICAL_COUNT`/`rehunt`/
   `review_mode` field semantics:** `../review-pr/reference.md` § write-review-state.sh — Field
   Contract & Amend Mode.
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
       1** (ADR 0009's bounded auto-loop) — never re-derive this from `round`/`stalled`/
       `force_human`/`convergence_state` yourself; `should-continue-loop.sh` is the single source
       of the decision, this renders from it:
       - **`$LOOP_EXIT == 0` (continue):** render `Round {round} — Critical {prev}→{now}, Important
         {prev}→{now} → convergence: progressing, auto-continuing to round {round+1}.` then
         **actually re-invoke `kbg:review-pr` from Phase 1 on the same branch**, without waiting
         for a fresh human prompt. Phase 6 in the new round still asks the human as today; Phase
         1's own dispatch-mode `AskUserQuestion` (if its trigger conditions are met) still fires
         exactly as on any invocation — auto-continue only removes the "should I re-invoke at all"
         click, nothing else in the skill is bypassed. `REVIEW_PR_ROUND_CEILING=1` disables
         auto-continue immediately with no code change, if ever needed as a rollback.
       - **`$LOOP_EXIT != 0` (stop):** drop the re-run suggestion; render the per-`$LOOP_REASON`
         message from `../review-pr/reference.md` § Loop Reason Stop Messages (`converged` /
         `regressed` / `churning` / `stalled` / `ceiling` / `reviewer-flow` / the integrity-stop
         reasons / `no-findings-nonclean`) — interpolate `{round}`/`{prev}`/`{now}`/`{N}`/
         `{churn_files}` from step 1's stdout as that section specifies. Any non-`converged`
         reason that blocks a merge does so via `/ship-merge`'s Critical-findings/`force_human`
         scoring (0 → hits the 40 floor → STOP) — the human decision is required before merge,
         not optional.
     - Reviewer comments came back externally → `/address-review`
     - Reviewer flow (PR #N), review posted → done; ping the author / await their `/address-review`
3. **Submit the review to GitHub** (gated — never auto-submit; posting a review is outward-facing). Posts findings as **individual line-level review comments** so the author sees each issue in context — not just a single top-level summary.

   **Build the review payload** (event/body/comments-array construction), the two entry points
   (reviewer-flow vs. author-flow, each gated on user confirmation so the submit ask never fires
   twice), and the exact `gh api` JSON-build command: `../review-pr/reference.md` § Build the
   Review Payload.
4. **Clean up the worktree** if Phase 2 created one: `cd` back to the original repo dir, then `git worktree remove "$WT" --force`.

---

**Reference tables** (aspect routing, agent descriptions, tips, workflow examples):
`../review-pr/reference.md`.

**Done when**: Phase 6's decision has been recorded, the review-state checkpoint and the
auto-loop verdict are written, the review payload (if any) has been submitted per the recorded
decision, and the worktree (if any) is cleaned up.
