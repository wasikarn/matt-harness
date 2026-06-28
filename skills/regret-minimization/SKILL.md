---
name: regret-minimization
description: Use when reversibility analysis alone does not resolve a high-stakes engineering or product decision — weigh a recoverable downside against a permanently missed upside. Complements skills/adr for choices where both paths seem viable but timing and opportunity asymmetry matter.
metadata:
  origin: kbg
  reasoning-model: regret-minimization
  vendored-ref: docs/reference/thinking-skills/skills/thinking-regret-minimization/SKILL.md
---

# Regret Minimization (Engineering Asymmetry)

> Scope: this skill applies the **asymmetry** concept from Bezos's framework to
> engineering and product decisions. The original framework is a human advisory
> lens ("imagine yourself at 80"). For agent decisions, the mechanism is structural:
> a recoverable downside vs a permanently foregone upside. For technical one-way
> doors, use `skills/adr` + pre-mortem first. Reach for this when both paths seem
> reversible but opportunity timing matters.

## The asymmetry

A failed attempt is usually recoverable. A never-taken opportunity is permanently gone.
When those are the two sides, the asymmetry favors trying.

```
Map the downside: recoverable in weeks / months?  → low regret risk
Map the upside:   gone permanently if delayed?    → high regret risk

Both true → asymmetry favors acting. Skip it only if the downside is also permanent.
```

## When to use

- Exposing a new data surface that adds regulatory scope (PDPA/GDPR): the surface
  can be removed; the early-mover value of having it cannot be recovered.
- Adopting a framework or ORM before the team has full conviction: adoption window
  closes as competitors converge; the learning cost is recoverable.
- Committing to a data model change that requires migration work: the migration is
  a recoverable cost; the schema that becomes the industry default is not.
- Deciding whether to build a feature before standards are final: shipping first
  shapes the standard; waiting until final locks you out of influence.

## When NOT to use

- The downside is also permanent (data loss, GDPR violation, broken public API
  contract) → use `skills/adr` + pre-mortem. Asymmetry does not apply.
- The decision is easily reversible → just pick one and adjust; no framework needed.
- You are reasoning about an agent's own tooling or architecture choices →
  use reversibility (`skills/adr`) + opportunity-cost (`skills/orchestrate`) instead.
  An agent has no "future self" to regret.

## Workflow

1. **Name both paths** — one sentence each, honest about cost.
2. **Map the downside** — is it recoverable? In what timeframe? At what cost?
3. **Map the upside** — is the opportunity time-bound? What closes the window?
4. **Check the asymmetry** — recoverable downside + permanent upside → act.
   Permanent downside → stop and use `skills/adr`.
5. **State the decision** — one sentence: "act now because [upside closes]; the
   [downside] is recoverable by [path]."

## Example — plate-level analytics surface

```
Option A: Build plate-level analytics endpoint now
  Downside: adds PDPA surface area → recoverable (endpoint can be gated/removed)
  Upside: enables billing granularity before competitors lock in the market expectation

Option B: Wait until PDPA guidance is clearer
  Downside: delay in shipping → recoverable
  Upside: ... none that closes if we wait; guidance will apply retroactively

Asymmetry: Option A downside is recoverable; its upside closes as market settles.
Decision: build now with data-minimization defaults; add gate to disable without
          removing the endpoint skeleton.
```

## Guardrail

"The asymmetry favors trying" is not a license to ignore irreversible consequences.
If the downside column contains "data breach," "broken SLA," or "regulatory fine,"
the asymmetry does not apply — stop and use `skills/adr` + pre-mortem.
