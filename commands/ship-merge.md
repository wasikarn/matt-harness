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

   **Incomplete-review guard on the Critical-findings criterion (check this first):** read the state file's `clean` and `rehunt` fields. If `clean` is `false` with `rehunt: "incomplete"` (review-pr Phase 5 step 3.6's blind-spot re-hunt was required but the hunter errored/timed out), or a dispatch failure was recorded, the review **never certified zero criticals** — `critical_count: 0` from an unfinished review means "the hunt didn't finish," not "no bug exists." Score the Critical-findings criterion **0**, which trips the fatal-weakness floor (0 < 40) → **STOP** on any repo, CI or solo. Tell the user the review is incomplete, not clean, and to re-run `kbg:review-pr` so the re-hunt completes before merge. Reading `critical_count: 0` from an unfinished review as a clean pass is the machine-boundary rubber-stamp the verifier-separation principle rejects.

   **Automation-bias guard on the Critical-findings criterion:** `review-last.json`'s `critical_count` is a same-session self-report when `review_mode` is `"own-branch"` — nothing independently re-derives whether the severity tiering was correct, only whether the file is fresh and present. Check the PR's changed file paths (`gh pr diff <n> --name-only`) against **either** (a) `auth|secret|credential|payment|billing|token`, **or** (b) the harness's own verifier/gate paths — under `hooks/gates/`, equal to `hooks/hooks.json`, equal to `skills/harness-audit/scripts/audit.sh`, or under `skills/harness-audit/scripts/checks/` (the exact set `hooks/gates/verifier-protect.sh` already treats as tamper-sensitive — reuse that list, don't redefine it). If any match AND `review_mode` is `"own-branch"` (not `"pr-by-number"`, which ran in an isolated worktree), **score the Critical-findings criterion 0 but keep its 30 weight in the denominator** — do **not** renormalize it away. This is the key difference from a verified-N/A criterion, and getting it backwards defeats the guard: a policy the repo never adopted genuinely *doesn't apply*, so it drops out of the weight base entirely (renormalize); a self-tiered sensitive review *does* apply — you simply refuse to trust it — so its weight stays in the denominator as dead weight the *deterministic* criteria must overcome, scored 0. **Exempt this criterion from the floor check only** (a deliberate 0 here must not trip the fatal-weakness floor, or it would STOP even a fully green CI repo). This applies the audit's own principle: an untrusted self-tiered LLM verdict must not be load-bearing for a pass. The arithmetic (walk it, don't eyeball it): a solo/no-CI repo has CI + approval verified-N/A (those renormalize away), leaving Critical (30, scored 0) + freshness (20) + coverage (10) = 60 weight base → `(30·0 + 20·100 + 10·100) ÷ 60 = 50`, below the 70 threshold → **STOP**; the exactly-70 pass the old cap-at-40 allowed can no longer happen. A repo with real CI + required review keeps every criterion in play → `(30·0 + 25·100 + 20·100 + 15·100 + 10·100) ÷ 100 = 70` → **PASS** when those deterministic signals are green — the pass now rests entirely on them, not on the self-tier. Tell the user why: "sensitive-path diff, self-reviewed — the self-tier is scored 0; re-review by PR number for an isolated pass, or land the deterministic checks (CI + approval), before this can merge."

   **Gate**: FAIL (below threshold or below floor on any criterion) → STOP, tell the user which criterion failed and why. PASS → proceed to Phase 2.

---

## Phase 2: Merge (GitHub Server-Side Only)

**Rule**: Merge must happen via GitHub (`gh pr merge`). Never run `git merge` locally and push the result.


1. Fetch latest: `git fetch origin`
2. Rebase onto base branch: `git rebase origin/<base-branch>`
   - Gate: rebase produces conflicts → STOP. Tell user to resolve manually and retry.
3. Force-push rebased branch: `git push --force-with-lease`
4. **AskUserQuestion** single-select: "Phase 2: PR [#N] — CI [green / red / N/A — no CI configured], approvals [N], conflicts [none / yes]. Target: [base-branch]. Merge will squash + delete branch. Proceed?"
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


1. If CI was verified-N/A in Phase 1 (step 3), skip to step 3 — there's nothing to monitor. Otherwise check CI on the merged commit: `gh run list --branch <target>` or `gh pr checks` on the closed PR.
2. If failures appear post-merge, be ready to revert or invoke `kbg:incident` (hotfix path).
3. Summarize: PR number, squash merge, commit sha, branch auto-deleted, CI status (or "N/A — no CI configured"). Keep a user-facing merge/release note factual and free of AI-flavor tells (no self-congratulation, no hedging filler).
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
