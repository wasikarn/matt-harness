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

Pre-declared acceptance rule: a change ships only if revised beats baseline on its target
fixture (aggregate full-pass across 3 trials, per the precedent's reading) AND the F1 control
does not regress on its leak-guard assertions.

## Headline results (Level A, per-trial)

Full-pass = every applicable assertion PASS in that trial. Grading was paired and blind
(variant names randomized per fixture; graders never told which set was tuned).

| Fixture (target content) | Baseline t1/t2/t3 | Tuned t1/t2/t3 | Verdict |
|---|---|---|---|
| **F1 control** — plain how-to (staff-eng + METHODOLOGY) | 4/4 · 3/4 · 3/4 | 3/4 · 3/4 · 3/4 | Leak guards (no menu / no decision machinery / ≤5 lines) **3:3 ↔ 3:3 unchanged**. A1 ("fix literally on line 1") 1/3→0/3 — instrument artifact, see Limitations |
| **F3** — ranking + floor trap (score-decision) | 4/6 · 5/6 · 4/6 — **0/3 full-pass** | 6/6 · 6/6 · 6/6 — **3/3 full-pass** | **Decisive win.** A1 weights-total 0→3, A2 full matrix 1→3; both flipped ≥2 trials |
| **F2** — contested decision (decide) | 7/7 · 6/7 · 7/7 — 2/3 | 7/7 · 7/7 · 7/7 — 3/3 | Improved on the exact targeted assertion (A3 evidence-tied confidence 2→3). Single-trial flip = weak evidence |
| **F5** — plan review, seeded defects (plan-reviewer) | 5/5 · 5/5 · 4/5 — 2/3 | 5/5 · 5/5 · 5/5 — 3/3 | Improved on targeted A1 (PII standalone finding 2→3); blind comparator also picked the tuned set |
| **F6** — vague ask, clarify shape (decide + staff-eng) | 4/4 · 2/4 · 4/4 — 2/3 | 4/4 · 4/4 · 4/4 — 3/3 | Improved on both targeted assertions (A1 one-question cap, A4 no fabricated menu: 2→3 each). Single-trial flip |
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
20% flag threshold (no verbosity purchase; per `response-conciseness-verbosity-2026-07-16.md`,
each fix is a directive + one worked example, no length rewards).

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

- **n=3.** F2/F5/F6 improvements are single-trial flips — each flipped trial failed exactly the
  assertion its edit targeted (a causal path exists), but by the strictest per-trial reading
  only F3 clears "beats on ≥2 of 3 trials". Reported as: F3 = confirmed; F2/F5/F6 = improved,
  weak-evidence.
- **F1-A1 (1/3→0/3) is verbatim-reported, classified artifact+noise:** the assertion demands the
  fix on literal line 1 of the raw file; all 3 tuned-run trials open with "Quote the variable:"
  and give the correct fix on the next line (same shape as baseline t3; baseline t2 failed on a
  ```` ```bash ```` fence opener). The only diff in F1's content set is one Rule-14 line about
  rank/recommend runner-ups — no causal path to line-1 formatting. Same treatment the precedent
  eval gave its S3 mark-rate wobble. The control's actual purpose — no recommendation machinery
  leaking into plain answers — held 3:3 ↔ 3:3 on all three leak-guard assertions.
- **Simulated single-turn instrument**: runners emulate an assistant from file contents alone —
  no real tool access, no cross-turn state. Same known blind spot the precedent documented for
  gap-1-style mid-draft failures.
- **Level B is not a quality score** — it's a to-do list generator. Only Level A numbers are
  evidence of behavior change.

## Verification

- `harness-audit` before: 0 CRIT / 0 WARN / 5 INFO — after: re-run green (see commit).
- All 39 frozen-list paths existed at freeze time; sweep graded every one (no silent truncation).
- Full raw transcripts (36 generation trials, 8 grading transcripts, comparator) in the session
  scratchpad `rec-tune/` — re-gradeable by hand if any number above is questioned.
