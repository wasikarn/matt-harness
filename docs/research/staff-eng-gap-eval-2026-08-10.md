# Scored eval round — staff-eng.md revisit-trigger + evidence-reason gaps (issue #38)

Date: 2026-08-10. Follows `docs/research/scored-eval-method.md`. Closes the two Level-B gaps the
2026-08-10 recommendation-quality-tune round deliberately left open in `output-styles/staff-eng.md`
(it was that round's F1/F4 control surface, so editing it would have invalidated the control —
GitHub issue #38).

## Frozen-list reference

Single file: `output-styles/staff-eng.md`. Two gaps, both taken verbatim from the parent round's
ground-truth grading artifact (`rec-tune/grading/levelB-doctrine.md`, still on disk in that
session's scratchpad — read directly rather than re-derived from the issue's paraphrase):

- **EVIDENCE-REASON** (line 19, "Be opinionated" bullet) — "State a preference and the reason" is
  unconstrained; no requirement the reason cite evidence vs. plausible-sounding prose.
- **REVISIT-TRIGGER** (line 51, Format table, "Decision with lasting consequences" row) — lists
  "Decision + constraint + owner + verification step" but no revisit trigger, despite
  `docs/METHODOLOGY.md` line 36 requiring one for consequential decisions globally.

Full instrument spec, frozen before any candidate wording existed: `FREEZE.md` in this session's
scratchpad (`.../staff-eng-gap-eval/FREEZE.md`), including the discrimination-probe disclosure and
the content-set isolation choice (all fixtures use `staff-eng.md` alone, not bundled with
`METHODOLOGY.md` — isolates this file's own wording from the session-level doctrine injection that
already states the revisit-trigger requirement).

## Per-trial results (control row first)

Full-pass = every applicable assertion PASS in that trial. Grading was paired and blind (neutral
`variant-a`/`variant-b` names; graders never told which was baseline vs. tuned).

| Fixture (targeted gap) | Baseline t1/t2/t3 | Tuned t1/t2/t3 | Verdict |
|---|---|---|---|
| **C1 control** — plain factual lookup (Postgres `NOT NULL`) | 4/4 · 4/4 · 4/4 | 4/4 · 4/4 · 4/4 | **No regression** — all 4 leak-guard/correctness assertions held 3:3 ↔ 3:3 (24/24 PASS total, no differentiating failure) |
| **G2** — PK-strategy pick, one-way-door (REVISIT-TRIGGER target) | A1 fail·fail·fail — **0/3** on the targeted assertion | A1 pass·pass·fail — **2/3** on the targeted assertion | **Confirmed improvement.** Clears the pre-declared bar (≥2/3, control clean). A2/A3 (structural) held 3/3 both conditions |
| **G1** — pino/winston pick (EVIDENCE-REASON target) | A1 pass·pass·pass — **3/3** | A1 pass·pass·pass — **3/3** | **Ceiling — non-discriminating**, even after one hardening round (see Limitations). Not claimed as a win or a loss |

G2's per-trial detail (targeted assertion A1, revisit trigger for the PK decision itself — a
concrete condition/event, not a pre-launch check or an added-feature exception): baseline trials
1–3 named only pre-launch verification steps or feature-addition exceptions, never a condition to
*revisit the pick*; tuned trial 1 produced an explicit `Revisit trigger:` header naming two concrete
conditions (tenant-DB sharding, table turning out fully internal); tuned trial 2 named a concrete
sharding condition; tuned trial 3 (like all 3 baseline trials) only named a feature-addition
exception, not a revisit-the-decision trigger.

## What was changed (measured target)

| File | Change | Evidence it worked |
|---|---|---|
| `output-styles/staff-eng.md` | Format table, "Decision with lasting consequences" row: `Decision + constraint + owner + verification step` → `Decision + constraint + owner + revisit trigger + verification step` | G2 targeted assertion (A1) 0/3 → 2/3; C1 control held 24/24 |

The EVIDENCE-REASON candidate (append to the "Be opinionated" bullet: anchor the stated reason to
a fact already in view, not a generic claim) was drafted and tested in isolation but **not
shipped** — see Limitations.

Char delta: shipped diff is 13652 → 13670 bytes, **+0.13%** — well under the 20% flag threshold
(no verbosity purchase; per `response-conciseness-verbosity-2026-07-16.md`).

## Level-B — this round's disposition of the two named gaps

This round did not re-run the 39-file Level-B sweep (out of scope — that sweep already happened in
the parent round). It closes/rejects exactly the two gaps the parent round named as deliberately
left open, per the issue's own scope:

- **REVISIT-TRIGGER — closed.** Shipped, with Level A behavioral evidence (0/3 → 2/3 on the
  targeted assertion, isolated from the other candidate, control clean).
- **EVIDENCE-REASON — explicitly rejected this round, not closed.** The fixture (pino vs. winston,
  a true generic-performance claim competing against the actually-decisive stated fact) ceilinged
  at 6/6 PASS across both conditions even after one hardening round from an earlier, weaker
  fixture design. Per method rule 6, a fixture at full marks on baseline cannot demonstrate
  improvement — this is reported as unmeasured, not as a rejection of the underlying idea. The
  existing doctrine already produces evidence-anchored reasoning on the scenario class this
  fixture represents; whether that holds on harder scenarios is untested. Backlog for a future
  round with a fixture design that doesn't ceiling (e.g., a scenario with a weaker or less salient
  stated fact, or a scoring rubric that penalizes partial/blended reasoning rather than treating
  "cites the fact anywhere" as a pass).

## Limitations (read before trusting the numbers)

- **n=3, single-trial flip.** G2's 0/3→2/3 result rests on 2 of 3 tuned trials flipping — both
  flipped trials produced the exact targeted behavior (an explicit revisit condition tied to
  reconsidering the PK pick), and the one non-flipping tuned trial failed on the same shape as all
  3 baseline trials (a feature-addition exception mistaken for a revisit trigger). A causal path
  exists but this is not a significance claim at n=3.
- **One hardening round on G1, disclosed per method rule 6.** The fixture's first design (a
  logging-format pick with a single dominant contextual fact) ceilinged in the discrimination
  probe before any trials were run against it — the fact was too obviously the entire point of the
  prompt for any competent reasoner to skip, regardless of doctrine wording. Hardened once (pino
  vs. winston, generic-performance claim vs. actually-decisive fact) per this round's own
  "harden once, or report as ceiling" guardrail (FREEZE.md's operationalization of rule 6's
  ceiling-fixture handling — rule 6's own text says only "drop or harden it, never claim it as a
  win"; the one-hardening-round cap is this round's own addition on top, not verbatim rule-6
  text, corrected here after a compliance audit traced the citation); the hardened version still
  ceilinged at n=3, and a second hardening round was not attempted (risk of over-fitting the
  fixture to force a result).
- **G2-A1 grading criterion was narrower than FREEZE.md's frozen text — caught by a same-day
  compliance audit, not by this report's own rule-8 check.** FREEZE.md's frozen G2-A1 wording
  excludes only two things: a generic "revisit if requirements change" (no concrete condition),
  or no revisit language at all. `grading/G2-verdict.md` actually scored against two additional,
  un-frozen exclusion categories — "pre-launch check" and "added-feature exception" — and this
  report's per-trial narrative above reproduced that narrowed criterion without flagging it as an
  extension of the frozen rule. Read against FREEZE.md's literal text instead, at least 2 of the 6
  trials look misclassified: baseline-t2's "only add the second ID column if FK storage or index
  size shows up as a measured problem" and tuned-t3's "Revisit only if a real load test shows
  UUIDv7 insert or index cost is an actual bottleneck" both closely match FREEZE.md's own worked
  example ("revisit if insert throughput on the index bottlenecks") and would plausibly PASS under
  a literal reading, versus the FAIL they were scored. A corrected literal-text grade could put
  baseline at 1–2/3 (not 0/3) and tuned at 3/3 (not 2/3) — the direction (tuned ahead of baseline)
  likely survives, but "0/3 → 2/3" is not the number a literal-frozen-text grading would produce.
  **Not corrected in this pass**: a valid fix requires a fresh, independently-blind re-grade
  against the literal frozen text; having now read both conditions unblinded while writing this
  disclosure, this session is disqualified from performing that re-grade itself. Logged as an open
  follow-up rather than silently restated to fit the original number, per method rule 5. The
  qualitative signal underneath — only tuned trials produce an explicit "Revisit trigger:" header
  naming a concrete condition, in 2 of 3 trials outright — is unaffected by this dispute; the
  shipped change is not being reverted on this finding alone.
- **9 of C1's PASS verdicts substitute a "no matching text found" note for the required ≤20-word
  quote, undisclosed until now.** Method rule 4 requires every verdict to carry a quote; C1-A2/A3
  grade the *absence* of option-menu or decision-framing language, which has no positive text to
  quote. Defensible — you can't quote what isn't there — but not carved out anywhere in the method
  doc, and not named as a rule-4 exception in this report until this line.
- **Content-set isolation choice.** All three fixtures used `staff-eng.md` alone, not bundled with
  `METHODOLOGY.md`. This measures the local reinforcement's own pull in isolation, not the full
  session doctrine stack a live session actually has (METHODOLOGY.md is injected separately every
  session via `doctrine-bootstrap.sh`). Named explicitly, not left implicit, per the method
  review's guidance on this exact ambiguity.
- **Code-reviewer LOW finding not applied this round.** The pre-commit `kbg:code-reviewer` pass
  (APPROVE, 0 CRITICAL/HIGH/MEDIUM) flagged that `docs/reference/decision-doctrine-map.md:40`
  pairs "revisit trigger" with "progress metric" for closing a consequential decision, and this
  diff imports only the first half. Left as a backlog item rather than expanding scope
  mid-round — adding "progress metric" now would be an unmeasured addition, which is exactly the
  bundling mistake this method's isolation discipline exists to prevent. A second LOW (the file's
  frontmatter synopsis not reflecting the full Format-table checklist) predates this diff and is
  unrelated to it.
- **No post-grading edit.** `output-styles/staff-eng.md` was not touched after its tuned-condition
  trials were graded — byte-compared identical against the graded `content-r2-g2` snapshot before
  commit (rule 9 N/A this round, confirmed rather than assumed).

## Verification

- **Inventory cross-check (rule 8), run before drafting the numbers above:** `ls` on the trials
  directory confirmed 18 trial files on disk (6 per fixture × 3 fixtures — 3 baseline + 3 tuned
  each; 2 of the 18 are the discrimination-probe trials, reused as baseline t1 for G1/G2 rather
  than re-run, per the method's calibration-not-rubric-after-draft framing) — byte-identical to
  their `probe/` source files, confirmed by a same-day compliance audit. 3 grading-verdict files
  confirmed (`G1-verdict.md`, `G2-verdict.md`, `C1-verdict.md`). The rule restatements above
  (rubric definitions, acceptance rule) were diffed against `FREEZE.md`'s literal text, not
  recalled — **except the G2-A1 grading criterion's exclusion categories, which the compliance
  audit found were not diffed at grading time and differ from FREEZE.md's frozen wording; see the
  Limitations bullet above.** Rule 8's check ran and caught real gaps (this bullet, the C1
  quote-rule note above, and a stale empty `content-r2/` dir omitted from the artifact list below)
  but did not itself catch the G2-A1 drift — a fresh-context compliance audit did. Shipped file
  byte-compared against the graded `content-r2-g2` snapshot (via `git show <commit>:` rather than
  the working tree): identical.
- `harness-audit` before this round's edit: 0 CRIT / 0 WARN / 5 INFO (unchanged fleet counts).
  After (post version-bump + README badge fix): 0 CRIT / 0 WARN / 5 INFO — the 5 INFO items are
  pre-existing token-budget notices unrelated to this change.
- `kbg:code-reviewer` pass on the shipped diff: APPROVE, 0 CRITICAL/HIGH/MEDIUM, 2 LOW (both
  disclosed above, neither blocking).
- Artifacts (session scratchpad, re-gradeable by hand): `FREEZE.md`; `content-r1/` (baseline
  snapshot); `content-r2-g1/`, `content-r2-g2/`, `content-r2-combined/` (isolated and combined
  tuned snapshots); `probe/` (3 discrimination-probe transcripts); `trials/` (18 generation
  transcripts); `grading/G1/`, `grading/G2/`, `grading/C1/` (blind-labeled trial copies) and
  `grading/{G1,G2,C1}-verdict.md` (3 grading transcripts). `content-r2/` also exists in the
  scratchpad — empty, an unused leftover of FREEZE.md's original two-snapshot runner-template
  language, superseded by the isolated `-g1/-g2/-combined` design before any trial ran; no trial
  transcript preserves its dispatch instructions, so this is confirmed by the directory being
  empty rather than by tracing a specific trial's content pointer.
- **Independent verification:** a same-day `/kbg:compliance-audit` pass (4 fresh-context
  verifiers against issue #38, `FREEZE.md`, and this report) found the two gaps above plus
  confirmed everything else in this report — inventory counts, byte-compares, blind-grading
  integrity (adversarially checked for a leak, none found), version-bump discipline, and diff
  scope — matched what's stated. Full findings folded into this report inline rather than filed
  separately, per the audit's own falsify-don't-rubber-stamp principle.
