# Hotfix Reference

On-demand detail for `hotfix` skill. Loaded when the agent needs phase-by-phase procedures, output formats, or anti-pattern checks.

---

## Phase 0: Stop the Bleeding (Rollback-First Gate)

**Goal**: Mitigate faster than code. Rollback always beats hotfix on speed.

**Actions**:
1. **Rollback check:** Is the previous commit/artifact known-good?
   - If yes → `git revert <bad-commit-sha>` or trigger rollback deploy. STOP hotfix. Done.
   - If no → continue.
2. **Kill-switch check:** Is there a feature flag, config toggle, or circuit breaker that can disable the broken behavior?
   - If yes → disable it. STOP hotfix. Done.
   - If no → continue.
3. **Scope check — production-wide vs subset:** Does the issue affect **all users / the entire service**, or only a subset (e.g., "3 enterprise clients", "iOS users", "users in region X")?
   - If subset → **decline hotfix**. Redirect to `/fix-bug`. A subset issue is a bug, not an incident. Hotfix risk (emergency `--admin` merge, bypassed review, rollback debt) is not justified when the majority of users are unaffected.
   - If production-wide → continue.
4. **Document why rollback/kill-switch was insufficient** in the PR body.

**Gate**: Rollback or kill-switch resolves the issue → STOP. No hotfix needed. Scope = subset → decline and redirect.

---

## Phase 1: Reproduce

**Goal**: Confirm the bug in under 5 minutes.

**Actions**:
1. Parse user input. Extract severity tier.
2. Reproduce deterministically. If you can't, STOP — escalate to `/fix-bug`.
3. Document the one-liner repro command for the PR.

**Gate**: No repro in 5 min → abort hotfix, route to `/fix-bug`.

---

## Phase 2: Fix

**Goal**: Smallest surgical change that resolves the repro.

**Actions**:
0. **Branch setup:** resolve the production branch — the branch prod deploys/tags cut from (repo CLAUDE.md → deploy config → latest release tag; never assume the repo default branch — gitflow defaults are integration branches). Then `git fetch origin && git switch -c hotfix/<ticket>-<slug> origin/<prod-branch>`.
1. Localize the bug — which file, which line.
2. Implement the fix. **No refactors.** No "while I'm here" changes.
3. Run the repro again — confirm it's fixed.
4. Regression test:
   - P0: Write test if possible in <3 min. If not, document manual verification steps.
   - P1/P2: Write minimal regression test. No exceptions.

**Gate**: Change touches >3 files or requires structural rework → abort hotfix, route to `/fix-bug`.

---

## Phase 3: Fast Review

**Goal**: One-pass review in parallel, not sequential. Timebox per tier.

**Actions**:
1. Launch `code-reviewer` agent (simplicity + correctness focus).
2. If fix touches auth/secrets/external input → also launch `security-reviewer` agent in parallel.
3. Wait for both. Consolidate into two buckets only:
   - **Block** — must fix before merge (security, data loss, breaks prod)
   - **Ship** — everything else is a follow-up
4. Fix Block items inline. Do NOT block on Minor/Important.

**Timebox**:
- P0: 3 minutes for review. Only Block items checked.
- P1: 10 minutes for review.
- P2: 15 minutes for review.

**Gate**: Block items exist and can't be fixed in timebox → abort hotfix, route to `/fix-bug`.

---

## Phase 4: Merge (GitHub Server-Side Only)

**Goal**: Land the fix immediately via GitHub. Never `git merge` locally + push.

**Actions**:
1. Commit with message prefix `hotfix:` + severity tag + short description + issue ref.
   ```
   hotfix(P0): null guard in auth middleware — prevents 500 on missing header

   Fixes #1234
   ```
2. Push branch: `git push origin <branch>`
3. Create PR with emergency labels — **`--base` is the production branch the hotfix was cut from, never the integration branch (develop):**
   ```bash
   gh pr create --base <prod-branch> --title "hotfix(P0): ..." --body "Emergency fix for ...\n\nRepro: ...\nRollback path: ..." --label "hotfix" --label "P0"
   ```
4. **AskUserQuestion** single-select: "Phase 4: severity = [P0/P1/P2], Block items = [0 / N], CI = [green / pending]. Merge will bypass branch protection (--admin). Proceed?"
   - `Merge now (Recommended when Block items are resolved and the user accepts the bypass risk)` — execute server-side merge
   - `Wait for normal CI (Recommended for P2 or when bypass is not acceptable)` — stop; user can run `/ship-merge` later
5. **Merge via GitHub CLI (server-side only):**
   ```bash
   gh pr merge <n> --admin --squash --delete-branch
   ```
   - `--admin` bypasses branch protection (use only when authorized).
   - `--squash` collapses to one commit.
   - `--delete-branch` cleans up.
   - **Caveat:** If repo has merge queues with "Do not allow bypassing" enabled, `--admin` may be blocked. Escalate to repo admin or use a GitHub App token.
6. Pull locally: `git checkout <base-branch> && git pull` (`<base-branch>` = the production branch the hotfix was cut from)
7. Verify merge landed: `git log --oneline -3`
8. If the repo has an integration branch (`develop`): backmerge `<prod-branch>` → `develop` immediately (merge commit, not rebase) — or open the backmerge PR now and record it in Phase 6 notes.

---

## Phase 5: Post-Merge Verify

**Goal**: Confirm the fix works in production. Be ready to revert.

**Actions**:
1. Watch CI on merged commit:
   ```bash
   gh run list --branch <base-branch> --limit 5
   gh run watch <run-id>
   ```
2. Run repro one more time against production/staging to confirm fix.
3. Monitor for 10 minutes (P0: 10 min, P1: 15 min, P2: 30 min).
4. If error rate spikes or symptoms return → **revert immediately** (`git revert <hotfix-sha>`) rather than debugging forward.
5. Summarize: severity, what broke, one-line fix, commit sha, monitoring instructions.

**Gate**: CI fails post-merge or symptoms return → revert, do NOT patch forward.

---

## Phase 6: Post-Mortem Scheduling

**Goal**: Ensure follow-up documentation happens within SLA.

**Actions**:
1. Tell user: "Schedule `/post-mortem` within 24 hours for P0/P1, within 72 hours for P2."
2. If user says "do it now", invoke `/post-mortem` immediately.
3. Summarize: severity, what broke, fix commit sha, rollback path, monitoring result.

**Done.**

---

## Output Format

**If declining the hotfix** (subset scope, non-urgent, kill-switch sufficient): produce a clear decline message without the ledger. State the Phase 0 gate that was hit, why it's not a hotfix, and the correct route (`/fix-bug`, normal PR, or "kill-switch applied — no code needed").

**If proceeding with the hotfix:** produce a running ledger in this format:

```
Hotfix | P<X> | <timestamp>
Phase 0: <rollback/kill-switch result | SKIP>
Phase 1: <repro command | PASS/FAIL | time>
Phase 2: <files changed | lines changed | repro re-run result>
Phase 3: <reviewers launched | Block count | Ship count | time spent>
Phase 4: <PR # | merge strategy | commit sha>
Phase 5: <CI result | prod repro result | monitor duration | revert decision>
Phase 6: <post-mortem scheduled Y/N | due date>
```

---

## Anti-Patterns

- **"Fix forward without trying rollback"** — The fastest fix is usually the previous commit. Try it first.
- **Hotfix PR to the integration branch** — basing on `develop` (or PR-ing a main-cut branch to `develop`) ships nothing to production and drags unreleased work into the release. Cut from the production branch; PR back to the same branch.
- **"While I'm here..."** — Hotfix is not the time for cleanup. Every extra line increases rollback risk.
- **"Subset of users = hotfix"** — Affecting only some users (even enterprise ones) is a bug, not an incident. Route to `/fix-bug`.
- **Skipping repro** — "I know what the bug is" without reproducing is a guess. Repro first.
- **Waiting for full review** — If Block items are resolved, merge. Don't wait for Minor nits.
- **No follow-up** — Every hotfix needs a post-mortem. Without it, the same bug will hotfix again.
- **Merging locally** — `git merge` + push skips GitHub branch protection and audit trail. Always `gh pr merge`.

---

## METHODOLOGY Alignment

- **Rule 1 (Decision-sizing triad):** Phase 0 forces a rollback check before any code is written.
- **Rule 2 (Match surface area to proven need):** "One file, one line if possible" — smallest change wins.
- **Surgical:** Hotfix is isolated; no adjacent code touched.
- **Rule 4 (Define done. Loop until verified):** MTTM target is the success criterion, not the fix itself.
- **Surface conflicts, don't average:** Severity tiers prevent averaging — P0 means skip, P2 means wait for CI.
- **Fail loud:** Phase 5 revert gate is explicit; CI failure → revert, not patch forward.
