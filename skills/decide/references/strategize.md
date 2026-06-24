---
name: strategize
description: "Use when making an irreversible or long-horizon strategic commitment under ambiguity. Thai: 'วางกลยุทธ์', 'กลยุทธ์', 'strategy', 'strategic judgment', 'strategic choice', 'ตัดสินใจเชิงกลยุทธ์'. Don't use for operational/analyzable decisions (use kbg:decide), chaotic immediate response (use kbg:incident), or choices already dictated by policy or constraint."
---

# Strategize

Apply **strategic judgment** — the art of choosing under ambiguity where commitments are hard to reverse and the payoff horizon is long. This skill is not a planning drill; it is a disciplined way to shape the situation before the situation shapes you.

Strategic judgment differs from operational decision-making. `kbg:decide` climbs the Judgment Ladder when the choice is analyzable and reversible. `kbg:decide (strategize mode)` is for commitments under uncertainty: the diagnosis is contested, the resources are constrained, the rivals adapt, and undoing the choice later would be costly or impossible.

> **Thai framing note.** This maps to "การตัดสินใจเชิงกลยุทธ์" — not merely picking a goal, but diagnosing the challenge, choosing a guiding policy, and designing actions that reinforce each other. It sits upstream of operational decision-making (ตัดสินใจปฏิบัติ) and upstream of execution.

## When to use

- The commitment is large, long-lived, or hard to reverse (capital, architecture, org design, market position, alliances).
- The situation is ambiguous: you can name forces and rivals, but cannot compute an optimal answer.
- Multiple stakeholders will be aligned or misaligned by the policy, not just informed by the decision.
- The user asks about strategy, strategic choice, where to play / how to win, competitive position, or adaptive planning.

## When NOT to use

- **Operational / analyzable decisions** — trade-offs are clear, data can answer the question, reversibility is high. Use `kbg:decide`.
- **Chaotic / time-pressed response** — stabilize first. Use `kbg:incident` (it embeds the hotfix path). For pure high-speed pattern-matching when no kbg surface fits, prompt an OODA loop from the vendored thinking reference (`docs/reference/thinking-skills/skills/thinking-ooda/`), not from a loadable `kbg:` surface.
- **Answer already dictated** — if architecture charter, policy, or a hard constraint removes choice, say so instead of running the strategy loop.
- **Pure research or intelligence gathering** — use `/deep-dive` or `kbg:decide (probe mode)` first; feed their output into `kbg:decide (strategize mode)`.
- **Execution planning only** — use `kbg:ship-task` or `kbg:adr` once the strategy is set.

## Procedure

### 1. Diagnose the situation

Name the core challenge. Separate symptoms (falling revenue, slow builds, attrition) from the underlying strategic problem (market position eroding, technical leverage decaying, talent model broken).

- What is happening? What are the observable symptoms and the underlying forces?
- What are the constraints we cannot change? Where are the degrees of freedom?
- Who are the rivals / alternatives / substitutes, and what are they betting on?
- What would happen if we did nothing for 6–12 months?
- What is the one challenge we must address for the strategy to matter?

**Stop if:** you can only list symptoms, or the diagnosis is a thinly disguised preferred solution.

### 2. Choose the guiding policy

A guiding policy is a concentrated response to the diagnosis. It tells the organization what to do *and* what not to do. It is not a vision statement or a list of goals.

- What is the central integrated response to the diagnosis?
- What is our winning aspiration? What does "winning" mean here?
- Where will we play? Where will we deliberately not play?
- How will we win where we choose to play?
- What capabilities must we have? What management systems must support them?
- What are we saying no to so we can say yes to the policy?

**Lafley/Martin five-choices check:** winning aspiration → where to play → how to win → capabilities → management systems. Not every question needs an answer, but none should be smuggled in untested.

**Stop if:** the policy tries to be everything to everyone, or it is a goal dressed as a strategy.

### 3. Design coherent actions

Actions are coherent when they reinforce each other and address the diagnosis. A list of initiatives is not coherence.

- What 3–5 actions, taken together, make the policy credible?
- How does each action strengthen the others?
- Which actions are prerequisites? Which are amplifiers?
- What resources and sequencing make the actions feasible?
- What does each action say no to, so effort does not diffuse?

**Coherence test:** remove any one action. Does the rest of the set still hold together? If yes, it may not have been load-bearing.

**Stop if:** actions are a wishlist, or they could be executed without the policy and still look sensible.

### 4. Map irreversibilities and real options

Strategic commitments differ by how hard they are to undo. Separate irreversible bets from reversible probes and stage gates.

- Which commitments are hard or impossible to reverse? Cost, time, reputation, relationships, architecture.
- Where can we preserve optionality? What smaller experiments buy information before a big bet?
- What are the adaptive commitment points: signals that should trigger doubling down, pivoting, or exiting?
- What is the cost of waiting vs. the cost of premature lock-in?

**Optionality rule:** never make a big irreversible bet before the smaller reversible tests that would change your mind.

**Stop if:** the plan front-loads irreversible commitments without first buying information.

### 5. Red-team the strategy

Use adversarial reasoning against the diagnosis and the policy. The goal is not to kill the strategy but to surface what would make it fail.

- What would prove our diagnosis wrong?
- What would make the guiding policy irrelevant?
- Which load-bearing assumption, if false, collapses the coherent actions?
- What are the second-order and third-order effects inside the org, the market, and the team?
- What would a competent rival do in response? What would a reckless rival do?
- Where are we overconfident? Where are we confusing ambition with evidence?

**Techniques:** pre-mortem on the strategy, reverse the policy and ask why it would win, steel-man the strongest objection.

**Stop if:** the red-team finds unaddressed load-bearing risks and the strategy loop does not return to diagnosis.

### 6. Commit to the strategy loop

A strategy is only as good as the loop that keeps it honest. Name the decision owner, the review cadence, and the signals that matter.

- Who owns the strategy and the authority to change it?
- What are the leading indicators that the strategy is working?
- What are the tripwires that should trigger an early review?
- When will we revisit the diagnosis? (Strategy reviews decay into performance reviews if the diagnosis is never re-examined.)
- What is the next smallest action that tests the strategy, not just executes it?

**Stop if:** there is no named owner, no review trigger, and no signal that could change the strategy.

## Output format

Respond with these sections, calibrated to the stakes. For small-stakes strategic choices, compress; for big bets, fill every block.

### 1. Diagnosis
- Core challenge (one paragraph)
- Key forces and constraints
- What "winning" would change

### 2. Guiding policy
- Winning aspiration
- Where to play / where not to play
- How to win
- Capabilities and management systems required
- Explicit nos

### 3. Coherent actions
- 3–5 actions, sequenced
- How each reinforces the others
- Prerequisites and amplifiers

### 4. Irreversibilities and real options
- Hard-to-reverse commitments
- Reversible probes / stage gates
- Adaptive commitment points and tripwires

### 5. Strategic red-team
- Biggest threats to the diagnosis
- Biggest threats to the policy
- Load-bearing assumptions to watch
- Second-order effects

### 6. Commitment loop
- Strategy owner
- Leading indicators of success
- Review cadence and triggers
- Next test, not just next task

## Applying `kbg:decide (strategize mode)` to software engineering

Use this skill when a technical commitment is large, long-lived, or hard to reverse. Do not use it for day-to-day implementation trade-offs; those belong in `kbg:decide`.

| Strategic technical bet | Why `kbg:decide (strategize mode)` fits | Typical real options |
|---|---|---|
| Monolith → services / modularization | Hard to reverse; changes team topology and deploy cadence | Pilot extraction of one bounded context first; clear rollback criteria |
| Primary database / storage technology | Lock-in spans years; migration is expensive | Spike + PoC with production-like load; stage gate before full migration |
| Language / runtime / framework commitment | Ecosystem, hiring, and training follow the choice | Prototype in a non-critical service; explicit sunset criteria |
| Build vs. buy / outsource vs. in-house | Alters capabilities and management systems for years | Trial with one team or one workflow; contract exit clauses |
| Auth / payment / compliance platform | Deep integration creates switching cost | Adapter layer + phased cutover; keep a parallel fallback |
| Team topology (squads vs. platform teams) | Hard to reverse; changes communication architecture | Run a temporary platform crew; measure cognitive load before scaling |

**Combined flow:**
1. `kbg:decide (strategize mode)` sets the guiding policy and boundaries (e.g., "extract services only where deploy independence pays back the operational cost").
2. `kbg:decide` climbs the Judgment Ladder for each implementation choice inside that policy (e.g., "which service boundary first?").
3. `kbg:adr` records the committed decision and the loop that keeps it honest.

## Failure modes

- **Strategy-as-goal.** "Be number one in X" is not a strategy; it lacks diagnosis, policy, and coherent action.
- **Wishlist planning.** A set of initiatives without mutual reinforcement.
- **Premature lock-in.** Making a large irreversible bet before small reversible tests.
- **Competitor amnesia.** Forgetting that rivals, substitutes, and markets respond.
- **Static strategy.** Setting a strategy without a loop to revisit the diagnosis.

## Related surfaces

- `kbg:decide` — operational / analyzable choices via the Judgment Ladder.
- `kbg:adr` — record a committed architectural decision once the strategy is set.
- `kbg:decide (probe mode)` — deep investigation of a slice of the situation before diagnosing.
- `/deep-dive` — external and competitive intelligence to feed diagnosis.
- `kbg:article-mine` — mine a strategy article or book chapter for doctrine.

> **Vendored thinking references (not loadable `kbg:` surfaces).** Cynefin, second-order thinking, red-team reasoning, and systems thinking live under `docs/reference/thinking-skills/skills/`. Use them as reasoning frames, not as invokable skills.
