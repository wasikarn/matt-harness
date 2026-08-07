# AskUserQuestion "(Recommended)" criterion — audit + scored before/after eval

Date: 2026-08-07. Target: `output-styles/staff-eng.md:15` (the "Decision questions" bullet),
iterated 4x already (v0.68.6–.9, all 2026-07-22), every commit explicitly stating "model
adherence only, no deterministic gate possible."

## Audit findings (gap map)

| Gap | Description | Evidence |
|---|---|---|
| 1 | No "stop before finishing the menu" check — agent drafts an N-way menu even when its own reasoning, or repo context, already picks a winner mid-draft | **2 confirmed real recurrences** — `askuserquestion-consistency-gap-2026-07-02.md` |
| 2 | multiSelect has an explicit "mark none if all comparable" rule; single-select does not | None — derived by close-read |
| 3 | multiSelect "minority" threshold undefined at exactly half | None — derived by close-read |
| 4 | No rule for when a `(best when X)`-style template has more than one condition holding at once | None — derived by close-read |

Also confirmed: 13 shipped skills/commands use the `(best when X)` template pattern this doctrine
governs (swept in v0.68.7); no existing hook/check inspects `AskUserQuestion` calls structurally —
the "no deterministic gate possible" claim in the commit history is about the *semantic* judgment
(should this be marked?), not the *structural* rules (marker placement, first-position, minority
ratio), which are mechanically checkable. Flagged as a possible follow-up, not built — bigger
blast radius (a hook fires every session), needs separate sign-off.

## Method

Per `advisor()` guidance: scenarios and grading rubric were frozen (written to disk) **before**
any revised doctrine text was drafted, to avoid the rubric silently encoding the revision. 6
scenarios (2 targeting gap 1, 1 control, 1 each for gaps 2/3/4), 3 independent trials per
scenario per condition (n=3, not n=1 — single-run deltas are noise). Baseline = current doctrine
text verbatim. Candidate v1 = full restructure addressing all 4 gaps. Grading done by a separate
agent, blind to which trial-group was baseline vs revised, against the frozen rubric.

Pre-declared acceptance rule (fixed before seeing any output): a gap counts as improved only if
the revised pass-rate beats baseline by ≥2 of 3 trials, AND the S3 control does not regress.

Full scenario text, rubric, raw transcripts (all 6 generation trials + the blind grading
transcript) are in `/private/tmp/claude-501/.../scratchpad/askq-eval-*.md` for this session —
re-gradeable by hand if the numbers below are questioned.

## Results

| Scenario | Gap tested | Baseline | Revised (v1, full restructure) | Verdict |
|---|---|---|---|---|
| S3 (control) | regression guard | asks 3/3, marks-correctly 1/3 | asks **2/3** (1 skipped), marks-correctly 0/2 | **Regressed** |
| S1 | 1 (should-skip) | 3/3 | 3/3 | Ceiling — ceiling both conditions, scenario too easy to discriminate |
| S2 | 1 (should-skip) | 3/3 | 3/3 | Ceiling — same |
| S4 | 2 (genuine tie) | 0/3 (fabricates a "winner" every trial) | 3/3 (asks/answers, no fabricated marker) | **Confirmed improvement** |
| S5 | 3 (half-boundary) | 3/3 self-consistent | 2/3 self-consistent | **Regressed** (added rule increased variance, not reduced it) |
| S6 | 4 (overlap ack.) | 0/3 | 3/3 | **Confirmed improvement** |

Root cause of the two regressions, both traced to the specific wording added, not the underlying
idea: step 1's "does a sensible default exist — from your own reasoning" phrasing let one trial
construct a plausible-sounding justification to skip a genuinely-contestable decision (S3) instead
of asking; step 4's explicit half-boundary rule collided with step 1's newly-strengthened skip
logic on the multiSelect scenario (S5), producing 3 different treatments across 3 trials instead
of the intended single consistent one.

Gap 1's own scenarios (S1/S2) never actually discriminated baseline from revised — both already
sit at ceiling on this synthetic instrument. The 2 real historical recurrences remain the
justification for eventually fixing gap 1, but this specific wording is not the fix — it measurably
made things worse elsewhere in the same run.

## Decision: ship the validated subset only

Per the pre-declared rule (S3 must not regress), the full v1 restructure does **not** clear the
bar. Recommended action is a much smaller diff — the two sentences that produced clean, isolated
wins (S4: 0/3→3/3, S6: 0/3→3/3) with no interaction against the scenarios that regressed:

1. After the marker-placement sentence: *"If the options are genuinely comparable — a real
   coin-flip, not just unexamined — mark none; don't fabricate a preference to satisfy the
   convention."*
2. After the `(best when X)` template-resolution sentence: *"If more than one condition plausibly
   holds at once, say so explicitly instead of silently picking one."*

Gap 1 (mid-draft self-check) and gap 3 (half-boundary) are **not** recommended for this release —
worth a separate attempt with a narrower trigger condition (e.g. gate the self-check on "the
alternative has a stated, objective flaw," not "you can construct a plausible argument"), tested
against S3/S5 again before shipping.

This inference (dropping steps 1/4 keeps the S4/S6 gains without the S3/S5 regressions) is drawn
from the same run, not a fresh confirming test — the two additions never interacted with the parts
of the rule that regressed. Reasonable but not independently re-verified; a confirming 3-trial run
of the minimal diff alone would close that gap if it matters before shipping.

## Round 2 — narrower triggers for gap 1 and gap 3, isolated this time

Requested follow-up: retry gap 1 and gap 3 with a narrower trigger. Round 1's design flaw carried
forward the risk of repeating itself — bundling both changes in one restructured bullet made it
impossible to tell which one caused the S3/S5 regressions. Round 2 fixes that: each candidate is
appended to the CURRENT (already-shipped, v0.68.218) doctrine text in isolation, tested against a
freshly-run BASE reference (round 1's baseline predates the gap-2/gap-4 fixes now live, so it's not
a valid comparison point anymore). Added one harder scenario, S7, mirroring the real 2026-07-02
incident's actual texture more closely — 4 options, 2 disqualified by an explicit out-of-scope
constraint, 1 disqualified by directly contradicting the stated complaint, 1 survivor — since S1/S2
turned out too easy (a single obvious fact settles them) to discriminate anything in round 1.

**Candidate A (narrower gap-1):** *"Run that filter while drafting the options, not while
reviewing a finished draft: if every option but one is ruled out by a fact you already have — a
stated hard constraint, an explicit convention, or resources/infrastructure that don't exist and
aren't being proposed — the survivor is the default; stop and state it instead of finishing the
menu. A trade-off where more than one option still has a real, undismissed advantage isn't this
case — that one gets asked."*

**Candidate B (gap-3 half-boundary):** *"At exactly half, treat it the same as comparable: mark
none, order strongest-first — don't round toward marking or skipping."*

| Scenario | BASE | +Candidate A | +Candidate B |
|---|---|---|---|
| S3 ask-rate (regression guard) | 3/3 | 3/3 — **no regression this time** | 3/3 — no regression |
| S3 mark-rate | 2/3 | 1/3 (no plausible mechanism connects A to this; likely n=3 noise) | 0/3 (B's clause is textually scoped to multiSelect only — no causal path to S3; noise) |
| S1 / S2 / S7 (gap-1 target) | 3/3 / 3/3 / 3/3 | 3/3 / 3/3 / 3/3 | not the target |
| S5 consistency (gap-3 target) | 2/3 (dominant treatment: skip to prose, decide 2-of-4 directly) | 2/3, same shape | **3/3, and all 3 trials use the intended treatment** (multiSelect tool call, all 4 left unmarked) |

**Candidate B (gap-3) clears the pre-declared bar** — beats baseline (2/3→3/3 consistency), the
winning treatment is exactly the intended one (not just internally consistent by accident), and S3
doesn't regress. Confirmed fix, isolating it from gap-1's wording was the right call.

**Candidate A (narrower gap-1) is safe but still unproven on this instrument.** The regression
from round 1 is gone — S3's ask-rate holds at 3/3 in both BASE and +A, so the narrower trigger
(requiring a stated fact to eliminate *every other* option, not just "a plausible lean") does what
it was designed to do. But S1/S2/S7 all sit at 3/3 ceiling in both conditions — even the harder S7
scenario didn't discriminate baseline from the candidate. Working theory: the real 2026-07-02
incident's failure mode is catching yourself mid-draft, after already starting to build a menu —
a state a stateless single-turn eval can't reproduce, since the model decides fresh each time
rather than course-correcting an in-progress mistake. The 2 real incidents remain the reason this
gap is worth closing; this specific wording just isn't validated as *the* fix by this harness, only
shown not to actively hurt.

Full round-2 scenario file, both candidate wordings, raw transcripts (18 generation trials this
round), and the blind grading transcript are in the same scratchpad directory as round 1, files
prefixed `askq-eval-round2-*`.
