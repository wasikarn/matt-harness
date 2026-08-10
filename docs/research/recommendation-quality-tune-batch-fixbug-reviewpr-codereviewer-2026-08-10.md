# Recommendation-quality tune — batch 2 (fix-bug + review-pr + code-reviewer)

Date: 2026-08-10. Follow-up batch from issue #40 (Level-B backlog: remaining ~30 gaps across
~16 files from `recommendation-quality-tune-2026-08-10.md`). Per that issue's own instruction —
"close in measured batches... bulk-closing unmeasured repeats the precedent eval's round-1
bundling mistake" — this is one batch, not the whole backlog. ~24 gaps remain across the other
~13 files; issue #40 stays open.

## Scope and rigor (explicit user choice)

Batch = the 3 files the issue itself nominates as highest-traffic: `commands/fix-bug.md`,
`skills/review-pr/SKILL.md`, `agents/code-reviewer.md`. Asked the user up front: full Level A
fixture round (new fixtures, n=3 trials × 2 conditions, blind grading — the rigor the original
3 measured files got) vs Level B only, honestly labeled unmeasured (the same lighter mode the
original round used for 5 of its 8 closed files). **User chose Level B only** — full Level A
for 3 new gap shapes would mean ~20+ agent dispatches, past this session's normal 5-agent
fan-out cap, and no `Workflow` opt-in was given for this task.

**This round is Level B only. No behavioral (Level A) evidence exists for these 3 files.** The
gaps below are closed against the static 9-criterion checklist from the original sweep
(`grading/levelB-{skills,commands}.md` in the 2026-08-10 session scratchpad, still readable at
audit time) — re-graded against current file content before editing, per issue #40's own
instruction that "several are already partially covered... re-grade before editing." All cited
line numbers matched current content; no drift found.

## What was changed

| File | Gap closed | Fix | Citation (pre-edit) |
|---|---|---|---|
| `commands/fix-bug.md` | 5 ASK-CONSEQUENCES | Phase 3 hypothesis-approval options now state their effect (locks in H1 / falls back to next hypothesis), not just `(best when X)` | Phase 3 ask, L88-89 |
| `commands/fix-bug.md` | 7 SELF-CONSISTENCY | Phase 4 fix-shape ask: don't offer Structural as a live option when step 3's Analyze already confined the bug to one function with no seam issue | Phase 4 ask, L106-109 |
| `commands/fix-bug.md` | 8 REVISIT-TRIGGER | New step 5: if Phase 5 implementation grows past the scope named in Phase 4 step 2, stop and re-open the fix-shape pick | Phase 4, L104-109 |
| `skills/review-pr/SKILL.md` | 7 SELF-CONSISTENCY | Phase 6 branch A: skip the fix/proceed ask entirely when all 3 tiers are 0 findings — none of the menu options apply to a clean pass | Phase 6, L173-249 |
| `skills/review-pr/SKILL.md` | 8 REVISIT-TRIGGER | "Proceed as-is" (branch A) and "Skip — I'll post manually" (branch B) both now name a re-open condition | Phase 6 step 2, L224-241 |
| `agents/code-reviewer.md` | 8 REVISIT-TRIGGER | Review Output Format template gets a `Revisit if:` field per finding | Output Format, L439-451 |

Char deltas (final, post-review-fix — all under the 20% flag threshold, no verbosity purchase):

| File | Before | After | Delta |
|---|---|---|---|
| `commands/fix-bug.md` | 17,418 chars | 18,390 chars | +5.58% |
| `skills/review-pr/SKILL.md` | 47,084 chars | 48,009 chars | +1.96% |
| `agents/code-reviewer.md` | 29,371 chars | 29,631 chars | +0.89% |

## Post-edit code-review pass

A `kbg:code-reviewer` pass ran on the diff before commit (matching the original round's own
practice). Found 2 HIGH + 1 MEDIUM + 1 LOW, all real — not noise — and all fixed pre-commit:

- **HIGH** — the review-pr self-consistency skip (checking only "tiers all 0") would have
  silently bypassed 3 existing must-fix conditions the file itself defines: `dispatch_failures`,
  an `incomplete` re-hunt, and a missing proof artifact — none of which are visible in the tier
  counts alone. Fixed: the skip condition now explicitly checks all three before treating a
  zero-tier result as clean, and records `proceeded-as-is` as the Phase 6 step 3 decision so
  Phase 7's summary has a label for the skip path.
- **HIGH** — the fix-bug self-consistency wording ("only ask if there's a real reason to
  override it") read as making Phase 4's `AskUserQuestion` itself conditional, which would have
  let Phase 5's "DO NOT START WITHOUT USER APPROVAL FROM PHASE 4" gate be skipped by the model's
  own judgment — the exact self-graded-gate pattern this repo's operating model forbids, and the
  same property CLAUDE.md cites as the reason `fix-bug` lost `disable-model-invocation`. Fixed:
  reworded so the ask always fires; only the menu narrows (drops Structural), never the gate.
- **MEDIUM** — the Phase 3 Reject option's new consequence clause ("falls back... and
  re-instruments") read as bypassing the adjacent Stall/Degrading no-progress halts. Fixed: added
  an explicit clause that the halts still apply on the next round.
- **LOW** — "Re-run this step" in the new Phase 4 revisit-trigger had an ambiguous antecedent.
  Fixed: "Re-run step 4."

`agents/code-reviewer.md`'s own change (the `Revisit if:` field) came back clean — no
contradictions with surrounding text.

## Level B — gaps found → closed

All 6 gaps in scope for this batch closed (table above), matching the original sweep's per-file
tallies exactly: `fix-bug.md` PASS=6 GAP=3 (criteria 5, 7, 8 — all closed), `review-pr/SKILL.md`
PASS=7 GAP=2 (criteria 7, 8 — both closed), `code-reviewer.md` PASS=5 GAP=1 (criterion 8 —
closed). No gap in these 3 files was left open.

Remaining backlog (unchanged from the original report, minus this batch): post-mortem, ship-*,
incident, pr, production-audit, recursive-improve, task-prep, goal-craft, performance-optimizer,
refactor-cleaner, code-architect, orchestrate/reference.md, ship/references/* — ~24 gaps across
~13 files. `output-styles/staff-eng.md` and `agents/ideate-critic.md` stay excluded for the
reasons the original report already gave.

## Limitations

- **No Level A evidence.** This batch never ran a fixture — there is no before/after behavioral
  number for these 3 files, by explicit user choice (see Scope). Treat the 3 fixes above as
  directive/template additions with a plausible causal story (matching the pattern of the
  original round's other Level-B-only closures), not a proven behavior change.
- **Simulated static grading**, same as the original round — the Level B checklist verdicts are
  a structured read of the file text, not a live-agent run.
- **Concurrent-session collision found mid-round, not caused by this batch**: another session
  had `plugin.json`/`marketplace.json` (bumped to v0.68.247) and `agents/ideate-critic.md` +
  `commands/ideate/COMMAND.md` already staged in the shared index while this batch's edits were
  in progress. Per CLAUDE.md's concurrent-session discipline, this batch's 3 files were left
  unstaged until the other session committed (`04c0044`, v0.68.247, closing 4 of `ideate-critic`'s
  gaps — a separate slice of the same issue #40 backlog). This batch bumps on top, to v0.68.248.

## Verification

- `harness-audit` before this batch's edits: 0 CRIT / 1 WARN (pre-existing, unrelated — README
  version badge stale against the other session's in-flight v0.68.247 bump) / 5 INFO.
- `harness-audit` after (post-review-fix, final state): 0 CRIT / 1 WARN (same pre-existing README
  cause, now against v0.68.247/.248) / 5 INFO — `review-pr` SKILL.md's char count moved inside
  the same INFO threshold band it was already in (I2), no new finding.
- Inventory cross-check (method rule 8): all 3 file paths resolved, all 3 pre-edit citations
  (line ranges) verified against current content before editing — no drift from the original
  2026-08-10 sweep. Char counts above computed via `wc -c` against `git show HEAD:<path>`, not
  recalled from memory.
- `kbg:code-reviewer` pass: 2 HIGH + 1 MEDIUM + 1 LOW found and fixed (see above) — a second
  round of the same checks was not re-run after the fixes; the fixes are narrow, targeted wording
  changes to the exact lines the reviewer flagged, not new logic.
