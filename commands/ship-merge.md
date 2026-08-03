---
name: ship-merge
description: "Merge a PR safely: validate, server-side merge, cleanup, monitor CI. Say 'merge PR/รวมโค้ด'. Don't use for failing CI or hotfixes (kbg:incident)."
argument-hint: Optional PR number or branch name
disable-model-invocation: true
disable-model-invocation-reason: irreversible external — merges a PR server-side
---

# Ship Merge

## Phase 1: Validate

**Gate**: ANY check fails → STOP. Tell user what's blocking. Don't merge.


1. Resolve PR: `gh pr view` (current branch) or `gh pr view <n>`.
2. Check branch protection rules once, upfront — this drives steps 3–4, the scored table below, and Phase 2's merge flags: `gh api repos/{owner}/{repo}/branches/<base>/protection 2>/dev/null` (404/error → no protection configured at all, treat `required_status_checks` and `required_pull_request_reviews` as absent; record this as "no protection" for Phase 2 step 4). Also check `gh api repos/{owner}/{repo} --jq .allow_squash_merge` once — if `false`, Phase 2's `--squash` merge will fail; Phase 2 step 4 stops on this before attempting it rather than discovering it mid-merge.
3. Check CI: `gh pr checks <n>`. If branch protection has no `required_status_checks` **and** `gh pr checks` reports zero registered checks (not pending, not red — genuinely none), the repo has no CI wired up at all — record **N/A**, not a failure; there is nothing to gate on. Otherwise, all required checks must pass — this step records the CI signal; step 6's scored table is where it gates. A check that isn't green (pending or red) doesn't stop Phase 1 here; it flows into step 6 and is scored there.
4. Note current review approvals: `gh pr view <n> --json reviews` — informational only, not a Phase 1 gate criterion (Approval status was removed as a scored/gating criterion: GitHub doesn't count a PR author's own approval, so this could never clear for a self-authored PR). If branch protection actually requires an approval, Phase 2 steps 4–5 are the real enforcement point — GitHub itself blocks the merge without either a genuine approval or the explicit `--admin` bypass the user confirms there.
5. Check mergeable state: no conflicts, no "merge requirements not met" flags.
6. **Review check — scored gate (`kbg:score-decision`)**: a bare `review-last.json.clean` boolean read isn't a measurable quality gate (METHODOLOGY Rule 14) — it collapses tier, freshness, and CI signal into one bit and can't distinguish "reviewed, 3 unresolved Criticals" from "never reviewed" from "reviewed, but for a commit 5 pushes ago." Score it instead:

   Read `${REVIEW_PR_STATE_DIR:-$HOME/.claude/state}/review-pr-<n>.json` if it exists — `review-pr`'s Phase 7 keys PR-by-number reviews per PR precisely so two reviews run close together (e.g. #357 then #358) don't clobber a shared file before this gate reads it. Fall back to `review-last.json` (the unkeyed file `review-pr` writes for own-branch/author-flow reviews) only if the keyed file is absent. Whichever file is used, cross-check its `last_sha` against the PR's actual current HEAD SHA (`gh pr view <n> --json headRefOid`) — a review from an earlier commit certifies different code, not this merge.

   | Criterion | Wt | Measures |
   |---|---|---|
   | Critical findings | 30 | 0 unresolved Critical findings in the review-state file (review-pr's own tier definition: production breaks / a 2am page / data corruption) |
   | CI status | 25 | all required checks green (`gh pr checks <n>`) — binary, no partial credit for some-but-not-all-green (same as Review coverage below) — **N/A** (step 3) when the repo has no CI configured at all |
   | Review freshness | 20 | the review-state file's `last_sha` matches the PR's current HEAD SHA |
   | Review coverage | 10 | a review actually ran (`review-pr-<n>.json` or a matching `review-last.json` exists for this PR) |

   **Floor rule (default):** each criterion above is scored 0–100 on its own terms, independent of its weight. Any criterion scoring below 40 trips the fatal-weakness floor and forces STOP by itself, regardless of what the weighted sum computes to — even a passing weighted score (≥70) does not override a single criterion below 40. This applies by default to every criterion that gets scored. The only stated exemption anywhere in this gate is the automation-bias guard's deliberate 0 on Critical findings (below) — no other *scored* criterion has one, distinct from a verified-N/A criterion (next paragraph), which is excluded from scoring entirely rather than scored-then-exempted, so it never reaches the floor check in the first place. A stale review (Review freshness scored 0), for example, trips the floor and stops the merge even when CI, Critical findings, and coverage are all clean.

   **Verified-N/A criteria are excluded, not zeroed.** A criterion is N/A only when steps 2–3 *confirmed via the branch-protection API* that the repo has no CI configured at all — never from a `gh` call erroring for an unrelated reason (auth, rate limit, network), and never guessed.

   - **When CI is confirmed-N/A:** drop it from both the weighted sum and the floor check. Recompute as (Σ applicable criteria's weight × score) ÷ (Σ applicable weights) — each criterion is already scored 0–100 per the floor rule, so no further scaling; same 70 pass threshold, same 40 floor, just across whatever's left. A solo-maintainer repo with no CI scores on Critical findings / Review freshness / Review coverage alone (30+20+10=60 becomes the full weight base) — it isn't penalized for CI it never adopted.
   - **When no review-state file exists at all** (neither the keyed `review-pr-<n>.json` nor the unkeyed `review-last.json`): say so plainly — this fails more than the coverage check alone. The Incomplete-review guard below only governs a file that exists, not a file's total absence, so it doesn't cover this case. Instead: Critical findings has no file to assert "0 unresolved" from, and Review freshness has no `last_sha` to match — both score **0**, alongside Review coverage (the table's own definition, "a review actually ran," is binary — no partial credit). **Never fabricate a clean result** — the agent's self-report is not ground truth; re-check against the PR, not memory.
   - **When `critical_count` is present but not a valid non-negative integer** (negative, non-numeric, or the key itself absent while the rest of the file is present): treat it exactly like the file being unreadable — score Critical findings **0**. A malformed count is exactly as uninformative as a missing file; don't average it in, don't read it as zero-meaning-clean, and don't skip scoring it.

   **Incomplete-review guard on the Critical-findings criterion (check this first):** read the state file's `clean` and `rehunt` fields. The review **never certified zero criticals** — treat `critical_count: 0` as "the hunt didn't finish" or "we can't tell," not "no bug exists" — when any of:

   - `clean` is `false` with `rehunt: "incomplete"` (review-pr Phase 5 step 3.6's blind-spot re-hunt was required but the hunter errored/timed out)
   - a dispatch failure was recorded
   - `rehunt` is missing entirely, or holds anything other than exactly `clean` / `skipped-trivial` / `incomplete` / `n/a` (audited against 105 real production state files, 2026-07-28: ≈19% omit `rehunt` entirely, and real values include free-text like `"not_triggered"` or a prose summary — signs of a hand-authored file rather than one produced by review-pr's own printf block. A missing or non-canonical field is exactly as uninformative as a genuinely incomplete hunt — neither tells you the hunt finished clean.)
   - `clean` is `false` while `rehunt` reports exactly `"clean"` (the file's own two verdict fields directly disagree — `rehunt: "clean"` claims the blind-spot re-hunt itself came back clean, which can't be reconciled with an overall `clean: false`; treat a self-contradictory file the same as an incomplete one rather than silently picking one field to trust over the other)

   Score the Critical-findings criterion **0**, which trips the fatal-weakness floor (0 < 40) → **STOP** on any repo, CI or solo. Tell the user the review is incomplete (or its state file unreadable), not clean, and to re-run `kbg:review-pr` so a canonical re-hunt result lands before merge. Reading `critical_count: 0` from an unfinished or malformed review as a clean pass is the machine-boundary rubber-stamp the verifier-separation principle rejects.

   **Automation-bias guard on the Critical-findings criterion:** `review-last.json`'s `critical_count` is a same-session self-report when `review_mode` is `"own-branch"` — nothing independently re-derives whether the severity tiering was correct, only whether the file is fresh and present. Check the PR's changed file paths (`gh pr diff <n> --name-only`) against **either** (a) `auth|secret|credential|payment|billing|token`, **or** (b) the harness's own verifier/gate paths — under `hooks/gates/`, equal to `hooks/hooks.json`, equal to `skills/harness-audit/scripts/audit.sh`, or under `skills/harness-audit/scripts/checks/` (the exact set `hooks/gates/verifier-protect.sh` already treats as tamper-sensitive — reuse that list, don't redefine it).

   If any match AND `review_mode` is not verifiably `"pr-by-number"` (the only value this guard trusts — an isolated-worktree run), **score the Critical-findings criterion 0 but keep its 30 weight in the denominator** — do **not** renormalize it away. This is a deny-list check on purpose, not an allow-list one: a missing `review_mode` key, a typo, or any unrecognized value gets the same distrust as an explicit `"own-branch"`, not a silent pass-through. (Closed gap, confirmed via `/kbg:review-fixtures` 2026-08-03: the original wording checked for `review_mode is "own-branch"` specifically, so a malformed or missing field bypassed the guard instead of tripping it — on a sensitive-path diff, exactly the case this guard exists to catch.) This check does not depend on a literal `review_mode` field being present, either: step 2's own file-resolution rule above already defines what the unkeyed `review-last.json` path *means* — the file `review-pr` writes for own-branch/author-flow reviews — so finding the review at that path is itself sufficient to treat it as not-`pr-by-number`, whether or not a `review_mode` field exists in the file or what it says if it does. A file at the keyed `review-pr-<n>.json` path, by that same file-resolution rule, already signals a `pr-by-number` run by its path alone. Don't let a missing field talk you out of a conclusion the file's own path already establishes. (A second discrimination gap closed the same day: a fixture built to test the missing-field case found a careful reader could bridge this via the path anyway — the guard's wording now states the bridge explicitly instead of relying on the reader to find it.) This is also the key difference from a verified-N/A criterion: a policy the repo never adopted genuinely *doesn't apply* (renormalize); a self-tiered sensitive review *does* apply — you simply refuse to trust it — so its weight stays as dead weight the *deterministic* criteria must overcome. **Exempt this criterion from the floor check** — the sole exemption named in the floor rule above; a deliberate 0 here must not trip the fatal-weakness floor, or it would STOP even a fully green CI repo. This applies the audit's own principle: an untrusted self-tiered LLM verdict must not be load-bearing for a pass.

   With Approval status removed from scoring (2026-07-23 — GitHub doesn't count the author's own approval, so it could never clear for a self-authored PR), deterministic signals alone can no longer clear the 70 threshold on a sensitive-path own-branch review, however green CI is — worked numbers in `docs/reference/ship-merge-scored-gate-margin.md`. The only path through is re-reviewing via `kbg:review-pr`'s `pr-by-number` mode (isolated worktree), which scores Critical findings on its own merits instead of the zeroed self-tier. Tell the user why: "sensitive-path diff, self-reviewed — the self-tier is scored 0, and deterministic signals alone can't reach the 70 threshold now that Approval isn't scored; re-review by PR number for an isolated pass before this can merge."

   **Maintainer note:** this floor exemption creates a margin invariant — any edit to this table's weights, or to the 70/40 thresholds, can silently move the point where the exemption stops covering a real sensitive-path review. Read `docs/reference/ship-merge-scored-gate-margin.md` before changing any weight or either threshold; it also tracks a known gap in this invariant's coverage.

   **Gate**: FAIL (below the 70 threshold, or below the 40 floor on any criterion per the floor rule above — no exemption unless one is named) → STOP, tell the user which criterion failed and why. PASS → proceed to Phase 2.

---

## Phase 2: Merge (GitHub Server-Side Only)

**Rule**: Merge must happen via GitHub (`gh pr merge`). Never run `git merge` locally and push the result.


1. Fetch latest: `git fetch origin`
2. Rebase onto base branch: `git rebase origin/<base-branch>`
   - Gate: rebase produces conflicts → STOP. Tell user to resolve manually and retry.
3. Force-push rebased branch: `git push --force-with-lease`
4. Decide the merge flags from Phase 1 step 2's protection read — no new API call:
   - **No protection at all** (step 2 read a 404) → plain merge, no `--admin` — there's nothing to bypass.
   - **Protection exists** → step 3's force-push just produced a fresh SHA with no completed status checks yet (and possibly dismissed reviews, if the repo dismisses stale reviews on push) → `--admin` is needed to land now instead of waiting for CI to re-run on the new SHA. This is a real bypass of a real policy — say so plainly in step 5, don't fold it silently into a generic confirmation line.
   - If step 2 found `allow_squash_merge: false` → STOP now. `--squash` will fail outright; resolve the strategy mismatch before retrying.
5. **AskUserQuestion** single-select: "Phase 2: PR [#N] — CI [green / red / N/A — no CI configured], approvals [N], conflicts [none / yes]. Target: [base-branch]. [No branch protection to bypass / Branch protection active — this merge uses --admin to bypass it]. Merge will squash + delete branch. Proceed?"
   - `Merge now (best when all gates pass and the user is ready to land)` — execute server-side merge
   - `Abort (best when something changed since validation or the user wants to re-check)` — stop; user can re-run later
6. Execute **server-side** merge via GitHub CLI, using step 4's flag decision:
   ```bash
   gh pr merge <n> --squash --delete-branch              # no protection (step 4: 404)
   gh pr merge <n> --admin --squash --delete-branch       # protection active — bypass confirmed in step 5
   ```
   - `--admin` bypasses branch protection — include it only when step 4 found protection active and step 5 confirmed the bypass, never as an unconditional default.
   - `--squash` collapses the PR into a single commit **on GitHub**.
   - `--delete-branch` removes the remote branch **on GitHub**.
   - Gate: merge attempted without `--admin` and GitHub refuses because a required check is still pending on the post-rebase SHA → STOP, tell the user CI needs to finish on the new SHA or the merge needs the bypass. Don't silently retry with `--admin` unprompted.

**Sync seam:** `skills/incident/references/hotfix-reference.md` Phase 4 duplicates
this exact merge command for the P0/P1 emergency path — the two are intentionally
separate calls, not a shared subroutine, since hotfix strips this phase's scored
gate for speed. Hotfix's unconditional `--admin` is a deliberate difference (an
emergency merge always needs the bypass), not drift from step 4 above. If you
change the merge flags or the confirm-prompt shape here, check whether hotfix's
Phase 4 needs the matching edit.

7. Pull the result locally: `git checkout <base-branch> && git pull`
8. Verify merge landed: `git log --oneline -3` on target branch.

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
- **Unconditional `--admin`** — bypassing branch protection by default defeats the checks Phase 1 just validated; use it only when Phase 2 step 4 found protection actually active, and say so in the confirmation prompt.
