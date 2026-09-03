# Phase 1 step 1 — branch assertion (moved verbatim from `SKILL.md`)

Read this before Phase 1 step 1's PR resolution completes — the assertion below is a
whole-flow halt, not just an edit gate.

   - **Assert working branch == PR branch before doing anything else in this command.** Run `git rev-parse --abbrev-ref HEAD`; it must equal `headRefName`. If it differs, STOP the entire run — don't fetch, triage, or edit: `git checkout <headRefName>` (if the local branch exists and worktree is clean) or tell the user they're on the wrong branch. This is a whole-flow halt, not just an edit gate — Phase 2's `isOutdated` handling reads the worktree's current state, so a mismatch corrupts triage too, and risks landing fixes on the wrong PR (the `fix/TP-582`-while-addressing-`feature/TP-650` failure mode).
   - Once the branch check passes, confirm local HEAD is current: `git fetch` and compare against `headRefOid` (or `git pull --ff-only` if behind) — branch-name equality alone doesn't catch a stale worktree, which risks an outdated diff or a rejected non-fast-forward push later.
