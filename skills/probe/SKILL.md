---
name: probe
description: "Use when applying a systems-thinking lens to a design or architecture decision before committing. Read-only analysis using Why? and What if? to probe assumptions, constraints, and second-order effects. Also fires on Thai requests like 'probe', 'ถาม why', 'what if', 'วิเคราะห์ตัดสินใจ'. Don't use for: implementation work (kbg:backend-dev), code review (kbg:review-pr), security audits (kbg:security-auditor), or pure research (kbg:research-brief)."
---

# Probe

Apply a systems-thinking lens to a design or architecture decision before committing. Inspired by Adam Bender's *Software Ecology* — probe with **Why?** and **What if?** rather than optimizing the first plausible answer.

This is a read-only analysis skill. It does not write code, edit files, or dispatch sub-agents. It produces a structured assessment for the user to act on.

## Procedure

1. **Frame the decision boundary.**
   - What is inside the scope of this decision? What is outside?
   - Time horizon: reversible in hours, days, or never?
   - Stakeholders: who else in the sociotechnical ecosystem is touched?

2. **First-order Why? — probe one level deeper.**
   - The user's stated reason is often a symptom. Ask: what is the root cause or constraint that makes this feel necessary?
   - If the answer is "performance," ask: which metric, under what load, compared to what baseline?
   - If the answer is "cleaner," ask: who reads this, how often, and what confusion does the current shape create?

3. **What-if scenarios — three branches.**
   - **(a) Scale 10x:** If the codebase, team, or traffic grew 10x tomorrow, does this decision hold or become a bottleneck?
   - **(b) Catastrophic failure:** If this choice is wrong, what breaks first? How do we detect it? What is the rollback path?
   - **(c) Status quo:** What happens if we do nothing for 3 months? Is the problem getting worse linearly or exponentially?

4. **Shared-fate mapping + loop closure.**
   - List the components, teams, or conventions that are tightly coupled to this decision.
   - For each: does this choice strengthen or weaken the link? Does it create a new implicit contract that others will unknowingly depend on?
   - **Chain or closed loop?** If an effect feeds back to change its own cause (more load → more retries → more load), it is a feedback loop — name it and mark it reinforcing (amplifies) or balancing (goal-seeking). A one-directional "A → B → C" map is linear attribution, not systems thinking.

5. **Surface contradictions — do not average (Rule 7).**
   - Identify two assumptions that cannot both be true. Example: "we want zero config" and "we want full customization."
   - Pick one as the dominant constraint. State what is given up, not what is "balanced."

6. **Recommendation.**
   - One path, with reason. Not "Option A or B."
   - Include: "This is the right call if X holds. If X turns out false, revisit at Y trigger."

7. **Check yourself — anti-self-deception.**
   - Did you draw the boundary or pick the variables to favor the answer you already wanted? Confirmation bias hides in the *map*, before any evaluation runs.
   - Are you applying scrutiny only to the option you dislike? (Motivated skepticism — more skill produces better rationalizations, not better judgment.)
   - Did you look for evidence that would *refute* the Rec, or only what confirms it? Asking "am I biased?" does not work — externalize: write the strongest counter-case, or have someone / an agent attack it. For an irreversible Rec, that externalization is `doubt-driven-development`: hand it the Rec as ARTIFACT + CONTRACT (not your reasoning) and let a fresh-context reviewer try to disprove it before you commit. probe frames *what* the decision is; doubt-driven validates *whether the Rec holds*.

## Output format

```
Boundary: <scope in / scope out / time horizon>
Root Why: <one level deeper than the user's framing>
What-if:
  10x: <holds | cracks at Z>
  Fail: <first breakage point + detection + rollback>
  Nothing: <decay curve>
Shared fate: <affected components and coupling direction>
Contradiction: <two incompatible assumptions + which one wins>
Bias check: <where the framing could be self-serving + the counter-case>
Disconfirming evidence: <what would refute the Rec, and whether you actually looked>
Rec: <one path + revisit trigger>
```

## Red flags — you only *think* you probed

- A causal map with no closed loop — one-way "A → B → C" is event-level attribution, not structure.
- The Rec matches your opening hunch and nothing in the probe pushed back.
- Confidence rose but no disconfirming evidence was sought.
- Every component couples to every other → can't decide (analysis paralysis).
- The boundary was drawn so the inconvenient variable sits just outside it.

## METHODOLOGY alignment

- **Rule 1 (Think before coding):** probe before implementation, not after.
- **Rule 7 (Surface conflicts, don't average):** contradiction step is mandatory, not optional.
- **Rule 4 (Goal-driven):** every probe ends with a revisit trigger, not an eternal decree.
- **Rule 2 (Simplicity first):** if the probe reveals the decision is premature (unknowns > knowns), the recommendation is "defer — gather X first."
- **Rule 7 (Surface conflicts, don't average):** step 7 turns this inward — surface the conflict between what the evidence shows and what you wanted it to show; the lens can confirm a prior as easily as it can clarify, so disconfirmation is forced, not optional.

**Named models** (cc-thinking-skills): probe is where kbg's mental-model vocabulary concentrates — *systems-thinking* and *feedback-loops* (reinforcing/balancing) by name, plus *first-principles*, *second-order*, *pre-mortem*, *five-whys*, *thought-experiment*, *reversibility*, and *debiasing*. Catalog + honesty caveat: read via Bash with `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"`. Do not try to `Read` a literal `${KBG_PLUGIN_ROOT}` path.
