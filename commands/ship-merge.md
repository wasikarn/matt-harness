---
name: ship-merge
description: "Merge an approved PR safely: validate state, execute server-side merge, clean up branch, monitor CI post-merge. Use when the user says 'merge this PR', 'ship it', or after /address-review or /ship-release reaches the merge gate, or when the user says 'merge PR', 'ship it', 'รวมโค้ด'. Do NOT use for: unapproved PRs (wait for approval), PRs with failing CI (fix first), or hotfixes that need direct push (use kbg:incident hotfix path)."
argument-hint: Optional PR number or branch name
disable-model-invocation: true
disable-model-invocation-reason: irreversible external — merges a PR server-side
---

# Ship Merge

Land a PR safely. Validation gates are non-negotiable — a merge without checks is a rollback waiting to happen.

## Core Principles

- **Validate before merge.** CI green, approvals in, no conflicts. Check every time.
- **Rebase before merge.** Stay current with the base branch to avoid post-merge surprises.
- **Squash and clean.** One commit per PR, delete branch automatically.
- **Monitor post-merge.** CI on the merged commit can differ from CI on the branch.

---

## Phase 1: Validate

**Goal**: Confirm the PR is ready to merge.

**Actions**:
1. Resolve PR: `gh pr view` (current branch) or `gh pr view <n>`.
2. Check CI: `gh pr checks <n>`. All required checks must pass.
3. Check approvals: `gh pr view <n> --json reviews`. At least one approval, no CHANGES_REQUESTED from a required reviewer.
4. Check mergeable state: no conflicts, no "merge requirements not met" flags.
5. Check branch protection rules: is squash required? Is linear history required?
6. **Review / acceptance check** (two layers — machine first, human second):
   - **Machine layer (deterministic):** If the PR's task has an `ACCEPTANCE.md` in `.scratch/<slug>/`, run `/ship-task <slug> --acceptance` (or auto-detect) to get machine-checkable results. If the result is **RED** (any failed/blocked criteria) → STOP. Do not merge until criteria pass.
   - **Human layer (judgment):** If no `ACCEPTANCE.md` exists, or if machine results are GREEN/AMBER, check whether a review ran on this PR (`kbg:review-pr` or `/address-review`). If yes → confirm **zero unresolved Critical findings** (mirrors `/ship-release`'s "Zero Critical findings" gate) and surface any open acceptance-gap.
   - If no review ran → say so plainly and pass; **never fabricate a clean result.** The agent's self-report is not ground truth — re-check against the PR, not memory.
   - The machine layer is **authoritative for criteria it can check**; the human layer handles prose criteria and findings beyond the contract.

**Gate**: ANY check fails → STOP. Tell user what's blocking. Don't merge.

**Next**: Phase 2 (Merge).

---

## Phase 2: Merge (GitHub Server-Side Only)

**Goal**: Keep the branch current, then let GitHub perform the squash-merge and auto-delete.

**Rule**: Merge must happen via GitHub (`gh pr merge`). Never run `git merge` locally and push the result.

**Actions**:
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

**Next**: Phase 3 (Clean Up).

---

## Phase 3: Clean Up

**Goal**: Tidy local references after merge.

**Actions**:
1. Prune local refs: `git fetch --prune`.
2. If the branch was checked out locally, switch to the target branch and pull.

**Next**: Phase 4 (Monitor).

---

## Phase 4: Monitor

**Goal**: Confirm the merged commit is healthy.

**Actions**:
1. Check CI on the merged commit: `gh run list --branch <target>` or `gh pr checks` on the closed PR.
2. If failures appear post-merge, be ready to revert or invoke `kbg:incident` (hotfix path).
3. Summarize: PR number, squash merge, commit sha, branch auto-deleted, CI status. (For a user-facing merge/release note, route the prose through the `tech-humanize` skill to strip AI-flavor tells.)

**Done.**

## Anti-Patterns

- **Merge on red CI** — "It'll probably be fine" is how outages start.
- **Rebasing without checking** — rebase rewrites history; ensure the branch is safe to force-push.
- **No post-merge monitoring** — CI on `main` can fail even when the PR branch passed.
