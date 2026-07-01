# Judgment Ladder

A **compressed Decision Quality process** for consequential choices: climb five rungs
from recognition to commitment, then act. It is a reasoning scaffold, not a guarantee.

Use it when the choice is analyzable, has real trade-offs, and the cost of a bad
decision exceeds the cost of a short structured pause. Do not use it in chaos or
when the situation demands fast pattern-matching (OODA / recognition-primed
decisions).

## The five rungs

```
Recognize → Frame → Test assumptions → Estimate risk → Decide, commit & follow through
```

The ladder is sequential but not one-way. A bad frame forces you back to re-recognize
the decision; an untested assumption forces you back to reframe; weak commitment
forces you back to values.

> **Thai training note.** This wording matches the Slingshot Group “Judgment
Ladder : บันได 5 ขั้น ในการตัดสินใจอย่างมีประสิทธิผล” material. Rung 1 is
framed as *recognizing that you are deciding, not just following duty* (รู้ตัวว่า
กำลังต้อง “ตัดสินใจ” ไม่ใช่แค่ “ทำตามหน้าที่”). Rung 5 explicitly adds
follow-through — measuring and tracking progress — because a decision without a
feedback loop decays.

## 1. Recognize the decision

Name the actual choice, its owner, its timing, and its trigger — not just the symptom
or the favorite solution.

| Checkpoint | Failure mode |
|---|---|
| Decision stated in one sentence | Solving the wrong problem because the choice was never named |
| Owner named | Diffused accountability, no one decides |
| Trigger and timing explicit | Acting on panic or delaying until options collapse |
| Decision separated from symptom/solution | Treating "fix the bug" as the decision when the real decision is strategy or root cause |

**Quick question:** "What would happen if we did nothing for 30 days?"

## 2. Frame the problem

Define scope, perspective, time horizon, objectives, constraints, and stakeholders.

| Checkpoint | Failure mode |
|---|---|
| Objectives are explicit and measurable | Optimizing for the wrong thing |
| Constraints separated from preferences | Confusing hard limits with nice-to-haves |
| Stakeholder perspectives listed | Single-stakeholder frame misses operators, users, finance, regulators |
| Scope in/out is explicit | Frame creep during execution |
| Frame is challengeable | Narrow framing or solution-bound frame |

**Reframe test:** "If our favorite option did not exist, how would we solve this?"

## 3. Gather and test assumptions

Make load-bearing beliefs explicit and seek evidence that could refute them.

| Checkpoint | Failure mode |
|---|---|
| Load-bearing assumptions listed | Hidden assumptions surface as surprises later |
| Each assumption has a disproof test | Confirmation bias |
| Facts / beliefs / guesses are separated | Assumption laundering |
| Evidence is updated when contradicted | Anchoring on the first story |

**Techniques:** devil’s advocate, assumption bet, pre-mortem light, external view / base rate.

**Quick question:** "Who disagrees with us, and what do they know that we don't?"

## 4. Estimate risk and uncertainties

Express uncertainty explicitly and value consequences, not just list them.

| Checkpoint | Failure mode |
|---|---|
| Outcomes as ranges or probabilities | Overconfidence / false precision |
| Key outcome drivers identified | Planning fallacy from best-case estimates |
| Compound / bad-world scenarios considered | Ignoring covariance and tail risks |
| Cost of delay estimated | Gathering too much or too little information |

**Quick question:** "What is the 90% confidence interval, and would we bet money on it?"

## 5. Decide, commit, and follow through

Choose, document trade-offs, align stakeholders, set a revisit trigger, and build the
feedback loop that makes the decision accountable.

| Checkpoint | Failure mode |
|---|---|
| Chosen option and rejected options documented | Decision paralysis or post-hoc rationalization |
| Trade-offs acknowledged | Sunk-cost commitment |
| Stakeholders with veto power buy in | Soft commitment — agreement in the room, no action |
| Revisit trigger defined | No feedback loop, never learning if the decision was right |
| Progress metric and check-in defined | Decision decays because no one tracks it |
| Sunk-cost guard applied | Continuing because of past investment, not future value |

**Quick questions:**
- "What signal would tell us this was the wrong choice, and when would we see it?"
- "How will we measure progress and track this decision after it is made?"
- "If we had not already started, would we start today?" (Sunk Cost guard)
- "Is the way the problem is stated driving the answer?" (Framing guard)
- "What was the first number or story we anchored on?" (Anchoring guard)
- "What evidence would prove our preferred option wrong?" (Confirmation guard)

## Decision record template

Use this to capture the output of a ladder session:

```markdown
# Decision: <title>

- Date: YYYY-MM-DD
- Owner: @name
- Consulted: @name

## Decision statement
<one sentence>

## Frame
- Objective: ...
- Constraints: ...
- Scope in: ...
- Scope out: ...
- Stakeholders: ...

## Assumptions tested
| Assumption | Confidence | Evidence | What would prove it wrong |

## Scenarios
| Scenario | Probability | Impact | Mitigation |

## Decision
Selected option: ...
Rejected options:
- ... (reason)
Trade-offs accepted: ...

## Commitment & follow-through
- Action owner: ...
- Due date: ...
- First reversible step: ...
- Progress metric: ...
- Next check-in date: ...
- Revisit trigger: ...
- Sunk-cost / anchoring / framing / confirmation guards: ...
```

## Proportionality rule

Match effort to stakes and reversibility.

| Climb high (all 5 rungs) | Climb low (1–2 rungs) |
|---|---|
| Hard to reverse | Reversible quickly |
| High stakes | Low stakes |
| Time available | Time-pressed |
| High uncertainty | Low uncertainty |
| No precedent | Done it many times |

Treat the decision as a one-way door by default. If it is clearly a two-way door,
act fast and loop.

## Domain fit

The ladder is not universal. Match the process to the domain:

| Domain | Use the ladder? | Better tool |
|---|---|---|
| Clear / repetitive | No | Best practice / SOP |
| Complicated but analyzable | Yes | This ladder / decision analysis |
| Complex / emergent | Partially | Probe first, then sense, then respond |
| Chaotic / crisis | No | Stabilize first; OODA / recognition-primed decisions |

## Using the ladder in software engineering

Use the ladder for **implementation and design choices inside an established architecture**, not for architecture-level bets. The latter belong in `kbg:decide (strategize mode)` first.

| Coding decision | Rung to stress | Typical bias trap |
|---|---|---|
| Library / framework choice | Frame + Test assumptions | Anchoring on the first HN post; confirmation from one benchmark |
| API contract / data model | Frame | Narrow framing around current schema; missing consumer perspective |
| Deploy / rollout strategy | Estimate risk + Commit | False precision on downtime; soft commitment without rollback owner |
| Refactor scope and sequence | Recognize + Commit | Sunk-cost attachment to old code; no revisit trigger |
| Hotfix vs. proper fix | Recognize | Treating an incident as a normal decision; use `kbg:incident` instead |

**Quick coding flow:**
1. Is the decision hard to reverse or long-lived? → `kbg:decide (strategize mode)`.
2. Is it reversible within days and analyzable? → climb the ladder with `kbg:decide`.
3. Is the answer already committed and only needs a record? → `kbg:domain-modeling` (owns the ADR rule).

## Connection to Decision Quality

The five rungs map to the six elements of the Decision Quality chain
(Spetzler, Winter, Meyer, 2016):

| Rung | DQ element |
|---|---|
| Recognize | Trigger for the whole chain |
| Frame | Appropriate Frame + Clear Values & Trade-offs |
| Test assumptions | Reliable Information |
| Estimate risk | Sound Reasoning + Creative Alternatives |
| Decide, commit & follow through | Commitment to Action |

Use the ladder to walk a team through the process, then cross-check against the
DQ chain to see if any element is weak.

## The Slingshot four-bias guard

The Slingshot Group “Decision Bias” slide highlights four biases that map
cleanly onto the ladder. Use them as a cross-check at the rung where each one
is most dangerous.

| Bias | Threatened rung | Slingshot-style guard | English counter |
|---|---|---|---|
| **Framing Bias** (อคติจากการถูกตีกรอบ) | Frame | เรามองปัญหานี้แคบไปไหม? มีมุมมองอื่นที่ควรมองอีกหรือเปล่า? | List stakeholder perspectives; separate constraints from preferences |
| **Anchoring Bias** (อคติจากการยึดติด) | Frame / Estimate risk | ตัวเลข/ข้อมูล/ทางเลือกแรกที่เรายึดไว้ถูกทดสอบแล้วหรือยัง? | Ask for 90% CI; remove the favorite option and re-solve |
| **Confirmation Bias** (อคติจากการมีธงในใจ) | Test assumptions | ข้อมูลที่มีน่าเชื่อถือแค่ไหน? | Assign a devil’s advocate; seek disconfirming evidence |
| **Sunk Cost Bias** (อคติจากสิ่งที่ลงทุนไปแล้ว) | Decide, commit & follow through | ถ้าเริ่มใหม่วันนี้ ยังทำต่อไหม? | Set kill criteria; ask if you would start today from blank slate |

## Common biases by rung

| Rung | Bias to watch | Counter |
|---|---|---|
| Recognize | Problem substitution, urgency bias | Write the decision statement before discussing solutions |
| Frame | Narrow framing, anchoring, solution bias, framing bias, **selection bias** (the option/evidence set considered may not be complete — was it generated exhaustively, or just handed to you?) | Force a third option before comparing A vs B; ask whether the option set was generated or given |
| Test assumptions | Confirmation bias, availability bias, overconfidence | Assign a devil’s advocate; ask what would prove you wrong |
| Estimate risk | Planning fallacy, base-rate neglect, false precision | Use 90% confidence intervals and reference-class forecasting |
| Decide, commit & follow through | Sunk-cost fallacy, groupthink, soft commitment, **automation bias** (trusting a self-generated score/tool output without independent re-derivation), **survivorship bias** (judging "improved" only by what the existing verifier happens to measure) | Set kill criteria and action owners before leaving the room; for a score you didn't independently re-derive, ask who verified it and how |

## kbg surfaces

- `kbg:decide` — interactive walk through the ladder
- `kbg:domain-modeling` — record the decision as an ADR after the ladder
- `kbg:decide` probe mode — systems-thinking analysis before the ladder
- `kbg:decide` clarify mode — when the decision itself is still ambiguous
- `kbg:decide` critique mode — stress-test reasoning in a decision or ADR
- `kbg:decide (strategize mode)` — upstream lens for irreversible / long-horizon commitments

> **Vendored thinking references (not loadable `kbg:` surfaces).** Cynefin, OODA, pre-mortem, debiasing, and bounded-rationality prompts live under `docs/reference/thinking-skills/skills/`. Use them as reasoning frames, not as invokable skills.

## References

- Spetzler, C., Winter, H., & Meyer, J. (2016). *Decision Quality: Value Creation
  from Better Business Decisions*. Wiley.
- Hammond, J. S., Keeney, R. L., & Raiffa, H. (1999). *Smart Choices: A Practical
  Guide to Making Better Decisions*. Harvard Business School Press.
- Howard, R. A., & Abbas, A. E. (2015). *Foundations of Decision Analysis*.
- Klein, G. (1998). *Sources of Power: How People Make Decisions*. MIT Press.
- Heath, C., & Heath, D. (2013). *Decisive: How to Make Better Choices in Life
  and Work*. Crown Business.

The Judgment Ladder itself is best understood as a practitioner-ready adaptation
of the Decision Quality / decision-analysis tradition, often packaged in workshop
or facilitation form, rather than a single canonical academic paper.
