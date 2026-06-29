---
name: thinking
description: On-demand index of 39 mental models. Read before reasoning on any complex, ambiguous, or high-stakes problem to pick the right scaffold. Use when facing a non-trivial decision or reasoning task. Don't use for simple, well-defined lookups or pure code generation.
metadata:
  origin: kbg
  sources: docs/reference/thinking-skills/skills/
---

# thinking — mental model dispatcher

This skill IS the index. Read it, pick 1–3 models that fit the situation, then
load each model's full file on demand. Do not load all 39 — pick and read only
what the situation requires.

## When to invoke this skill

- Problem is complex, ambiguous, or has no clear path forward
- A quick answer arrived but the stakes are high — force a verification pass
- A fix was applied but the same problem keeps recurring
- About to commit to something hard to reverse
- Under time pressure and unsure which angle to take
- Request is vague or assumption-laden before any work starts
- Need to find where to intervene in a system

## How to use

1. Scan the trigger table below.
2. Pick 1–3 models that match the situation. Do not blend more than 3.
3. Load each chosen model: `Read docs/reference/thinking-skills/skills/thinking-<name>/SKILL.md`
4. Apply the model. Let it constrain reasoning — do not cherry-pick only confirming parts.

**Honesty caveat:** none of the 39 models clears a replicated accuracy bar (see
`docs/reference/reasoning-models.md`). Use as structured reasoning scaffolds and
shared vocabulary, not a correctness guarantee.

---

## Trigger index

### Diagnosis / Root cause

| Trigger | Model | One-line purpose |
|---|---|---|
| Multiple causes could explain a bug; test simplest first | `occams-razor` | Fewest-assumption hypothesis first; escalate only when evidence forces it |
| Fault localized to component, proximate cause known, systemic root not | `five-whys-plus` | Chain 'why' with evidence, counterfactual test, explicit stop condition |
| Defect is selective — some but not all endpoints/users/times affected | `kepner-tregoe` | Map IS vs IS-NOT; boundary contrast points at root cause |
| Symptom has multiple causes, need falsifiable hypotheses | `scientific-method` | Rank hypotheses, check cheapest discriminating observation first |
| Bug spans services or behavior is emergent, no single component explains it | `systems` | Map the system, trace causes across feedback loops |
| Recurring problem despite previous fixes | `archetypes` | Match to known structural pattern instead of re-diagnosing |

### Decision / Choice

| Trigger | Model | One-line purpose |
|---|---|---|
| About to commit — is this hard to reverse? | `reversibility` | One-way vs two-way door; decide two-way fast, make one-way reversible |
| Scarce resource (time/people/money) being committed | `opportunity-cost` | What is the next-best use; what does doing nothing cost |
| About to add a feature/layer/process to fix something | `via-negativa` | Ask what to remove instead — subtraction is often more robust |
| High-stakes life/career choice, hard to undo | `regret-minimization` | Asymmetry between recoverable downside and permanent missed opportunity |
| Need structured decision support with trade-off analysis | Use `kbg:decide` — not a thinking-skill, it's a full workflow |

### Estimation / Numbers

| Trigger | Model | One-line purpose |
|---|---|---|
| Need a number; can't measure, can't look up | `fermi-estimation` | Decompose into estimable factors, multiply for order-of-magnitude |
| Stating a forecast, estimate, or risk | `probabilistic` | Anchor on base rate, give confidence range, update when evidence arrives |
| Provisioning capacity, setting a timeout/limit under uncertainty | `margin-of-safety` | Size buffer to cost of being wrong, not to the optimistic edge |

### Risk / Pre-flight

| Trigger | Model | One-line purpose |
|---|---|---|
| Before committing to a plan or launch | `pre-mortem` | Assume it failed; reason backward through why |
| Planning work; optimism may be hiding risks | `inversion` | "How would I guarantee failure?" — turn top paths into explicit requirements |
| Change has effects past the immediate fix | `second-order` | "And then what?" across horizons before committing |
| Reviewing code, auth, or APIs for security | `red-team` | Attacker mindset; enumerate attack surface; report only concrete paths |
| Two architecture requirements seem mutually exclusive | `triz` | Name the contradiction precisely, then separate conflicting states |

### Clarification / Understanding

| Trigger | Model | One-line purpose |
|---|---|---|
| Request is vague or assumption-laden before starting | `socratic` | Surface hidden requirements and false premises before building |
| Unsure why a feature isn't adopted or what to build | `jobs-to-be-done` | Reframe to the "job" users hire the product for |
| Behavior contradicts docs, tests, or diagram | `map-territory` | Go verify the running code or data; let the territory overrule the map |
| Unsure whether you actually know the answer | `circle-of-competence` | Abstain, ask, or fetch rather than confabulate a confident reply |

### System design / Architecture

| Trigger | Model | One-line purpose |
|---|---|---|
| Picking where to intervene; parameter tuning keeps not sticking | `leverage-points` | Rank interventions by Meadows' hierarchy; move to highest-leverage point |
| One pipeline stage dominates latency or throughput | `theory-of-constraints` | Focus all effort on the bottleneck; speeding up the rest changes nothing |
| System shows runaway growth, collapse, or oscillation | `feedback-loops` | Identify reinforcing/balancing loops and delays driving the behavior |
| Reasoning from a model/diagram — may be stale | `map-territory` | Verify the running system before trusting the map |

### Constraint is treated as fixed

| Trigger | Model | One-line purpose |
|---|---|---|
| "Too expensive / impossible / always done this way" | `first-principles` | Ask whether it's physics or convention; rebuild from what's actually true |
| Scale or failure mode can't be cheaply tested | `thought-experiment` | Imagine the scenario; walk the consequence chain step by step |

### Speed / Under pressure

| Trigger | Model | One-line purpose |
|---|---|---|
| Time pressure; must act before certainty | `ooda` | Observe→Orient→Decide→Act on ~70% confidence, then re-observe |
| Fast answer arrived on high-stakes or unfamiliar task | `dual-process` | Force one explicit verification pass before committing |

### Bias / Self-check

| Trigger | Model | One-line purpose |
|---|---|---|
| Defending a committed path; explaining away evidence | `debiasing` | Run self-check for sunk-cost and confirmation bias |
| Investigation could run indefinitely — need a stopping rule | `bounded-rationality` | Set explicit "good enough" threshold; stop at first option that clears it |
| Interpreting a test result, metric, or new evidence | `bayesian` | State base rate first; update by likelihood ratio |
| About to reject a proposal or about to agree too easily | `steel-manning` | Build the strongest opposing case first, then engage that |

### Technology / Longevity choice

| Trigger | Model | One-line purpose |
|---|---|---|
| Choosing a technology/framework where longevity matters | `lindy-effect` | Expected remaining life is proportional to current age — favor the proven |

### Unknown domain / Innovation

| Trigger | Model | One-line purpose |
|---|---|---|
| Unsure how to approach — plan, analyze, experiment, or stabilize? | `cynefin` | Classify by cause-effect clarity; match approach to domain |
| Startup, innovation, or novel domain where planning is unreliable | `effectuation` | Start with means, not goals; co-create; leverage contingencies |
| Complex problem needing multiple lenses | `model-combination` | Combine 2–3 models; use `model-selection` to pick which ones |
| Need a general entry point when trigger is unclear | `model-router` | Routes to the right model based on domain and problem type |

---

## Load path

```
docs/reference/thinking-skills/skills/thinking-<name>/SKILL.md
```

Example — to load the full pre-mortem scaffold:
```
Read docs/reference/thinking-skills/skills/thinking-pre-mortem/SKILL.md
```

Do not move any file from `docs/reference/thinking-skills/` into `skills/` — that
would register them as auto-discovered invokable skills and break the fleet count.
