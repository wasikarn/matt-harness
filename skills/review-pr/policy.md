# Tightening Policy — SCRUTINIZE-4 Rejection-Rate Ledger

The ledger (see `ledger.md`) records per-Q rejection counts. The policy decides **when and how to tighten the gate** so the rubric gets *stricter over time where it matters*, without drifting into "gate too strict, agents under-report" (the failure mode that makes SCRUTINIZE-4 useless in the other direction).

## Threshold

A Q is eligible for tightening when **both** conditions are met:

1. **Rate**: rejection rate ≥ **50%** in the rolling 10-session window.
2. **Sample size**: ≥ **5 sessions of data** (so a single noisy session cannot trigger tightening on a Q with 1-of-1 rejections = 100%).

If either condition fails, the Q is **not eligible** for tightening this session. The trend line still surfaces (Phase 6), but no policy change.

## Tightening action

When a Q is eligible, the orchestrator promotes the Q's falsifiable check to a **stricter rule** for the current session only (ephemeral; not persisted to `SKILL.md`):

| Q | Default check (SCRUTINIZE-4) | Tightened check (when eligible) |
|---|-------------------------------|----------------------------------|
| Q1 Challenge intent | "You can name the simpler alternative in one sentence, OR you can name why the existing approach is the right one" | "You must name the simpler alternative AND justify why it was rejected (1 sentence each)" |
| Q2 Trace call graph | "You followed the call path; the result is 'safe' or 'unsafe' with `file:line` evidence" | "You must trace 2+ callers of the changed function, with `file:line` for each" |
| Q3 Verify execution branches | "You named at least one branch (success + 1 error/edge) and traced it" | "You must trace 2+ error/edge branches (not just 1)" |
| Q4 Evidence requirement | "Finding has `file:line` (or commit SHA) + the *minimal* command/output that confirms it" | "Finding has `file:line` AND a *reproducible* command (one that the user can re-run and get the same output)" |

Tightening is communicated to the user as: `Q3 tightened for this session (67% rejection over 10 sessions — was 45%)`. After the session, the tightening is *not persisted* — the next session re-evaluates eligibility from the (updated) ledger.

## Hard caps

| Cap | Value | Why |
|---|---|---|
| Max 1 tightening event per Q per **90 days** (rolling) | 1 | Prevents drift into "the gate is now 4× stricter than v1". Once a Q has been tightened, it has to *hold* its improved rejection rate for 90 days before it can be tightened again. |
| Max 1 tightening event **per session** (across all Qs) | 1 | Prevents a single bad session from cascading into a 4-Q tightening storm. If multiple Qs are eligible, pick the one with the highest rate. |
| Ledger size | 200 sessions (FIFO) | Bounded disk. Pruned on session start. |
| Sample size for eligibility | ≥ 5 sessions | A single noisy session with 1-of-1 rejections = 100% should not trigger tightening. |

## Reversibility

A tightening event is **fully reversible** in one line. The user can:

1. **Undo this session's tightening**: tell the orchestrator "skip the policy", the default SCRUTINIZE-4 check is used for all Qs this session. The ledger still records the session, but with a `policy_skipped: true` footer line.
2. **Reset the ledger**: delete all `.scratch/review-pr-*/ledger.md` files. The next session starts with no history; eligibility is unreachable until 5 fresh sessions accumulate. Useful when the project changes scope (e.g. moved from `auth-refactor` work to `frontend-polish` — old rejection rates are stale).
3. **Reset one Q's counter**: keep the ledger, but tag the last N ledgers as `Q3: ignored` (see `ledger.md` § Format) and drop those whole files from the `find`/`head -10` input when computing that Q's rate. Coarser than per-row (it excludes the tagged session's other 3 Qs too, for that run), but still narrower than a full ledger reset.

## Aggregation helper (awk one-liner)

The orchestrator can compute the rolling rate for a single Q with:

```bash
find .scratch -path '*/review-pr-*/ledger.md' -type f -exec stat -f '%m %N' {} + \
  | sort -rn | head -10 \
  | cut -d' ' -f2 \
  | xargs awk -F'|' '
    /^\| Q[0-9] / {
      qnum = $2; gsub(/[^0-9]/, "", qnum)
      rej = $3; gsub(/ /, "", rej)
      sur = $4; gsub(/ /, "", sur)
      rejected[qnum] += rej
      survived[qnum] += sur
    }
    END {
      for (q in rejected) {
        r = rejected[q]; s = survived[q];
        # Skip 0-rejection rows: nothing to tighten on. (Eligibility gate
        # in §Threshold already filters by ≥50%, so 0% never qualifies.)
        if (r > 0) printf "Q%s: %d%%\n", q, (r*100)/(r+s)
      }
    }'
```

(For a single-Q query, restrict `awk` to the row you want.) No binary dependency, no install. The orchestrator runs it inline during Phase 6 trend-line emission.

**macOS note**: this uses `stat -f '%m %N'` (BSD stat, mtime in seconds + filename) so it works on macOS — `find -printf` is GNU-only and silently fails on the BSD `find` shipped with macOS, which would surface as "no ledger data" in Phase 6 with no error. **Gotcha:** BSD stat's `%p` is octal permission bits (e.g. `100644`), not the path — `%N` is the filename.

## What this policy is *not*

- **Not an ML system.** No training, no model, no auto-tuning. Just counters + thresholds. Per `skills/orchestrate/SKILL.md`'s Verify-tier principle (non-code producer output — stats, patterns, claims — needs corroboration before it's trusted), anything cleverer than counters + thresholds is exactly that kind of artifact and needs the same explicit verification here.
- **Not a hard blocker.** A tightening is an *advisory strictness* — the orchestrator surfaces it, the user can override. The gate is not silently enforced; the user sees the rule being applied.
- **Not persistent across machines.** `.scratch/` is local. A second clone / a new machine starts with no ledger history.
