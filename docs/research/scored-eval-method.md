# Scored-eval method — frozen-instrument before/after evaluation

**Living method doc** (not a dated snapshot). Canonical checklist for any measured
content-tuning round in this repo. Precedent runs, kept as dated result snapshots:

- `askuserquestion-recommended-criterion-eval-2026-08-07.md` — established the core method.
- `recommendation-quality-tune-2026-08-10.md` — scaled it to 39 files / 6 fixtures; its
  post-run defects produced rules 8–9 below
  (`docs/post-mortems/eval-report-inventory-claims-2026-08-10.md`).

Future rounds follow this doc instead of re-deriving from a dated report — one canonical copy,
no copy-from-snapshot sync seam.

## The method

1. **Freeze instruments BEFORE any tuning text exists.** File list, rubric criteria, fixture
   prompts + assertions, and the acceptance rule all land in a `FREEZE.md` in the eval workspace
   first. A rubric written after seeing a draft is the maker grading its own work. Before
   freezing, check open GitHub issues labeled `eval-fold-in` for pending fold-in items on any
   file this round is touching, and add any that apply as tested fixture variables in the
   frozen file/variable list — not a Level-B-only mention — this is the only point where a
   deferred item re-enters a round (see issue #48).

2. **Behavioral headline vs static work-list, honestly separated.**
   - *Level A (behavioral)* — fixtures run against content; the only numbers reported as
     evidence of change.
   - *Level B (static checklist)* — a gap finder over the file list; reported as gaps
     found/closed, **never** as a scored delta (tuning adds the checked instructions, so a
     Level-B "improvement" is true by construction).

3. **n=3 fresh-context trials per condition, snapshot reads only.** Runners read snapshot
   copies of the content (`content-r1/`, `content-r2/`), never `Skill()`/agent-name/slash
   resolution — the plugin cache serves the installed version, not the session's edits
   (CLAUDE.md § Plugin lifecycle). Report per-trial results; no significance claims at n=3;
   a single-trial flip is labeled weak evidence even when it hits the targeted assertion.

4. **Blind paired grading.** Neutral variant names (`variant-a/b`), per-fixture A/B
   randomization recorded in FREEZE.md, graders never told which set is tuned, every verdict
   carries a ≤20-word quote. A holistic blind comparator is a secondary signal with ties
   allowed — it does not override rubric verdicts.

5. **Acceptance rule pre-declared, deviations named.** The ship/no-ship condition is written in
   FREEZE.md before any run. If the shipped call deviates from the rule's letter (e.g. accepting
   a control-assertion wobble as instrument noise), the report names it as a judged deviation
   against the frozen wording — never silently restates the rule to fit the outcome.

6. **Ceiling fixtures are non-discriminating.** A fixture at full marks on baseline can't show
   improvement; drop or harden it, and never claim it as a win.

7. **Anti-verbosity guard.** Track per-file char deltas; growth >20% is flagged (length is not
   quality; `response-conciseness-verbosity-2026-07-16.md`).

8. **Inventory cross-check before committing the report** *(added 2026-08-10, post-mortem
   follow-up 1)*. Every count, artifact path, and rule restatement in the report is verified
   against disk — count the trial files, resolve every cited path, diff every restated rule
   against FREEZE.md's text — and the report's Verification section records that the check ran.
   Root cause it prevents: drafting inventory claims from end-of-session recall (the planned
   "6×3×2 = 36" instead of the on-disk 33).

9. **Post-grading edit rule** *(added 2026-08-10, follow-up 2)*. Any edit to a measured file
   after its after-runs (e.g. a code-review fix round) requires a byte-compare of shipped
   content vs the graded snapshot, plus a disclosure bullet in Limitations scoping what the
   graded numbers do and don't cover.

10. **Grader-prompt neutrality on re-grades** *(added 2026-08-10, issue #47's contaminated
    first dispatch)*. A re-grade or grading-correction prompt hands graders the complete
    verbatim frozen rubric text with no additional grading guidance layered on top (the
    trials under neutral labels and output-format instructions are fine — extra
    pass/fail steering is not); if a reading is disputed, the prompt flags
    the ambiguity neutrally — it never resolves it directionally ("don't fail a response just
    because X" answers the disputed question before the grader can reason about it). Graders
    see no prior verdicts, no issue narrative, and not each other's output. A grading result
    that reproduces the hypothesis its prompt author already read is contaminated, not
    evidence — discard it and disclose the voided run, never average it in.

## Report skeleton (what the committed report must carry)

Frozen-list reference · per-trial table with the control row first · what-changed table with
per-file evidence · char-delta note · Level-B found/closed section with deliberate-skip reasons ·
Limitations (including any rule deviations, post-grading edits, and N/A dispositions) ·
Verification section (harness-audit before/after — or a named N/A/substitution for a
docs-only round, never a silent swap — reviewer pass, **the rule-8 inventory-check line**,
**the pre-commit checklist-verifier line**, artifact paths).

## Pre-commit verification (mandatory, decided 2026-08-10)

Before a measured-round report is committed, dispatch at least one fresh-context verifier
whose prompt **embeds the literal checklist below verbatim** — not a "compare against this
doc" brief, and not the doc path alone. The incident behind this
(`docs/post-mortems/eval-report-skeleton-gaps-2026-08-10.md`): two review layers briefed
generally caught only salient defects, while a silent absence and a silent substitution
survived both and fell only to a fresh-context verifier walking the enumerated list. The
maker never grades its own report. The user can additionally run `/kbg:compliance-audit`
for the full multi-verifier pass — that command is user-invoked only; this step never
invokes it and does not replace it.

**No automated skeleton check, deliberately** *(same decision, that post-mortem's
follow-up 3)*: both escaped defects were content-level (a rule silently unaddressed, a
check silently substituted) — a heading/structure linter would have passed both while
adding false confidence. The checklist verifier above is the containment. Revisit only if
this class recurs with that step in place.

## Literal checklist (embed verbatim in reviewer/verifier prompts)

Every item gets an explicit disposition: CONFORMS (with evidence) or N/A (with the reason
stated in the report itself). An item with no disposition is a finding, not a pass.

Rules — R1 open `eval-fold-in`-labeled issues touching this round's files checked before
freezing, applicable items folded in as tested fixture variables, then instruments (file
list, rubric criteria, fixture prompts + assertions, acceptance rule) frozen in `FREEZE.md`
before any tuning text · R2 Level A behavioral
vs Level B work-list separated, Level B never a scored delta · R3 n=3 fresh-context trials
per condition, snapshot reads only (never `Skill()`/agent-name/slash resolution — the
plugin cache serves stale installed content), no significance claims at n=3 (a
single-trial flip is weak evidence) · R4 blind paired grading: neutral names, graders
never told which set is tuned, A/B randomization recorded in `FREEZE.md`, every verdict
carries a ≤20-word quote, comparator secondary with ties allowed and never overriding a
rubric verdict · R5 acceptance rule pre-declared in `FREEZE.md`, deviations named against
its frozen wording · R6 ceiling fixtures dropped or hardened, never claimed as wins ·
R7 per-file char deltas
tracked, >20% flagged · R8 inventory cross-check against disk (counts, artifact paths,
restated rules diffed against `FREEZE.md`'s text), recorded in Verification · R9
post-grading edits byte-compared and disclosed, the disclosure scoping what the graded
numbers do and don't cover · R10 re-grade prompts carry the verbatim `FREEZE.md` rubric
with no grading guidance layered on top (no pass/fail steering), flag disputed readings
neutrally, keep graders isolated (no prior verdicts, no issue narrative, not each other's
output); contaminated runs discarded and disclosed.

Skeleton — frozen-list reference · per-trial table, control row first · what-changed table
with per-file evidence · char-delta note · Level-B found/closed with skip reasons ·
Limitations (deviations, post-grading edits, N/A dispositions) · Verification
(harness-audit before/after, or a named N/A/substitution — never silent; reviewer pass,
rule-8 line, pre-commit checklist-verifier line, artifact paths).
