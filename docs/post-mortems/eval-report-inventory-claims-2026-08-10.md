# Post-Mortem: Eval report shipped false self-referential inventory claims (eval-report-inventory-claims-2026-08-10)

## 1. Summary

The recommendation-quality eval report committed in `4646705` (v0.68.246) shipped with three
false claims about its own evidence base and one undisclosed content drift, while every headline
eval number in it was accurate. Same-day fresh-context verifiers from `/kbg:compliance-audit`
caught all four; fixed in `e04c167`. This is the third confirmed instance of the "self-reported
inventory" defect class in this repo (2026-08-05 cross-foot totals, 2026-08-09 scope counts).

## 2. Symptom

Four defects in the committed report text
(`docs/research/recommendation-quality-tune-2026-08-10.md`), none affecting the measured results:

- Claimed "36 generation trials" — disk inventory was 33 (18 baseline + 15 tuned; F4 never re-run).
- Cited a comparator transcript in the scratchpad — no such file existed anywhere under `rec-tune/`.
- Restated the frozen acceptance rule as "does not regress on its leak-guard assertions" —
  `FREEZE.md`'s frozen wording is "ANY assertion," and the narrowing was not marked as a departure.
- Shipped `skills/decide/SKILL.md` differed from the graded `content-r2` snapshot (a post-review
  clause), with no disclosure that a measured file changed after grading.

## 3. Root Cause (Mechanism)

The report was drafted from session working memory at the end of a 6-phase run, and every
inventory claim was asserted from recall of intent rather than re-derived from disk. "36" is the
planned arithmetic (6 fixtures × 3 trials × 2 conditions), not the post-F4-drop reality.
"Comparator" was listed as an artifact because the comparator agent ran and returned its verdict
inline — a transcript-writing step never existed. The acceptance-rule restatement reproduced the
post-decision operative interpretation (leak-guards) instead of quoting `FREEZE.md`. The decide
drift existed because the code-review fix round edited a measured file after grading, and no step
byte-compared shipped content against the graded snapshot.

## 4. Symptom Linkage

The false claims all sit in the report's provenance sections (§Scope, §Verification) — exactly
the text whose job is to make the eval re-checkable. Between drafting and commit, nothing
compares those claims to disk: the pre-commit gauntlet validates syntax, JSON, versions, and
harness-audit checks, none of which read report semantics. Recall errors therefore pass every
gate and land as authoritative-looking text in the permanent record (`docs/research/` is also the
`kbg-research` qmd collection, so the false claims would have been served as search results
later).

## 5. Fix

Commit `e04c167`: trial count corrected to 33; comparator verdict written to
`rec-tune/grading/comparator.md` with a provenance note; frozen rule wording restored and the
F1-A1 acceptance named as a judged letter-level deviation; the worked-example claim itemized
(3 clean + 1 borderline of 13); the post-grading decide edit disclosed in Limitations; README
version badge fixed (the related harness-audit W1). Memory `re-review-after-every-fix-round`
updated to 5 confirmations with the eval-report variant named.

## 6. Discovery Method

`/kbg:compliance-audit` Phase 3: three fresh-context verifiers cross-checked the report against
artifacts they located themselves. V1 (measurement integrity) counted trial files (`ls` → 18+15),
ran a recursive search for "comparator" (zero artifact hits), diffed the report's rule
restatement against `FREEZE.md`'s text, and byte-compared `content-r2/decide-SKILL.md` against
the shipped commit. The deterministic backstop (fresh harness-audit) separately caught the stale
README badge.

## 7. Escape Reason

No check — human or mechanical — compares a report's self-referential claims against the
artifacts it cites. Verified: zero harness-audit checks read report content, and checks 37/40
exclude `docs/research/*.md` from even pointer-rot scanning by design (dated snapshots). The
pre-commit code-reviewer pass did review the report — it caught a wrong file count ("7 files" →
5) because that was checkable against the diff it was given — but it had no knowledge of the
scratchpad artifact tree, so counts and artifact paths pointing outside the diff were
unverifiable from its seat. The defect class was already memorized twice, and memory guidance
alone did not prevent recurrence under end-of-session compression.

## 8. Validation Proof

V1's re-check (post-`e04c167`) returned RESOLVED on all four findings with supporting quotes;
fresh harness-audit: 0 Critical / 0 Warnings; the push-time gauntlet passed all six layers.
**Regression test: none exists** — there is no automated check that report inventory claims
match disk. Flagged as a gap; follow-up 1 below is the containment.

## 9. Follow-Ups

- [ ] Add an "inventory cross-check" step to the scored-eval method: before committing an eval
  report, verify every count, artifact path, and rule restatement against disk, and record the
  check in the report's Verification section (owner: @kobig; done when: the method's
  freeze-template/precedent doc mandates it and the next scored eval's report carries the checked
  line).
- [ ] Add a "post-grading edit" rule to the same method: any edit to a measured file after its
  after-runs requires a byte-compare against the graded snapshot plus a disclosure bullet
  (owner: @kobig; done when: the method doc carries the rule).
- [ ] Decide build-or-skip on a deterministic check (e.g., a harness-audit INFO that flags
  artifact paths in eval reports that don't resolve) — Rule 2 gate: build only if the class
  recurs after follow-up 1 lands (owner: Unowned — needs assignment; done when: an explicit
  build/skip decision is recorded).
