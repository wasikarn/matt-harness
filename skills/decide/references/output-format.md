# decide — decision-record template

Moved verbatim from SKILL.md § Output format (2026-08-23, 200-LOC cap refactor). The qualifier
paragraphs are load-bearing — the Completion criterion in SKILL.md holds outputs to them.

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
