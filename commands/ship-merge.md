---
name: ship-merge
description: "Merge an approved PR safely: validate, server-side merge, cleanup, monitor CI. Say 'merge PR/รวมโค้ด'. Don't use for unapproved PRs, failing CI, or hotfixes (kbg:incident)."
argument-hint: Optional PR number or branch name
disable-model-invocation: true
disable-model-invocation-reason: irreversible external — merges a PR server-side
---

# Ship Merge

## Phase 1: Validate

**Gate**: ANY check fails → STOP. Tell user what's blocking. Don't merge.


1. Resolve PR: `gh pr view` (current branch) or `gh pr view <n>`.
2. Check branch protection rules once, upfront — this drives steps 3–4 and the scored table below: `gh api repos/{owner}/{repo}/branches/<base>/protection 2>/dev/null` (404/error → no protection configured at all, treat both `required_status_checks` and `required_pull_request_reviews` as absent). Is squash required? Is linear history required?
3. Check CI: `gh pr checks <n>`. If branch protection has no `required_status_checks` **and** `gh pr checks` reports zero registered checks (not pending, not red — genuinely none), the repo has no CI wired up at all — record **N/A**, not a failure; there is nothing to gate on. Otherwise, all required checks must pass.
4. Check approvals: `gh pr view <n> --json reviews`. If branch protection has no `required_pull_request_reviews` (or `required_approving_review_count` is 0) — routine for solo-maintainer repos — record **N/A**, not a failure; the repo has no review policy to check against. Otherwise, at least one approval is required, no CHANGES_REQUESTED from a required reviewer.
5. Check mergeable state: no conflicts, no "merge requirements not met" flags.
6. **Review check — scored gate (`kbg:score-decision`)**: a bare `review-last.json.clean` boolean read isn't a measurable quality gate (METHODOLOGY Rule 14) — it collapses tier, freshness, CI, and approval signal into one bit and can't distinguish "reviewed, 3 unresolved Criticals" from "never reviewed" from "reviewed, but for a commit 5 pushes ago." Score it instead:

   Read `${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}/review-pr-<n>.json` if it exists — `review-pr`'s Phase 7 keys PR-by-number reviews per PR precisely so two reviews run close together (e.g. #357 then #358) don't clobber a shared file before this gate reads it. Fall back to `review-last.json` (the unkeyed file `review-pr` writes for own-branch/author-flow reviews) only if the keyed file is absent. Whichever file is used, cross-check its `last_sha` against the PR's actual current HEAD SHA (`gh pr view <n> --json headRefOid`) — a review from an earlier commit certifies different code, not this merge.

   | Criterion | Wt | Measures |
   |---|---|---|
   | Critical findings | 30 | 0 unresolved Critical findings in the review-state file (review-pr's own tier definition: production breaks / a 2am page / data corruption) |
   | CI status | 25 | all required checks green (`gh pr checks <n>`) — **N/A** (step 3) when the repo has no CI configured at all |
   | Review freshness | 20 | the review-state file's `last_sha` matches the PR's current HEAD SHA |
   | Approval status | 15 | ≥1 approval, no CHANGES_REQUESTED from a required reviewer — **N/A** (step 4) when the repo has no required-review policy at all |
   | Review coverage | 10 | a review actually ran (`review-pr-<n>.json` or a matching `review-last.json` exists for this PR) |

   **Verified-N/A criteria are excluded, not zeroed.** A criterion is N/A only when steps 2–4 *confirmed via the branch-protection API* that the repo has no policy to check — never from a `gh` call erroring for an unrelated reason (auth, rate limit, network), and never guessed. Confirmed-N/A criteria drop out of both the weighted sum and the floor check entirely: recompute the score as (Σ applicable criteria's weight × score) ÷ (Σ applicable weights) × 100, same 70 pass threshold, same 40 floor — but only across whatever's left. A solo-maintainer repo with no CI and no required reviews is scored on Critical findings / Review freshness / Review coverage alone (30+20+10=60 becomes the full weight base); it is not penalized for policies the repo never adopted. If no review ran, say so plainly and score Review coverage low — **never fabricate a clean result**; the agent's self-report is not ground truth, re-check against the PR, not memory.

   **Automation-bias guard on the Critical-findings criterion:** `review-last.json`'s `critical_count` is a same-session self-report when `review_mode` is `"own-branch"` — nothing independently re-derives whether the severity tiering was correct, only whether the file is fresh and present. Check the PR's changed file paths (`gh pr diff <n> --name-only`) against **either** (a) `auth|secret|credential|payment|billing|token`, **or** (b) the harness's own verifier/gate paths — under `hooks/gates/`, equal to `hooks/hooks.json`, equal to `skills/harness-audit/scripts/audit.sh`, or under `skills/harness-audit/scripts/checks/` (the exact set `hooks/gates/verifier-protect.sh` already treats as tamper-sensitive — reuse that list, don't redefine it). If any match AND `review_mode` is `"own-branch"` (not `"pr-by-number"`, which ran in an isolated worktree), cap the Critical-findings criterion at 40 (the floor) regardless of its reported `critical_count` — tell the user why ("sensitive-path diff, self-reviewed — re-review by PR number for an isolated pass before this can score above the floor") rather than trusting the self-tier.

   **Gate**: FAIL (below threshold or below floor on any criterion) → STOP, tell the user which criterion failed and why. PASS → proceed to Phase 2.

---

## Phase 2: Merge (GitHub Server-Side Only)

**Rule**: Merge must happen via GitHub (`gh pr merge`). Never run `git merge` locally and push the result.


1. Fetch latest: `git fetch origin`
2. Rebase onto base branch: `git rebase origin/<base-branch>`
   - Gate: rebase produces conflicts → STOP. Tell user to resolve manually and retry.
3. Force-push rebased branch: `git push --force-with-lease`
4. **AskUserQuestion** single-select: "Phase 2: PR [#N] — CI [green / red], approvals [N], conflicts [none / yes]. Target: [base-branch]. Merge will squash + delete branch. Proceed?"
   - `Merge now (Recommended when all gates pass and the user is ready to land)` — execute server-side merge
   - `Abort (Recommended when something changed since validation or the user wants to re-check)` — stop; user can re-run later
5. Execute **server-side** merge via GitHub CLI:
   ```bash
   gh pr merge <n> --admin --squash --delete-branch
   ```
   - `--admin` bypasses branch protection (use only when you are authorized to force merge).
   - `--squash` collapses the PR into a single commit **on GitHub**.
   - `--delete-branch` removes the remote branch **on GitHub**.
6. Pull the result locally: `git checkout <base-branch> && git pull`
7. Verify merge landed: `git log --oneline -3` on target branch.

---

## Phase 3: Clean Up

1. Prune local refs: `git fetch --prune`.
2. If the branch was checked out locally, switch to the target branch and pull.

---

## Phase 4: Monitor


1. Check CI on the merged commit: `gh run list --branch <target>` or `gh pr checks` on the closed PR.
2. If failures appear post-merge, be ready to revert or invoke `kbg:incident` (hotfix path).
3. Summarize: PR number, squash merge, commit sha, branch auto-deleted, CI status. Keep a user-facing merge/release note factual and free of AI-flavor tells (no self-congratulation, no hedging filler).
4. **Suggested next step:**
   - Fix worth recording        → /post-mortem while context is warm
   - Last change before release → /ship-release
   - Base-branch CI red         → kbg:incident (per step 2)
   - Otherwise                  → done; pick up the next task

**Done.**

## Anti-Patterns

- **Merge on red CI** — "It'll probably be fine" is how outages start.
- **Rebasing without checking** — rebase rewrites history; ensure the branch is safe to force-push.
- **No post-merge monitoring** — CI on `main` can fail even when the PR branch passed.
