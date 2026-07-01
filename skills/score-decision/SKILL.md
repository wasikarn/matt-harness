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

Propose 4–6 judging criteria, each **measurable** (you can cite the evidence that moves the score), and assign each a weight (integers summing to 100). If the user named criteria, honor them. Default rubric for "should we act on this proposal?" — adapt to the decision at hand:

| Criterion | Wt | Measures |
|---|---|---|
| Evidence | 25 | direct verification vs inferred |
| Doctrine | 25 | alignment with the governing principles (Matt / verifier-separation / the project's reduce mandate) |
| Net load | 20 | complexity / token / context / maintenance reduced (or added) |
| Risk-inverted | 15 | low blast radius = high score |
| Proportionality | 10 | smallest change for the gain (not a ceremony trap) |
| No-conflict | 5 | does not re-litigate a settled decision |

### 3. Score each criterion

Score each 0–100 with a one-line reason anchored to evidence. **If the data is insufficient to score a criterion, do not guess** — mark that criterion `ข้อมูลไม่เพียงพอ` and block the verdict on the operator (a score with a guessed criterion is not a verdict). A single point value implies more precision than most evidence supports (overconfidence/false-precision — see `docs/reference/judgment-ladder.md`'s "Estimate risk" rung); where the evidence is genuinely borderline, note a range or a confidence qualifier alongside the score rather than forcing one point.

### 4. Verdict

Weighted sum = `Σ(weight × score) / 100`. Apply **both** gates:
- **Pass threshold**: weighted sum ≥ the threshold (default 70).
- **Fatal-weakness floor**: no criterion below the floor (default 40).

A decision **passes** only if both hold. A criterion below the floor fails the decision regardless of the weighted sum.

### 5. Trace + confidence

- **Confidence** = derived from the two highest-weight criteria both being evidence-backed (high / medium / low).
- **Trace**: name which single criterion, if it moved ~15 points, would flip the verdict — that is the leverage point to re-verify.

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

**Weighted: NN / 100** — Pass threshold 70 · Fatal-weakness floor 40
**Verdict**: PASS | FAIL (below threshold | below floor on <criterion>)
**Confidence**: high | medium | low
**Leverage**: <which criterion would flip it, and what evidence would move it>
**Blocked**: ข้อมูลไม่เพียงพอ on <criterion> — <what's needed to score it>
```

## Ranking (≥2 options)

Before scoring, name whether the option set was **generated exhaustively** or **handed to you** (selection bias — a confident rank over an incomplete set can't surface an absent, better option). If handed to you and the stakes are real, ask whether a completeness/reframe pass ran first; if not, say so in the output rather than silently ranking as if the set were complete.

When the decision is to choose among ≥2 options (rank / recommend), score **each** option against the *same* rubric (Steps 2–4) — identical criteria + weights so the comparison is apples-to-apples — then rank by weighted sum. The fatal-weakness floor applies **per option**: any option with a criterion below the floor is **disqualified** regardless of its weighted sum, so a high-scoring-but-fragile option cannot win on averages alone. Render a compact rank table, then the **recommended** option's full criterion breakdown so the pick is auditable.

```markdown
## Decision Score: <decision> — rank <N> options

| Option | Weighted | Floor | Verdict |
|---|---|---|---|
| A | NN | ✓ | PASS |
| B | NN | ✗ (Risk 25) | DISQ — below floor |

**Recommend**: Option A — highest weighted among floor-passing.
**Leverage**: <which criterion would flip A vs the runner-up, and what evidence would move it>

— then render Option A's full criterion table (the single-decision format above).
```

## Completion criterion

A Decision Score table with every criterion scored (or explicitly blocked), a weighted total, a pass/fail verdict against the threshold AND the fatal-weakness floor, a confidence level, and a named leverage point — or a one-line "no real decision to score" exit. **For ranking**: a ranked table with the per-option floor verdict, a named recommendation among floor-passing options, and the recommended option's full criterion breakdown.

## Failure modes

- **Scoring without evidence.** A criterion score must cite why; "looks right" is not a reason.
- **Guessing past missing data.** If you cannot honestly score a criterion, block — do not fill the gap with a vibe.
- **Weighted sum without the floor.** A 75 weighted score with one criterion at 20 is not a pass — the floor is a gate, not a suggestion.
- **Scoring a non-decision.** Applying the rubric to a trivial/already-made choice manufactures ceremony (the #31.1 trap). Exit early.
- **Ranking by weighted sum alone.** A top-ranked option that fails the per-option floor is disqualified — do not recommend it. The floor is a gate in ranking too, not a tiebreaker.

## Don't duplicate canon

- **METHODOLOGY Rule 14** owns the principle (criteria + weights + score + trace). This skill is the structured application tool.
- The model applies Decision Scoring **inline** by default per Rule 14; this skill is the explicit, on-demand artifact the operator requests for a formal verdict.