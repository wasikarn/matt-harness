---
name: ship-merge
description: "Merge a PR safely: validate, server-side merge, cleanup, monitor CI. Use when a reviewed PR is ready to land. Say 'merge PR/รวมโค้ด'. Don't use for failing CI or hotfixes (mh:incident)."
bucket: workflow
argument-hint: Optional PR number or branch name
disable-model-invocation: true
disable-model-invocation-reason: external, irreversible action — executes a server-side PR merge on GitHub that cannot be undone; only a human-typed /mh:ship-merge, confirmed through Phase 2's explicit go/no-go, may trigger it
model: inherit
effort: high
---

# Ship Merge

**Needs**: the `gh` CLI installed and authenticated (`gh auth status`) — every phase below merges and validates through it.

## Phase 1: Validate

**Gate**: ANY check fails → STOP. Tell user what's blocking. Don't merge.

1. Resolve PR: `gh pr view` (current branch) or `gh pr view <n>`.
2. Check branch protection rules once, upfront — drives steps 3–4 and Phase 2's merge flags: `gh api repos/{owner}/{repo}/branches/<base>/protection 2>/dev/null` (404/error → no protection at all; treat `required_status_checks`/`required_pull_request_reviews` as absent, record "no protection" for Phase 2 step 4). Also check `gh api repos/{owner}/{repo} --jq .allow_squash_merge` once — `false` means Phase 2's `--squash` will fail; Phase 2 step 4 stops on this before attempting it, not mid-merge.
3. Check CI: `gh pr checks <n>`. No `required_status_checks` **and** zero registered checks (not pending/red — genuinely none) → repo has no CI at all, record **N/A**, not a failure. Otherwise all required checks must pass — not green (and not verified-N/A) → STOP, per this phase's gate.
4. Note current review approvals: `gh pr view <n> --json reviews` — informational only, not a Phase 1 gate criterion (GitHub doesn't count a PR author's own approval). If branch protection requires an approval, Phase 2 steps 4–5 are the real enforcement point — GitHub blocks the merge without either a genuine approval or the explicit `--admin` bypass confirmed there.
5. Check mergeable state: no conflicts, no "requirements not met" flags.
6. **Sensitive-path check — deterministic classification, never a merge decision.** Run the PR's changed file paths (`gh pr diff <n> --name-only`) through the two classifiers documented in `references/scored-gate-guards.md`: the `auth|secret|credential|payment|billing|token` keyword regex, and the harness's own verifier/gate paths via `hooks/gates/lib/_protected_paths.py`'s `is_gate_path()` (the shared classifier — never a hardcoded path list; that file has the exact command and the drift history). Record the result — **sensitive** (list the matched paths) or **not sensitive** — and carry it into Phase 2 step 5's prompt. This step never STOPs and never auto-passes anything: its whole job is putting an honest risk label in front of the explicit user go/no-go, which is the only authorization to merge. If `gh pr diff` itself fails, STOP — an unclassified diff is not a "not sensitive" diff.

7. **CODEOWNER check — binary/3-way gate.** Read `references/codeowners-gate-detail.md` (matching grammar, SHA-pinning rationale, fixture coverage) before ever changing this step's shape.

   **Locate CODEOWNERS pinned to this PR's head SHA** (not the local working tree — Phase 2's rebase hasn't run yet), via GitHub's search order (`.github/`, root, `docs/` — first found wins). Resolve `<head_sha>` once (`gh pr view <n> --json headRefOid --jq .headRefOid`) and reuse it for both calls below — never a value captured earlier in Phase 1 (a new commit landing between captures would let a review pinned to the older SHA still pass, the staleness issue #50 fixed):
   ```bash
   CODEOWNERS_CONTENT=$(python3 "${MH_PLUGIN_ROOT}/hooks/gates/lib/_codeowners_match.py" --discover "<head_sha>" 2>"${TMPDIR:-/tmp}/codeowners-err-$$")
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
   Exit codes: `0` = found (content on stdout, possibly empty), `3` = genuinely absent everywhere (verified-N/A), `4` = a real fetch error (message on stderr). `$CODEOWNERS_ERROR` non-empty → **fail-closed, STOP** ("CODEOWNERS fetch failed, not confirmed absent — the 'never fabricate a clean result' rule applies here too"). `$CODEOWNERS_FOUND` still `0` → **N/A**, proceed to Phase 2.

   **If `$CODEOWNERS_FOUND` is `1`**, parse + match with the shared script, not prose reasoning. Reuse `gh pr diff <n> --name-only` (step 6 already calls it) and step 4's `gh pr view <n> --json reviews -q .reviews` (don't re-fetch either), plus the same `<head_sha>`:
   ```bash
   CHANGED_FILES=$(gh pr diff <n> --name-only)
   REVIEWS_JSON=$(gh pr view <n> --json reviews -q .reviews)
   python3 "${MH_PLUGIN_ROOT}/hooks/gates/lib/_codeowners_match.py" "$CODEOWNERS_CONTENT" "$CHANGED_FILES" "$REVIEWS_JSON" "<head_sha>"
   ```
   `tests/commands/test-ship-merge-codeowners.sh` exercises this shared script directly — see `references/codeowners-gate-detail.md` for the matching grammar and fixture list.

   **Gate — 3-way, not binary**, read off the script's first printed line: `PASS` (every required entry satisfied, or N/A/no-owned-files) → proceed to Phase 2. `STOP` (an unsatisfied `@username` entry, an unparseable pattern, or a non-404 fetch error) → hard Phase 1 failure; render the reason + detail lines. `DEFERRED` (every remaining entry is `@org/team` or a bare email — unresolvable against the reviews API's usernames) → don't stop; carry the detail lines into Phase 2 step 5's prompt for human acknowledgment (same pattern as the branch-protection `--admin` bypass) — proceed to Phase 2.

   `MH_SKIP_CODEOWNERS_GATE=1` is the escape hatch for a repo with no CODEOWNERS policy; detail in `references/codeowners-gate-detail.md`. (The former `convergence-merge-gate.sh` hook that intercepted a raw `gh pr merge` outside this flow was retired with the review pipeline, 2026-08-24 #82 — this command's in-flow gates are now the only merge-door protection.)

---

## Phase 2: Merge (GitHub Server-Side Only)

**Rule**: Merge must happen via GitHub (`gh pr merge`). Never run `git merge` locally and push the result.

1. Fetch latest: `git fetch origin`
2. Rebase onto base branch: `git rebase origin/<base-branch>`
   - Gate: rebase produces conflicts → STOP. Tell user to resolve manually and retry.
3. Force-push rebased branch: `git push --force-with-lease`
4. Decide the merge flags from Phase 1 step 2's protection read — no new API call:
   - **No protection** (step 2 read a 404) → plain merge, no `--admin`.
   - **Protection exists** → cross-check this phase's step 2 rebase result with Phase 1 step 3's CI signal. Rebase replayed commits (not a no-op) **and** CI not N/A → step 3's force-push produced a fresh SHA with no completed checks yet (possibly dismissed reviews too) → `--admin` is needed to land now rather than wait for CI to re-run; a real bypass — say so plainly in step 5, not folded into a generic line. Rebase was a no-op, **or** CI was verified-N/A → the fresh-CI concern doesn't apply, but step 6 still uses `--admin` regardless (protection active always does — no partial-bypass command exists); only the *why* differs: some other protection rule (e.g. required reviews), not an unvalidated CI check.
   - `allow_squash_merge: false` (Phase 1 step 2) → STOP now — `--squash` would fail outright.
   - **Phase 1 step 7 found required CODEOWNER entries (not N/A)** and this phase's rebase replayed commits → **re-run step 7's matching+approval logic** against the new post-rebase SHA before step 6 — a force-push can dismiss stale CODEOWNER approvals the same way it dismisses CI-relevant reviews. Skip when step 7 was N/A or the rebase was a no-op. A newly-unsatisfied `@username` → STOP as in step 7. A newly-DEFERRED entry folds into step 5's prompt like one found in Phase 1.
5. **AskUserQuestion** single-select — this is the explicit go/no-go, the only authorization to merge: "Phase 2: PR [#N] — CI [green / red / pending / N/A — no CI configured], approvals [N], conflicts [none / yes]. Sensitive paths [none / {matched paths from Phase 1 step 6} — this diff touches sensitive surface, confirm deliberately]. [CODEOWNER: N/A / satisfied / DEFERRED — {file} requires {team-or-email} approval, unverified — confirm an owner has approved before proceeding]. Target: [base-branch]. [No branch protection to bypass / Branch protection active — this merge uses --admin to bypass it]. Merge will squash + delete branch. Proceed?" Always render the Sensitive-paths field — a **sensitive** result never auto-blocks, so the go/no-go must show it. Render the CODEOWNER field only when step 7 (or its re-check) returned DEFERRED — omit on PASS/N/A. Base the recommendation on step 4's decision, this phase's rebase result, and Phase 1 step 3's CI signal, not a blanket "Phase 1 already passed" assumption. Render the chosen option's `(best when X)` clause as `(Recommended)` — the list below is a template, not literal text:
   - No protection, protection with a no-op rebase (Phase 1's validated SHA still current), or CI verified-N/A → recommend Merge now.
   - Protection active, rebase replayed commits, and CI not N/A (step 4's fresh-SHA case — likely `pending`) → recommend Abort: the fresh SHA hasn't been CI-validated, so Merge now needs the user to knowingly accept an unvalidated `--admin` bypass, not a default nudge.
   - `Merge now (best when all gates pass and the user is ready to land)` — execute server-side merge. Bypasses branch protection when active (step 4); on a fresh rebased SHA under active protection with a real CI signal, also merges before CI re-runs — not a concern when CI is N/A.
   - `Abort (best when something changed since validation or the user wants to re-check)` — stop; user can re-run later. PR stays unmerged; Phase 1's gate must pass again.
6. Execute **server-side** merge via GitHub CLI, using step 4's flag decision:
   ```bash
   gh pr merge <n> --squash --delete-branch              # no protection (step 4: 404)
   gh pr merge <n> --admin --squash --delete-branch       # protection active — bypass confirmed in step 5
   ```
   - `--admin` bypasses branch protection — include it only when step 4 found protection active and step 5 confirmed the bypass, never as a default.
   - `--squash` collapses the PR into a single commit **on GitHub**; `--delete-branch` removes the remote branch **on GitHub**.
   - Gate: merge attempted without `--admin` and GitHub refuses because a required check is still pending on the post-rebase SHA → STOP, tell the user CI needs to finish or the merge needs the bypass. Don't silently retry with `--admin` unprompted.

**Sync seam:** this merge command is duplicated in `skills/incident/references/hotfix-reference.md` Phase 4 for the P0/P1 emergency path (hotfix strips Phase 1's validation for speed, so it's a deliberately separate call, not a shared subroutine) — see `references/sync-seams.md` before changing the merge flags or confirm-prompt shape here.

7. Pull the result locally: `git checkout <base-branch> && git pull`
8. Verify merge landed: `git log --oneline -3` on target branch.

---

## Phase 3: Clean Up

1. Prune local refs: `git fetch --prune`.
2. If the branch was checked out locally, switch to the target branch and pull.

---

## Phase 4: Monitor

1. If CI was verified-N/A in Phase 1 step 3, skip to step 3 — nothing to monitor. Otherwise check CI on the merged commit: `gh run list --branch <target>` or `gh pr checks` on the closed PR.
2. Failures post-merge → be ready to revert or invoke `mh:incident` (hotfix path).
3. Summarize: PR number, squash merge, commit sha, branch auto-deleted, CI status (or "N/A — no CI configured"). Keep the merge/release note factual, free of AI-flavor tells (no self-congratulation, no hedging).
4. **Suggested next step:**
   - Fix worth recording        → /post-mortem while context is warm
   - Last change before release → /ship-release
   - Base-branch CI red         → mh:incident (per step 2)
   - Otherwise                  → done; pick up the next task

**Done.**

## Anti-Patterns

- **Merge on red CI** — "It'll probably be fine" is how outages start.
- **Rebasing without checking** — rebase rewrites history; ensure the branch is safe to force-push.
- **No post-merge monitoring** — CI on `main` can fail even when the PR branch passed.
- **Unconditional `--admin`** — bypassing branch protection by default defeats Phase 1's checks; use it only when Phase 2 step 4 found protection active, and say so in the confirmation prompt.
