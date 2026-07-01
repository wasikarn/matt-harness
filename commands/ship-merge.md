---
name: ship-merge
description: "Merge an approved PR safely: validate state, execute server-side merge, clean up branch, monitor CI post-merge. Use when the user says 'merge this PR', 'ship it', or after /address-review or /ship-release reaches the merge gate, or when the user says 'merge PR', 'ship it', 'รวมโค้ด'. Do NOT use for: unapproved PRs (wait for approval), PRs with failing CI (fix first), or hotfixes that need direct push (use kbg:incident hotfix path)."
argument-hint: Optional PR number or branch name
disable-model-invocation: true
disable-model-invocation-reason: irreversible external — merges a PR server-side
---

# Ship Merge

## Phase 1: Validate

**Gate**: ANY check fails → STOP. Tell user what's blocking. Don't merge.


1. Resolve PR: `gh pr view` (current branch) or `gh pr view <n>`.
2. Check CI: `gh pr checks <n>`. All required checks must pass.
3. Check approvals: `gh pr view <n> --json reviews`. At least one approval, no CHANGES_REQUESTED from a required reviewer.
4. Check mergeable state: no conflicts, no "merge requirements not met" flags.
5. Check branch protection rules: is squash required? Is linear history required?
6. **Review check — scored gate (`kbg:score-decision`)**: a bare `review-last.json.clean` boolean read isn't a measurable quality gate (METHODOLOGY Rule 14) — it collapses tier, freshness, CI, and approval signal into one bit and can't distinguish "reviewed, 3 unresolved Criticals" from "never reviewed" from "reviewed, but for a commit 5 pushes ago." Score it instead:

   Read `${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}/review-last.json` if it exists, and cross-check its `last_sha` against the PR's actual current HEAD SHA (`gh pr view <n> --json headRefOid`) — a review from an earlier commit certifies different code, not this merge.

   | Criterion | Wt | Measures |
   |---|---|---|
   | Critical findings | 30 | 0 unresolved Critical findings in `review-last.json` (review-pr's own tier definition: production breaks / a 2am page / data corruption) |
   | CI status | 25 | all required checks green (`gh pr checks <n>`) |
   | Review freshness | 20 | `review-last.json`'s `last_sha` matches the PR's current HEAD SHA |
   | Approval status | 15 | ≥1 approval, no CHANGES_REQUESTED from a required reviewer |
   | Review coverage | 10 | a review actually ran (`review-last.json` exists for this PR) |

   Pass threshold 70, fatal-weakness floor 40 (Rule 14) — no criterion below 40 regardless of weighted sum, so "great CI, zero review" and "reviewed but 3 unresolved Criticals" both fail on their own floor rather than averaging out. If no review ran, say so plainly and score Review coverage low — **never fabricate a clean result**; the agent's self-report is not ground truth, re-check against the PR, not memory.

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

**Done.**

## Anti-Patterns

- **Merge on red CI** — "It'll probably be fine" is how outages start.
- **Rebasing without checking** — rebase rewrites history; ensure the branch is safe to force-push.
- **No post-merge monitoring** — CI on `main` can fail even when the PR branch passed.
