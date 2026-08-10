# Recommendation-quality tune — scored before/after eval

Date: 2026-08-10. Ask: make every recommendation-producing surface more detailed, confident,
and precise — measured with scores before AND after, per the method proven in
`askuserquestion-recommended-criterion-eval-2026-08-07.md` (frozen instruments before any tuning
text, n=3, blind paired grading, pre-declared acceptance rule).

## Scope (frozen before grading)

Inclusion rule: kbg-authored shipped surface whose output names a pick the user acts on, or
doctrine governing how such picks are made. **39 files**: 4 doctrine + 11 agents + 10 commands +
14 skills (full list + rubric + fixture prompts + A/B mapping: session scratchpad
`rec-tune/FREEZE.md`; grading transcripts under `rec-tune/grading/`). Excluded: vendored
`docs/reference/thinking-skills/**`, eval-workspace artifacts, incidental mentions.

Two instruments, honestly separated:
- **Level A (behavioral, the headline)**: 6 fixtures × 3 fresh-context trials per condition;
  runners read only the target content files (snapshot copies, never `Skill()`-resolution).
- **Level B (static sweep)**: 9-criterion checklist over all 39 files with line citations —
  reported as gaps found/closed, **never** as a scored delta (tuning adds the checked
  instructions, so a Level B "score improvement" would be true by construction).

Pre-declared acceptance rule (as frozen in FREEZE.md): a change ships only if revised beats
baseline on its target fixture (aggregate full-pass across 3 trials, per the precedent's
reading) AND the F1 control does not regress on **any** assertion. **The shipped call accepts
one letter-level deviation from that second clause** — F1-A1 moved 1/3→0/3 and the batch
shipped anyway on artifact evidence; that is a judged deviation documented in Limitations, not
a re-reading of the frozen rule.

## Headline results (Level A, per-trial)

Full-pass = every applicable assertion PASS in that trial. Grading was paired and blind
(variant names randomized per fixture; graders never told which set was tuned).

| Fixture (target content) | Baseline t1/t2/t3 | Tuned t1/t2/t3 | Verdict |
|---|---|---|---|
| **F1 control** — plain how-to (staff-eng + METHODOLOGY) | 4/4 · 3/4 · 3/4 | 3/4 · 3/4 · 3/4 | Leak guards (no menu / no decision machinery / ≤5 lines) **3:3 ↔ 3:3 unchanged**. A1 ("fix literally on line 1") 1/3→0/3 — instrument artifact, see Limitations |
| **F3** — ranking + floor trap (score-decision) | 4/6 · 5/6 · 4/6 — **0/3 full-pass** | 6/6 · 6/6 · 6/6 — **3/3 full-pass** | **Decisive win.** A1 weights-total 0→3, A2 full matrix 1→3; both flipped ≥2 trials |
| **F2** — contested decision (decide) | 7/7 · 6/7 · 7/7 — 2/3 | 7/7 · 7/7 · 7/7 — 3/3 **(superseded → 1/3, then 2/3 post-fix — see Follow-up 2)** | Improved on the exact targeted assertion (A3 evidence-tied confidence 2→3). Single-trial flip = weak evidence. **Follow-up (issue #41, same day): downgraded to 1/3 on A6, an untargeted assertion — see § Follow-up. Follow-up 2 (issue #42): A6 fix shipped, re-tested at 2/3 (A6 itself 1/3→2/3) — see § Follow-up 2** |
| **F5** — plan review, seeded defects (plan-reviewer) | 5/5 · 5/5 · 4/5 — 2/3 | 5/5 · 5/5 · 5/5 — 3/3 **(reconfirmed 3/3, see Follow-up)** | Improved on targeted A1 (PII standalone finding 2→3); blind comparator also picked the tuned set. **Follow-up (issue #41, same day): confirmed — see § Follow-up below** |
| **F6** — vague ask, clarify shape (decide + staff-eng) | 4/4 · 2/4 · 4/4 — 2/3 | 4/4 · 4/4 · 4/4 — 3/3 **(re-tested 2/3, see Follow-up)** | Improved on both targeted assertions (A1 one-question cap, A4 no fabricated menu: 2→3 each). Single-trial flip. **Follow-up (issue #41, same day): re-tested, weak-evidence label stands — see § Follow-up below** |
| F4 — genuine fork, AskUserQuestion shape (staff-eng) | 5/5 · 5/5 · 5/5 | not re-run (content untouched) | **Ceiling — non-discriminating.** Consistent with the 2026-08-07 eval's already-shipped fixes; deliberately not re-litigated |

Secondary blind comparator (ties allowed): F5 → tuned set wins; F2/F3/F6 → tie ("within
run-to-run variation" on holistic quality — the rubric deltas are structural auditability
elements the comparator's holistic lens doesn't weight). Comparator divergence note: on F6's one
failing baseline trial the comparator felt the two extra questions "resolve real ambiguity";
the rubric's position is doctrine-backed (both questions carried pre-picked `(Recommended)`
defaults — the answer was already knowable; the twice-confirmed 2026-07-02 defect class).

## What was changed (measured targets)

| File | Change | Evidence it worked |
|---|---|---|
| `skills/score-decision/SKILL.md` | Declare weight total in output; render full per-criterion × per-option matrix (not just the winner's breakdown); `Re-score when:` line in both templates | F3 A1 0→3, A2 1→3 |
| `skills/decide/SKILL.md` | `Confidence:` field in the decision record (evidence-tied, about the pick itself); `Selected: … (driven by: <facts>)`; clarify mode: one-question cap + settled-ask guard with a non-fixture worked example | F2 A3 2→3; F6 A1/A4 2→3 |
| `agents/plan-reviewer.md` | Lens 4: data-exposure surface is its own finding, never a sub-clause of encoding; `verdict_movers:` output field | F5 A1 2→3 |

Char deltas: score-decision +10%, decide +6%, plan-reviewer +5% — all under the pre-declared
20% flag threshold (no verbosity purchase, no length rewards; per
`response-conciseness-verbosity-2026-07-16.md`). Worked examples landed where the target
failure was behavioral — decide's clarify guard, plan-reviewer's exposure rule +
`verdict_movers`, address-review's pick line; the remaining closures are directive/template
only. That is a judged narrowing of the plan's "directive + one worked example per gap" bar —
noting F3's 0/3→3/3 landed on template-only changes, so the example bar was not what moved it.

## Level B sweep — gaps found → closed (work-list, not a score)

~50 cited gaps across 39 files (detail: `rec-tune/grading/levelB-*.md` in the session
scratchpad). Closed this round (5 files beyond the 3 measured ones, all unmeasured by fixtures —
labeled honestly as such):

- `docs/METHODOLOGY.md` Rule 14: rank/recommend verdicts name the runner-up + why it lost.
- `skills/orchestrate/SKILL.md`: dispatch-gate recommendation anchors blast-radius labels to what
  each task touches, names the rejected order + the fact that would flip it; deferred/dropped
  rows carry a re-open condition.
- `skills/learn/SKILL.md`: gate menu ordered strongest-first, options carry consequences,
  multiSelect minority-marking, no options the skill's own filter already refuted.
- `agents/backend-architect.md`: Alternatives Considered + Confidence & Assumptions output
  sections (the Alternatives bar mirrors `code-architect`'s; the Confidence section is net-new).
- `commands/address-review/COMMAND.md`: Phase 2 recommendation names its driving fact inline and
  resolves `(best when …)` → `(Recommended)` at render time; multi-condition case said aloud.

Deliberately NOT closed (with reasons):
- `output-styles/staff-eng.md` — it is the F1/F4 control surface and the 2026-08-07 eval's
  already-measured territory; its two sweep gaps (reason-anchoring wording, revisit-trigger) are
  backlog for a future isolated round with fresh controls.
- `agents/ideate-critic.md` (4 gaps) — every fix changes a JSON envelope `/ideate` parses
  programmatically; blast radius exceeds the gain without a coordinated host-side change.
- `agents/task-prep-checker.md` DEFAULT-BEFORE-ASK — its guardrail *forbids* inventing defaults
  by design; the "gap" is the feature.
- Remaining ~30 gaps (fix-bug, post-mortem, ship-*, review-pr, incident, pr, production-audit,
  recursive-improve, task-prep, goal-craft, code-reviewer, performance-optimizer,
  refactor-cleaner, code-architect, orchestrate/reference.md, ship/references/*) — backlog;
  several are already partially covered by the doctrine layer's render-time rules. Closing them
  unmeasured in bulk would have repeated round 1's bundling mistake from the precedent eval.

## Limitations (read before trusting the numbers)

- **n=3.** F2/F5/F6 improvements were originally single-trial flips — each flipped trial failed
  exactly the assertion its edit targeted (a causal path exists), but by the strictest per-trial
  reading only F3 cleared "beats on ≥2 of 3 trials". Firmed up same-day (issue #41, 3 fresh
  trials each against current shipped content — see § Follow-up): **F3 = confirmed** (unchanged,
  not re-run); **F5 = confirmed**, weak-evidence label lifted (3/3 full-pass, content
  byte-identical to what was graded); **F6 = still weak-evidence** (re-tested 2/3, ties
  baseline's own rate — not distinguishable at n=3); **F2 = downgraded** (1/3 full-pass — the
  targeted assertion A3 held 3/3 clean, but a non-targeted assertion, A6 falsifiability, failed
  in 2 of 3 fresh trials; not connected to the drift below, since F2's fixture is a full-climb
  path; **superseded same-day by Follow-up 2 (issue #42) — A6 fixed and re-tested at 2/3, up from
  1/3 — see § Follow-up 2, this bullet otherwise stands as the as-of-#41 historical record**).
  **Both F2 and F6 load the drifted `decide/SKILL.md`** (see next bullet); neither's
  rubric assertions touch the drifted clause (a Confidence-field exemption), so the drift is
  disclosed here for both but doesn't explain either fixture's result. **A second, initially
  undisclosed drift**: F6 also loads `output-styles/staff-eng.md`, which changed (commit
  `7790da3`) in the ~26-minute window between this round's content snapshot and this report's
  own commit — see § Follow-up's byte-compare table for what changed and why it doesn't touch
  F6's checked assertions. Caught by a same-day compliance audit, not by rule 8/9 at commit time.
- **F1-A1 (1/3→0/3) — a letter-level deviation from the frozen control rule, accepted by
  judgment:** the rule as frozen forbids regression on ANY control assertion; this one
  regressed and the batch shipped anyway. Basis: the assertion demands the
  fix on literal line 1 of the raw file; all 3 tuned-run trials open with "Quote the variable:"
  and give the correct fix on the next line (same shape as baseline t3; baseline t2 failed on a
  ```` ```bash ```` fence opener). The only diff in F1's content set is one Rule-14 line about
  rank/recommend runner-ups — no causal path to line-1 formatting. Same treatment the precedent
  eval gave its S3 mark-rate wobble. The control's actual purpose — no recommendation machinery
  leaking into plain answers — held 3:3 ↔ 3:3 on all three leak-guard assertions.
- **Simulated single-turn instrument**: runners emulate an assistant from file contents alone —
  no real tool access, no cross-turn state. Same known blind spot the precedent documented for
  gap-1-style mid-draft failures.
- **One post-grading micro-edit to a measured file**: the code-review pass (run after grading)
  fixed an internal contradiction in `skills/decide/SKILL.md` — the rungs-1–2 completion
  exception now explicitly exempts the Confidence line. The graded transcripts predate that
  clause. F2's fixture is a full-climb decision the exception cannot reach, so the measured
  result stands; the clause itself is unmeasured.
- **Level B is not a quality score** — it's a to-do list generator. Only Level A numbers are
  evidence of behavior change.

## Follow-up: confirmation trials for F2/F5/F6 (issue #41, same day)

Issue #41, "Confirmation trials for F2/F5/F6 — firm up single-trial flips from the v0.68.246
tune," asked to re-run n=3 fresh-context trials per fixture against current shipped content and
report each fixture confirmed or downgraded. Per `scored-eval-method.md`, fixtures and rubric are
reused verbatim from this round's frozen FREEZE.md — no new instruments. Pre-declared outcome rule
(written before any trial ran): 3/3 new
full-pass → confirmed, weak-evidence label lifted; 2/3 → ties baseline's own 2/3, not
distinguishable at n=3, label stands; ≤1/3 → downgraded. A 2/3 result is deliberately **not**
reported as "confirmed" even though it clears the issue's literal bar — it would be identical to
baseline's own rate and prove nothing, the exact defect class the 2026-08-10 post-mortem exists to
prevent.

**Content byte-compare (rule 9), run first:**

| File | vs. graded `content-r2/` | Used for |
|---|---|---|
| `skills/decide/SKILL.md` | **Differs** — the post-grading edit already disclosed above (rungs-1–2 exception now also exempts Confidence) | F2, F6 |
| `docs/METHODOLOGY.md` | Identical | F2 |
| `agents/plan-reviewer.md` | Identical | F5 |
| `output-styles/staff-eng.md` | Identical **at the 11:22 snapshot** — a second edit (commit `7790da3`, 11:48, adding a "revisit trigger" column to the Format table's "Decision with lasting consequences" row) landed before this report's own commit (11:52); not caught by the byte-compare above because it ran before that edit existed | F6 |

F2 and F6 trials ran against genuinely post-edit content (per issue #41's explicit ask to test
current shipped state); F5 is a clean re-confirmation of the exact bytes that were graded. The
staff-eng.md gap above surfaced only on a later independent compliance audit (2026-08-10, same
day) — none of F6's checked assertions (A1–A4) test for a revisit-trigger element, so it doesn't
change F6's 2/3 result, but the byte-compare table's own "Identical" claim was stale by the time
this report was committed and should have been re-checked before commit, not just at snapshot
time.

**New trials — 3 fresh-context runs per fixture, graded independently (neutral framing, no
mention this was a confirmation run), full per-assertion tables in the session scratchpad.**
Rule 4's blind A/B pairing doesn't apply here — there is only one condition to grade (current
shipped content), not a baseline/tuned pair to re-litigate; the baseline numbers are already
frozen in the original round and aren't re-run.

| Fixture | New trials (full-pass per trial) | Aggregate | Verdict |
|---|---|---|---|
| F2 | FULL-PASS · fail A6 · fail A6 | **1/3** | **Downgraded.** Targeted assertion A3 (confidence tied to evidence) held 3/3 clean — the original causal claim about A3 stands. What sank the aggregate is A6 (falsifiability), an assertion the tuning never targeted, failing in 2 of 3 fresh trials with near-identical wording ("none of these flip the direction"). Not connected to the decide/SKILL.md drift — F2 is a full-climb path the drifted clause doesn't reach. Read as: a real, previously-undetected weak spot in decide's full-climb falsifiability output, not a false original claim. Not in this issue's scope to fix — logged here as a finding for a future round. |
| F5 | FULL-PASS · FULL-PASS · FULL-PASS | **3/3** | **Confirmed.** Content unchanged since grading — a clean re-confirmation, not a drift artifact. Weak-evidence label lifted. |
| F6 | FULL-PASS · FULL-PASS · fail A1 | **2/3** | **Weak-evidence label stands.** Ties baseline's own 2/3 exactly. The one failing trial tripped A1 by stacking two "say if" branches (the second an explicit two-way menu) — the same shape of slip the original tuning targeted, still surfacing on 1 of 3 fresh trials. decide/SKILL.md's drift doesn't touch this assertion (the exempted clause is about a Confidence field the F6 rubric never checks). |

Runner/grading harness matched the original round's shape (read-only snapshot content, one
runner template, an independent grading pass with a required ≤20-word quote per verdict); one
original tuned transcript (`runs-after/F2-t1.md`) was read first to confirm the response format
expected. Full trial transcripts and grading tables: session scratchpad
`rec-tune-confirm/` (`content-current/`, `runs/`, `grading/`, `FOLLOWUP-FREEZE.md`).

## Verification

- `harness-audit` before: 0 CRIT / 0 WARN / 5 INFO — after: re-run green (see commit).
- All 39 frozen-list paths existed at freeze time; sweep graded every one (no silent truncation).
- A `kbg:code-reviewer` pass ran on the final diff before commit: 2 HIGH (missing version bump;
  a rungs-1–2 Confidence contradiction in decide) + 1 MEDIUM + 2 LOW (report numeric
  corrections) — all addressed pre-commit.
- Full raw transcripts (33 generation trials — 18 baseline + 15 tuned, F4 not re-run; 8 grading
  transcripts; comparator verdict at `grading/comparator.md`, saved verbatim from the comparator
  agent's inline return) in the session scratchpad `rec-tune/` — re-gradeable by hand if any
  number above is questioned.
- **Follow-up (issue #41) inventory cross-check (rule 8), run before writing this section**: 9
  new trial files on disk in `rec-tune-confirm/runs/` (3 per fixture, matches the table above), 3
  grading tables in `rec-tune-confirm/grading/`, 4 content snapshots in
  `rec-tune-confirm/content-current/` matching the byte-compare table's file list, `FOLLOWUP-FREEZE.md`
  present. No shipped surface file was edited by this follow-up (docs/research is outside the
  runtime-loaded set) — no version bump, no harness-audit re-run required.

## Follow-up 2: A6 falsifiability fix (issue #42, same day)

Issue #42 asked to close the A6 gap Follow-up 1 surfaced: 2 of 3 fresh trials denied any fact
existed that would flip the pick, near-identically worded ("none of these flip the direction" /
"none of them flips which option to commit to"). Root cause, found by reading both failing
transcripts in full: Rung 3's "what evidence would refute it?" only asks about individual
assumptions, and the mode's separate "genuine fork → `AskUserQuestion`" test (a different
question — pause and ask now, or not) was getting reused by the model to answer the falsifiability
question too. Trial 3 of the prior round shows the conflation directly: "No genuine two-branch
fork survives this list ... None of them flips which option to commit to — so no
`AskUserQuestion` here."

**Fix**, per `docs/research/scored-eval-method.md`: no new fixture — F2's frozen ASK/assertions
reused verbatim.

| File | Change |
|---|---|
| `skills/decide/SKILL.md` | Rung 3 now states the fork test and the flip test are different questions and requires naming the one assumption that reverses the pick; Output format's Decision block gained a required `Flip condition` line, distinct from Confidence and Revisit trigger; Completion criterion's `decide` bullet (and its rungs-1–2 exception) updated to match |
| `docs/reference/judgment-ladder.md` | Matching `Flip condition` line added to the full decision-record template and a Rung 3 checkpoint-table row, for live-usage consistency — not part of the graded content set (F2 loads only `decide-SKILL.md` + `METHODOLOGY.md`, simulated single-turn) |

**Content byte-compare (rule 9):** both files are new edits made for this issue, not
previously-graded snapshots — no drift to disclose against a prior grading pass, for F2. **F6
disclosure**: F6 also loads `skills/decide/SKILL.md` (Follow-up 1's byte-compare table), so its
currently-published 2/3 result (§ Follow-up) now predates this edit too. Not re-tested here — out
of #42's scope — but the edited sections (`decide` mode's Rung 3, Output format, Completion
criterion) are outside `clarify` mode, the only section F6's rubric (A1–A4) reads; F6's own
Completion criterion bullet is untouched. Practical drift risk is near zero, not zero — flagged
per rule 9 rather than silently left for the next round to discover.

**Pre-declared outcome rule** (written before any trial ran, full text in
`issue-42-f2-rerun/FREEZE.md`): 3/3 or (2/3 with A6 passing ≥2/3) → fixed; 2/3 with A6 still the
dominant failure mode at its prior rate → not closed; ≤1/3 → not closed.

**New trials — 3 fresh-context runs, independent blind grading (grader given only the 3
transcripts + rubric, no framing that this tests a fix):**

| Assertion | Trial 1 | Trial 2 | Trial 3 |
|---|---|---|---|
| A1–A5, A7 | PASS ×5 | PASS ×5 | PASS ×5 |
| **A6** (flip fact named) | **PASS** — "the pick flips to Reject A" | **FAIL** — states hardening "becomes the faster thing to try first" but Commitment separately says "migration kickoff follows that check" regardless of outcome — the reversal is asserted in prose, never operationalized | **PASS** — "Option A flips to Option B (or a third path)" |

**Per-trial: Trial 1 FULL-PASS (7/7). Trial 2 not full-pass (6/7, A6 only). Trial 3 FULL-PASS
(7/7). Aggregate: 2/3.** A6 specifically: **2/3 pass**, up from **1/3** in Follow-up 1 — the
targeted gap. Per the pre-declared rule this clears as fixed, but the honest read at n=3: this is
a directional improvement, not a clean sweep. Trial 2's failure is qualitatively different from
Follow-up 1's — a *stated* reversal that the plan doesn't act on, not a flat denial that any
reversal exists — which reads as the fix working (it now produces flip language) while exposing a
narrower follow-on gap: nothing yet checks that Commitment's actual plan honors the flip condition
declared above it. Logged here, not fixed — a smaller, distinct issue from #42's scope.

Runner/grading harness matched prior rounds' shape (read-only snapshot content, one runner
template, an independent grading pass with a required ≤20-word quote per verdict, recomputed
aggregate from the per-assertion table). Full transcripts and grading verdict: session scratchpad
`issue-42-f2-rerun/` (`content-tuned/`, `runs/`, `FREEZE.md`).

**Verification**

- Char delta: `decide/SKILL.md` +1,214 bytes (+6.8%); `judgment-ladder.md` +391 bytes (+3.0%) —
  both under the 20% anti-verbosity flag (rule 7).
- `harness-audit`: 0 CRIT / 1 WARN (stale README version badge, unrelated pre-existing drift,
  fixed in the same commit) / 5 INFO before the badge fix → 0 CRIT / 0 WARN / 5 INFO after.
- Version bump: v0.68.250 → v0.68.251 in both `plugin.json` and `marketplace.json` (both files
  edited are in the runtime-loaded set: `skills/**` and `docs/reference/**`).
- Inventory cross-check (rule 8): 3 trial files on disk in `issue-42-f2-rerun/runs/` (matches n=3),
  1 grading pass (agent-returned table, cross-footed above against the per-assertion cells, not
  trusted from its own stated total).
