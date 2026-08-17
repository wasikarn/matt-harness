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

   See `references/scored-gate-guards.md` for the floor rule, verified-N/A handling, the incomplete-review guard, the non-convergence guard, the automation-bias guard, and the maintainer margin-invariant note — everything between the criteria table above and the Gate line below.

   **Gate**: FAIL (below the 70 threshold, or below the 40 floor on any criterion per the floor rule above — no exemption unless one is named) → STOP, tell the user which criterion failed and why. PASS → proceed to step 7.

7. **CODEOWNER check — binary/3-way gate, not scored.** Kept fully outside the table above on purpose: a new weighted criterion at weight ≥15 breaks the margin invariant `docs/reference/ship-merge-scored-gate-margin.md` documents — read that file before ever changing this step's shape, not just before changing the table's.

   **Locate CODEOWNERS pinned to this PR's head SHA** (not the local working tree — Phase 2's checkout/rebase hasn't run yet, so local files aren't guaranteed to reflect the PR), in GitHub's own documented search order (`.github/`, root, `docs/` — first one found wins, this is not a merge of all three), **distinguishing a genuine 404 (file absent) from any other fetch error** (auth, rate-limit) — the two get opposite verdicts below. Resolve `<head_sha>` once via `gh pr view <n> --json headRefOid --jq .headRefOid` and reuse the same value for both the discovery call below and the match call later in this step — don't re-derive it in between, and don't reuse a value captured earlier in Phase 1 (e.g. step 1's initial `gh pr view`): a new commit landing on the PR between an earlier capture and this step's use would let a review pinned to that older SHA still pass, a narrower version of the exact staleness issue #50 fixed. This doc-driven path can't fetch `headRefOid`, `changed_files`, and `reviews` atomically the way `convergence-merge-gate.sh`'s single `gh pr view --json headRefOid,files,reviews` call does — Phase 2 step 3's rebase re-check (below) is the backstop if a race here slips a stale approval through:
   ```bash
   CODEOWNERS_CONTENT=$(python3 "${KBG_PLUGIN_ROOT}/hooks/gates/lib/_codeowners_match.py" --discover "<head_sha>" 2>"${TMPDIR:-/tmp}/codeowners-err-$$")
   DISCOVER_RC=$?
   CODEOWNERS_FOUND=0
   CODEOWNERS_ERROR=""
   if [ "$DISCOVER_RC" -eq 0 ]; then
     CODEOWNERS_FOUND=1
   elif [ "$DISCOVER_RC" -ne 3 ]; then
     CODEOWNERS_ERROR=$(cat "${TMPDIR:-/tmp}/codeowners-err-$$" 2>/dev/null)
   fi
   trash "${TMPDIR:-/tmp}/codeowners-err-$$" 2>/dev/null
   ```
   The discovery loop itself (3-path search order, exit-code-based found/absent/error distinction) lives in the shared `hooks/gates/lib/_codeowners_match.py`'s `discover()` — the exact same implementation `hooks/gates/convergence-merge-gate.sh`'s own CODEOWNER check imports in-process, not a second, independently-maintained copy. `--discover <head_sha>` exit codes: `0` = found (content on stdout, possibly empty — still authoritative per GitHub's first-found-wins search order, not the same as absent), `3` = genuinely absent everywhere (verified-N/A), `4` = a real fetch error (message on stderr instead of stdout). If `$CODEOWNERS_ERROR` is non-empty → **fail-closed, STOP** — "CODEOWNERS fetch failed ($CODEOWNERS_ERROR), not confirmed absent — the 'never fabricate a clean result' rule applies here too." If `$CODEOWNERS_FOUND` is still `0` → **N/A**, proceed to Phase 2 (verified-absent-everywhere, same treatment as CI's absence above).

   **If `$CODEOWNERS_FOUND` is `1`**, parse + match with a real translator, not prose reasoning — run this even when `$CODEOWNERS_CONTENT` is empty (an empty or comment-only file naturally parses to zero rules; the shared script's own `no-owned-files-changed` branch already handles that correctly, so don't special-case it above the script). Matching logic — GitHub's documented CODEOWNERS grammar (verified against GitHub's own docs, 2026-08-14 — two `.gitignore` features explicitly do NOT carry over: `[ ]` character ranges and `!` negation, so the matcher needs neither: no `/` in a pattern matches the basename at any depth; a `/` anywhere except a lone trailing one anchors to the repo root; a trailing `/` matches that directory and everything under it; `*` matches within one path segment, `**` crosses segments, `?` matches one character; last-matching-line wins) — lives in the same shared script, not embedded here. Reuse `gh pr diff <n> --name-only` (step 6's automation-bias guard already calls it — don't fetch twice) and step 4's already-fetched `gh pr view <n> --json reviews -q .reviews` (also don't re-fetch), plus the same `<head_sha>` already resolved above — an approval only counts if it's pinned to the PR's *current* head commit (`gh pr view --json reviews` generally includes each review's `commit.oid`; GitHub's GraphQL schema documents the field as nullable, e.g. on rewritten history, and a null/missing oid is treated the same as a non-matching one — no approval — since a repo without branch protection's "dismiss stale reviews" enabled never strips it out upstream):
   ```bash
   CHANGED_FILES=$(gh pr diff <n> --name-only)
   REVIEWS_JSON=$(gh pr view <n> --json reviews -q .reviews)
   python3 "${KBG_PLUGIN_ROOT}/hooks/gates/lib/_codeowners_match.py" "$CODEOWNERS_CONTENT" "$CHANGED_FILES" "$REVIEWS_JSON" "<head_sha>"
   ```
   Verified against 22 fixture cases (matching-engine cases — exact path match, `*.ext` any-depth, `/docs/` root-anchored directory, `apps/` unanchored directory, `docs/*` single-level-only confirming a nested file does NOT match, `db/**/index.md` recursive, last-match-wins, an `[abc]` bracket pattern correctly failing the whole check closed rather than silently resolving to no-match — plus the review-decision-state, email-owner-`DEFERRED`, and head-SHA-pinning regressions) plus `discover()`'s own found/found-but-empty/absent/error fixtures — `tests/commands/test-ship-merge-codeowners.sh` and `tests/hooks/test-convergence-merge-gate.sh` both exercise the shared script directly, not a markdown-embedded copy.

   **Gate — 3-way, not binary**, read off the script's first printed line: `PASS` (every required entry satisfied, or N/A/no-owned-files) → proceed to Phase 2. `STOP` (any unsatisfied `@username` entry, regardless of what else, or an unparseable pattern, or a non-404 fetch error) → hard Phase 1 failure, render the reason + file/owner detail lines. `DEFERRED` (every remaining unsatisfied entry is `@org/team` or a bare email address — this matcher can't resolve either against the reviews API's usernames) → do not stop here — carry the printed file/team detail lines forward into Phase 2 step 5's confirmation prompt for explicit human acknowledgment before merge (the same "make a human knowingly accept a real bypass" pattern this file already uses for the branch-protection `--admin` bypass) — proceed to Phase 2.

   **Not a standalone check — the gate covers the same ground.** `hooks/gates/convergence-merge-gate.sh` independently intercepts a raw `gh pr merge` call outside this flow entirely — the actual reason `ship-merge` is `disable-model-invocation` in the first place (see that hook and `docs/reference/hook-lifecycle-contracts.md`) — and, as of 2026-08-15, calls the same `_codeowners_match.py` script this Phase 1 step calls, resolving `PASS`/`STOP` the same way and mapping `DEFERRED` to a `permissionDecision: "ask"` prompt rather than a hard block (so a human confirmation here doesn't dead-end against the gate re-evaluating the same PR). `KBG_SKIP_CODEOWNERS_GATE=1` is the gate's escape hatch if this needs to be bypassed for a repo with no CODEOWNERS policy to enforce.

---

## Phase 2: Merge (GitHub Server-Side Only)

**Rule**: Merge must happen via GitHub (`gh pr merge`). Never run `git merge` locally and push the result.


1. Fetch latest: `git fetch origin`
2. Rebase onto base branch: `git rebase origin/<base-branch>`
   - Gate: rebase produces conflicts → STOP. Tell user to resolve manually and retry.
3. Force-push rebased branch: `git push --force-with-lease`
4. Decide the merge flags from Phase 1 step 2's protection read — no new API call:
   - **No protection at all** (step 2 read a 404) → plain merge, no `--admin` — there's nothing to bypass.
   - **Protection exists** → check this phase's step 2 rebase result and Phase 1 step 3's CI signal together. If the rebase actually replayed commits (not "already up to date") **and** CI is not N/A, this phase's step 3 force-push just produced a fresh SHA with no completed status checks yet (and possibly dismissed reviews, if the repo dismisses stale reviews on push) → `--admin` is needed to land now instead of waiting for CI to re-run on the new SHA. This is a real bypass of a real policy — say so plainly in step 5, don't fold it silently into a generic confirmation line. If the rebase was a no-op, **or** CI was verified-N/A in Phase 1 step 3, the fresh-CI concern doesn't apply — but step 6 still uses `--admin` here, the same as the fresh-SHA case (protection active always uses it once you reach step 6's flag decision — there's no partial-bypass command); the difference is only in *why*: whatever other protection rule is configured (e.g. required reviews), not an unvalidated CI check.
   - If Phase 1 step 2 found `allow_squash_merge: false` → STOP now. `--squash` will fail outright; resolve the strategy mismatch before retrying.
   - **If Phase 1 step 7 found required CODEOWNER entries (not N/A)** and this phase's step 2 rebase actually replayed commits (not a no-op) → **re-run step 7's matching+approval logic** (CODEOWNERS fetch, changed-file match, approval check) against the new post-rebase head SHA, before step 6's merge. A force-push can dismiss stale reviews (already noted above for CI); the same risk applies to CODEOWNER approvals Phase 1 certified against the pre-rebase SHA. Skip this re-check when step 7 was N/A, or when this phase's rebase was a no-op — nothing could have been invalidated either way. Re-check surfaces a newly-unsatisfied `@username` entry → STOP here, same as a Phase 1 step 7 failure; don't proceed to step 6. A newly-DEFERRED `@org/team` or email entry folds into step 5's prompt exactly like one found in Phase 1.
5. **AskUserQuestion** single-select: "Phase 2: PR [#N] — CI [green / red / pending / N/A — no CI configured], approvals [N], conflicts [none / yes]. [CODEOWNER: N/A / satisfied / DEFERRED — {file} requires {team-or-email} approval, unverified — confirm an owner has approved before proceeding]. Target: [base-branch]. [No branch protection to bypass / Branch protection active — this merge uses --admin to bypass it]. Merge will squash + delete branch. Proceed?" The CODEOWNER field renders only when step 7 (or this step's re-check above) returned DEFERRED — omit it entirely on PASS/N/A, don't pad the prompt with a field that has nothing to say. Base the recommendation on step 4's branch decision, this phase's step 2 rebase result, and Phase 1 step 3's CI signal — not a blanket "Phase 1 already passed" assumption. Render whichever option this resolves to as the literal `(Recommended)` tag, replacing its `(best when X)` clause at render time — the list below is a template, not fixed text to paste verbatim:
   - **No protection at all**, **protection exists but the rebase was a no-op** (already up to date — Phase 1's validated SHA is still current), or **CI was verified-N/A in Phase 1 step 3** (no CI configured for this repo at all — there's nothing for a fresh SHA to leave unvalidated) → recommend Merge now.
   - **Protection exists, the rebase actually replayed commits, and CI is not N/A** (step 4's fresh-SHA case — a real check that hasn't re-run on the new SHA yet, likely showing `pending`) → do not default to Merge now: recommend Abort instead, and tell the user the fresh SHA hasn't been CI-validated — picking Merge now there needs the user to knowingly accept an unvalidated `--admin` bypass, not a default nudge toward it.
   - `Merge now (best when all gates pass and the user is ready to land)` — execute server-side merge. Bypasses branch protection when it's active (step 4); on a genuinely re-based SHA under active protection with a real (non-N/A) CI signal, this also means merging before CI has re-run on it — not a concern when CI was verified-N/A.
   - `Abort (best when something changed since validation or the user wants to re-check)` — stop; user can re-run later. The PR stays unmerged and Phase 1's gate must pass again before retrying.
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
Phase 4 needs the matching edit. **Checked 2026-08-10:** hotfix's Phase 4 already
carries the equivalent default-recommendation + consequence-stating language
(v0.68.256) — this step's edit matches that shape, no further edit needed there.

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
