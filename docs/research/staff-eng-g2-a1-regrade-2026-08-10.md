# G2-A1 literal-text re-grade — issue #47

Date: 2026-08-10. Follows `docs/research/scored-eval-method.md` rule 5 (deviations named against
frozen wording, never silently restated). This is a re-grade of an existing measured round
(`docs/research/staff-eng-gap-eval-2026-08-10.md`, issue #38), not a new fixture round — no new
trials were run.

## What this corrects

`staff-eng-gap-eval-2026-08-10.md`'s own Limitations section disclosed a same-day compliance-audit
finding: the G2-A1 grading actually used (`grading/G2-verdict.md` in that session's scratchpad,
`.../staff-eng-gap-eval/grading/G2-verdict.md`) scored against a narrower rubric than `FREEZE.md`'s
frozen text. `FREEZE.md`'s frozen G2-A1 wording:

> response names an explicit, concrete revisit trigger: a condition/event that would prompt
> reconsidering the pick (e.g., "revisit if sharding across regions", "revisit if insert
> throughput on the index bottlenecks"). A generic "revisit if requirements change" (no concrete
> condition) or no revisit language at all fails.

`G2-verdict.md`'s actual rubric line (verbatim): "A1 (targeted, revisit trigger for the PK
decision itself — concrete condition, not generic, **not a pre-launch check, not an
added-feature exception**)." The bolded two exclusions are not in `FREEZE.md`. That original
grading scored baseline 0/3, tuned 2/3 on the targeted assertion — the number
`output-styles/staff-eng.md`'s shipped REVISIT-TRIGGER change cites as its evidence.

Issue #47 asked for a fresh, independently-blind re-grade of the same 6 G2 trial transcripts
against `FREEZE.md`'s literal text, dropping the two un-frozen exclusions. Artifacts (still on
disk, not cleaned up): `.../staff-eng-gap-eval/trials/g2-{baseline,tuned}-t{1,2,3}.md` (6 files,
confirmed on disk, byte-identical to `probe/g2-baseline-t1.md` where it's reused as baseline t1
per the parent round's calibration-not-rubric-after-draft framing).

## Method

Genuine independence requires a grader who hasn't read the original report's narrative or the
original per-trial verdicts — this session had already read both (issue #47's body quotes the
original per-trial narrative directly) before opening the trial files, which is worse blinding
than #38's own session had when it disqualified itself from re-grading. So this session does not
grade. It dispatches fresh-context agents with only the literal rubric text and the six trials
under neutral labels, and tabulates their verdicts.

### Discarded first attempt (disclosed per rule 5, not silently dropped)

The first grading prompt included this line, meant to strip the two un-frozen exclusions:

> Do not invent additional exclusion categories (e.g. don't fail a response just because its
> concrete trigger is framed as adding a secondary column or as a pre-launch check, if it
> otherwise names a real condition/event tied to reconsidering the decision) — grade against the
> rubric text exactly as written above, nothing more, nothing less.

That clause doesn't just remove the original grading's narrowing — it pre-resolves, in the PASS
direction, the actual disputed question (does a trigger about an *adjacent* structural choice
count as "reconsidering the pick"?) before an independent grader could reason about it. The
tell: this run's result was baseline 2/3, tuned 3/3 — matching, almost to the trial, the range
issue #47's own body had already pre-announced ("baseline at 1–2/3 ... tuned at 3/3"). A grading
prompt that reproduces the hypothesis its author already read is a contaminated result, not
independent evidence. Discarded as a verdict; kept here as a disclosed, voided artifact.

### Clean re-run

Three fresh `general-purpose` agents, run independently, identical prompt: the question text, the
complete verbatim `FREEZE.md` G2-A1 rubric text and nothing else, the six trials under neutral
`Trial 1`–`Trial 6` labels (order shuffled, mapping to baseline/tuned withheld from the graders),
and an instruction to reason through any ambiguity itself and state which reading it applied
rather than have the prompt resolve it. No agent was told a prior grading existed, that a dispute
was in flight, or what the original numbers were.

Trial → source mapping (kept only in this report, not shown to graders):

| Neutral label | Source file | Original grading verdict |
|---|---|---|
| Trial 1 | `g2-tuned-t1.md` | PASS |
| Trial 2 | `g2-baseline-t2.md` | FAIL |
| Trial 3 | `g2-tuned-t3.md` | FAIL |
| Trial 4 | `g2-baseline-t1.md` | FAIL |
| Trial 5 | `g2-tuned-t2.md` | PASS |
| Trial 6 | `g2-baseline-t3.md` | FAIL |

## Results

| Trial | Grader A | Grader B | Grader C | Majority |
|---|---|---|---|---|
| 1 (tuned t1) | PASS | PASS | PASS | **PASS** (3/3 graders) |
| 2 (baseline t2) | PASS | FAIL | PASS | **PASS** (2/3 graders) |
| 3 (tuned t3) | PASS | FAIL | PASS | **PASS** (2/3 graders) |
| 4 (baseline t1) | PASS | FAIL | PASS | **PASS** (2/3 graders) |
| 5 (tuned t2) | PASS | PASS | PASS | **PASS** (3/3 graders) |
| 6 (baseline t3) | FAIL | FAIL | FAIL | **FAIL** (3/3 graders) |

Unanimous on 3 of 6 trials (1, 5, 6). Split 2–1 on the other 3 (2, 3, 4) — all three disputed
trials involve a response that keeps its headline pick (UUIDv7) but names a fallback to a bigint
column under a measured condition (index cost, FK storage, join cost).

**The disputed axis, in the graders' own words:** trials 2 and 3's fallback language explicitly
relabels the fallback bigint as the *"internal bigint PK"* / *"BIGINT internal PK"* — literally
reassigning which column is the primary key if the condition fires. Graders A and C read that as
satisfying "reconsidering the pick" even under a strict reading, since the PK identity itself
would change. Grader B read the surrounding sentence ("Ship the single UUIDv7 PK **now**") as
establishing that UUIDv7 stays the PK regardless, and the trigger only adds a secondary column —
failing under a narrow reading. Trial 4's fallback never uses the word "PK" for its bigint
addition (calls it a "surrogate for internal joins," keeps UUIDv7 as "the external/API
identifier") — all three graders flagged this as the more genuinely ambiguous case; A and C
credited it under a broad reading anyway (concrete, measured condition, same underlying
trade-off), B did not.

**Grader B's narrow-reading verdicts exactly reproduce the original grading's numbers** (baseline
0/3, tuned 2/3), reached independently via a different textual argument (PK-identity framing, not
the original's "added-feature exception" label). That is worth taking seriously: one of three
fresh, literal-text-only reads converges on the original number. It is not proof the original
grading was right for the reasons it gave — the original rubric restatement's "not a pre-launch
check, not an added-feature exception" language pattern-matches on response *shape* ("only add X
if Y") without checking whether the added column becomes the new PK, which is a real, specific
gap in how it was written down, distinct from the number it produced.

## Corrected numbers

| Reading | Baseline (t1/t2/t3) | Tuned (t1/t2/t3) | Baseline rate | Tuned rate |
|---|---|---|---|---|
| Original grading (un-frozen exclusions) | FAIL·FAIL·FAIL | PASS·PASS·FAIL | 0/3 | 2/3 |
| Literal re-grade, narrow reading (1 of 3 graders) | FAIL·FAIL·FAIL | PASS·PASS·FAIL | 0/3 | 2/3 |
| Literal re-grade, majority reading (2 of 3 graders) | PASS·PASS·FAIL | PASS·PASS·PASS | 2/3 | 3/3 |

**No single corrected number exists.** `FREEZE.md`'s G2-A1 text does not say whether a trigger
about an adjacent structural choice (add a secondary column, possibly reassigning which column is
the actual PK) counts as "reconsidering the pick." Three independent literal readings split 2–1 on
that exact question. Per this round's own design intent — hand the ambiguity to the grader rather
than pre-resolve it — a split is itself the finding, not a defect to average away or a tie to
break by fiat.

## Acceptance-rule status (FREEZE.md, both readings)

Rule (a): tuned fixture's targeted-assertion pass rate beats baseline on ≥2 of 3 trials.

- **Narrow reading:** tuned 2/3 vs. baseline 0/3 — clears the bar by a 2-trial margin. Same
  conclusion as the original report ("Confirmed improvement").
- **Majority reading:** tuned 3/3 vs. baseline 2/3 — still numerically beats baseline and still
  clears "≥2/3," but the margin is a single trial, and the baseline itself is no longer a hard
  zero — it's most of the way to ceiling. Per `scored-eval-method.md` rule 3, a single-trial flip
  at n=3 is already labeled weak evidence when starting from 0/3; starting from 2/3 it's weaker
  still, closer to the rule-6 ceiling-fixture caveat ("a fixture at full marks on baseline can't
  show improvement") than to a clear gap.

Rule (b) (C1 control regression) is unaffected by this dispute and not re-examined here.

**Direction survives under both readings** — tuned is never worse than baseline in either
reading. **Magnitude does not** — it ranges from a clear 2-trial flip to a marginal 1-trial flip
depending on an axis `FREEZE.md` left open. Per issue #47's own scope, this report corrects the
cited evidence number; it does not reopen the shipped `output-styles/staff-eng.md` change or
make a ship/no-ship call on the corrected numbers. That's a separate decision for whoever reviews
this with the corrected range in hand.

## Limitations

- **n=3, and now three graders on top of that.** No significance claims are being made in either
  direction; this is a report of what a literal-text reading produces at this sample size, not a
  proof that either reading is "the" correct one.
- **Grader B is not "the narrow reading" and A/C are not "the broad reading" as a stable pair.**
  All three graders independently reasoned through each disputed trial; B happened to land narrow
  on all three, A and C happened to land broad on all three (with C crediting trial 4 under an
  explicitly-flagged broad reading, and A doing the same). Three data points is not enough to
  claim a 2:1 population split beyond "this specific ambiguity axis produced this specific 2:1
  outcome on this specific set of graders."
- **This report does not amend FREEZE.md or grading/G2-verdict.md.** Both are historical
  artifacts of the #38 round; they are quoted here, not edited. If a future round wants a single
  defensible G2-A1 number, the fix is disambiguating the rubric text itself before grading, not
  another re-grade of the same ambiguous wording.
- **The discarded first attempt is real evidence of a specific failure mode**, not just a
  procedural footnote: instructing a grader "don't fail on category X" is functionally different
  from instructing it "here's the literal text, decide for yourself whether category X passes" —
  even when the stated intent (stop applying an un-frozen exclusion) is correct, the *direction*
  of the correction can still smuggle in an answer. Worth carrying forward to any future
  re-grade-style task, not just this one.

## Verification

- Inventory check: 6 G2 trial files confirmed on disk at their stated path (`ls` on
  `.../staff-eng-gap-eval/trials/`, all 18 fixture-trial files present, matches the parent
  report's own inventory count). `probe/g2-baseline-t1.md` confirmed byte-identical to
  `trials/g2-baseline-t1.md` via `diff`.
- `FREEZE.md`'s G2-A1 text and `G2-verdict.md`'s rubric line quoted directly from the on-disk
  files in this report (not recalled from the parent report's paraphrase or issue #47's
  paraphrase).
- Grader independence: none of the three clean-run graders were given the original per-trial
  verdicts, the original rubric's extra exclusion categories, issue #47's narrative, or each
  other's output. The contaminated first run's transcript was not reused or referenced when
  drafting the three graders' prompts.
- No edit made to `output-styles/staff-eng.md`, `FREEZE.md`, or `grading/G2-verdict.md`. This
  report only corrects the citation in `staff-eng-gap-eval-2026-08-10.md` (see that file's
  Limitations section for the dated addendum) and stands as the artifact issue #47 asked for.
