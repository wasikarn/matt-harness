# Hotfix path (reference for `kbg:incident`)

The fix-forward branch of `kbg:incident`, loaded from step 6 when rollback/kill-switch is insufficient. Ship a critical fix fast — a compressed `/fix-bug` + `kbg:review-pr` + `/ship-merge` with gates removed for speed. **Rollback first, fix forward second.** The main agent executes inline (no sub-agents) and acts with surgical speed; the irreversible `gh pr merge --admin` is reached only after the in-skill severity + review gates below.

## Core Principles

- **Stop the bleeding first.** Rollback or kill-switch is always faster than code. Only hotfix when rollback is impossible or insufficient.
- **Branch from the production branch — resolve it first.** The production branch is the one prod deploys/tags actually cut from (check repo CLAUDE.md → deploy config → latest release tag). Never assume the repo default branch: in gitflow-style repos the default is the integration branch (`develop`), and a hotfix based there ships unreleased work. `git fetch origin && git switch -c hotfix/<ticket>-<slug> origin/<prod-branch>`. The PR targets `<prod-branch>` — never the integration branch. After merge: backmerge `<prod-branch>` → `develop` (merge, not rebase) if an integration branch exists.
- **Severity drives speed.** P0 = ship in <15 min. P1 = <1 hr. P2 = <4 hr. Maps 1:1 to kbg:incident's
  S-tier by MTTR: S1↔P0, S2↔P1, S3↔P2 (S4/noise never reaches this path).
- **Smallest possible change.** One file, one line if possible. No refactors, no cleanups.
- **Server-side merge only.** Never `git merge` locally + push. Use `gh pr merge --admin`.
- **Post-merge watch, not hope.** Verify CI + monitor for 10 minutes. Be ready to revert.

---

## Severity Classification

Infer from user input or ask explicitly.

| Tier | User Says | MTTM Target | Merge Gate |
|------|-----------|-------------|------------|
| **P0** | "down", "outage", "exploit", "data loss", "P0" | <15 min | Zero Block items. Skip non-Critical review. `--admin` merge immediately after fix + 1 reviewer. |
| **P1** | "critical", "security patch", "broken", "P1" | <1 hr | Fast review (code-reviewer + conditional security-reviewer). Minimal regression test. `--admin` merge. |
| **P2** | "degraded", "slow", "SLO breach", "P2" | <4 hr | Standard fast review. Full regression test. Use `/ship-merge` (admin-merges when branch protection is active); only hold for full CI when CI is green and the change is large enough to warrant the wait. |

**Default if unclear:** Assume P1. Do not waste time debating — pick one and move.

---

## Phase Overview

| Phase | Goal | Gate |
|-------|------|------|
| 0 | Rollback / kill-switch first | Resolves? STOP. Subset scope? Decline |
| 1 | Reproduce in <5 min | No repro → abort to `/fix-bug` |
| 2 | Smallest surgical fix | >3 files / structural rework → abort |
| 3 | Fast review (parallel) | Block items unresolved → abort |
| 4 | Server-side merge via `gh pr merge --admin` | Never merge locally + push |
| 5 | Post-merge verify + monitor | CI fails / symptoms return → revert |
| 6 | Schedule `/post-mortem` | Within 24h (P0/P1) or 72h (P2) |

## Handoff Reference

| Phase | Action | When |
|---|---|---|
| 0 → 1 | Rollback or kill-switch check | Before any code change |
| 1 → 2 | Branch `hotfix/<ticket>-<slug>` from `origin/<prod-branch>`, then fix inline | After repro confirmed ≤5 min |
| 2 → 3 | Launch `code-reviewer` (+ `security-reviewer` if needed) | After fix + regression test |
| 3 → 4 | Commit + push + `gh pr merge --admin --squash --delete-branch` | After zero Block findings |
| 4 → 5 | `gh run watch` + repro against prod | After merge |
| 5 → 6 | Tell user to schedule `/post-mortem` | After verify passes |

See `hotfix-reference.md` (same dir) for: full Phase 0–6 procedures, output format (ledger), anti-patterns, and METHODOLOGY alignment.
