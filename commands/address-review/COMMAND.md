---
name: address-review
description: "Triage + respond to open PR review comments (fetch, classify, fix via /fix-bug, reply). Say 'address review/แก้ตามรีวิว'. Don't use to review (kbg:review-pr) or merge (/ship-merge)."
argument-hint: Optional PR number
disable-model-invocation: true
disable-model-invocation-reason: external write — posts replies to GitHub PR review threads
---

# Address Review

You are helping a developer respond to PR review feedback from someone else (human reviewer, review-pr, code-review-graph, external tool). Follow the discipline: triage before fixing, fix in clusters, reply per-thread with a sha citation, leave zero open actionable threads on exit.

## Core Principles

- **Zero open actionable threads on exit.** Phase 5 is non-negotiable — every actionable thread gets a reply (sha citation, wontfix rationale, or clarifying question). Pushing fixes silently is incomplete work (encoded in memory: `feedback_reply_after_pr_fix`).
- **Cite the sha.** Replies that addressed a comment must include the commit sha that fixed it + a one-line summary of the change. Reviewers shouldn't have to re-read the diff to figure out what changed.
- **Triage before fix.** Phase 2 gates Phase 4 — don't start editing code until classifications are user-approved. Avoids fixing things that should have been wontfix and skipping things that should have been fixed.
- **Use gh CLI.** All GitHub operations via `gh`, never raw `curl` (per repo convention + memory `feedback_prefer_gh_cli_for_github`).
- **Delegate bugs.** Phase 4 routes bug-shaped comments to `/fix-bug` rather than fixing inline — gets the full reproduce → minimise → hypothesize → TDD discipline.
- **Use TodoWrite.** Track phases + per-thread state so the user can see triage decisions + sha mapping at any point.

---

## Phase 1: Fetch Threads

**Goal**: Get every open review thread + comment into structured state. Don't lose any.

Initial input: $ARGUMENTS

**Actions**:
1. Resolve PR + pin review window:
   - No args → `gh pr view --json number,baseRefName,headRefName,headRefOid,state,url` (current branch's PR)
   - `<n>` → `gh pr view <n> --repo "$(gh repo view --json nameWithOwner --template '{{.nameWithOwner}}')" --json number,baseRefName,headRefName,headRefOid,state,url`
   - Abort if no PR found OR state != OPEN.
   - **Assert working branch == PR branch before doing anything else in this command.** Run `git rev-parse --abbrev-ref HEAD`; it must equal `headRefName`. If it differs, STOP the entire run here — don't fetch threads, don't triage, don't edit: either `git checkout <headRefName>` (local branch exists + worktree clean) or tell the user they're on the wrong branch. This is a whole-flow halt, not just an edit gate: Phase 2's `isOutdated` handling reads the file's *current* state off the local worktree, so continuing past a branch mismatch risks triaging off the wrong branch's file content, not just editing on the wrong branch. Editing the current worktree while it sits on a different branch also lands fixes on the wrong PR (the `fix/TP-582`-while-addressing-`feature/TP-650` failure mode).
   - Once the branch check passes, confirm local HEAD is current before any edit lands: `git fetch` and compare against `headRefOid` (or just `git pull --ff-only` if behind). Branch-name equality alone doesn't catch a worktree that's on the right branch but stale — editing there risks a diff based on outdated context or a rejected non-fast-forward push later.
   - Capture **PR_HEAD_AT_FETCH = headRefOid** — this is the commit Claude sees the review against. Phase 4 commits land AFTER this; Phase 5 citations reference the NEW shas, not `PR_HEAD_AT_FETCH`. Pinning makes "what was the PR state when the review was triaged?" answerable.
2. Fetch all review threads via **GraphQL, not REST** — the REST `pulls/<n>/comments` endpoint has no resolved-status field at all, so it cannot answer "is this thread open." Run the exact query in `references/fetch-threads-query.md` via `gh api graphql`. **Loop on `pageInfo.hasNextPage`/`endCursor` until false** — a single unpaged call silently drops overflow threads, which breaks "don't lose any"; the reference file has the full field-selection detail (thread id, resolved/outdated status, root comment ids for Phase 5 replies).
3. Fetch overall reviews: `gh pr view <n> --json reviews` — capture review-level state (CHANGES_REQUESTED / APPROVED / COMMENTED), which reviewer left it, and the review's own **`body`** field. A non-empty `body` (verified live: reviewers routinely put the actual substantive ask here, not just in line comments) is a first-class item to triage in Phase 2 — it has no thread to reply into or resolve, so address it in code and acknowledge it in the Phase 5 summary rather than expecting a thread-reply.
4. **READ holistically** — before grouping or classifying, read every comment body (including review bodies from step 3) in full once. Build a holistic sense of what the reviewer is concerned about overall (theme: "auth handling is sloppy" vs "tests need work" vs "just style nits"). This frames the per-thread triage in Phase 2 and prevents missing connections between threads that look unrelated in isolation.
5. Identify open threads — a thread is open iff **`isResolved == false`** (the real field; GraphQL returns pre-grouped threads, so no manual `in_reply_to_id` reconstruction is needed).
6. Output: structured list — one entry per open thread, with thread node `id` + root comment `databaseId` + author + `path:line` + body excerpt (≤200 chars), plus one entry per non-empty review body from step 3 (marked `(general)`, no path:line).

---

## Phase 2: Triage

**Goal**: Classify every open thread. Gate on AskUserQuestion before editing code.

**Actions**:
1. For each thread, propose a classification:
   - **actionable** — fix the code
   - **clarify** — reviewer's concern needs more info; reply with a question
   - **wontfix** — disagree or out-of-scope; reply with rationale, leave thread open
   - **out-of-scope** — track as follow-up issue, reply pointing to the issue
   - **`isOutdated` threads** (from Phase 1): the code at that `path:line` has since moved or been rewritten — read the file's *current* state before classifying. The comment may already be moot (code deleted/replaced) or still apply at a different line; don't classify off the stale diff position alone. If it's moot because a commit already resolved it (whether landed this session or pre-existing on the branch before this run started) → classify **wontfix**, cite that commit's sha via the "addressed in `<other-place>`" reply shape. Never `actionable` for a thread with nothing left to fix in Phase 4 — and never auto-resolve-eligible, since only `actionable + fixed` qualifies for auto-resolve in Phase 5 step 1.
2. Present a table to the user:

   ```
   | # | path:line       | reviewer | category      | summary (≤80 chars)     |
   |---|-----------------|----------|---------------|-------------------------|
   | 1 | api/auth.ts:42  | @alice   | actionable    | null-check missing on X |
   | 2 | api/auth.ts:97  | @alice   | clarify       | "is X intentional?"     |
   ...
   ```

3. **Analyze**: ratio of actionable vs clarify vs wontfix, presence of Critical findings, reviewer authority (maintainer vs peer), and user's past triage pattern from memory. **Recommend** the action that clears the most threads with least back-and-forth.
4. **AskUserQuestion** single-select: "Phase 2 triage: [N] threads classified ([A] actionable / [C] clarify / [W] wontfix / [O] out-of-scope). Approve these classifications and proceed to implementation?"
   - `Approve — proceed to Phase 3 (best when categories look correct and the plan clears the most threads with least back-and-forth)`
   - `Revise — specify which thread(s) are misclassified (best when a thread's category doesn't match the reviewer's intent)`
   - `Pause — need more context before proceeding (best when the table is incomplete or a reviewer is a required maintainer with unresolved Critical findings)`

**Anti-pattern**: starting Phase 4 implementation on best-guess classifications. Triage is the human/user's call, not yours.

---

## Phase 3: Plan

**Goal**: Cluster + order the actionable threads. Identify which ones route to `/fix-bug`.

**Actions**:
1. Cluster related comments — same file, same concern, same fix. One cluster → one commit (where possible).
2. Order clusters: critical (security / data correctness) → high → low. Wontfix / clarify / out-of-scope clusters skip implementation; queued for Phase 5.
3. Mark bug-shaped clusters for `/fix-bug` delegation:
   - Reviewer described observable wrong behavior + can be reproduced
   - Reviewer's concern is a missing edge case in a code path
4. Present plan to user. Confirm before Phase 4 — a plain-text acknowledgment is enough here (unlike Phase 2/5's `AskUserQuestion` gates): the plan is a re-ordering of choices the user already approved in Phase 2, not a new classification decision.

---

## Phase 4: Implement

**Goal**: Apply fixes per cluster. Record `sha → thread-ids` mapping for Phase 5.

**Actions**:
1. **Pre-implement verification** (per cluster, before editing — external reviewers including LLM-based ones often lack codebase context):
   - **Verify the claim against THIS codebase**: read the code the reviewer is commenting on. Check whether their suggested fix is technically correct for the current context (existing patterns, constraints, dependencies). If the suggestion is wrong or context-blind, re-classify the cluster (move to `clarify` with a pushback question, or `wontfix` with a technical rationale) — don't blindly implement. Default to `wontfix` when the counter-evidence is direct, written, and dated (a runbook, a comment, a prior decision record); default to `clarify` when it's inferred or the reviewer might be citing information this pass doesn't have. Same as the YAGNI bullet below, surface every reclassified cluster to the user before Phase 5 posts its reply — a reclassification is a new decision Phase 2's approval never covered, and posting it unreviewed can push back on a blocking reviewer with no human checkpoint in between.
   - **YAGNI check on "do it properly" suggestions**: if the reviewer says "implement properly" / "expand this" / "refactor to support X", grep the codebase for actual usage of the affected code path first. Unused endpoints/functions should be deleted, not expanded. Surface DELETE as an alternate proposal to the user before implementing any expansion.
   - **Author-aware dedup**: skip re-firing a fix on a thread already addressed *more recently* than the reviewer's comment by a commit on this branch authored by the PR's own author (compare the thread's `originalCommit.oid` / `created_at` from Phase 1 against `git log --format='%H %an %s' <headRefName>` filtered to that author — this covers the whole branch history, not just commits made earlier in this Phase 4 pass). Re-acting on an already-handled thread is how an uncapped fix loop churns no-op commits. This is the same "already resolved, just not by this pass" situation as the `isOutdated` case above — handle it the same way: re-classify to `wontfix`, cite the pre-existing commit's sha via the "addressed in `<other-place>`" reply shape, and surface it to the user alongside the other reclassified clusters. Don't leave it silently `actionable` with nothing in the Phase 4 sha mapping — Phase 5 still needs a reply for it.
2. For each verified actionable cluster (in Phase 3 order):
   - **Bug-shaped** → invoke `/fix-bug` with the reviewer's concern as the bug report. `/fix-bug` usually returns with its own commit sha — capture it. But `/fix-bug` can legitimately stall with no commit (its own "no-progress halts" — a stagnation guard, a different mechanism from this command's per-cluster retry cap below — route to its step-7 "need more investigation" branch instead of committing). If it returns empty-handed, treat that cluster like this command's own retry-cap outcome below: re-classify `clarify` or `wontfix`, no sha to cite, surface why in Phase 5.
   - **Inline edit** → apply the fix directly, commit with a focused message (reference the thread: `fix(auth): null-check user_id (review #thread-1)`). Capture the sha.
   - **Wontfix / clarify / out-of-scope** → skip code; will be handled in Phase 5 reply only.
3. **Per-cluster test step.** After each cluster commits, run any tests relevant to the changed code. If they fail, fix and retry **once (same failure twice is guessing, not fixing — escalate, don't retry again)**; if they still fail, **stop that cluster** — don't keep patching, even if the retry surfaced a *different* failure that looks like an unrelated flake. Re-classify its thread as `clarify` or `wontfix`. (An uncapped per-cluster fix loop is exactly the 80-no-op-"fix CI"-commits failure mode.)
   - **Don't assert an unverified cause.** If the note attributes the residual failure to something ("unrelated flake," "pre-existing issue") without having actually checked, say so as an open question in the reply, not as fact — a reviewer-facing claim about why something broke needs the same evidence bar as any other claim in this command.
   - **A stalled cluster isn't always "nothing fixed."** If a commit landed before the cluster stalled — this Phase 4 pass, or `/fix-bug` per the branch above — the `clarify`/`wontfix` reclassification doesn't erase it: cite the sha and summarize what it changed (per Core Principles' "cite the sha," which isn't scoped to `actionable + fixed` only) *alongside* the clarify question or wontfix rationale in Phase 5 — see `review-pr/reference.md` §"Blending a sha into Wontfix / Clarify" for the shape. Real progress that happened doesn't disappear because the cluster didn't fully resolve.
4. Maintain a running mapping: `{sha: [thread-id, ...]}`. This is the input to Phase 5.
5. Conditional agent routing **launched in parallel** for inline-edit clusters only (bug-shaped clusters get this routing from `/fix-bug`'s own Phase 7 — don't double-route):
   - Reviewer flagged error handling → `silent-failure-hunter` agent on the fix
   - Reviewer flagged auth/secrets/external input → `security-reviewer` agent on the fix
   - Reviewer flagged general correctness → `code-reviewer` agent on the fix

---

## Phase 5: Reply Per-Thread (the discipline)

**Goal**: Every thread from Phase 1 gets a reply. Zero unaddressed exits.

This phase encodes memory `feedback_reply_after_pr_fix.md`: replies citing sha + summary are part of "done"; pushing fixes silently is incomplete work.

**Actions**:
1. **Ask once, up front**: `AskUserQuestion` single-select — *"After replying, auto-resolve the actionable threads you fixed?"*:
   - `Leave open (Recommended)` — reviewer verifies and resolves. Default. The reply (sha + summary) is correct maker output; closing the reviewer's thread on their behalf is the maker asserting the verifier's job — the exact circularity kbg's verifier-separation model exists to prevent.
   - `Auto-resolve fixed threads` — after replying, resolve every `actionable + fixed` thread. Never `wontfix` / `clarify` / `out-of-scope` — those stay open by design regardless of this choice.
2. For EVERY line-level thread classified in Phase 2, post a reply via `gh api "repos/{owner}/{repo}/pulls/<n>/comments" --method POST --field body="<text>" --field in_reply_to=<databaseId>` (the root comment's `databaseId` from Phase 1, identical to a REST comment `id`). Use the reply body shapes in `review-pr/reference.md` §"Reply Comment Templates" (Fixed / Wontfix / Clarify / Out-of-scope, plus §"Blending a sha into Wontfix / Clarify" for a stalled-but-partially-fixed cluster per Phase 4 step 3) — the single source. For non-empty **review-body** items from Phase 1 step 3 (no thread to reply into), post one `gh pr comment <n> --body "<text>"` acknowledging how it was addressed. Per-category thread action:
   - **actionable + fixed** → post the `Fixed in <sha>: …` reply. If the user opted into auto-resolve in step 1, resolve the thread now:
     ```graphql
     mutation($threadId:ID!) {
       resolveReviewThread(input:{threadId:$threadId}) { thread { id isResolved } }
     }
     ```
     via `gh api graphql -F threadId=<id> -f query='<above>'`, using the thread node `id` from Phase 1 (not the comment `databaseId`). Requires repo write access (a PR author's PAT qualifies — verified against GitHub's docs: resolving needs write access, not authorship of the original thread). `unresolveReviewThread` (same shape) reverses it if needed. If the user chose "leave open," skip resolution entirely — the reply alone is this thread's Phase 5 output.
   - **wontfix** → post the rationale reply. Leave thread open.
   - **clarify** → post the question reply. Leave thread open.
   - **out-of-scope** → post the `Tracked as #<issue-number>` reply. Leave thread open — same as wontfix and clarify, per step 1's auto-resolve rule (only `actionable + fixed` is ever eligible).
3. **Verify gate**: count line-level threads from Phase 1 == count of thread-replies posted, AND count non-empty review-body items from Phase 1 step 3 == count of acknowledgment comments posted. Track these as two separate tallies — a review body was never going to get a thread-reply, so folding it into one count either false-alarms (looks like a missed reply) or false-passes (masks an actually-missed thread). If either tally is short, STOP and reply to the missed ones before continuing.
4. Surface a summary to the user: `N threads addressed (X fixed / Y wontfix / Z clarify / S out-of-scope)` + `M review-body items acknowledged` + (if auto-resolve was chosen) `R threads resolved`. `N` is line-level threads only (`X+Y+Z+S == N`) — `M` is a separate tally, never folded into `N` or its breakdown, since a review-body item was never a thread to begin with (per step 3's dual-tally gate). Worked example: 3 line-level threads (2 fixed, 1 wontfix) + 1 non-empty review body acknowledged → `3 threads addressed (2 fixed / 1 wontfix / 0 clarify / 0 out-of-scope)` + `1 review-body item acknowledged` — not `4 threads addressed`.

**Anti-patterns**: see `review-pr/reference.md` §"Anti-patterns (author)" — silent push, performative agreement, defensive tone. The sha citation + one-line summary IS the acknowledgment; skip the social ceremony. Silent push (fixing without per-thread replies) is the failure mode this command exists to prevent.

> **Templates**: `review-pr/reference.md` is the single source for §"Review Comment Templates" and §"Reply Comment Templates".

---

## Phase 6: Re-Request Review + Verify

**Goal**: Move the PR back to reviewer's queue + confirm CI is happy.

**Actions**:
1. Push all Phase 4 commits if not already pushed: `git push`.
2. If the PR was draft (state changed during work) → `gh pr ready <n>`.
3. If the previous review was dismissed-on-push, re-request from the same reviewer: `gh pr edit <n> --add-reviewer @<user>` (or `gh api ... requested_reviewers`).
4. Check CI: `gh pr checks <n>`. If failures, surface to user before declaring done.
5. Output:
   - PR number + URL
   - Commits pushed in this session (sha + 1-line)
   - Thread-to-sha mapping for the user's records
   - CI state

---

## Phase 7: Summary

**Goal**: Document the response cycle.

**Actions**:
1. Mark all todos complete.
2. Summarize:
   - PR # and URL
   - Threads handled — breakdown by category (fixed / wontfix / clarify / out-of-scope)
   - Review-body items acknowledged (separate count, from Phase 5 step 4 — not folded into the thread breakdown above, since it was never a thread)
   - Commits added with sha → thread mapping
   - CI state from Phase 6
   - **Suggested next step:**
     - Fixes pushed, awaiting re-review → await reviewer; ping if urgent
     - Reviewer approves on push        → /ship-merge
     - Another pass wanted before merge → kbg:review-pr
     - wontfix-heavy and abandoned      → `gh pr close <n>`
     - Pushback posted, nothing to push, a required reviewer's block still stands → await their response to the rationale; escalate if unresponsive. Don't reach for `gh pr close` here — no code changed doesn't mean the effort is abandoned, it means the ball is in the reviewer's court.

---

## Integration Notes (Project-Specific)

See `references/integration-notes.md` — METHODOLOGY alignment, memory dependencies, `/fix-bug` delegation recap, hooks active, agent-routing recap, thread auto-resolve default, and fork-PR handling.
