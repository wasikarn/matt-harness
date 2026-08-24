# Strategic judgment

**Strategic judgment** is the discipline of choosing under ambiguity when commitments are hard to reverse and the payoff horizon is long. It is not the same as operational decision-making, long-term planning, or goal-setting.

Use it when the diagnosis is contested, the rivals adapt, the resources are constrained, and undoing the choice later would be costly or impossible. For analyzable, reversible choices, use the Judgment Ladder (`docs/reference/judgment-ladder.md`) instead.

## What strategic judgment is not

| Not strategic judgment | What it actually is | kbg surface |
| --- | --- | --- |
| Goal-setting | A destination without a diagnosis or policy | — |
| Operational decision-making | Analyzable trade-offs inside an existing frame | METHODOLOGY Rule 1 triad + `advisor()`, `docs/reference/judgment-ladder.md` |
| Execution planning | Sequencing tasks after the strategy is set | `/ship`, `mattpocock-skills:domain-modeling` |
| Chaos response | Stabilize first, decide fast | `kbg:incident` |
| Research | Gathering intelligence before committing | `mattpocock-skills:research` |

## Core model: Rumelt's kernel

Richard Rumelt (*Good Strategy Bad Strategy*) reduces good strategy to three elements:

1. **Diagnosis** — a simplified explanation of the nature of the challenge.
2. **Guiding policy** — the overall approach chosen to cope with the obstacles identified by the diagnosis.
3. **Coherent actions** — steps that coordinate with each other to carry out the guiding policy.

The kernel is iterative. A weak diagnosis produces a vague policy; incoherent actions reveal a weak policy. The loop runs until the three elements fit.

## Five strategic choices (Lafley & Martin)

A. G. Lafley and Roger Martin (*Playing to Win*) frame strategy as five interlocking choices:

| Choice | Question | Failure mode |
| --- | --- | --- |
| Winning aspiration | What does winning mean? | Aimless activity or borrowed ambition |
| Where to play | In which markets, segments, geographies, or domains? | Trying to be everywhere |
| How to win | What is our competitive advantage there? | No unique answer |
| Capabilities | What abilities must we possess? | Capability gap ignored |
| Management systems | What systems support and measure those capabilities? | Capabilities starved of support |

The five choices and Rumelt's kernel map to each other: aspiration and where/how to play shape the guiding policy; capabilities and systems shape the coherent actions.

## Integrative thinking (Martin)

Roger Martin's integrative thinking asks you to hold two opposing models of the problem, understand the tension, and generate a creative resolution that preserves what is best in both. It is the opposite of either/or thinking.

| Step | Action |
| --- | --- |
| Salience | Identify the factors that matter in each model |
| Causality | Trace how each model explains outcomes |
| Architecture | See the models as whole structures, not isolated facts |
| Resolution | Generate a new model that incorporates the best of both |

Use this when the diagnosis splits into two camps (e.g., "build vs. buy", "centralize vs. decentralize", "fast vs. safe") and neither camp is obviously wrong.

## Real options and adaptive commitment

Strategic commitments differ in reversibility. Good strategy preserves optionality where uncertainty is high and commits firmly where delay is costly.

| Commitment type | When to use | Example |
| --- | --- | --- |
| Irreversible bet | Uncertainty is low; delay is costly | Building a factory, signing an exclusive partnership |
| Reversible probe | Uncertainty is high; information is cheap | A/B test, pilot market, prototype architecture |
| Stage gate | Commit in tranches, conditioned on signals | Product launch in phases, regional rollout |
| Adaptive commitment | Pre-decide responses to future signals | "If metric X drops below Y for two quarters, exit market Z" |

The discipline is to **buy information before buying irreversibility**. Premature lock-in is the most common strategic error.

## Strategic red-team

A strategy red-team is not optimism control; it is a search for load-bearing assumptions and second-order effects that the strategy loop must revisit.

| Question | What it surfaces |
| --- | --- |
| What would prove the diagnosis wrong? | Brittle diagnosis |
| What would make the guiding policy irrelevant? | External shock or competitor move |
| Which assumption, if false, collapses the coherent actions? | Hidden load-bearing belief |
| What would a competent rival do in response? | Competitive dynamics |
| What would a reckless rival do? | Tail-risk disruption |
| What second-order effects ripple inside the org? | Internal friction, misalignment, perverse incentives |
| Where are we confusing ambition with evidence? | Overconfidence and planning fallacy |

## Superforecasting discipline (Tetlock)

Philip Tetlock's research on expert political judgment and superforecasting adds a calibration discipline to strategic estimates:

- **Decompose** the big question into smaller, answerable sub-questions.
- **Take the external view** first: what is the base rate for events like this?
- **Update** incrementally as evidence arrives; avoid premature closure.
- **Express uncertainty** as probabilities with confidence intervals, not binary claims.
- **Score** forecasts later to calibrate future judgment.

This is not a substitute for the Rumelt/Martin framework, but it sharpens the estimate step inside the strategy loop.

## Applying this reference: the six-step loop

The harness applies this reference inline (no dedicated skill wrapper), walking six steps:

1. Diagnose the situation
2. Choose the guiding policy
3. Design coherent actions
4. Map irreversibilities and real options
5. Red-team the strategy — `mattpocock-skills:grilling` is the surface for this step when the strategy needs a relentless external skeptic
6. Commit to the strategy loop

## When to reach for this loop vs. the Judgment Ladder

| Signal | Reach for |
| --- | --- |
| The choice is analyzable, reversible, and time-pressured | Judgment Ladder (`judgment-ladder.md`) |
| The commitment is large, long-lived, and hard to reverse | this loop |
| The diagnosis is contested and the best option is not computable | this loop |
| Rivals, markets, or stakeholders will adapt in response | this loop |
| The question is "which of these known options is best?" | Judgment Ladder (`judgment-ladder.md`) |
| The question is "what game are we playing, and how do we win it?" | this loop |

## Strategic judgment in software engineering

Software strategy is not about picking technologies. It is about choosing commitments that shape what the organization can build, how fast, and at what cost — and then designing actions that reinforce each other.

| Strategic bet | Diagnosis question | Guiding policy shape | Coherent actions |
| --- | --- | --- | --- |
| Monolith → services | Where does deploy independence actually pay back its operational cost? | Extract only where coupling blocks business speed; keep the rest modular-but-monolithic | Bounded-context pilot; platform tooling; team-topology pilot; metrics |
| Database / storage choice | What access patterns and consistency requirements do we actually have? | Match storage to workload; abstract the choice behind an owned interface | Spike on production-like load; migration stage gates; operator runbooks |
| Build vs. buy (auth, billing, CRM, etc.) | Is this capability core to our differentiation? | Build what differentiates; buy what is table-stakes | Integration-adapter design; contract exit clauses; data-portability tests |
| Team topology | What is the limiting factor: cognitive load, coordination cost, or skill depth? | Organize teams around the flow of value they can independently deliver | Platform-crew pilot; SLO-based handoff; revisit after two quarters |
| Language / framework commitment | What ecosystem, hiring market, and runtime constraints bind us? | Standardize on one primary stack; allow escape hatches for proven needs | Prototype in a non-critical service; training pipeline; deprecation policy |

**Mapping to the kbg flow:**
1. This loop answers "what game are we playing and how do we win it?" and produces a guiding policy.
2. The Judgment Ladder (`judgment-ladder.md`) answers "which known option is best?" inside that policy.
3. `mattpocock-skills:domain-modeling` records the commitment, the tripwires, and the loop that revisits it.

## Related surfaces and references

- `docs/reference/judgment-ladder.md` — Judgment Ladder for operational/consequential choices
- `mattpocock-skills:domain-modeling` — record a committed decision once the strategy is set (owns the ADR rule)
- `mattpocock-skills:grilling` — adversarial stress-test of a contested plan, decision, or diagnosis
- `mattpocock-skills:research` — external and competitive intelligence, including mining a strategy article or book chapter for doctrine

> **Vendored thinking references (not loadable `kbg:` surfaces).** Cynefin, second-order thinking, red-team reasoning, and systems thinking live under `docs/reference/thinking-skills/skills/`. Use them as reasoning frames, not as invokable skills.
