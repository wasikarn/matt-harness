---
name: address-review
description: "Triage and respond to existing PR review comments — fetch threads via gh, classify (action/clarify/wontfix/out-of-scope), implement fixes (delegate to /fix-bug), reply per-thread with commit sha, re-request review. Use when a PR has open review threads, after kbg:review-pr returns findings, or user says 'address the review', or when the user says 'แก้ตามรีวิว', 'ตอบรีวิว', 'address review'. Don't use for: doing the review yourself (use kbg:review-pr), pre-PR cleanup, or merging post-approval (use /ship-merge)."
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
   - **Assert working branch == PR branch before any edit.** Run `git rev-parse --abbrev-ref HEAD`; it must equal `headRefName`. If it differs, STOP — don't edit: either `git checkout <headRefName>` (local branch exists + worktree clean) or tell the user they're on the wrong branch. Editing the current worktree while it sits on a different branch lands fixes on the wrong PR (the `fix/TP-582`-while-addressing-`feature/TP-650` failure mode).
   - Capture **PR_HEAD_AT_FETCH = headRefOid** — this is the commit Claude sees the review against. Phase 4 commits land AFTER this; Phase 5 citations reference the NEW shas, not `PR_HEAD_AT_FETCH`. Pinning makes "what was the PR state when the review was triaged?" answerable.
2. Fetch all review-thread comments: `gh api "repos/{owner}/{repo}/pulls/<n>/comments" --paginate`. Capture comment `id`, `user.login`, `path`, `line`, `body`, `in_reply_to_id` (to identify thread roots vs replies), **`original_commit_id`** (the commit the comment was left against — Phase 5 can show "Fixed in <new-sha> (was flagged at <original_commit_id>)" for traceability), `created_at`.
3. Fetch overall reviews: `gh pr view <n> --json reviews` — capture review-level state (CHANGES_REQUESTED / APPROVED / COMMENTED) and which reviewer left it.
4. **READ holistically** — before grouping or classifying, read every comment body in full once. Build a holistic sense of what the reviewer is concerned about overall (theme: "auth handling is sloppy" vs "tests need work" vs "just style nits"). This frames the per-thread triage in Phase 2 and prevents missing connections between threads that look unrelated in isolation.
5. Identify open threads — group comments by thread (root + replies). A thread is "open" if no comment in the thread says it's resolved AND the GitHub-resolved flag is false.
6. Output: structured list — one entry per open thread, with thread-root comment id + author + `path:line` + body excerpt (≤200 chars).

---

## Phase 2: Triage

**Goal**: Classify every open thread. Gate on AskUserQuestion before editing code.

**Actions**:
1. For each thread, propose a classification:
   - **actionable** — fix the code
   - **clarify** — reviewer's concern needs more info; reply with a question
   - **wontfix** — disagree or out-of-scope; reply with rationale, leave thread open
   - **out-of-scope** — track as follow-up issue, reply pointing to the issue
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
   - `Approve — proceed to Phase 3 (Recommended when categories look correct and the plan clears the most threads with least back-and-forth)`
   - `Revise — specify which thread(s) are misclassified (Recommended when a thread's category doesn't match the reviewer's intent)`
   - `Pause — need more context before proceeding (Recommended when the table is incomplete or a reviewer is a required maintainer with unresolved Critical findings)`

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
4. Present plan to user. Confirm before Phase 4.

---

## Phase 4: Implement

**Goal**: Apply fixes per cluster. Record `sha → thread-ids` mapping for Phase 5.

**Actions**:
1. **Pre-implement verification** (per cluster, before editing — external reviewers including LLM-based ones often lack codebase context):
   - **Verify the claim against THIS codebase**: read the code the reviewer is commenting on. Check whether their suggested fix is technically correct for the current context (existing patterns, constraints, dependencies). If the suggestion is wrong or context-blind, re-classify the cluster (move to `clarify` with a pushback question, or `wontfix` with a technical rationale) — don't blindly implement.
   - **YAGNI check on "do it properly" suggestions**: if the reviewer says "implement properly" / "expand this" / "refactor to support X", grep the codebase for actual usage of the affected code path first. Unused endpoints/functions should be deleted, not expanded. Surface DELETE as an alternate proposal to the user before implementing any expansion.
   - **Author-aware dedup**: skip re-firing a fix on a thread your own commit already addressed *more recently* than the reviewer's comment (compare the thread's `original_commit_id` / `created_at` from Phase 1 against your commits). Re-acting on an already-handled thread is how an uncapped fix loop churns no-op commits.
2. For each verified actionable cluster (in Phase 3 order):
   - **Bug-shaped** → invoke `/fix-bug` with the reviewer's concern as the bug report. `/fix-bug` returns with its own commit sha. Capture it.
   - **Inline edit** → apply the fix directly, commit with a focused message (reference the thread: `fix(auth): null-check user_id (review #thread-1)`). Capture the sha.
   - **Wontfix / clarify / out-of-scope** → skip code; will be handled in Phase 5 reply only.
3. **Per-cluster test step.** After each cluster commits, run any tests relevant to the changed code. If they fail, fix and retry **once (per Rule 12 — escalate sub-rule)**; if they still fail, **stop that cluster** — don't keep patching. Re-classify its thread as `clarify` or `wontfix` with a note explaining the failed fix, and surface it in Phase 5. (An uncapped per-cluster fix loop is exactly the 80-no-op-"fix CI"-commits failure mode.)
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
1. For EVERY thread classified in Phase 2, post a reply via `gh api "repos/{owner}/{repo}/pulls/<n>/comments" --method POST --field body="<text>" --field in_reply_to=<thread-root-id>`:
   - **actionable + fixed** → body: `Fixed in <sha>: <one-line change summary>`. After posting, **prompt the user to resolve** the thread in the GitHub web UI (gh CLI doesn't reliably support thread resolution as of writing — Claude can't do it directly).
   - **wontfix** → body: `<rationale, 1-3 sentences>`. Leave thread open.
   - **clarify** → body: `<specific question to the reviewer>`. Leave thread open.
   - **out-of-scope** → body: `Tracked as #<issue-number> — out of scope for this PR.` Leave open or resolve at user's discretion.
2. **Verify gate**: count threads from Phase 1 == count of replies posted in this phase. If any miss, STOP and reply to the missed ones before continuing.
3. Surface a summary to the user: `N threads addressed (X fixed / Y wontfix / Z clarify / W out-of-scope)`.

**Anti-patterns**:
- **Silent push** — pushing the fix commits and stopping. Without per-thread replies, the reviewer has to re-read the diff to figure out what was addressed. That's the failure mode this command exists to prevent.
- **Performative agreement** — replies like "Great catch!" / "You're absolutely right!" / "Good point, thanks!" violate technical rigor (per obra/superpowers `receiving-code-review` discipline). The sha citation + one-line change summary IS the acknowledgment. Skip the social ceremony — actions demonstrate you heard the feedback.
- **Defensive tone** — "Actually..." / "But the spec says..." triggers adversarial loops. State the rationale plainly, cite evidence, move on.

> **Templates**: See `review-pr/reference.md` §"Review Comment Templates" and §"Reply Comment Templates" for concrete starting points.

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
   - Commits added with sha → thread mapping
   - CI state from Phase 6
   - Suggested next step: await re-review, ping reviewer if urgent, merge if reviewer auto-approves, or close PR if wontfix-heavy and abandoned.

---

## Integration Notes (Project-Specific)

- **METHODOLOGY alignment**: Rule 1 (Think before coding) → Phases 1-3 (understand all threads + classify + plan before editing). Rule 7 (Surface conflicts, don't average) → Phase 2 forces explicit per-thread classification, never "kind of fix". Rule 9 (Tests verify intent) → Phase 4 cluster tests + Phase 6 CI check. Rule 12 (Fail loud) → Phase 5 verify-count gate aborts if any thread is missed.
- **Memory dependencies**:
  - `feedback_reply_after_pr_fix.md` — Phase 5 is the codified version of "per-thread reply + cite sha = part of done"
  - `feedback_prefer_gh_cli_for_github.md` — all GitHub ops via gh, not curl
- **`/fix-bug` delegation**: Phase 4 invokes `/fix-bug` for bug-shaped comments. `/fix-bug` returns with its own commit sha — capture it for Phase 5 citation. Don't run /fix-bug recursively per-comment; cluster first, then one /fix-bug per cluster.
- **Hooks active**: secret-scan, block-dangerous-git, block-bash-doctrine-write, doctrine-edit-gate run automatically during commits.
- **Agent routing reference**: silent-failure-hunter (error-handling regressions in fixes), security-reviewer (auth/secrets fixes), code-reviewer (general correctness regression on fixes), comment-analyzer (if fix added/changed docstrings).
- **Does NOT auto-resolve threads**: GitHub's "Resolve conversation" button is separate from posting a reply. After Phase 5, surface to the user which threads can be resolved via the web UI (gh CLI's thread-resolve support is limited as of writing — verify current version).
- **Fork PRs**: If the PR is from a fork, `gh api` calls need explicit `--repo <upstream-owner>/<repo>` to target the right repo. Phase 1 step 1 captures `nameWithOwner` for this purpose.
