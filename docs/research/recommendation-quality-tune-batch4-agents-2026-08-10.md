# Recommendation-quality tune — batch 4 (review-agent cluster)

Date: 2026-08-10. Fourth batch from issue #40 (Level-B backlog:
`recommendation-quality-tune-2026-08-10.md`). Follows batch 2 (fix-bug/review-pr/code-reviewer)
and batch 3 (`/ship` pipeline cluster).

## Scope and rigor

Batch = the 3 remaining `agents/*.md` files with an open Level-B gap: `agents/refactor-cleaner.md`,
`agents/performance-optimizer.md`, `agents/code-architect.md`. A clean directory-type ("layer")
grouping per issue #40's own instruction, and the smallest, lowest-risk remaining cluster (1 gap
each, vs. `orchestrate/reference.md`'s 5 or the 2-3-gap skill files).

Same rigor as batches 2-3 — **Level B only, unmeasured** (no new fixtures, no fresh-context
trials). Gaps re-graded against current file content before editing per issue #40's own
instruction; all 3 files matched their original citations exactly, no drift.

## Correction to prior batch-3 progress comment's remaining-count estimate

Pulling the actual per-file grading tallies for all 11 remaining files (to scope this batch)
surfaced that the "~13 gaps" figure posted after batch 3 — and re-asserted as correct in the
follow-up correction comment for the file-count error — was itself never independently verified
against the underlying rubric data. Summing the real `GAP=` tallies from
`grading/levelB-{skills,commands,agents}.md` for the 11 remaining files gives **21 gaps**, not 13:

| File | Tally | Gaps |
|---|---|---|
| `commands/post-mortem.md` | PASS=6 GAP=3 | 1, 4, 6 |
| `skills/recursive-improve/SKILL.md` | PASS=6 GAP=3 | 3, 7, 8 |
| `skills/task-prep/SKILL.md` | PASS=5 GAP=2 NA=2 | 4, 5 |
| `skills/pr/SKILL.md` | PASS=6 GAP=2 NA=1 | 4, 9 |
| `skills/production-audit/SKILL.md` | PASS=5 GAP=1 NA=3 | 8 |
| `skills/incident/SKILL.md` | PASS=7 GAP=1 NA=1 | 7 |
| `skills/goal-craft/SKILL.md` | PASS=7 GAP=1 NA=1 | 5 |
| `skills/orchestrate/reference.md` | PASS=1 GAP=5 NA=3 | 2, 3, 4, 8, 9 |
| `agents/refactor-cleaner.md` | PASS=6 GAP=1 NA=2 | 4 |
| `agents/performance-optimizer.md` | PASS=6 GAP=1 NA=2 | 4 |
| `agents/code-architect.md` | PASS=7 GAP=1 NA=1 | 2 |
| **Total** | | **21** |

This batch closes the last 3 rows (3 gaps). Post-batch remaining: **8 files, 18 gaps**. The
original "~30 gaps / ~16 files" figure at issue-filing time was always an approximate aggregate
(explicitly "~"-prefixed) from the original sweep's own framing, not a claim that summing the
strict 9-criterion rubric would land on exactly 30 — so this isn't new drift, it's the first time
the remaining set's real total was actually summed rather than derived by subtraction from an
already-approximate baseline. Flagging this plainly rather than quietly using the corrected number
with no note, per this report's own rule against restating a deviation to fit the outcome.

## What was changed

| File | Gap closed | Fix |
|---|---|---|
| `agents/refactor-cleaner.md` | 4 ALTERNATIVE | §4 Consolidate Duplicates now requires naming why each rejected duplicate lost (missing coverage, narrower scope, known bug, stale), not just "choose the best implementation" |
| `agents/performance-optimizer.md` | 4 ALTERNATIVE | Report Format gets an **alternative** field — when §2's table names a different "Better Alternative" than what shipped, or another viable fix existed, state which and why it lost; single-viable-fix case has an explicit out |
| `agents/code-architect.md` | 2 EVIDENCE-REASON | Design Decisions now requires citing what Process §1 actually found (analog grepped, import-direction check, DI style) instead of an unsupported "fits the existing pattern"; explicit no-analog escape hatch included |

3 of 3 gaps in scope closed. No gap left open or deliberately skipped.

## Char deltas

| File | Before | After | Delta |
|---|---|---|---|
| `agents/refactor-cleaner.md` | 8,819 chars | 9,017 chars | +2.25% |
| `agents/performance-optimizer.md` | 14,231 chars | 14,491 chars | +1.83% |
| `agents/code-architect.md` | 8,340 chars | 8,622 chars | +3.38% |

All well under the 20% flag threshold — no deviation to name.

## Post-edit code-review pass

A `kbg:code-reviewer` pass ran on the diff before commit. Found 1 MEDIUM + 1 LOW, both real, both
fixed pre-commit:

- **MEDIUM** — `code-architect.md`'s first-drafted citation requirement had no sanctioned path for
  a first-of-its-kind feature with no comparable analog in the codebase, while explicitly banning
  the phrase ("fits the existing pattern") an agent would otherwise reach for — and the batch's own
  sibling fix (`performance-optimizer.md`) already had this exact escape hatch
  ("if truly only one fix was viable, say so"), making code-architect the one instance that missed
  its own batch's established pattern. Fixed: added "if no analog exists, say so and cite the
  layer-direction and DI-style findings instead."
- **LOW** — the same first draft put 3 lines of instruction inside the `[Rationale]` placeholder
  itself, off the file's own convention of a separate parenthetical bullet below the placeholder
  (used twice elsewhere in the same Output Format block). Fixed: moved to its own `- (...)` bullet.

`refactor-cleaner.md` and `performance-optimizer.md` came back clean — no findings.

## Verification

- `harness-audit` after: 0 CRIT (gauntlet run pre-commit, see below).
- Inventory cross-check (method rule 8): all 3 file paths resolved, all 3 pre-edit citations
  verified against current content before editing — no drift from the original sweep. Char counts
  computed via `wc -c` against the working-tree file vs. `git show HEAD:<path>`.
- A second code-review round was not re-run after the MEDIUM/LOW fixes — both are narrow, targeted
  additions to the exact lines flagged, verified by re-reading the file section rather than a
  second agent dispatch. Matches the standing deviation both prior batches also disclosed.

## Limitations

- **No Level A evidence** — same explicit-choice basis as batches 2-3.
- **Simulated static grading** — same as prior batches.
- **No second code-review round** after the fix — see Verification above; a repeat of the same
  disclosed gap in batches 2 and 3.
