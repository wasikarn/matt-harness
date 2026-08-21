---
name: review-dashboard
description: "List every in-flight PR review's status in one table, or drill into one PR/branch. Don't use for merge decisions (/ship-merge) or running a review (kbg:review-pr)."
argument-hint: "[pr-number|branch]"
model: inherit
effort: medium
---

# Review Dashboard

Aggregates `kbg:review-pr`'s own state files into one view. Read-only — never
writes, never scores a merge decision, never triggers a review. Every field
shown is a raw read of what `skills/review-pr/scripts/write-review-state.sh`
already wrote; this command adds no new tracking.

**Why this exists**: nothing else in this codebase globs
`review-pr-*.json` — `ship-merge/COMMAND.md`, `address-review/COMMAND.md`, and
`should-continue-loop.sh` all resolve one already-known PR#/branch. This is
the first surface that lists what's actually in flight.

**Complementary native command**: this dashboard answers "what's the status of PR N's
review." `claude --from-pr <N>` answers the follow-up — it opens the session picker
filtered to whichever Claude Code sessions are linked to that PR, so you can reopen the
one that actually produced the review instead of starting fresh.

## Default: list every active review

Extracted to `skills/review-pr/scripts/render-dashboard.sh` (2026-08-15 — this was the
largest embedded `python3 -c` block among this repo's `.md` commands, past the point
where this repo's own precedent, `hooks/gates/lib/_codeowners_match.py`, says it
should already be a real file; pure move, no logic change). Reads
`REVIEW_PR_STATE_DIR` (default `~/.claude/state`), same as
`write-review-state.sh`/`should-continue-loop.sh`.

```bash
bash skills/review-pr/scripts/render-dashboard.sh
```

**If the printed object has a non-null `own_branch_state_path` key** (an
own-branch review exists — `{}` alone means it doesn't, that's still valid
JSON so check the key, not just "is it an object"), and `own_branch_current_head`
is **not** null, run `should-continue-loop.sh` against that real current
HEAD to show the *authoritative* auto-continue verdict — reuse the real
decision script, don't re-derive `convergence_state`/`force_human` logic
here (the exact sync-seam ADR 0009's implementation was about closing):

```bash
bash skills/review-pr/scripts/should-continue-loop.sh "<own_branch_current_head from the JSON above>" ""
```

**Never pass the state file's own `last_sha`** as the expected sha here —
that was the tautological bug above. Render the script's two-line output as
`Auto-continue verdict: continue` or `Auto-continue verdict: stop
(reason=<token>)`. **If `own_branch_current_head` is null** (branch
unresolvable from this working directory — deleted, or you're not in the
right repo), print `Auto-continue verdict: unavailable — can't resolve
<branch>'s current HEAD from here` instead of guessing.

**Do not compute a `ship-merge`-style score anywhere in this command.** For
Critical findings, print the raw count with a one-line pointer only —
`Critical findings: 0 (ship-merge weights this 30/100 — see /kbg:ship-merge
for the actual merge decision)` — never a computed pass/fail of your own.

## Drill-down: `/review-dashboard <pr-number-or-branch>`

1. **Resolve the target** — same pattern as `address-review/COMMAND.md`'s
   Phase 1 step 1:
   - No argument → `gh pr view --json number,headRefOid,headRefName,url` (current branch's PR)
   - A bare integer `<n>` → `gh pr view <n> --json number,headRefOid,headRefName,url`
   - Anything else → treat as a branch name; there is no PR to resolve, read
     `review-last.json` directly and check its `branch` field matches.
2. **Read the one relevant state file** — PR-keyed
   (`review-pr-<n>.json`) if a PR number resolved, else `review-last.json`
   (same fallback order `ship-merge/COMMAND.md` Phase 1 already documents).
3. **Render every field**, human-labeled: `review_mode`, `round`,
   Critical/Important/Minor counts + `prev_*` deltas, `convergence_state`,
   `clean`, `rehunt`, `last_sha` (full), `branch`, `ts` (with computed age),
   `stalled`, `regressed`, `force_human`, `finding_files` (if non-empty),
   `file_streaks`/`churn_files` (if non-empty). Same "point at ship-merge,
   don't score" rule as the list view for anything ship-merge's gate weighs.
4. **Get the real current HEAD to check freshness against** — prefer step 1's
   `headRefOid` if a PR was resolved; otherwise (branch-name target) run
   `git rev-parse <branch>` (best-effort — the branch may be deleted, or this
   command may run from a different repo). **Never use the state file's own
   `last_sha` as the freshness reference** — it would always trivially match
   itself, defeating the one check `should-continue-loop.sh`'s `stale-sha`
   guard exists to run (tautology bug found in a deep-audit pass, 2026-08-14).
   - **If the state file's `last_sha` doesn't match this real current HEAD**,
     say so explicitly — `⚠ state is stale: last reviewed <sha>, current HEAD
     is now <sha>` — this command never re-runs a review to refresh it;
     that's `kbg:review-pr`'s job.
   - **If the real current HEAD couldn't be resolved at all**, say so —
     `⚠ can't verify freshness — <branch>'s current HEAD isn't resolvable
     from here` — and skip step 5 rather than guessing.
5. **If `review_mode == "own-branch"` and step 4 resolved a real current
   HEAD**, run `should-continue-loop.sh "<real current HEAD>" ""` and render
   its verdict the same way the list view does.

## Notes

- `review-last.json` is a single shared slot keyed by branch name (not a
  history) — reviewing branch A, then B, then A again shows only A's *second*
  pass. This command surfaces the `branch` field so that's visible, not
  hidden.
- Rejection-rate trend / ledger health (`skills/review-pr/ledger.md`,
  `policy.md`) is a different axis (session-level fleet health, not
  per-review status) and already surfaces in `review-pr-finish`'s own Phase 6 —
  intentionally not duplicated here.
- The `.scratch/<slug>/proofs/` evidence directory `review-pr-finish/SKILL.md`
  specifies is never actually instantiated in real usage (confirmed against
  every session directory on disk) — this command doesn't render an
  always-empty evidence section for it.
