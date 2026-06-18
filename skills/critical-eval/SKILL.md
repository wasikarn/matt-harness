---
name: critical-eval
description: "Stress-test reasoning in arguments, PRs, ADRs, RFCs, incidents, decisions. Use when asked to critique, evaluate reasoning, check assumptions, stress-test arguments, review logic, verify it holds up, or when something feels off. Flag overconfident plans (definitely safe, zero downtime). Don't use for: adversarial review of error-handling/fallback code paths (defer to silent-failure-hunter), system dynamics/architecture trade-offs (kbg:backend-dev/code-architect), code review (kbg:review-pr), security audit (kbg:security-auditor), or research (kbg:research-brief)."
---

# Critical Eval

Read-only reasoning auditor. Evaluates the quality of arguments, evidence, and conclusions without exploring new territory or writing code.

## Procedure

0. **Claim inventory — scan before slotting.**
   - List every explicit claim, assertion, or causal link in the input text.
   - Do NOT skip a claim just because it does not fit the 6-step categories below.
   - If a claim is not addressed by steps 1–5, surface it as an additional gap in the Verdict.

1. **Frame the target.**
   - What is the specific claim, decision, or recommendation being evaluated?
   - Who is the audience and what is at stake?
   - Is this forward-looking (prediction) or backward-looking (post-hoc explanation)?

2. **Hidden assumptions — what is taken for granted?**
   - List 2–4 unstated premises that must be true for the conclusion to hold.
   - For each: is it proven, plausible, or speculative?
   - Flag any circular reasoning (conclusion smuggled into premises).

3. **Evidence → conclusion chain.**
   - Does the evidence actually support the conclusion, or is it adjacent/weakly correlated?
   - Any cherry-picking (selective evidence that favors one side)?
   - Quantified claims: are the numbers correct and the baseline appropriate?

4. **Unconsidered alternatives.**
   - What are 1–2 reasonable alternatives that were dismissed or never mentioned?
   - Why was each rejected? Is the rejection based on evidence or preference?

5. **Confidence calibration.**
   - Does the language match the evidence strength? (e.g., "definitely" when evidence is suggestive)
   - What would it take to reduce confidence by 50%? Is that scenario plausible?

6. **Verdict.**
   - Strong / Cautious / Weak — based on assumption solidity + evidence quality + alternative coverage.
   - **Weak:** Top 2–3 specific gaps that would most improve the argument if addressed.
   - **Strong / Cautious:** 0–2 minor refinements. A well-reasoned argument does not need 3 "gaps"; forcing them produces false positives. If the reasoning is solid, say so and move on.

## Output format

```
Target: <claim/decision being evaluated>
Assumptions:
  1. <premise> — <proven | plausible | speculative>
Evidence chain: <supports | weakly supports | does not support>
  Gap: <specific weak link>
Alternatives missed:
  1. <alternative> — <why dismissed>
Confidence: <over | calibrated | under>
  Confidence killer: <what would cut it in half>
Verdict: <Strong | Cautious | Weak>
Fix: <if Weak: top 2–3 gaps | if Strong/Cautious: 0–2 minor refinements>
```

## METHODOLOGY alignment

- **Rule 1 (Think before coding):** Evaluating reasoning before implementation prevents building on shaky premises.
- **Rule 7 (Surface conflicts, don't average):** If evidence points two ways, say so — don't smooth over contradiction.
- **Rule 5 (Use model only for judgment):** Evidence quality is a deterministic question; confidence labels must map to actual evidence strength, not rhetorical force.

**Named models** (cc-thinking-skills): *red-team* (attack the argument), *steel-manning* (cover the strongest opposing case), *debiasing* (confidence calibration). Catalog + honesty caveat: `docs/reference/reasoning-models.md` (absolute path injected each session).
