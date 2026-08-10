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
   first. A rubric written after seeing a draft is the maker grading its own work.

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

## Report skeleton (what the committed report must carry)

Frozen-list reference · per-trial table with the control row first · what-changed table with
per-file evidence · char-delta note · Level-B found/closed section with deliberate-skip reasons ·
Limitations (including any rule deviations and post-grading edits) · Verification section
(harness-audit before/after, reviewer pass, **the rule-8 inventory-check line**, artifact paths).
