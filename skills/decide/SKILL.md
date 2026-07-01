---
name: decide
description: "Doctrine-backed decision support, clarify scope, stress-test reasoning, pick among defensible options (probe/decide/strategize). Use when facing a non-trivial choice. Don't use for obvious or already-decided calls."
metadata:
  origin: kbg
  references:
    - docs/reference/judgment-ladder.md
    - docs/reference/decision-doctrine-map.md
    - docs/reference/strategic-judgment.md
---

# decide

Structured decision support built on the Judgment Ladder (Decision Quality tradition).
Three modes — pick by reversibility and diagnosis clarity.

## Mode selection

Run the decision-sizing triad first (METHODOLOGY Rule 1, injected each session): one-way door? → blast radius → riskiest assumption. A one-way door defaults to `strategize`.

| Situation | Mode |
|---|---|
| Scope or assumptions still unclear | Stop — ask the structured clarifying question (analyze → recommend → ask) before deciding |
| Read-only: understand before committing | `probe` |
| Reversible choice, analyzable trade-offs | `decide` (default — Judgment Ladder) |
| Irreversible / long-horizon / contested diagnosis | `strategize` |
| Chaos or incident | Stop — use `kbg:incident` instead |
| Decision already made, needs a record | `kbg:domain-modeling` directly (owns the ADR rule) |

---

## Mode: decide (default)

Interactive walk through the 5-rung Judgment Ladder.
Match depth to stakes — reversible low-stakes choices need only 1–2 rungs.

### 1. Recognize
Name the actual choice, its owner, its timing, and its trigger.
> Quick check: "What would happen if we did nothing for 30 days?"

### 2. Frame
Objectives, constraints (hard limits vs preferences), stakeholders, scope in/out.
> Reframe test: "If our favorite option did not exist, how would we solve this?"

### 3. Test assumptions
List load-bearing beliefs. For each: what evidence would refute it?
> "Who disagrees with us, and what do they know that we don't?"

### 4. Estimate risk
Express uncertainty as ranges, not point estimates. Name compound/tail scenarios.
> "What is the 90% confidence interval, and would we bet money on it?"

### 5. Decide, commit, follow through
Document chosen and rejected options, trade-offs, revisit trigger, progress metric.
> Bias guards before closing: framing, anchoring, confirmation, sunk-cost.
> "If we had not already started, would we start today?"

**Full rung detail and decision record template:** `docs/reference/judgment-ladder.md`

---

## Mode: probe

Systems-thinking analysis *before* committing to a frame. Use when the diagnosis
itself is contested or the problem space is complex/emergent.

1. Map the system: actors, flows, feedback loops, delays.
2. Name the leverage points — the highest-impact spots to intervene (see `docs/reference/thinking-skills/`).
3. Stress-test the diagnosis: what would prove the current frame wrong?
4. Output: a framing memo, not a decision — hand off to `decide` or `strategize`.

---

## Mode: strategize

For irreversible or long-horizon commitments where rivals adapt and resources are
constrained. Grounded in Rumelt's kernel:

1. **Diagnosis** — simplified explanation of the actual challenge (not a goal).
2. **Guiding policy** — overall approach to the obstacles named in the diagnosis.
3. **Coherent actions** — steps that coordinate to carry out the policy.

A weak diagnosis produces a vague policy. If the three elements don't fit, loop.

Cross-check with Lafley-Martin five choices: winning aspiration → where to play →
how to win → capabilities → management systems.

**Full model detail:** `docs/reference/strategic-judgment.md`

---

## Output format

Produce a decision record at the end of any `decide` or `strategize` session:

```markdown
# Decision: <title>

- Date: YYYY-MM-DD
- Owner: @name
- Mode: decide | strategize

## Decision statement
<one sentence>

## Frame
- Objective:
- Constraints (hard):
- Scope in / out:
- Stakeholders:

## Key assumptions tested
| Assumption | Confidence | What would refute it |

## Decision
Selected: ...
Rejected: ... (reason)
Trade-offs accepted: ...

## Commitment
- Action owner + due date:
- First reversible step:
- Progress metric:
- Revisit trigger:
- Bias guards applied: framing / anchoring / confirmation / sunk-cost
```

Persist via `kbg:domain-modeling` (owns the ADR rule) when the decision warrants a durable ADR.

## Guardrails

- Do not run this skill in chaos or under active incident — stabilize first.
- `probe` output is a memo, not a decision. Do not skip to commitment from probe.
- A decision without a revisit trigger is not finished.
- Match effort to stakes: trivial reversible choices skip to rung 5 directly.

1. verify the decision is recorded with its score + revisit trigger — confirm a reader could re-derive the verdict from the trace.
   If the reasoning drifts from the stated criteria or the revisit trigger is missing, the decision is not finished — never close a choice without a re-open condition.
