---
name: address-review
description: "Triage + respond to open PR review comments (fetch, classify, fix via mattpocock-skills:diagnosing-bugs, reply). Say 'address review/แก้ตามรีวิว'. Don't use to review (mattpocock-skills:code-review) or merge (mh:ship-merge)."
argument-hint: Optional PR number
disable-model-invocation: true
disable-model-invocation-reason: external write — posts replies to GitHub PR review threads
model: inherit
effort: high
---

# Address Review

You are helping a developer respond to PR review feedback from someone else (human reviewer, mattpocock-skills:code-review, code-review-graph, external tool). Discipline: triage before fixing, fix in clusters, reply per-thread with a sha citation, leave zero open actionable threads on exit.

**Needs**: the `gh` CLI installed and authenticated (`gh auth status`) — every phase below reads/writes PR review threads through it.

## Core Principles

- **Zero open actionable threads on exit.** Phase 5 is non-negotiable — every actionable thread gets a reply (sha citation, wontfix rationale, or clarifying question); pushing fixes silently is incomplete work. Exception: if the user explicitly says mid-session they're abandoning the PR (Phase 7's "abandoned" bullet), that overrides this rule — don't insist on replying before honoring it, and don't invent a reason those threads were exempt from triage.
- **Cite the sha.** Replies that addressed a comment must include the commit sha that fixed it plus a one-line summary — reviewers shouldn't have to re-read the diff to figure out what changed.
- **Triage before fix.** Phase 2 gates Phase 4 — don't edit code until classifications are user-approved, avoiding fixing things that should've been wontfix and skipping things that should've been fixed.
- **Use gh CLI.** All GitHub ops via `gh`, never raw `curl` (per repo convention + memory `feedback_prefer_gh_cli_for_github`).
- **Delegate bugs.** Phase 4 routes bug-shaped comments to `mattpocock-skills:diagnosing-bugs` instead of fixing inline — gets the full feedback-loop → reproduce → minimise → hypothesise → regression-test discipline.
- **Use TodoWrite.** Track phases + per-thread state so the user sees triage decisions + sha mapping at any point.

---

## Phase 1: Fetch Threads

**Goal**: Get every open review thread + comment into structured state. Don't lose any.

Initial input: $ARGUMENTS

**Actions**:
1. Resolve PR + pin review window:
   - No args → `gh pr view --json number,baseRefName,headRefName,headRefOid,state,url` (current branch's PR)
   - `<n>` → `gh pr view <n> --repo "$(gh repo view --json nameWithOwner --template '{{.nameWithOwner}}')" --json number,baseRefName,headRefName,headRefOid,state,url`
   - Abort if no PR found OR state != OPEN.
   - **Assert working branch == PR branch before doing anything else in this command.** Run `git rev-parse --abbrev-ref HEAD`; it must equal `headRefName`. If it differs, STOP the entire run — don't fetch, triage, or edit: `git checkout <headRefName>` (if the local branch exists and worktree is clean) or tell the user they're on the wrong branch. This is a whole-flow halt, not just an edit gate — Phase 2's `isOutdated` handling reads the worktree's current state, so a mismatch corrupts triage too, and risks landing fixes on the wrong PR (the `fix/TP-582`-while-addressing-`feature/TP-650` failure mode).
   - Once the branch check passes, confirm local HEAD is current: `git fetch` and compare against `headRefOid` (or `git pull --ff-only` if behind) — branch-name equality alone doesn't catch a stale worktree, which risks an outdated diff or a rejected non-fast-forward push later.
   - Capture **PR_HEAD_AT_FETCH = headRefOid** — the commit the review is triaged against. Phase 4 commits land after this; Phase 5 citations reference the NEW shas, not this one.
2. Fetch all review threads via **GraphQL, not REST** — REST's `pulls/<n>/comments` has no resolved-status field, so it can't answer "is this thread open." Run the query in `references/fetch-threads-query.md` via `gh api graphql`, **looping on `pageInfo.hasNextPage`/`endCursor` until false** — an unpaged call silently drops overflow threads, breaking "don't lose any." The reference file has the full field selection (thread id, status, root comment ids).
3. Fetch overall reviews: `gh pr view <n> --json reviews` — capture review-level state (CHANGES_REQUESTED / APPROVED / COMMENTED), reviewer, and the review's own **`body`** field. A non-empty `body` (reviewers often put the real ask here, not just in line comments) is a first-class Phase 2 triage item with no thread to reply into — address it in code and acknowledge it in the Phase 5 summary instead.
4. **READ holistically** — before grouping or classifying, read every comment body (including review bodies from step 3) in full once, to build a sense of the reviewer's overall concern (theme: "auth handling is sloppy" vs "tests need work" vs "style nits"). This frames Phase 2 triage and prevents missing connections between threads that look unrelated in isolation.
5. Identify open threads — a thread is open iff **`isResolved == false`** (the real field; GraphQL returns pre-grouped threads, so no manual `in_reply_to_id` reconstruction is needed).
6. Output: one entry per open thread — thread node `id`, root comment `databaseId`, author, `path:line`, body excerpt (≤200 chars) — plus one entry per non-empty review body from step 3 (marked `(general)`, no path:line).

---

## Phase 2: Triage

**Goal**: Classify every open thread. Gate on AskUserQuestion before editing code.

**Actions**:
1. For each thread, propose a classification:
   - **actionable** — fix the code
   - **clarify** — reviewer's concern needs more info; reply with a question
   - **wontfix** — disagree or out-of-scope; reply with rationale, leave thread open
   - **out-of-scope** — track as follow-up issue, reply pointing to the issue
   - **`isOutdated` threads** (from Phase 1): the code at that `path:line` has since moved or been rewritten — read the file's current state before classifying; the comment may be moot (code deleted/replaced) or apply at a different line, so don't classify off the stale diff position. If it's moot because a commit already resolved it (this session or already on the branch) → classify **wontfix**, citing that sha via the "addressed in `<other-place>`" shape. Never `actionable` with nothing left to fix in Phase 4, and never auto-resolve-eligible (only `actionable + fixed` qualifies, per Phase 5 step 1).
2. Present a table to the user:

   ```
   | # | path:line       | reviewer | category      | summary (≤80 chars)     |
   |---|-----------------|----------|---------------|-------------------------|
   | 1 | api/auth.ts:42  | @alice   | actionable    | null-check missing on X |
   | 2 | api/auth.ts:97  | @alice   | clarify       | "is X intentional?"     |
   ...
   ```

   **`summary` must name the concrete risk, not just the location** — "null-check missing on X"
   names the risk; "issue in auth.ts" or "see comment" doesn't. The user approves or revises
   classification from this table alone (step 4's gate), so a location-only summary forces a
   re-read of the original comment before that gate means anything.

3. **Analyze**: ratio of actionable/clarify/wontfix, Critical findings present, reviewer authority (maintainer vs peer), and the user's past triage pattern from memory. **Recommend** the action that clears the most threads with least back-and-forth — name the driving fact in one line (e.g. "12/14 actionable, no Critical → Approve") before the ask, and resolve the matching option's `(best when …)` annotation to `(Recommended)` at render time; if more than one condition plausibly holds, say so instead of picking silently.
4. **AskUserQuestion** single-select: "Phase 2 triage: [N] threads classified ([A] actionable / [C] clarify / [W] wontfix / [O] out-of-scope). Approve these classifications and proceed to implementation?"
   - `Approve — proceed to Phase 3 (best when categories look correct and the plan clears the most threads with least back-and-forth)`
   - `Revise — specify which thread(s) are misclassified (best when a thread's category doesn't match the reviewer's intent)`
   - `Pause — need more context before proceeding (best when the table is incomplete or a reviewer is a required maintainer with unresolved Critical findings)`

**Anti-pattern**: starting Phase 4 on best-guess classifications. Triage is the user's call, not yours.

---

## Phase 3: Plan

See `references/phase3-plan.md` for the full clustering, ordering, and
`mattpocock-skills:diagnosing-bugs` delegation criteria, plus the plain-text-confirm rationale.

---

## Phase 4: Implement

**Goal**: Apply fixes per cluster. Record `sha → thread-ids` mapping for Phase 5.

See `references/phase4-implementation-details.md` for the full per-cluster procedure: pre-implement
verification (verify the reviewer's claim against this codebase before implementing, YAGNI-check
"do it properly" suggestions, author-aware dedup against commits the PR author already made on this
branch), bug-shaped (`mattpocock-skills:diagnosing-bugs`) vs. inline-edit routing (grep every caller, fix sibling call sites
in the same commit — the Ponytail root-cause rule, incident precedent included — commit-message
shape), and the per-cluster test/retry-once/escalate discipline. Any reclassification
(`clarify`/`wontfix`) that surfaces during implementation must be shown to the user before Phase 5 —
it's a new decision Phase 2's approval never covered.

**Actions**:
1. Maintain a running mapping: `{sha: [thread-id, ...]}`. This is the input to Phase 5.
2. Conditional agent routing, launched in parallel, for inline-edit clusters only
   (bug-shaped clusters already carry `mattpocock-skills:diagnosing-bugs`'s own
   regression-test + cleanup discipline — don't double-route)
   — see `references/phase4-agent-routing.md` for the full flagged-concern → agent
   mapping.

---

## Phase 5: Reply Per-Thread (the discipline)

**Goal**: Every thread from Phase 1 gets a reply. Zero unaddressed exits.

This phase encodes memory `feedback_reply_after_pr_fix.md`: replies citing sha + summary are part of "done"; pushing fixes silently is incomplete work.

**Actions**:
1. **Ask once, up front**: `AskUserQuestion` single-select — *"After replying, auto-resolve the actionable threads you fixed?"*:
   - `Leave open (Recommended)` — reviewer verifies and resolves. Default. The reply (sha + summary) is correct maker output; closing the reviewer's thread on their behalf is the maker asserting the verifier's job — the exact circularity kbg's verifier-separation model exists to prevent.
   - `Auto-resolve fixed threads` — after replying, resolve every `actionable + fixed` thread. Never `wontfix` / `clarify` / `out-of-scope` — those stay open by design regardless of this choice.
2. For EVERY line-level thread from Phase 2, post a reply via `gh api "repos/{owner}/{repo}/pulls/<n>/comments" --method POST --field body="<text>" --field in_reply_to=<databaseId>` (root comment's `databaseId` from Phase 1). Use the reply shapes in `references/reply-templates.md` §"Reply Comment Templates" (Fixed / Wontfix / Clarify / Out-of-scope, plus §"Blending a sha into Wontfix / Clarify" for a stalled-but-partially-fixed cluster) — the single source. For non-empty **review-body** items from Phase 1 step 3 (no thread to reply into), post `gh pr comment <n> --body "<text>"` instead. Per category:
   - **actionable + fixed** → post the `Fixed in <sha>: …` reply; if auto-resolve was chosen in step 1, resolve the thread's node `id` (not `databaseId`) via `resolveReviewThread` — see `references/phase5-reply-mechanics.md` for the exact call, write-access requirement, and `unresolveReviewThread` reversal. If "leave open" was chosen, skip resolution — the reply alone is this thread's output.
   - **wontfix** → post the rationale reply. Leave thread open.
   - **clarify** → post the question reply. Leave thread open.
   - **out-of-scope** → post the `Tracked as #<issue-number>` reply. Leave thread open — same as wontfix and clarify, per step 1's auto-resolve rule (only `actionable + fixed` is ever eligible).
3. **Verify gate**: count line-level threads from Phase 1 == thread-replies posted, AND count non-empty review-body items == acknowledgment comments posted — two separate tallies, since a review body was never going to get a thread-reply and folding it in either false-alarms or false-passes. If either tally is short, STOP and reply to the missed ones before continuing.
4. Surface a summary: `N threads addressed (X fixed / Y wontfix / Z clarify / S out-of-scope)` + `M review-body items acknowledged` + (if auto-resolve chosen) `R threads resolved`. `N` is line-level only (`X+Y+Z+S == N`); `M` is a separate tally, never folded in (per step 3's dual-tally gate). See `references/phase5-reply-mechanics.md` for a worked example.

**Anti-patterns**: see `references/reply-templates.md` §"Anti-patterns (author)" — silent push, performative agreement, defensive tone. The sha citation + one-line summary IS the acknowledgment; skip the social ceremony.

> **Templates**: `references/reply-templates.md` is the single source for §"Review Comment Templates" and §"Reply Comment Templates".

---

## Phase 6: Re-Request Review + Verify

See `references/phase6-verify.md` for the full procedure (push, draft-ready toggle,
re-request-review criteria including the required-vs-non-required-reviewer
distinction, and the CI check).

---

## Phase 7: Summary

See `references/phase7-summary.md` for the full report shape (thread/review-body
breakdown and the suggested-next-step branch table including the "abandoned"
definition and its false-trigger guard).

---

## Integration Notes (Project-Specific)

See `references/integration-notes.md` — METHODOLOGY alignment, memory dependencies, bug-diagnosis delegation, active hooks, agent-routing, thread auto-resolve default, and fork-PR handling.
