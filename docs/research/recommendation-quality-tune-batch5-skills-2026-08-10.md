# Recommendation-quality tune — batch 5 (smallest skills cluster)

Date: 2026-08-10. Fifth batch from issue #40 (Level-B backlog:
`recommendation-quality-tune-2026-08-10.md`). Follows batch 2 (fix-bug/review-pr/code-reviewer),
batch 3 (`/ship` pipeline cluster), batch 4 (review-agent cluster).

## Scope and rigor

Batch = the 3 remaining files with exactly 1 open gap each: `skills/production-audit/SKILL.md`,
`skills/incident/SKILL.md`, `skills/goal-craft/SKILL.md`. Mirrors batch 4's shape — smallest,
lowest-risk remaining cluster first. Same rigor as batches 2-4 — **Level B only, unmeasured**.
Gaps re-graded against current file content before editing; all 3 matched their original
citations exactly, no drift.

## What was changed

| File | Gap closed | Fix |
|---|---|---|
| `skills/production-audit/SKILL.md` | 8 REVISIT-TRIGGER | Added a re-audit condition after Output Format: once `Blockers` are fixed, re-run before actual launch — a fixed blocker changes the score band |
| `skills/incident/SKILL.md` | 7 SELF-CONSISTENCY | Step 3's mitigation-confirm ask now skips (escalates immediately) when blast radius is confirmed expanding — matching the file's own pre-existing "Escalate, don't absorb" rule. Explicitly never skips toward `Execute mitigation now` |
| `skills/goal-craft/SKILL.md` | 5 ASK-CONSEQUENCES | Step 2's ask now requires each option to state what it changes about the resulting `/goal` condition, not a bare label |

3 of 3 gaps in scope closed. No gap left open or deliberately skipped.

## Char deltas

| File | Before | After | Delta |
|---|---|---|---|
| `skills/production-audit/SKILL.md` | 8,424 chars | 8,599 chars | +2.08% |
| `skills/incident/SKILL.md` | 5,548 chars | 6,293 chars | +13.43% |
| `skills/goal-craft/SKILL.md` | 11,148 chars | 11,342 chars | +1.74% |

All under the 20% flag threshold — no deviation to name.

## Post-edit code-review pass

A `kbg:code-reviewer` pass ran on the diff before commit, specifically briefed to scrutinize
`incident/SKILL.md` hardest — Step 3 gates real mitigation actions the file itself calls
"outward-facing / irreversible actions," and this repo has a 3x-confirmed history of
self-consistency-skip additions weakening exactly this kind of gate. Found 1 MEDIUM + 1 LOW:

- **MEDIUM** — the first draft's skip condition had two disjuncts (severity S1, OR blast radius
  expanding) sharing one justification, but only the blast-radius-expanding half is actually
  backed by an existing rule in the file (`Escalate, don't absorb`). Nothing mandates
  escalate-over-execute for S1 alone — the ask's own option text only *recommends* it, and an
  incident commander is free to pick `Execute mitigation now` on a confirmed, non-expanding S1.
  The unjustified S1 disjunct would have removed that choice unilaterally on the tier with the
  tightest MTTR target (<15 min). Fixed: narrowed the skip to blast-radius-expanding only,
  explicitly states severity alone never triggers it. Re-verified by a second fresh-context read
  after the fix — confirmed correct.
- **LOW** — the self-consistency bullet was ordered after the `AskUserQuestion` it pre-empts,
  a minor sequencing hazard for a top-down reader. Fixed: reordered above the ask.

The reviewer explicitly confirmed the dangerous direction (skip leaking toward the risky
`Execute mitigation now` branch, or escalation bypassing a human entirely) was **not**
reproduced — this is a scope-of-skip issue on the trigger condition, not the 4th instance of the
prior 3x-confirmed defect class (skip justification missing a downstream route). `production-audit/SKILL.md`
and `goal-craft/SKILL.md` came back clean — no findings.

## Verification

- `harness-audit` + full gauntlet: green (see commit).
- Inventory cross-check (method rule 8): all 3 file paths resolved, all 3 pre-edit citations
  verified against current content before editing — no drift from the original sweep. Char
  counts computed via `wc -c` against `git show HEAD:<path>`.
- The MEDIUM fix was independently re-verified by a second fresh-context agent (not the same
  reviewer that found it) before commit — confirmed the narrowed skip condition, the cited
  METHODOLOGY line, the unconditional-ask-for-S1-alone behavior, and the bullet reordering are
  all correct with no remaining internal contradiction.

## Limitations

- **No Level A evidence** — same explicit-choice basis as batches 2-4.
- **Simulated static grading** — same as prior batches.
- **No second full code-review round** after the MEDIUM/LOW fixes — the targeted re-verification
  above (a fresh-context read specifically checking the fix) substitutes for a full second
  reviewer dispatch, matching this batch's higher scrutiny on the one file that touched a
  confirmation gate. A repeat of the disclosed no-second-round gap for the other 2 files.
