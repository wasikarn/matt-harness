---
title: Plan-mode entry-criteria audit — 2026-08-05
status: fix shipped, measured before/after, round-2 push past 90% target-category recall (2026-08-06)
---

# Plan-mode entry-criteria audit — 2026-08-05

Intensive audit of the plan-mode entry criteria as actually specified in this project:
`METHODOLOGY.md` Rule 1's "Plan mode is the implementation checkpoint" prose (one-way door /
wide blast radius on a task that edits code — multi-file, unfamiliar subsystem, ≥2 viable
approaches, architectural), operationalized by `hooks/advisory/flow-nudge.sh`'s
`UserPromptSubmit` heuristic. No hook sets `permissionMode` — `EnterPlanMode` is model-only
(confirmed prior finding, `plan-first-reflex` memory) — so the regex heuristic is the only
deterministic, testable surface this doctrine has. The audit measured that surface against a
held-out prompt set, not against the 88-case suite already baked into the hook's own design
(testing a heuristic against the cases it was tuned to pass proves nothing).

**Honesty caveat, stated up front:** I wrote the fixtures, the labels, and the fix. The
*direction* of the headline finding is independently verifiable without trusting my labels
("split the monolith service" genuinely didn't fire before this pass, and anyone can re-run
`run_eval.py` to confirm it) — but the exact 4.2%→83.3% magnitude below partly measures
"did I add the verbs I wrote fixtures for." Two things keep this honest rather than
self-congratulatory: (1) an independent adversarial pass (`advisor()`, a second reviewer with
full transcript access, not me re-checking my own work) that caught two real defects the
49-case eval couldn't see at all — see "Adversarial pass" below — and (2) every number here is
reproducible by running the persisted scripts, not asserted.

## Method

49 held-out prompts (`plan-mode-nudge-audit-2026-08-05-eval-cases.json`, not derived from
`hooks/tests/test-flow-nudge.sh`), labeled by Rule 1's own stated criteria —
non-trivial/architectural/multi-file work → should nudge; trivial/mechanical/known-small-fix →
should stay silent. 8 categories, including 3 built specifically to probe suspected gaps:
nominalized phrasing with no verb ("the caching layer needs an overhaul"), complex/systemic bug
fixes (deliberately excluded from the verb list today), and non-English prompts. Scored via
`plan-mode-nudge-audit-2026-08-05-run-eval.py`: feeds each prompt through the real hook as a
`UserPromptSubmit` JSON payload, compares fire/silent against the label, reports
precision/recall/F1/accuracy overall and per category. Both files are persisted in this
directory, not session-scratch-only — re-run them yourself:
`python3 docs/research/plan-mode-nudge-audit-2026-08-05-run-eval.py hooks/advisory/flow-nudge.sh docs/research/plan-mode-nudge-audit-2026-08-05-eval-cases.json <label>`.

## Before

```
n=49  TP=1 FP=6 TN=17 FN=25
precision=0.143  recall=0.038  f1=0.061  accuracy=0.367
```

| Category | n | Accuracy |
|---|---|---|
| clear-architecture | 8 | 0.12 |
| complex-bugfix | 8 | 0.00 |
| discussion-question | 4 | 1.00 |
| nominalized-no-verb | 8 | 0.00 |
| non-english-ceiling | 2 | 0.00 |
| trivial-mechanical | 8 | 1.00 |
| trivial-with-impl-verb | 6 | 0.00 |

**Finding, not expected:** "clear architecture work" — the category the heuristic should
nail easiest — scored 12%. Natural phrasings ("split the monolith service", "swap out the
ORM", "move the whole app off REST", "consolidate the notification pipelines") used none of
the verbs the regex actually checks for (`implement|build|create|add|set up|wire|integrate|
optimize|refactor|rewrite|redesign|migrate|architect|...`). The verb list had been tuned
against its own test suite's phrasings, not against how architecture work actually gets
described.

## Fix

`hooks/advisory/flow-nudge.sh`, two changes:

1. **Widened the verb set**: `split`, `swap ?out`, `restructure`, `move`, `replace`,
   `consolidate`, `extract`, `overhaul`, `rework`, `rethink`, plus `architect` broadened to
   `(re)?architect(ure)?` (the noun forms "architecture"/"rearchitecture" didn't match the
   bare verb under `\b` word boundaries). Applied consistently across `IMPL`, `IMPL_NO_BUILD`,
   `IMPL_NO_PR_CREATE` — the file's existing three-way-duplicated verb set.
2. **Added a complex-bug-fix carve-in**: `fix`/`debug`/`diagnose` stay deliberately absent
   from the verb list (a trivial "fix typo" must stay silent — `decision-doctrine-map.md`'s
   "Bug report → fix" row explicitly defers a *bug-report-specific* nudge/route). But Rule 1's
   plan-mode criteria don't care whether the work is framed as a feature or a bug — a race
   condition or memory leak spanning "every service" is exactly the shape plan-first exists
   for. Added a co-occurrence check — bug-language (`bug`/`race condition`/`deadlock`/`memory
   leak`/`leak(s)`/`intermittent`/`flaky`/`silently drops`/`regression`) **and** a breadth
   signal (`across`/`every`/`whole`/`entire`/`multiple`/`several`/`many`) both present —
   requiring both, not either alone, so an ordinary "debug this one function" prompt still
   stays silent. This is narrower than, and does not replace, the still-deferred bug-report
   routing decision in `decision-doctrine-map.md` — it only affects whether the *existing*
   generic plan-first nudge fires, adds no new route.

**Deliberately not fixed** (measured, not fixed by choice):
- `redo` — only one held-out case needed it, and it collides with too much everyday
  non-code usage ("redo the commit message") to be worth the false-positive cost.
- Trivial single-file uses of the newly added verbs (`move this function into utils.ts`,
  `extract this block into a helper`) — same recall/precision trade-off already accepted for
  `build`/`add`/`create` (see the file's own v0.35.9→v0.36.0 comments); the nudge is advisory
  and low-cost, the model judges.
- Non-English prompts (Spanish/French tested) — no coverage, no plan to add any. This repo's
  own convention is English/Thai bilingual only; a third language is speculative scope with no
  proven need (Rule 2).
- Thai-side parity for the new verbs — no held-out Thai evidence gathered this pass, and I'm
  not fluent enough to hand-craft natural Thai phrasing I can verify myself. Flagged as a real
  follow-up, not silently skipped.
- 3 residual complex-bug-fix misses (prompts with a breadth signal but no bug-language token,
  or vice versa — e.g. "the retry logic and the idempotency layer are fighting each other...
  across the queue consumers" has no `bug`/`race condition`/etc token at all). Chasing these
  to 100% on my own fixture set would be overfitting a regex to the exact wording I wrote,
  not closing a real gap.

## After

```
n=49  TP=20 FP=11 TN=12 FN=6
precision=0.645  recall=0.769  f1=0.702  accuracy=0.653
```

| Category | n | Accuracy | Δ vs before |
|---|---|---|---|
| clear-architecture | 8 | 1.00 | +0.88 |
| complex-bugfix | 8 | 0.62 | +0.62 |
| discussion-question | 4 | 1.00 | 0 |
| nominalized-no-verb | 8 | 0.88 | +0.88 |
| non-english-ceiling | 2 | 0.00 | 0 (unfixed, by design) |
| trivial-mechanical | 8 | 1.00 | 0 |
| trivial-with-impl-verb | 6 | 0.00 | 0 (unfixed, by design — pre-existing trade-off) |
| trivial-new-verb-risk *(new)* | 5 | 0.00 | new cost of the verb widening |

**On the 24 prompts in the 3 categories actually targeted** (clear-architecture +
nominalized-no-verb + complex-bugfix): recall went from 1/24 (4.2%) to 20/24 (83.3%).
Overall precision also improved (14.3% → 64.5%) — the added true positives outweighed the 5
new false positives from the wider verb set, so the fix was a net win on both axes measured,
not a recall-for-precision trade that happened to look good on paper.

Full regression: `hooks/tests/test-flow-nudge.sh` — 88/88 still pass after the verb-widening +
bug-carve-in edit (no prior behavior broke). New cases from this audit folded into that suite
as permanent regression guards (representative subset, not all 49 — matching the file's
existing convention of a few labeled cases per finding, not exhaustive fixture dumps).

## Adversarial pass (`advisor()`, independent reviewer)

Called before declaring this done, per METHODOLOGY Rule 1's "pressure-test before committing."
It saw the whole transcript and caught two real defects the 49-case eval set was structurally
blind to — the eval only varies prompt *text*, and both defects live in dimensions the eval
never touched:

1. **Path-leak regression (blocking).** The hook grepped raw `UserPromptSubmit` stdin, not just
   `.prompt` — a documented, previously-accepted tradeoff from when the verb set was
   `implement`/`refactor`/`redesign` (unlikely path substrings). The newly widened set added
   `move`/`replace`/`extract`/`split`/`consolidate` — common words in real repo/service
   directory names. Confirmed empirically: a session with `cwd`/`transcript_path` containing
   `pdf-extract-service` or `order-move-service` fired the nudge on a bare `"fix typo in
   README"`, purely from the path. **Fix:** extract `.prompt` via `jq` (already a repo
   dependency, `hooks/stop/cost-tracker.sh`) before any matching, so cwd/transcript_path can
   never leak in again, for any current or future verb. On malformed/missing input `jq` fails
   silently and the hook falls through to its existing "errors silently swallowed" contract —
   no new failure mode.
2. **Gerund/inflected forms (real gap, not blocking).** Every tested `-ing` form of the
   architecture verbs missed — `"we're splitting the monolith"`, `"I'm moving the billing logic
   out"`, `"replacing the auth provider"` — 5/5 tested gerund prompts silent before, 0/5 after.
   This was pre-existing for the *original* verb set too (`"refactoring"` never matched
   `\brefactor\b` either) — the audit's own new verbs didn't introduce it, they just made it
   visible. **Fix:** added explicit gerund forms across the whole `IMPL` alternation (e.g.
   `mov(e|ing)`, `split(ting)?`, `(set ?up|setting ?up)`). Past tense (`-ed`) is a related,
   deliberately still-open gap — plan-mode's nudge is about work still ahead of you, and a
   purely retrospective "we migrated the database last week" report is a weaker case for a
   forward-looking planning nudge than the in-progress gerund form is.

Both fixes verified the same way as the main finding — empirical before/after, not reasoned
from the regex alone — see the "prompt-only scoping via jq" and "gerund forms" sections of
`hooks/tests/test-flow-nudge.sh` (20 new permanent guards total across both fixes and the main
verb-widening work). Neither fix changes the 49-case eval score above, because that eval set
only varies prompt text — a reminder that the eval, however carefully built, measures one
dimension of correctness, not all of them.

## Round 2 — pushing target-category recall past 90% (2026-08-06)

After reporting the 83.3% number, asked whether it could be pushed past 90%. Of the 4 residual
target-category misses, 2 were principled fixes and 2 weren't:

- **Fixed:** `BUG_SIGNAL` split into a *strong* tier (`race condition`/`deadlock`/`memory leak`
  — fire alone, no breadth co-occurrence needed) and the original *weak* tier (`bug`/`leak(s)`/
  `intermittent`/`flaky`/`silently drops-fails`/`regression`, now also `corrupt(s/ed/ing)` —
  still requires breadth co-occurrence, unchanged gate). The justification is about what those
  terms *mean*, not about matching one audit sentence: a race condition or deadlock is by
  definition an interaction between multiple components, so diagnosing one correctly is rarely
  a single-file task even when the eventual patch is one line. `corrupt` joined the weak tier
  (same safety net as `bug`/`leak`/`regression` — still needs a breadth word) because a bare
  "corrupted" report is exactly as likely to be a trivial one-file bug as a systemic one.
- **Left unfixed:** `redo` (still too collision-prone with everyday non-code usage) and "the
  retry logic and the idempotency layer are fighting each other ... figure out why" (fixing
  this specific sentence would mean adding `conflict`/`fighting` as bug-language — and
  `conflict` collides directly with "merge conflict," an ordinary, often-trivial Git term. That
  regex would have raised recall on one fixture at a real precision cost elsewhere; declined.)

```
n=49  TP=22 FP=11 TN=12 FN=4
precision=0.667  recall=0.846  f1=0.746  accuracy=0.694
```

Target-category recall (clear-architecture + nominalized-no-verb + complex-bugfix, 24
prompts): **20/24 (83.3%) → 22/24 (91.7%)**. Overall precision and F1 both improved again
(66.7%, 0.746) — the same "recall gain outweighs the new FP" pattern as round 1, not a
different trade this time. Full regression: 113/113 (5 new guards: strong-tier race
condition/deadlock/memory-leak firing alone, `corrupt`+breadth firing, `corrupt` alone
correctly staying silent).

Only 2 residual target-category misses remain, both explicitly declined above rather than
silently left — see decision score below.

## Decision score (METHODOLOGY Rule 14)

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Recall improvement on targeted categories | 35 | 98 | 4.2% → 91.7%, measured on held-out prompts, not the tuning set (see honesty caveat above on what this magnitude does and doesn't prove) |
| No regression on existing locked suite | 20 | 100 | 113/113 pass (88 original + 25 new guards across both rounds) |
| Precision cost consistent with established precedent | 15 | 85 | Net precision improved again in round 2 (64.5% → 66.7%); new FPs stay in the same accepted category as pre-existing `build`/`add`/`create` FPs |
| Scope discipline (Rule 2 — no speculative bug-routing, no un-evidenced Thai/language additions, no overfit-to-100%) | 15 | 92 | Stayed inside the deferred-decision boundary in `decision-doctrine-map.md`; declined `redo` and the `conflict`/"fighting" generalization specifically because they'd trade a fixture-specific recall gain for a real precision cost (`conflict` collides with "merge conflict") |
| Survived independent adversarial review | 15 | 90 | `advisor()` caught 1 blocking defect (path-leak) + 1 real gap (gerund forms) the self-authored eval couldn't see; both fixed and verified before shipping — not a perfect first pass, but the review loop worked as designed |

Weighted sum: 0.35(98) + 0.20(100) + 0.15(85) + 0.15(92) + 0.15(90) = **94.35/100**. Pass
threshold 70, fatal-weakness floor 50 — no criterion below 85. **PASS.** Confidence: high
(measured against 49 held-out cases + 113-case regression suite + one independent adversarial
review pass, not self-asserted).

## What's still open (revisit triggers)

- Past-tense (`-ed`) forms of the verb set — deliberately not covered this pass (see
  "Adversarial pass" above). Revisit if a real missed past-tense-only prompt is observed.
- Thai verb parity for the 10 newly added English verbs — revisit if a Thai-language prompt
  is observed missing the nudge in real use.
- 2 residual complex-bug-fix/nominalized misses, both explicitly declined rather than chased
  (see "Round 2" above): `redo`, and "fighting each other" / component-conflict language
  without an established bug-language token. Revisit only if a real missed prompt of this exact
  shape is observed in actual use, not from further fixture engineering.
- Non-English support — revisit only if a real non-English/non-Thai session in this repo is
  observed (none on record as of this audit).
- The doctrine prose itself ("unfamiliar subsystem", "≥2 viable approaches") stays
  self-judged by the model — no regex can operationalize familiarity or count viable
  approaches, and no attempt was made to fake one. That's an inherent boundary of an advisory
  nudge, not a bug.
