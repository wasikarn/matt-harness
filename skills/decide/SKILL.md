---
name: decide
description: "Use when you need structured decision support across four modes: decide (Judgment Ladder for consequential, analyzable choices), probe (systems-thinking Why? / What if?), strategize (irreversible / long-horizon commitment), or debate (parallel technical debate between options). Thai: 'ตัดสินใจ', 'ช่วยตัดสินใจ', 'judgment ladder', 'decision quality', 'วิเคราะห์ตัดสินใจ', 'strategy', 'กลยุทธ์', 'probe', 'what if', 'debate', 'ถกเถียง', 'which option', 'should we use X or Y'. Don't use for chaotic/time-pressed situations (use kbg:incident), choices already dictated by policy, or after the decision is committed and only needs recording (use kbg:adr)."
---

# Decide

Single decision-support surface. Apply the right mode based on the user's request:

- **decide mode (default)** — Judgment Ladder for consequential, analyzable choices.
- **probe mode** — systems-thinking lens (Why? / What if?) before committing. Formerly `kbg:decide (probe mode)`.
- **strategize mode** — irreversible or long-horizon strategic commitment under ambiguity. Formerly `kbg:decide (strategize mode)`.
- **debate mode** — parallel technical debate between options using Advocate/Skeptic/Synthesizer/Cost-Analyst agents. Formerly `/debug-debate`.

The ladder is a reasoning scaffold, not a proof. It slows you down just enough to surface the real decision, the hidden assumptions, and the risks that usually get skipped.

The five rungs are sequential but iterative: a bad frame sends you back to re-recognize the decision; a failed assumption test sends you back to reframe; weak commitment sends you back to values.

> **Thai framing note.** This ladder matches the Slingshot Group “Judgment Ladder : บันได 5 ขั้น ในการตัดสินใจอย่างมีประสิทธิผล” material. Rung 1 emphasizes recognizing that you are *deciding*, not just *following duty* (รู้ตัวว่ากำลังต้อง “ตัดสินใจ” ไม่ใช่แค่ “ทำตามหน้าที่”). Rung 5 explicitly adds follow-through — measuring, tracking progress, and revisiting — because a decision without a feedback loop decays.

## When to use

- A choice is consequential, analyzable, and has real trade-offs.
- You have enough time to climb the ladder once before committing.
- The user asks for help deciding, weighing options, reality-testing a plan, or running a decision through a structured process.

## When NOT to use

- **Chaotic / time-pressed situations** — stabilize first, then loop. Use `kbg:incident`. If no kbg surface fits, fall back to an OODA-loop prompt from the vendored thinking-skills reference (`docs/reference/thinking-skills/skills/thinking-ooda/`), not to a loadable `kbg:` surface.
- **Domain is complex and unknowable** — switch to **probe mode** (read `references/probe.md`) before estimating; Cynefin is available as a vendored thinking reference (`docs/reference/thinking-skills/skills/thinking-cynefin/`).
- **Answer is already dictated** — if policy, architecture, or a hard constraint makes the choice, say so instead of running the ladder.
- **Decision is already made and only needs recording** — use `kbg:adr` for the decision record.
- **Trivial / low-stakes / reversible choices** — a 2-minute gut check is enough.
- **Irreversible / long-horizon strategic commitment** — switch to **strategize mode** (read `references/strategize.md`).

## Procedure

### 1. Recognize the decision

Name the actual choice. Separate it from the symptom, the complaint, the favorite solution, and the implementation detail.

- What is the single-sentence decision we are facing?
- Who owns this decision?
- Why now? What is the trigger?
- What happens if we do nothing?

**Stop if:** you cannot state the decision in one sentence or name an owner.

### 2. Frame the problem

Define scope, perspective, time horizon, objectives, constraints, and stakeholders.

- What are we optimizing for?
- What is a hard constraint vs. a preference?
- What is in scope? What is explicitly out of scope?
- How would our main stakeholder describe this decision?
- If we reframed the decision as X, would the answer change?

**Reframe test:** remove the favorite option from the table. If CockroachDB/TiDB/etc. did not exist, how would we solve the problem?

**Stop if:** objectives are vague, scope is unbounded, or the frame is solution-bound.

### 3. Gather and test assumptions

Make load-bearing beliefs explicit and seek evidence that could refute them.

- What must be true for our preferred option to be the right one?
- For each important assumption: what would prove it wrong?
- What is fact, what is belief, what is a guess?
- Who disagrees with us, and what do they know that we do not?
- Have we looked for disconfirming evidence, not only confirming evidence?

**Techniques:** devil’s advocate, assumption bet (“would we bet $1,000 this is true?”), pre-mortem light, external view / base rate.

**Stop if:** the load-bearing assumptions are untested or confidence is high without evidence.

### 4. Estimate risk and uncertainties

Express uncertainty explicitly and value consequences, not just list them.

- What are optimistic / base / pessimistic scenarios?
- What is the 90% confidence interval for the key variables?
- What variables drive the outcome most?
- What if we are wrong by 2× or 0.5×?
- What if multiple things go wrong at once?
- What is the cost of delay vs. the cost of deciding wrong?

**Stop if:** you only have point estimates, or the risks are listed but not estimated.

### 5. Decide, commit, and follow through

Choose, document the trade-offs, align stakeholders, set a revisit trigger, and build the feedback loop that makes the decision accountable.

- Which option best satisfies the frame?
- What trade-offs are we explicitly accepting?
- Why were the rejected options rejected?
- Do the people who must execute buy in?
- What is the smallest reversible first step?
- What signal would tell us this was the wrong choice, and when would we see it?
- How will we measure progress and track the decision after it is made?

**Slingshot-style four-bias guard at this stage:**
- **Sunk Cost** — If we had not already started, would we start today? What is the kill criteria?
- **Anchoring** — What was the first number / first story / first option we anchored on? Has it been re-examined?
- **Framing** — Is the way the problem is stated driving the answer? Would a different stakeholder phrase it differently?
- **Confirmation** — What evidence would prove our preferred option wrong? Have we actually looked for it?

**Stop if:** there is no written decision, no action owner, no revisit trigger, or no follow-up metric.

## Output format

```
Decision statement: <one sentence>
Owner: <name>
Frame:
  - Objective: ...
  - Constraints: ...
  - Scope in/out: ...
  - Stakeholders: ...
Load-bearing assumptions:
  - <assumption> | confidence <high/medium/low> | evidence | what would prove it wrong
Risk estimate:
  - Scenario | probability | impact | mitigation
Decision:
  - Selected option
  - Rejected options + why
  - Trade-offs accepted
  - Revisit trigger
Commitment & follow-through:
  - Action owners + due dates
  - First reversible step
  - Progress metric
  - Next check-in date
Four-bias guard:
  - Sunk Cost check: ...
  - Anchoring check: ...
  - Framing check: ...
  - Confirmation check: ...
```

## Applying `kbg:decide` to software engineering

Most code decisions are reversible operational choices, not strategic commitments. Use **decide mode** inside a boundary that is already set — by architecture charter, by a prior strategize-mode run, or by a hard constraint.

| Coding decision | Mode | What to watch |
|---|---|---|
| Library/framework choice inside an approved stack | decide | Anchoring on the first benchmark; confirmation from one blog post |
| REST vs. gRPC, cursor vs. offset pagination | decide | Framing the problem around the technology, not the user flow |
| Deploy strategy (canary, blue-green, feature flags) | decide | False precision on risk; no revisit trigger |
| Refactor sequence | decide | Sunk-cost attachment to old code; soft commitment |
| Monolith → services, database commitment, team topology | strategize | Premature lock-in; missing real options |
| "Why is this necessary?" / "What if we scale 10x?" | probe | Map the domain before estimating |

**Combined flow:**
1. If the choice is hard to reverse, run **strategize mode** first to set the guiding policy (`references/strategize.md`).
2. If the domain is complex/unknowable, run **probe mode** first (`references/probe.md`).
3. Inside the policy, use **decide mode** for reversible implementation choices.
4. Record the committed decision in `kbg:adr`.

## Proportionality rule

Do not climb every rung for every choice.

| Climb high (all 5 rungs) | Climb low (1–2 rungs) |
|---|---|
| Hard to reverse | Reversible in hours/days |
| High stakes | Low stakes |
| Time available | Time-pressed |
| High uncertainty | Low uncertainty |
| No precedent | Done it many times |

**Rule of thumb:** treat the decision as a one-way door by default. If it is clearly a two-way door, act fast and loop.

## Failure modes

- **Skipping rungs under pressure** — deciding before recognizing the real question.
- **Narrow framing** — comparing A vs B when the real choice is broader.
- **Solution-bound frame** — letting a favorite technology define the problem.
- **Confirmation bias** — testing only the assumptions that support the preferred option.
- **False precision** — giving point estimates when ranges are more honest.
- **Soft commitment** — agreement in the room, no action afterward.
- **No revisit trigger** — never learning whether the decision was good.
- **No follow-through** — deciding and walking away without metrics or progress tracking.
- **Ladder abuse** — applying all 5 rungs to a two-way-door choice, causing unnecessary delay.

## The Slingshot four-bias guard at every rung

Use these four biases as a cross-check while climbing. They are not the only
biases that matter, but they are the ones most likely to flip a rung.

| Rung | Bias | Quick guard |
|---|---|---|
| **Recognize** | **Urgency / duty bias** | รู้ตัวว่ากำลังต้อง “ตัดสินใจ” ไม่ใช่แค่ “ทำตามหน้าที่” |
| **Frame** | **Framing Bias** | เรามองปัญหานี้แคบไปไหม? มีมุมมองอื่นที่ควรมองอีกหรือเปล่า? |
| **Frame / Estimate risk** | **Anchoring Bias** | ตัวเลข/ข้อมูล/ทางเลือกแรกที่เรายึดไว้ ถูกทดสอบแล้วหรือยัง? |
| **Test assumptions** | **Confirmation Bias** | ข้อมูลที่มีน่าเชื่อถือแค่ไหน? หาหลักฐานที่ refute ตัวเองบ้างหรือยัง? |
| **Decide, commit, follow through** | **Sunk Cost Bias** | ถ้าเริ่มใหม่วันนี้ ยังทำต่อไหม? kill criteria คืออะไร? |

## Mode selection

Pick the mode from the user's wording before climbing:

| User signal | Mode | Reference |
|---|---|---|
| "ตัดสินใจ", "judgment ladder", "which option", "A vs B", trade-offs inside a known boundary | **decide** | this file |
| "probe", "what if", "systems thinking", "second-order effects", "why is this necessary", "scale 10x" | **probe** | `references/probe.md` |
| "strategy", "strategic choice", "where to play", "irreversible commitment", "long-horizon bet" | **strategize** | `references/strategize.md` |
| "debate", "ถกเถียง", "should we use X or Y", "which is better", "ประชุมถก" | **debate** | `references/debate.md` |

## Related

- `kbg:adr` — record the decision after the ladder
- `kbg:clarify-first` — when the decision itself is still ambiguous
- `kbg:critical-eval` — stress-test the reasoning in a decision or ADR
- `references/debate.md` — technical debate for disagreements, now a `debate` mode of this skill

> **Vendored thinking references (not loadable `kbg:` surfaces).** Cynefin, OODA, pre-mortem, debiasing, and bounded-rationality prompts live under `docs/reference/thinking-skills/skills/`. Use them as reasoning frames, not as invokable skills.

## METHODOLOGY alignment

- **Rule 1 (Think before coding):** use the ladder before implementation choices.
- **Rule 7 (Surface conflicts, don't average):** the contradiction step in framing and the disconfirmation step in testing assumptions are mandatory.
- **Rule 4 (Goal-driven):** every ladder ends with a revisit trigger and a follow-through metric, not an eternal decree.
- **Rule 2 (Simplicity first):** if the ladder reveals the decision is premature, the recommendation is "defer — gather X first."
