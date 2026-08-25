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
   - If subset → **decline hotfix**. Redirect to `mattpocock-skills:diagnosing-bugs`. A subset issue is a bug, not an incident. Hotfix risk (emergency `--admin` merge, bypassed review, rollback debt) is not justified when the majority of users are unaffected.
   - If production-wide → continue.
4. **Document why rollback/kill-switch was insufficient** in the PR body.

**Gate**: Rollback or kill-switch resolves the issue → STOP. No hotfix needed. Scope = subset → decline and redirect.

---

## Phase 1: Reproduce

**Goal**: Confirm the bug in under 5 minutes.

**Actions**:
1. Parse user input. Extract severity tier.
2. Reproduce deterministically. If you can't, STOP — escalate to `mattpocock-skills:diagnosing-bugs`.
3. Document the one-liner repro command for the PR.

**Gate**: No repro in 5 min → abort hotfix, route to `mattpocock-skills:diagnosing-bugs`.

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

**Gate**: Change touches >3 files or requires structural rework → abort hotfix, route to `mattpocock-skills:diagnosing-bugs`.

---

## Phase 3: Fast Review

**Goal**: One-pass review in parallel, not sequential. Timebox per tier.

**Actions**:
1. Launch the matching per-language reviewer agent (`typescript-reviewer`/`python-reviewer`; simplicity + correctness focus).
2. If fix touches auth/secrets/external input → also launch `security-reviewer` agent in parallel.
3. Wait for both. Consolidate into two buckets only — if both reviewers flag the same file:line, note it once rather than picking one silently:
   - **Block** — must fix before merge (security, data loss, breaks prod)
   - **Ship** — everything else is a follow-up
4. Fix Block items inline. Do NOT block on Minor/Important.

**Timebox**:
- P0: 3 minutes for review. Only Block items checked.
- P1: 10 minutes for review.
- P2: 15 minutes for review.

**Gate**: Block items exist and can't be fixed in timebox → abort hotfix, route to `mattpocock-skills:diagnosing-bugs`.

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
   Write the body to a temp file first (the Write tool, not a bash heredoc or quoted string —
   real hotfix content routinely contains apostrophes/backticks that break inline shell-string
   construction; `--body-file` sidesteps quoting entirely), matching this structure — mirrors
   `mh:pr`'s Summary/Changes/Testing/Related-Issues headings (see `skills/review/pr/SKILL.md` Phase 4)
   plus a hotfix-only **Rollback** section:

   ```markdown
   ## Summary

   <P0/P1/P2> hotfix: <what broke, one line> — <what this fix does, one line>

   ## Changes

   <files touched, one line>

   ## Testing

   Repro: `<repro command>`
   <regression test note from Phase 2, or "manual verification: ...">

   ## Rollback

   <rollback path if this fix needs to be reverted>

   ## Related Issues

   Fixes #<issue>
   ```

   Then:
   ```bash
   gh pr create --base <prod-branch> --title "hotfix(P0): ..." --body-file <path-to-file> --label "hotfix" --label "P0"
   ```
   A hotfix skips `mh:pr`'s own preview-confirm gate for speed (Phase 0-3 already are the review), but
   the body shape stays the same so a hotfix PR reads like every other PR in this repo.
4. **AskUserQuestion** single-select: "Phase 4: severity = [P0/P1/P2], Block items = [0 / N], CI = [green / pending]. Merge will bypass branch protection (--admin). Proceed?" Recommend whichever option this incident's actual severity favors — P0/P1 favors Merge now (production stays broken every minute you wait, and Phase 0 already ruled out rollback/kill-switch as sufficient); P2 favors Wait for normal CI — and render that pick as the literal `(Recommended)` tag on the matching option below, replacing its `(best when X)` clause at render time; the template below spans all severities, it isn't fixed text to paste verbatim.
   - `Merge now (best when Block items are resolved and the user accepts the bypass risk)` — execute server-side merge. Bypasses branch protection.
   - `Wait for normal CI (best for P2 or when bypass is not acceptable)` — stop; user can run `mh:ship-merge` later. Production stays on the current build for however long CI + normal review takes.
5. **Merge via GitHub CLI (server-side only):**
   ```bash
   gh pr merge <n> --admin --squash --delete-branch
   ```
   - `--admin` bypasses branch protection (use only when authorized).
   - `--squash` collapses to one commit.
   - `--delete-branch` cleans up.
   - **Caveat:** If repo has merge queues with "Do not allow bypassing" enabled, `--admin` may be blocked. Escalate to repo admin or use a GitHub App token.

**Sync seam:** `skills/workflow/ship-merge/SKILL.md` Phase 2 duplicates this exact merge command
(same `gh pr merge`/`AskUserQuestion` shape) — the two are intentionally not the
same call, since hotfix strips the scored gate for speed. Unconditional `--admin`
here is deliberate, not drift: an emergency P0/P1 merge always needs the bypass,
unlike ship-merge's normal path (which now conditions `--admin` on branch
protection actually being active). If you edit the merge flags or the confirm
prompt here, check whether ship-merge's Phase 2 needs the matching edit too.
**Checked 2026-08-10:** ship-merge.md's Phase 2 ask carried the same unresolved
`(best when X)` pattern this edit fixed here — flagged as a separate, out-of-scope
gap when this note was first written, then closed the same day once the user
confirmed it as a follow-up. Ship-merge's Phase 2 step 5 now has its own
default-recommendation sentence too, keyed to its own rebase-freshness signal
(not severity — that axis doesn't exist there), not a copy of this step's logic.

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
1. Tell user: "Schedule `/mh:post-mortem` within 24 hours for P0/P1, within 72 hours for P2."
2. If user says "do it now", start the post-mortem work (`mh:post-mortem`) immediately.
3. Summarize: severity, what broke, fix commit sha, rollback path, monitoring result.

**Done.**

---

## Output Format

**If declining the hotfix** (subset scope, non-urgent, kill-switch sufficient): produce a clear decline message without the ledger. State the Phase 0 gate that was hit, why it's not a hotfix, and the correct route (`mattpocock-skills:diagnosing-bugs`, normal PR, or "kill-switch applied — no code needed").

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
- **"Subset of users = hotfix"** — Affecting only some users (even enterprise ones) is a bug, not an incident. Route to `mattpocock-skills:diagnosing-bugs`.
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
