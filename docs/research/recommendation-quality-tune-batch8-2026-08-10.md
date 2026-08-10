# Recommendation-quality tune — batch 8 (issue #43, 6 files)

Date: 2026-08-10. First batch against issue #43 — the leftover Level-B gaps discovered when
verifying issue #40's own closure (`docs/research/recommendation-quality-tune-2026-08-10.md`'s
39-file sweep was larger than #40's tracked scope; 8 files' gaps never made it into any tracking
issue). Follows the same discipline as batches 2-7. **Level B only, unmeasured.**

## Scope and rigor

Issue #43 lists 4 "never tracked anywhere" files (2 with citations already derived, 2 flagged as
needing a fresh re-grade) plus 3 "leftover from the separately-tracked measured round" files. This
batch covers 6 of those 7 files (all but `output-styles/staff-eng.md`, which was never in #43 —
it's a deliberate exclusion documented in the master sweep, not open work).

- **Re-graded against current content, citations matched** (method rule 5): `agents/task-prep-checker.md`
  (2 gaps), `skills/review-pr/reference.md` (2 gaps), `skills/decide/SKILL.md` (1 gap — the
  ambiguous HONEST-CONFIDENCE half; SELF-CONSISTENCY confirmed already closed elsewhere in the
  file, out of this batch's scope), `agents/plan-reviewer.md` (1 gap).
- **Freshly graded from scratch** (issue #43 flagged these as never having real citations derived):
  `skills/incident/references/hotfix-reference.md` (2 gaps found), `commands/iterate-skill.md`
  (1 gap found).
- **Re-graded and found already closed**: `skills/score-decision/SKILL.md`'s cited REVISIT-TRIGGER
  gap — issue #43 said "still open — Trace names the flip criterion (§5) but no timing/condition
  to actually re-open the decision," but the file already has a `**Re-score when**:` field in its
  Output Format (line 81) that is exactly this. The citation was stale as of today; not part of any
  batch's edit, and not touched here. This is method rule 5 working as designed — a citation
  written against an earlier state of the file, since overtaken by unrelated work (likely part of
  the same Level A measured round issue #43 itself names as the source of ambiguity for these 3
  files).

## What was changed

| File | Gap closed | Fix |
|---|---|---|
| `agents/task-prep-checker.md` | HONEST-CONFIDENCE, REVISIT-TRIGGER | Added `confidence: high\|medium\|low` (always present) and `revisit_if` (present only on `verdict: ready`) to the structured Output Format schema |
| `skills/review-pr/reference.md` | REVISIT-TRIGGER | `[Revisit if: ...]` line added to the Wontfix reply-comment template, and propagated to its reproduction in the "Blending a sha" section (caught by review, see below) |
| `skills/review-pr/reference.md` | FALSIFIABILITY | 4th "Falsifying fact" element added to the review-comment "Structure" template (judgment calls only, skip on objective bugs) |
| `skills/decide/SKILL.md` | HONEST-CONFIDENCE | One instruction line under the "Key assumptions tested" table requiring the same evidence-anchor as the Decision block's own Confidence line |
| `agents/plan-reviewer.md` | REVISIT-TRIGGER | New `revisit_if` field, explicitly distinguished from the existing `verdict_movers` (a fact that changes one finding's severity, vs. the whole review going stale) |
| `skills/incident/references/hotfix-reference.md` | EXPLICIT-PICK, ASK-CONSEQUENCES | Phase 4's merge-authorization ask now states which option the incident's actual severity favors (P0/P1 → merge, P2 → wait) as the literal `(Recommended)` pick, and states both options' costs — not just the risky one's |
| `commands/iterate-skill.md` | EXPLICIT-PICK | Step 4's ASK gate states which of the 3 options the diff earns on its own merits before presenting the `AskUserQuestion` |

9 of 9 gaps in scope closed (7 fresh fixes above — note 2 files each closed 2 gaps in one edit
region). 1 gap (`score-decision/SKILL.md`) found already closed on re-grade, no edit needed.
`output-styles/staff-eng.md` intentionally excluded (not this batch's scope, per the master doc).

## Char delta

| File | Before | After | Delta |
|---|---|---|---|
| `agents/plan-reviewer.md` | 17,668 | 18,084 | +2.35% |
| `agents/task-prep-checker.md` | 11,848 | 12,925 | +9.09% |
| `commands/iterate-skill.md` | 12,369 | 12,850 | +3.89% |
| `skills/decide/SKILL.md` | 19,171 | 19,361 | +0.99% |
| `skills/incident/references/hotfix-reference.md` | 10,219 | 11,104 | +8.66% |
| `skills/review-pr/reference.md` | 16,594 | 17,013 | +2.53% |

All under the 20% flag threshold — no deviation to name.

## Post-edit code-review pass

A `kbg:code-reviewer` pass ran on the full 6-file diff, briefed specifically on the two risks this
kind of batch has repeatedly hit: retroactive rubric-filling that restates a nearby sentence
without adding real information, and a claim that reads as accurate but isn't when checked against
its actual source (same-file or cross-file). Found 2 MEDIUM + 1 LOW, zero CRITICAL/HIGH:

- **MEDIUM** — `review-pr/reference.md`'s new Wontfix `[Revisit if: ...]` line wasn't propagated to
  the same file's "Blending a sha into Wontfix / Clarify" section, which reproduces the Wontfix
  body for a different case — that section's own text says explicitly "don't abbreviate the body,"
  and the diff briefly made the file violate its own stated rule one section down. The trailing
  "swap the last two lines" reference also became ambiguous once the body grew to 3 lines. Fixed:
  added the Revisit-if line to the reproduction, reworded the parenthetical to name the two lines
  explicitly instead of by position. Independently re-verified — both bodies confirmed in sync.
- **MEDIUM** — `hotfix-reference.md`'s own "Sync seam" note requires checking whether
  `commands/ship-merge.md`'s Phase 2 needs a matching edit whenever the confirm prompt here
  changes; this batch edited that prompt but never checked or documented checking. Fixed: added a
  dated note recording the check's outcome — `ship-merge.md` Phase 2 does carry the same unresolved
  `(best when X)` pattern this edit fixed here, but it's out of scope for issue #43 (not in the
  tracked file list), so it's flagged rather than silently fixed or silently dropped. Independently
  re-verified, including a direct check of `ship-merge.md` Phase 2's actual current text — the
  note's factual claim about it is accurate.
- **LOW** — `task-prep-checker.md`'s parseability-contract sentence said "text outside the four
  labeled lines," a count that went stale the moment this batch added a 5th always-present field
  (`confidence`). Fixed: reworded to avoid depending on an exact count. Independently re-verified.

The reviewer also checked and cleared: `plan-reviewer.md`'s `revisit_if` vs. `verdict_movers`
distinction genuinely holds (not an invented split); `decide/SKILL.md`'s citation of "the Decision
block's own Confidence line below" is accurate; `hotfix-reference.md`'s new claim that "Phase 0
already ruled out rollback/kill-switch" is accurate against Phase 0's own gate logic; the new
severity-based recommendation logic doesn't contradict Phase 3's Block-items-always-0-by-Phase-4
gate; and the `(Recommended)` tag mechanic in both edited files matches the pre-existing convention
(`output-styles/staff-eng.md`, and two prior instances in `post-mortem.md` / `address-review`).

## Verification

- `run-gauntlet.sh` + `harness-audit`: green (see commit).
- Inventory cross-check (method rule 8): all 6 file paths resolved; all re-graded citations
  verified against current content before editing; the 2 freshly-graded files' gaps were derived
  directly from this session's own reading of the current file, not inherited from any prior note.
- All 3 MEDIUM/LOW fixes were independently re-verified by a second fresh-context agent (not the
  reviewer that found them) — confirmed the Wontfix template and its reproduction are back in sync,
  confirmed the sync-seam note's factual claim about `ship-merge.md` against that file's actual
  current text, and confirmed the stale "four" is gone with no new staleness introduced.

## Limitations

- **No Level A evidence** — same explicit-choice basis as batches 2-7.
- **Simulated static grading** — same as prior batches. The 2 freshly-graded files
  (`hotfix-reference.md`, `iterate-skill.md`) had no prior grading pass at all; this session's own
  read against the 9-criterion rubric is the only grading they've had, unlike the other 4 files
  where an earlier session's citations were being re-checked.
- **`score-decision/SKILL.md`'s gap being found already-closed is not this batch's achievement** —
  it was closed by unrelated prior work (likely the separately-tracked Level A measured round),
  simply mis-recorded as still-open in issue #43's own text. Recorded here as a re-grade catch, not
  a fix.
- **No second full code-review round** after the MEDIUM/LOW fixes — the targeted independent
  re-verification above substitutes, same pattern as every prior batch.
- **`ship-merge.md`'s own EXPLICIT-PICK gap, surfaced as a side effect of this batch's review, was
  left unfixed in the batch-8 commit** — flagging it in the file (per the sync-seam fix above) was
  transparency, not scope creep, since fixing it would have gone beyond issue #43's own file list.
  The user authorized it as an immediate follow-up the same day (v0.68.257): the fix took 3 review
  rounds to land correctly (a `kbg:code-reviewer` pass on round 1 caught a wrong-default risk on a
  freshly-rebased, CI-unvalidated SHA; round 2's fix introduced a second, narrower category error
  on the CI-N/A case; round 3 closed both). Worth naming as its own data point on this backlog's
  established pattern (re-review after every fix round, confirmed 5+ times now): a fix to a
  *merge-authorization gate* earned meaningfully more review depth than this backlog's typical
  doc-content fix, and needed it — each of the first two rounds shipped a real, distinct logic gap
  that only surfaced under adversarial review, not a self-check. See commit history for the
  specifics; not written up as a separate batch report since it's one file, no new gap discovered
  in a *tracked* backlog file.

## Backlog status: issue #43 partially closed

7 of 7 files from issue #43's own two tables addressed (6 edited, 1 confirmed already-closed).
Remaining from issue #43: `output-styles/staff-eng.md` — deliberately excluded (per the master
sweep, it's the eval control surface for a separate, already-measured round, not this backlog).
That leaves issue #43 with no further open work under its own stated scope, unless the newly
surfaced `ship-merge.md` gap (see Limitations) is deliberately pulled in as new scope — a decision
for the user, not assumed here.
