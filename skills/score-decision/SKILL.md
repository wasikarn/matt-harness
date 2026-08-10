---
name: score-decision
description: "Score pending decisions on weighted criteria: numeric verdict, pass/fail, confidence, trace. Use when a decision needs a verdict. Don't use for trivial or already-decided choices."
disable-model-invocation: true
disable-model-invocation-reason: on-demand formal scorer — the model applies Decision Scoring (METHODOLOGY Rule 14) inline by default; this skill is the explicit, structured artifact the operator requests when a decision needs a traceable verdict
argument-hint: "The pending decision to score"
---

# Score a Decision

Apply the Decision Scoring Framework (METHODOLOGY Rule 14) to a pending decision — approve / reject / rank / recommend / optimize / validate — and return a structured, traceable verdict. **Score, not feel.**

## Procedure

### 1. Frame the decision

State, in one line: the decision being scored, the options (if ≥2), and what a "pass" would authorize. If there is no real decision to make (the choice is trivial or already made), **say so and stop** — do not manufacture a score (no-op test). If the task is to **rank/recommend** across ≥2 options, score each against the *same* rubric (Steps 2–4) and rank by weighted sum — see **Ranking** below.

### 2. Set the criteria + weights

Propose 4–6 judging criteria, each **measurable** (you can cite the evidence that moves the score), and assign each a weight (integers summing to 100) — and **state that total in the output** ("weights sum to 100"), don't leave the reader to add the column to check the rubric is well-formed. If the user named criteria, honor them. Default rubric for "should we act on this proposal?" — adapt to the decision at hand:

| Criterion | Wt | Measures |
|---|---|---|
| Evidence | 25 | direct verification vs inferred |
| Doctrine | 25 | alignment with the governing principles (Matt / verifier-separation / the project's reduce mandate) |
| Net load | 20 | complexity / token / context / maintenance reduced (or added) |
| Risk-inverted | 15 | low blast radius = high score |
| Proportionality | 10 | smallest change for the gain (not a ceremony trap) |
| No-conflict | 5 | does not re-litigate a settled decision |

### 3. Score each criterion

Score each 0–100 with a one-line reason anchored to evidence. **If the data is insufficient to score a criterion, do not guess** — mark that criterion `ข้อมูลไม่เพียงพอ` and block the verdict on the operator (a score with a guessed criterion is not a verdict). Reserve the block for when there's no basis to place any number at all — a criterion whose only basis is secondhand, self-reported, or uncorroborated still has a real, low position on most criteria's own scale (the default rubric's Evidence criterion measures "direct verification vs inferred" — inferred is a valid low score, not grounds to block) and should be scored there instead, letting the fatal-weakness floor (Step 4) catch it. A single point value implies more precision than most evidence supports (overconfidence/false-precision — see `judgment-ladder.md`'s "Estimate risk" rung, read via Bash: `cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"`); where the evidence is genuinely borderline, note a range or a confidence qualifier alongside the score rather than forcing one point.

**No-conflict is scored by search, not recall:** query `qmd` (lex + vec) with the decision's
scenario, scoped to the project's memory + research collections (`kbg-memory` + `kbg-research`
in kbg-harness; other projects' own collections per `qmd status`), and cite the hit — or `no
precedent found for "<query>"`, naming the query string actually run — as that criterion's
evidence. An uncited "no precedent found" is unverifiable self-report and doesn't count. A settled precedent with no new evidence in the
current ask scores No-conflict below the fatal-weakness floor — the decision fails on the floor
regardless of weighted sum. If qmd is unavailable, mark the criterion `ข้อมูลไม่เพียงพอ` per the
rule above rather than scoring from memory. (Adapted from semantica-agi/semantica's
`find_precedents` lifecycle step.)

### 4. Verdict

Weighted sum = `Σ(weight × score) / 100`. Apply **both** gates:
- **Pass threshold**: weighted sum ≥ the threshold (default 70).
- **Fatal-weakness floor**: no criterion below the floor (default 40).

A decision **passes** only if both hold. A criterion below the floor fails the decision regardless of the weighted sum.

### 5. Trace + confidence

- **Confidence** = derived from the two highest-weight criteria both being evidence-backed (high / medium / low).
- **Trace**: name which single criterion, if it moved ~15 points, would flip the verdict — that is the leverage point to re-verify.

**Named models** (cc-thinking-skills): the weighted-criteria + ranking loop is *tournament* (N options scored on the same rubric, winner by weighted sum) + *steel-manning* (the strongest version of each option is what gets scored — don't straw-man); the "single criterion that flips the verdict" trace is *leverage-points* (find the small number of places a change has outsized effect). Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`.

## Output Format

```markdown
## Decision Score: <decision>

| Criterion (wt) | Score | Reason |
|---|---|---|
| Evidence (25) | NN | <one-line, cited> |
| Doctrine (25) | NN | ... |
| Net load (20) | NN | ... |
| Risk-inverted (15) | NN | ... |
| Proportionality (10) | NN | ... |
| No-conflict (5) | NN | ... |

*Weights sum to 100.*

**Weighted: NN / 100** — Pass threshold 70 · Fatal-weakness floor 40
**Verdict**: PASS | FAIL (below threshold | below floor on <criterion>)
**Confidence**: high | medium | low
**Leverage**: <which criterion would flip it, and what evidence would move it>
**Re-score when**: <the concrete event that re-opens this verdict — e.g. the leverage evidence lands, or a named constraint changes>
**Blocked**: ข้อมูลไม่เพียงพอ on <criterion> — <what's needed to score it>
```

## Ranking (≥2 options)

Before scoring, name whether the option set was **generated exhaustively** or **handed to you** (selection bias — a confident rank over an incomplete set can't surface an absent, better option). If handed to you and the stakes are real, ask whether a completeness/reframe pass ran first; if not, say so in the output rather than silently ranking as if the set were complete.

When the decision is to choose among ≥2 options (rank / recommend), score **each** option against the *same* rubric (Steps 2–4) — identical criteria + weights so the comparison is apples-to-apples — then rank by weighted sum. **Render the full per-criterion × per-option score matrix, every cell**, before the rank table: a weighted total whose per-criterion scores aren't on the page is unauditable (one total is consistent with many different splits), so "scored on the same rubric" must be quotable from the output, not implied by it. The fatal-weakness floor applies **per option**: any option with a criterion below the floor is **disqualified** regardless of its weighted sum, so a high-scoring-but-fragile option cannot win on averages alone. Render a compact rank table, then the **recommended** option's full criterion breakdown so the pick is auditable. **If the highest raw weighted sum belongs to a disqualified option** (not the one recommended), render that option's full breakdown too — a reader needs to verify the disqualification was a genuine floor call, not a scoring artifact, and that check is impossible without seeing the numbers behind it.

```markdown
## Decision Score: <decision> — rank <N> options

Criteria + weights (sum to 100) declared before any scoring, then the full matrix:

| Criterion (wt) | A | B |
|---|---|---|
| Evidence (25) | NN | NN |
| ... every criterion × every option — no cell omitted | | |

| Option | Weighted | Floor | Verdict |
|---|---|---|---|
| A | NN | ✓ | PASS |
| B | NN | ✗ (Risk 25) | DISQ — below floor |

**Recommend**: Option A — highest weighted among floor-passing.
**Leverage**: <which criterion would flip A vs the runner-up, and what evidence would move it>
**Re-score when**: <the concrete event that re-opens this ranking>

— then render Option A's full criterion table with per-cell reasons (the single-decision format above). If Option B's raw weighted sum was higher than A's despite disqualification, render B's table too.
```

## Completion criterion

A Decision Score table with every criterion scored (or explicitly blocked), a weighted total, a pass/fail verdict against the threshold AND the fatal-weakness floor, a confidence level, and a named leverage point — or a one-line "no real decision to score" exit. **For ranking**: the full per-criterion × per-option score matrix, a ranked table with the per-option floor verdict, a named recommendation among floor-passing options, and the recommended option's full criterion breakdown — plus the disqualified top scorer's breakdown too, if a different, disqualified option has the higher raw weighted sum.

## Failure modes

- **Scoring without evidence.** A criterion score must cite why; "looks right" is not a reason.
- **Guessing past missing data.** If you cannot honestly score a criterion, block — do not fill the gap with a vibe.
- **Weighted sum without the floor.** A 75 weighted score with one criterion at 20 is not a pass — the floor is a gate, not a suggestion.
- **Scoring a non-decision.** Applying the rubric to a trivial/already-made choice manufactures ceremony (the #31.1 trap). Exit early.
- **Ranking by weighted sum alone.** A top-ranked option that fails the per-option floor is disqualified — do not recommend it. The floor is a gate in ranking too, not a tiebreaker.

## Don't duplicate canon

- **METHODOLOGY Rule 14** owns the principle (criteria + weights + score + trace). This skill is the structured application tool.
- The model applies Decision Scoring **inline** by default per Rule 14; this skill is the explicit, on-demand artifact the operator requests for a formal verdict.