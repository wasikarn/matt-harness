---
name: fermi-estimation
description: Use when you need a number you cannot measure or look up cheaply. Decompose the unknown into estimable factors, multiply through, and report an order-of-magnitude answer with a confidence range. Do not Fermi a value that is one query or one lookup away.
metadata:
  origin: kbg
  reasoning-model: fermi-estimation
  vendored-ref: docs/reference/thinking-skills/skills/thinking-fermi-estimation/SKILL.md
---

# Fermi Estimation

Use for capacity planning, cost estimation, and feasibility checks where
exact measurement would take longer than the decision warrants.

## Stop — look it up first

Before estimating, ask: can I get the real number in under 60 seconds?

- Table row count → `COUNT(*)`
- File size → `ls -lh` or `stat`
- Latency → profile it or read the monitoring dashboard
- Price → check the pricing page
- API rate limit → read the docs

If yes, do that. A measured value is always better than an estimate.

## When to estimate instead

- Sizing a new system before any data exists
- Checking feasibility before committing to instrumentation
- Order-of-magnitude sanity check on a design decision
- Redis / TimescaleDB / queue capacity planning from first principles

## Core workflow

```
1. Clarify  — state the quantity precisely, not vaguely
2. Decompose — Q = F₁ × F₂ × ... × Fₙ  (rate × time, population × fraction, etc.)
3. Estimate  — give each factor a range; use the geometric mean; round to 1 sig fig
4. Multiply  — show the arithmetic, don't hide it
5. Sanity    — does the order of magnitude make sense? would 10× error change the decision?
6. Report    — "~X, within 3–5×" — never false precision
```

## Common decomposition patterns

| Situation | Decomposition |
|-----------|--------------|
| Storage growth | users × data/user/day × retention × replication |
| Queue memory | cameras × events/day × bytes/event |
| API load | DAU × requests/session × sessions/day × peak multiplier / seconds in peak window |
| Cost | resources × unit cost × duration × overhead |

## Example — Redis sorted-set memory for ANPR

```
Q: Can 50 cameras fit in a single Redis instance?

cameras       = 50
events/day    = 100,000 per camera  (plate-reads at peak site)
bytes/event   = ~50  (sorted-set entry: score + member string)
days retained = 1  (sorted sets reset per-day)

Memory = 50 × 100,000 × 50 bytes = 250 MB/day
Redis default maxmemory = 512 MB–16 GB depending on instance

Result: ~250 MB — comfortably within a $50/mo Redis instance.
Decision: no special sharding needed for current fleet size.
```

## Guardrails

- Report a range, not a point: "~250 MB, within 2–3×" not "247.3 MB".
- Every factor you can measure narrows the error — substitute real values when available.
- If factors are correlated (both depend on the same growth assumption), errors amplify instead of canceling. Flag it.
- If the decision is the same across the entire plausible range, skip the estimate and act.
