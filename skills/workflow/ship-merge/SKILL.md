---
name: ship-merge
description: "Ship a PR: validate, server-side merge, monitor CI."
argument-hint: "[pr-number|branch]"
disable-model-invocation: true
disable-model-invocation-reason: external, irreversible action — executes a server-side PR merge on GitHub that cannot be undone; only a human-typed /mh:ship-merge, confirmed through Phase 2's explicit go/no-go, may trigger it
model: inherit
effort: high
---

# Ship Merge

**When to use / not:** use when a reviewed PR is ready to land. Don't use for failing CI or
hotfixes (`mh:incident`).

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

   Run the step as written in `references/codeowners-gate-detail.md`'s "Step 7 — commands and gate" section: locate CODEOWNERS pinned to the PR head SHA via `_codeowners_match.py --discover`, then match with the shared script. Gate is 3-way off the script's first printed line: `PASS` → Phase 2; `STOP` → hard Phase 1 failure; `DEFERRED` (`@org/team` / bare email) → carry the detail lines into Phase 2 step 5's prompt. A fetch error is fail-closed, never "absent".

   `MH_SKIP_CODEOWNERS_GATE=1` is the escape hatch for a repo with no CODEOWNERS policy; detail in `references/codeowners-gate-detail.md`. (The former `convergence-merge-gate.sh` hook that intercepted a raw `gh pr merge` outside this flow was retired with the review pipeline, 2026-08-24 #82 — this command's in-flow gates are now the only merge-door protection.)

---

## Phase 2: Merge (GitHub Server-Side Only)

**Rule**: Merge must happen via GitHub (`gh pr merge`). Never run `git merge` locally and push the result.

1. Fetch latest: `git fetch origin`
2. Rebase onto base branch: `git rebase origin/<base-branch>`
   - Gate: rebase produces conflicts → STOP. Tell user to resolve manually and retry.
3. Force-push rebased branch: `git push --force-with-lease`
   - **Who runs steps 1–3:** one dispatched foreground `general-purpose` agent, not main. F9-style brief: PR number + branch + `<base-branch>`; run exactly `git fetch origin`, `git rebase origin/<base-branch>`, `git push --force-with-lease` — nothing else — and report the verbatim output, including whether the rebase replayed commits or was a no-op (step 4 reads that). `irrecoverable.sh` still gates that agent's Bash calls; this moves who issues the command, not what checks it.
4. Decide the merge flags from Phase 1 step 2's protection read — no new API call. Read `references/merge-flag-decision.md` (steps 4-5, verbatim): no protection → plain merge; protection active → `--admin` always, with the *why* depending on whether the rebase replayed commits under a real CI signal; `allow_squash_merge: false` → STOP; CODEOWNER entries + replayed rebase → re-run step 7 against the new SHA.
5. **AskUserQuestion** single-select — the explicit go/no-go, the only authorization to merge. Prompt template, field-rendering rules (Sensitive paths always; CODEOWNER only on DEFERRED), and the Merge-now / Abort recommendation logic keyed to step 4: `references/merge-flag-decision.md`.
6. Execute **server-side** merge via GitHub CLI, using step 4's flag decision:
   ```bash
   gh pr merge <n> --squash --delete-branch              # no protection (step 4: 404)
   gh pr merge <n> --admin --squash --delete-branch       # protection active — bypass confirmed in step 5
   ```
   - **Who runs it:** one dispatched foreground `general-purpose` agent, not main. Brief: PR number + step 4's flag decision; run exactly that one `gh pr merge` line, nothing else, and report the verbatim output. `merge-door.sh` and `irrecoverable.sh` still apply their own checks to that agent's Bash call — this moves who issues the command, not what gates it.
   - `--admin` bypasses branch protection — include it only when step 4 found protection active and step 5 confirmed the bypass, never as a default.
   - `--squash` collapses the PR into a single commit **on GitHub**; `--delete-branch` removes the remote branch **on GitHub**.
   - Gate: merge attempted without `--admin` and GitHub refuses because a required check is still pending on the post-rebase SHA → STOP, tell the user CI needs to finish or the merge needs the bypass. Don't silently retry with `--admin` unprompted.
   - Fold step 7 (below) into this same dispatched agent's brief — after the merge report comes back, the same agent runs step 7's `git checkout <base-branch> && git pull` as the final action and reports that output too, rather than main running it or a second agent being dispatched.

**Sync seam:** this merge command is duplicated in `skills/workflow/incident/references/hotfix-reference.md` Phase 4 for the P0/P1 emergency path (hotfix strips Phase 1's validation for speed, so it's a deliberately separate call, not a shared subroutine) — see `references/sync-seams.md` before changing the merge flags or confirm-prompt shape here.

7. Pull the result locally: `git checkout <base-branch> && git pull` — same dispatched agent as step 6, run as that agent's final action (not main; `git checkout`/`git pull` aren't on main's read-only allowlist either — see step 6's note).
8. Verify merge landed: `git log --oneline -3` on target branch (`git log` is read-only — main can run this one itself).

---

## Phase 3: Clean Up

1. Prune local refs: `git fetch --prune`.
   - **Who runs it:** one dispatched foreground `general-purpose` agent, not main (`git fetch` isn't on the read-only allowlist). Brief: run exactly `git fetch --prune` and report the verbatim output.
2. If the branch was checked out locally, the same dispatched agent as step 1 switches to the target branch and pulls.

---

## Phase 4: Monitor

1. If CI was verified-N/A in Phase 1 step 3, skip to step 3 — nothing to monitor. Otherwise check CI on the merged commit: `gh run list --branch <target>` or `gh pr checks` on the closed PR.
2. Failures post-merge → be ready to revert or invoke `mh:incident` (hotfix path).
3. Summarize: PR number, squash merge, commit sha, branch auto-deleted, CI status (or "N/A — no CI configured"). Keep the merge/release note factual, free of AI-flavor tells (no self-congratulation, no hedging).
4. **Suggested next step:**
   - Fix worth recording → `mh:post-mortem` while context is warm
   - Base-branch CI red  → `mh:incident` (per step 2)
   - Otherwise           → done; pick up the next task

**Done.**

## Anti-Patterns

- **Merge on red CI** — "It'll probably be fine" is how outages start.
- **Rebasing without checking** — rebase rewrites history; ensure the branch is safe to force-push.
- **No post-merge monitoring** — CI on `main` can fail even when the PR branch passed.
- **Unconditional `--admin`** — bypassing branch protection by default defeats Phase 1's checks; use it only when Phase 2 step 4 found protection active, and say so in the confirmation prompt.
