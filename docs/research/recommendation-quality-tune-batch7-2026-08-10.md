# Recommendation-quality tune — batch 7 (orchestrate/reference.md) — backlog closed

Date: 2026-08-10. Seventh and final batch from issue #40 (Level-B backlog:
`recommendation-quality-tune-2026-08-10.md`). Follows batch 2 (fix-bug/review-pr/code-reviewer),
batch 3 (`/ship` pipeline cluster), batch 4 (review-agent cluster), batch 5 (smallest skills
cluster), batch 6 (post-mortem/recursive-improve/task-prep/pr). **This closes issue #40** — no
files remain in the Level-B backlog.

## Scope and rigor

Batch = `skills/orchestrate/reference.md`, the last file in the backlog (5 gaps: EVIDENCE-REASON,
HONEST-CONFIDENCE, ALTERNATIVE, REVISIT-TRIGGER, FALSIFIABILITY — all clustered around two
locations, the Value×Risk routing table and the "Full triage example" worked scenario). Flagged
since batch 5 as likely needing its own batch given the size of the content lift it implied — a
prediction that held: this is the largest single-file addition in the backlog. Same rigor as
batches 2-6 — **Level B only, unmeasured**. All 5 gaps re-verified against current file content
before editing; citations matched exactly, no drift.

## What was changed

| Gap closed | Fix |
|---|---|
| 3 HONEST-CONFIDENCE | New "Insufficient-data fallback" paragraph after the Value×Risk table's "No numeric scoring" paragraph — a binary high/low call with genuinely no basis (not merely a contested one) must say so and route through `research`/`code-architect` to generate the missing signal, rather than forcing a bucket |
| 2 EVIDENCE-REASON, 4 ALTERNATIVE, 8 REVISIT-TRIGGER, 9 FALSIFIABILITY | New "Why each row landed where it did" bullet list, one bullet per row of the 5-row triage example table — each states the evidence behind the quadrant call, the alternative route considered and rejected + why, a falsifying fact that would flip the pick, and (only the 2 deferred rows) a distinct revisit trigger |

5 of 5 gaps in scope closed. No gap left open or deliberately skipped. This clears the full
Level-B backlog from issue #40 — every file the original sweep covered now has 0 open gaps.

## Char delta

| File | Before | After | Delta |
|---|---|---|---|
| `skills/orchestrate/reference.md` | 32,603 chars | 35,973 chars | +10.34% |

Under the 20% flag threshold — no deviation to name, despite this being the largest single-file
addition across all 7 batches (the file itself is also the largest in the backlog, so the
percentage stayed proportionate).

## Post-edit code-review pass

A `kbg:code-reviewer` pass ran on the diff before commit, specifically briefed to check for the
exact failure mode this kind of retroactive rubric-satisfying content risks: text shaped to check
a criterion box without adding real information, or a citation that reads as accurate but isn't
when checked against its actual source. Found 1 MEDIUM + 2 LOW:

- **MEDIUM** — the HONEST-CONFIDENCE fix's first draft claimed its fallback trigger list ("novel
  domain, no comparable precedent, contested estimate") was "the same discipline"
  `score-decision`'s `ข้อมูลไม่เพียงพอ` block-condition uses — but `score-decision/SKILL.md`
  explicitly reserves that block for "no basis to place any number at all," not a merely
  *contested* estimate (which it says should still be scored, at its real low/high position, and
  caught by the fatal-weakness floor if that's wrong). A contested-but-real signal is a different
  case than zero signal. Fixed: narrowed the trigger to "no basis at all" with an explicit
  carve-out for contested estimates, and corrected the comparison to state the two skills' shared
  *line* (no-basis-only) while naming their different *remedies* (score-decision blocks the
  verdict; this table routes to generate the missing signal).
- **LOW** — the auth-refactor bullet's first draft stated the same fact ("a security finding
  surfaces") under both "Revisit trigger" and "Falsifying fact," restating one idea as two labels
  — exactly the after-the-fact rubric-filling failure this batch was specifically briefed to hunt
  for. Fixed: revisit trigger is now a scheduled check-in ("re-triage at the next security sprint
  even if nothing new has surfaced"); falsifying fact is now the specific event that bypasses that
  schedule (a live vulnerability report).
- **LOW** — the dark-mode-toggle bullet's first draft carried a "Revisit trigger" label, but the
  list's own stated schema reserves that label for the 2 *deferred* rows only — dark-mode is
  `dropped`, not deferred. Fixed: relabeled to "Falsifying fact" (the content itself — roadmap
  entry would flip the verdict — was already correct, just mislabeled).

The reviewer separately confirmed: the "Security override, above" citation in the auth-refactor
bullet is accurate (the override paragraph genuinely sits above the triage table in the file), the
Thai-term citation isn't fabricated (verified against `score-decision/SKILL.md` and
`docs/METHODOLOGY.md`), and the new fallback paragraph isn't redundant with the pre-existing "No
numeric scoring" paragraph beside it — they address distinct failure modes (false precision vs.
forced classification on missing signal).

## Verification

- `harness-audit` + full gauntlet: green (see commit).
- Inventory cross-check (method rule 8): file path resolved, all 5 pre-edit citations verified
  against current content before editing — no drift from the original sweep. Char counts computed
  via `wc -c` against `git show HEAD:<path>`.
- All 3 MEDIUM/LOW fixes were independently re-verified by a second fresh-context agent (not the
  same reviewer that found them) before commit — confirmed the fallback paragraph's trigger is
  narrowed to "no basis at all" with the remedy-comparison corrected (checked directly against
  `score-decision/SKILL.md` line 34), the auth-refactor bullet's two fields now carry genuinely
  distinct information, and the dark-mode-toggle bullet is labeled "Falsifying fact" with no stray
  "Revisit trigger" — confirmed against the table's actual `dropped` status.

## Limitations

- **No Level A evidence** — same explicit-choice basis as batches 2-6.
- **Simulated static grading** — same as prior batches.
- **No second full code-review round** after the MEDIUM/LOW fixes — the targeted re-verification
  above substitutes for a full second reviewer dispatch, same pattern as every prior batch.
- **The re-grading source (method rule 5) came from a different prior session's scratchpad**, same
  caveat as batch 6 — citations were verified to still match current content, but the underlying
  grading judgment (whether a criterion genuinely applies, N/A vs GAP) was inherited from the
  original sweep, not re-derived from scratch.
- **This is retroactively-synthesized worked-example content**, not a behavioral change to how the
  skill actually routes — the fix adds explanatory reasoning to a static reference doc's example
  table, which is exactly the shape the code-review brief targeted as a risk (text shaped to
  satisfy a rubric label without adding real information). The review caught 3 real instances of
  drift toward that failure mode across 5 new bullets + 1 paragraph; none survived to commit, but
  the base rate (3 issues in a first draft of ~6 new content blocks) is a signal this kind of
  after-the-fact synthesis needs the review pass, not a reason to skip it next time.

## Backlog status: issue #40 closed

All 39 files in the original Level-B sweep (`recommendation-quality-tune-2026-08-10.md`) now have
0 open gaps, across 7 batches:

| Batch | Files | Gaps closed |
|---|---|---|
| 2 | fix-bug, review-pr, code-reviewer | 6 |
| 3 | ship-release, ship/COMMAND.md, ship/references/classify.md, ship/references/pre-ship-verify.md | 11 |
| 4 | refactor-cleaner, performance-optimizer, code-architect | 3 |
| 5 | production-audit, incident, goal-craft | 3 |
| 6 | post-mortem, recursive-improve, task-prep, pr | 10 |
| 7 | orchestrate/reference.md | 5 |

Files explicitly excluded from this backlog at the start (not gaps — deliberate scope decisions,
documented in the master doc): `output-styles/staff-eng.md` (control surface for a separate,
already-measured eval), `agents/ideate-critic.md` (blast radius exceeds gain — a JSON-envelope
consumer), `agents/task-prep-checker.md`'s single DEFAULT-BEFORE-ASK gap (the guardrail forbids
inventing defaults by design — the gap is the feature).
