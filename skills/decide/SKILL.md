---
name: decide
description: "Doctrine-backed decision support for hard/contested-diagnosis choices past advisor()-level pressure-testing. Trigger on 'stuck between'/'hard call', Thai 'ตัดสินใจยาก'/'เลือกไม่ลง'. Don't use for routine decisions: default triad + advisor()."
bucket: workflow
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

Rows are checked top-to-bottom; apply the **first** row that matches — this is what
resolves an apparent conflict between rows, not a judgment call made fresh each time.

Run the decision-sizing triad first (METHODOLOGY Rule 1, injected each session):
one-way door? → blast radius → riskiest assumption. The triad sizes the stakes; it
does not bypass the table. A one-way door pulls toward `strategize`, but only once
the rows above it don't match first — scope still unstated routes to `clarify` (you
can't judge "one-way door?" without knowing scope first), and an existing plan/ADR
routes to `critique` (auditing what's on the table beats re-deriving it from scratch,
even when that plan reads as hard to reverse).

| Situation | Mode |
|---|---|
| Chaos or incident | Stop — use `kbg:incident` instead |
| A pile of competing tasks/asks, not yet one bounded question | Stop — use `kbg:orchestrate` first to triage effort and execution shape; come back here once triage lands on a single decision to size against the rows below |
| Scope or assumptions still unstated | `clarify` |
| Read-only: understand before committing | `probe` |
| Reversible choice, analyzable trade-offs | `decide` (default — Judgment Ladder) |
| Reasoning/plan/ADR already exists **from outside this session** — stress-test it | `critique` |
| Disprove a confident output **this session already produced** | Stop — spawn an external fresh-context skeptic that has not seen the work (`doubt-driven` pattern; canonical instance is the adversarial pass in `kbg:review-pr`) — not a mode here, because the skeptic must not share this context; `critique`'s own confirmation-bias guard can't substitute for genuine context separation on this session's own output |
| Irreversible / long-horizon / contested diagnosis | `strategize` |
| Decision already made, needs a record | `mattpocock-skills:domain-modeling` directly (owns the ADR rule) |

**Compound request, one table, multiple hits:** if a single request bundles two or more
distinct asks that land on different rows (e.g. "critique this ADR, then help me decide
whether to greenlight the follow-up"), run the table separately per clause and state each
mode's own banner separately, in the order the asks appear — don't force multiple distinct
asks under one banner just because they arrived in the same message.

**Handing off to the external skeptic:** when the "disprove a confident output this session
already produced" row fires, hand over the full reasoning/artifact produced — not a filtered
summary or just a closing assumptions table. A same-session summary is exactly the kind of
filtering the context-separation guard exists to route around; a brief that only carries
forward what this session already flagged as risky hands the skeptic this session's blind
spots along with its context. The full protocol for structuring the skeptic's actual review
lives in `kbg:review-pr`'s doubt-driven pattern — this note only covers what decide itself
hands off.

## Precedent check

Before any decision-producing mode runs (`decide` / `strategize` / `critique`), query `qmd`
(lex + vec) with the decision's scenario, scoped to the project's memory + research collections
(`kbg-memory` + `kbg-research` in kbg-harness; other projects' own collections per `qmd status`).
State the result in one line of the first response, **citing the query string actually run**:
the precedent found, or `no precedent found for "<query>"`. A bare "no precedent found" with no
query cited is unverifiable self-report and doesn't satisfy this check (a "nothing found" needs
one checkable fact). A hit showing the same decision already settled, with no new evidence in the current
ask, ends the run — cite the settled record instead of re-litigating it. If qmd is unavailable
in this context, say the check couldn't run; don't silently skip it. (Adapted from
semantica-agi/semantica's `find_precedents` lifecycle step — the store and the search already
existed here; this section wires the mandated query.)

## Announce the active mode

Before the analysis runs, the first line of the response states the active mode and its named principle(s) — one clause, no preamble:

| Mode | Banner |
|---|---|
| clarify | `**Mode: clarify** — socratic questioning (framing-bias guard)` |
| probe | `**Mode: probe** — systems-thinking + leverage-points` |
| decide | `**Mode: decide** — Judgment Ladder (5 rungs)` |
| critique | `**Mode: critique** — red-team + steel-manning` |
| strategize | `**Mode: strategize** — Rumelt kernel + real options + red-team + Lafley-Martin` |

---

## Mode: clarify

See `references/mode-clarify.md` for the full procedure (analyze → recommend → ask,
the framing-bias guard, and the settled-ask check).

---

## Mode: decide (default)

See `references/mode-decide.md` for the full 5-rung Judgment Ladder walk (Recognize →
Frame → Test assumptions → Estimate risk → Decide/commit/follow-through), the
Proportionality depth-matching rule, and the rungs-1–2 shortcut's spot-check
exception.

---

## Mode: probe

See `references/mode-probe.md` for the full systems-thinking procedure (map the
system → name leverage points → stress-test the diagnosis → output a framing memo).

---

## Mode: strategize

See `references/mode-strategize.md` for the full 6-step walk (Diagnosis → Guiding
policy → Coherent actions → Map irreversibilities/real options → Red-team →
Commit to the strategy loop).

---

## Mode: critique

See `references/mode-critique.md` for the full procedure (Skeptic → Steel-man →
Synthesis, the confirmation-bias guard, and the required verdict shape).

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

Each Confidence cell carries the same evidence-anchor requirement as the Decision block's
Confidence line below — a bare high/medium/low with no cited evidence doesn't count here either.

## Decision
Selected: ... (driven by: <the 1–3 stated facts that decided it>)
Rejected: ... (reason: <the specific fact or constraint that ruled it out — same
  evidence standard as Selected's driven-by line; a generic quality adjective with
  no cited fact doesn't count>)
Trade-offs accepted: ...
Confidence: high | medium | low — <the named evidence this rests on, and the
  load-bearing thing NOT verified>. Confidence is about the selected option itself,
  not a sub-assumption; a bare label with nothing behind it doesn't count.
Flip condition: <the one fact from the tested assumptions that, resolved the other
  way, reverses Selected → Rejected — an actual reversal, not a cost/pace/confidence
  adjustment>. Distinct from Confidence above (what's uncertain) and Revisit trigger
  below (when to re-open); this names what specifically would flip the pick. An
  unexamined "nothing would flip it" doesn't satisfy this line — either name the
  fact, or say why the two options are genuinely too lopsided to be flippable.

## Commitment
- Action owner + due date:
- First reversible step:
- Progress metric:
- Revisit trigger:
- Bias guards applied: framing / anchoring / confirmation / sunk-cost
```

`First reversible step` must be consistent with the Flip condition above it — if the step proceeds
on the original pick regardless of how the Flip condition resolves, that's a contradiction, not a
plan. Either the step tests the flip condition before committing further, or state explicitly why
proceeding anyway still holds even if the flip condition resolves against the pick. A flip
condition the plan doesn't act on is the same failure as no flip condition at all.

This is the compact default. For a one-way-door or high-stakes decision, use
`judgment-ladder.md`'s fuller template instead (adds `Consulted`, an `Evidence`
column on the assumptions table, a `## Scenarios` probability/impact table, and a
separate `Next check-in date`) — read via Bash,
`cat "${KBG_PLUGIN_ROOT}/docs/reference/judgment-ladder.md"`.

Persist via `mattpocock-skills:domain-modeling` (owns the ADR rule) when the decision warrants a durable ADR.

## Guardrails

- Do not run this skill in chaos or under active incident — stabilize first.
- `probe` output is a memo, not a decision. Do not skip to commitment from probe.
- Match effort to stakes: trivial reversible choices need only rungs 1–2 (Recognize
  + Frame), not the full climb — see "Match depth to stakes" under Mode: decide. This
  scales down tested assumptions, the formal progress metric, and the Flip condition —
  which also scales down the `First reversible step`/Flip-condition consistency check
  below, since there's no Flip condition to be consistent with at that depth (see the
  Completion criterion's `decide` exception below); it does not scale down
  the revisit trigger.
- A decision without a revisit trigger is not finished — this applies at every depth,
  including a rungs-1–2-only response.

## Completion criterion

This criterion applies per mode's own output shape, not one template for all five. Every
decision-producing mode (`decide` / `strategize` / `critique`) additionally owes the one-line
Precedent check result (see § Precedent check) — a run that never stated it is not finished:

- **`decide`** — verify the decision is recorded with its Frame, tested assumptions, an evidence-tied Confidence on the selected option, a Flip condition naming the one fact that reverses the pick, and Commitment (revisit trigger + progress metric) whose `First reversible step` doesn't silently proceed regardless of how that Flip condition resolves; confirm a reader could re-derive the Decision from the Frame and assumptions. **Exception for a rungs-1–2-only response** (per the Proportionality guardrail above): tested assumptions, a formal progress metric, the Confidence line, the Flip condition, and its `First reversible step` consistency check are not required — Frame plus a named revisit trigger is sufficient. A response that stops at rungs 1–2 but skips even the revisit trigger is not finished; one that goes further than rung 2 owes the full record.
- **`strategize`** — same Output format template, mapped from its own step vocabulary: Diagnosis + Guiding policy fill the Frame section, the irreversibility map and red-team results are the tested assumptions, and Commitment's revisit trigger comes from step 6's strategy loop (progress metric = whatever the red-team/tripwire step names as the signal to watch).
- **`critique`** — verify the verdict (holds / holds with caveat / needs rework), the one assumption most worth re-verifying, and — when the verdict isn't a clean "holds" — what specifically would need to change are all stated. No Frame/Commitment record required; critique audits an existing plan rather than producing a new one.
- **`clarify` / `probe`** — completion is the stated handoff itself (resolved scope + working default, or a framing memo) — these modes never produce a decision record and aren't held to the Frame/Commitment bar.

For a numeric weighted verdict, apply the `kbg:score-decision` rubric (METHODOLOGY Rule 14) inline — its default criteria (Evidence/Doctrine/Net load/Risk-inverted/Proportionality/No-conflict) are shaped for a `decide`-style trade-off table; for a `strategize` output, adapt them to score the guiding policy's coherence and whether it survived the red-team rather than forcing a single-option comparison onto a qualitative kernel. `score-decision` itself is `disable-model-invocation: true`, so tell the operator to run `/kbg:score-decision` if a formal, on-demand artifact is what's actually needed.

If a `decide`/`strategize` session's reasoning drifts from the stated criteria or the revisit trigger is missing, it is not finished — never close a choice without a re-open condition.
