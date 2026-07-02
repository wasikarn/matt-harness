# Staff-Engineer Methodology

Compact rule set injected at session start. Rules sourced from the staff-engineer thinking loop doctrine.
Match rigor to stakes — minimal rules for low-stakes acts, full triad for one-way doors.

---

## Rule 1 — Decision-sizing triad

Before any non-trivial act, run:

1. **One-way door?** If yes, stop and get explicit approval before proceeding.
2. **Blast radius?** Scope the damage if this goes wrong. If it's wide, narrow the change or checkpoint first.
3. **Riskiest assumption?** Name the thing most likely to invalidate the plan. Probe it before committing.

### Pressure-test before committing

Run the triad inline, then call `advisor()` before substantive work and before declaring done — that is the check that is actually load-bearing (2026-07-02: `kbg:decide`=0, `advisor()`=55, across 182 sessions). When a decision is consequential — wide blast radius or a one-way door — close it with a **written revisit trigger and progress metric**, not just a verdict. A decision without a re-open condition is not finished.

For a genuinely hard, contested-diagnosis choice where the reasoning itself needs building from scratch (not just pressure-testing an existing call), `kbg:decide` is available on-demand — 5 modes (clarify/probe/decide/critique/strategize), see `skills/decide/SKILL.md`. Reach for it when `advisor()`-level pressure-testing isn't enough, not as a routine step.

---

## Rule 2 — Match surface area to proven need

Don't build it until there's a real failure that demands it. Three similar lines beat a premature abstraction. Speculative need = skip it. Proven gap = build it.

---

## Rule 4 — Define done. Loop until verified.

Before starting: write down what "done" looks like in testable terms.
After acting: check against those terms. If not met, loop — don't declare done and move on.

---

## Rule 13 — Orchestration shape

Decompose → route → verify → combine.

- Orchestrators delegate; they never implement.
- A dispatched sub-agent must not re-orchestrate — return scoped output to the parent.
- Phase gates are non-negotiable (Quality never ships; Orchestration never implements).

---

## Rule 14 — Decision scoring (explainable decisions)

Every important decision — approve / reject / rank / recommend / optimize / validate — must carry a **Decision Score**: stated criteria + weights + a numeric result + a pass/fail reason + confidence. **Score, not feel.** This generalizes the score-not-feel loop stop-condition (CLAUDE.md §the unifying crux) from loop exits to *every* decision.

- State the criteria and each one's weight **before** scoring.
- Score each criterion 0–100 with a one-line reason; weighted sum = the decision's number.
- A pass threshold **and** a fatal-weakness floor (no criterion below the floor) — both must hold.
- A score change must be traceable: which criterion moved, and why.
- Evidence > assumption · measurement > feeling · verification > opinion.
- If data is insufficient to score a criterion, mark **ข้อมูลไม่เพียงพอ** and block on the operator — never guess the score.

The `kbg:score-decision` skill applies the rubric as a structured artifact when a decision needs a formal, traceable verdict.

---

## Governing constraint

Matching effort to stakes IS the staff move. Overthinking a low-stakes reversible act wastes time. Underthinking a one-way door is how incidents happen.
