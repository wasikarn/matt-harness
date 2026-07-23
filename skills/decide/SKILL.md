---
name: decide
description: "Doctrine-backed decision support for hard/contested-diagnosis choices past advisor()-level pressure-testing. Trigger on 'stuck between'/'hard call', Thai 'ตัดสินใจยาก'/'เลือกไม่ลง'. Don't use for routine decisions: default triad + advisor()."
metadata:
  origin: kbg
  references:
    - docs/reference/judgment-ladder.md
    - docs/reference/decision-doctrine-map.md
    - docs/reference/strategic-judgment.md
---

# decide

Structured decision support built on the Judgment Ladder (Decision Quality tradition).
Five modes — pick by reversibility, diagnosis clarity, and whether the reasoning
already exists or still needs to be built.

## Mode selection

Run the decision-sizing triad first (METHODOLOGY Rule 1, injected each session): one-way door? → blast radius → riskiest assumption. A one-way door defaults to `strategize`.

| Situation | Mode |
|---|---|
| Scope or assumptions still unstated | `clarify` |
| Read-only: understand before committing | `probe` |
| Reversible choice, analyzable trade-offs | `decide` (default — Judgment Ladder) |
| Reasoning/plan/ADR already exists — stress-test it | `critique` |
| Irreversible / long-horizon / contested diagnosis | `strategize` |
| Chaos or incident | Stop — use `kbg:incident` instead |
| Decision already made, needs a record | `domain-modeling` directly (owns the ADR rule) |
| Disprove a confident output before committing to it | Stop — spawn an external fresh-context skeptic that has not seen the work (`doubt-driven` pattern; canonical instance is the adversarial pass in `kbg:review-pr`) — not a mode here, because the skeptic must not share this context |
| A pile of competing tasks/asks, not yet one bounded question | Stop — use `kbg:orchestrate` first to triage effort and execution shape; come back here once triage lands on a single reversible-choice question |

## Announce the active mode

Before the analysis runs, the first line of the response states the active mode and its named principle(s) — one clause, no preamble:

| Mode | Banner |
|---|---|
| clarify | `**Mode: clarify** — socratic questioning (framing-bias guard)` |
| probe | `**Mode: probe** — systems-thinking + leverage-points` |
| decide | `**Mode: decide** — Judgment Ladder (5 rungs)` |
| critique | `**Mode: critique** — red-team + steel-manning` |
| strategize | `**Mode: strategize** — Rumelt kernel + Lafley-Martin` |

---

## Mode: clarify

Resolve unstated scope or assumptions before any other mode runs. Analyze → recommend
→ ask — do not enumerate a long list of questions when a stated assumption will do.

1. **Analyze.** Name what's actually ambiguous: scope boundary, success criterion, or
   a load-bearing assumption the request leaves implicit.
2. **Recommend.** State your working interpretation as a default, not a question.
3. **Ask.** Only if the ambiguity is consequential enough that guessing wrong is
   expensive — use `AskUserQuestion` for a genuine fork; otherwise proceed on the
   stated default and flag it.

**Bias to guard:** framing bias — a narrow first framing of the ask silently
constrains every option considered downstream. Reframe test: "if the literal request
did not exist, what problem is actually being solved?"

Output: scope is resolved, then hand off to `probe`, `decide`, or `strategize`.

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

**Full rung detail and decision record template:** read via Bash — `cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"` (the bare repo-relative path resolves nowhere in a foreign-project CWD; the plugin cache is the stable anchor).

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

**Full model detail:** read via Bash — `cat "${KBG_PLUGIN_ROOT}/docs/reference/strategic-judgment.md"`.

---

## Mode: critique

Adversarial stress-test of reasoning that **already exists** — a plan, an ADR, an RFC,
a proposal on the table. Not for generating a new decision from scratch (`decide`/
`strategize` do that); this mode only audits one that's already made.

1. **Skeptic.** Argue against the proposal on its own terms: what load-bearing
   assumption, if false, collapses it? What would a competent rival or reviewer
   attack first? (red-team)
2. **Steel-man.** State the strongest version of the opposing case, not the weakest —
   the version that would actually change the decision if true. (steel-manning)
3. **Synthesis.** Name any unconsidered alternative the Skeptic/Steel-man pass
   surfaced. If the proposal survives, say why the strongest objection doesn't hold.
   If it doesn't survive, name what changes.

**Bias to guard:** confirmation bias — the proposal's author (possibly this session)
is structurally motivated to find it sound. Ask: "what evidence would prove this
proposal wrong, and did we look for it or just for evidence it's right?"

Output: a verdict — the reasoning holds, holds with a named caveat, or needs rework —
plus the one assumption most worth re-verifying.

---

## Output format

Produce a decision record at the end of any `decide` or `strategize` session:

```markdown
# Decision: <title>

- Date: YYYY-MM-DD
- Owner: @name
- Mode: clarify | probe | decide | critique | strategize

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

Persist via `domain-modeling` (owns the ADR rule) when the decision warrants a durable ADR.

## Guardrails

- Do not run this skill in chaos or under active incident — stabilize first.
- `probe` output is a memo, not a decision. Do not skip to commitment from probe.
- A decision without a revisit trigger is not finished.
- Match effort to stakes: trivial reversible choices skip to rung 5 directly.

## Completion criterion

Verify the decision is recorded with its Frame, tested assumptions, and Commitment (revisit trigger + progress metric) — confirm a reader could re-derive the Decision from the Frame and assumptions. For a numeric weighted verdict, apply the `kbg:score-decision` rubric (METHODOLOGY Rule 14) inline — the skill itself is `disable-model-invocation: true`, so tell the operator to run `/kbg:score-decision` if a formal, on-demand artifact is what's actually needed.

If the reasoning drifts from the stated criteria or the revisit trigger is missing, the decision is not finished — never close a choice without a re-open condition.
