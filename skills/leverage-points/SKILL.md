---
name: leverage-points
description: Use when parameter tuning keeps not sticking — rank candidate interventions by Meadows' hierarchy and choose the highest-leverage point you can actually move. Requires the system to be already mapped; use skills/decide probe mode first if it isn't.
metadata:
  origin: kbg
  reasoning-model: leverage-points
  vendored-ref: docs/reference/thinking-skills/skills/thinking-leverage-points/SKILL.md
---

# Leverage Points

Use when you've tuned a parameter multiple times and the problem keeps returning.
That's the signal: you're operating at the wrong level of the system.

## Prerequisite

You must already understand the system's causal structure before ranking
interventions. If you haven't mapped it, use `skills/decide` probe mode
(systems-thinking + feedback-loops) first.

## When to use

- Incremental parameter changes (timeouts, buffer sizes, retry counts) keep not
  solving the problem.
- Choosing between a quick config tweak and a structural fix.
- Picking where to focus engineering effort when multiple interventions are possible.

## When NOT to use

- A single wrong parameter genuinely is the fix (e.g., wrong timeout value) —
  just change it; don't manufacture a structural intervention.
- The decision is one-off with no system behind it.

## The hierarchy (low → high leverage)

| Level | Type | Engineering examples |
|-------|------|----------------------|
| 12 | Constants / parameters | cache TTL, retry count, timeout, rate limit |
| 11 | Buffer sizes | queue depth, connection pool size, batch size |
| 10 | Stock-and-flow structure | queue topology, pipeline stages, data model shape |
| 9 | Delays | async vs sync, materialization lag, replication lag |
| 8 | Balancing feedback loops | circuit breaker, backpressure, rate limiter |
| 7 | Reinforcing feedback loops | viral coefficient, compounding cache hit rate |
| 6 | Information flows | who gets what telemetry, when, at what fidelity |
| 5 | Rules / constraints | API contract, DB schema constraint, auth policy |
| 4 | System goals | what the system optimizes (throughput vs latency vs cost) |
| 3 | Paradigm | the model of the problem the system embeds |

**Heuristic:** if you've changed a parameter three times and the problem returns,
move up at least two levels.

## Workflow

1. **State the symptom** — what keeps not sticking?
2. **Identify current intervention level** — which level have you been tuning?
3. **Scan upward** — what is the highest level you can actually change?
4. **Check for resistance** — higher-leverage points face more organizational or
   technical resistance; confirm it's movable before committing.
5. **Intervene** — change at the highest feasible level, not the easiest.

## Example — ANPR leaderboard accuracy

```
Symptom: leaderboard over-counts by ~2.4×; fix doesn't stick after 3 iterations.

Current interventions (all Level 12):
  - tuned PASS_GAP_SECONDS from 60→30→45
  - adjusted Redis key TTL
  - changed dedup window

Root cause: counting model operates on per-frame events, not sessions (Level 10:
  stock-and-flow — the wrong structural unit is being accumulated).

Highest feasible lever: Level 10 — replace Redis per-frame increment with
  TimescaleDB cagg-backed session counting. One structural change replaces all
  parameter tuning.

Note: plate-read rate (Level 6 — information flow: what data enters the system)
  is even higher-leverage. A 10% improvement in plate detection rate moves every
  downstream metric more than any counting-model fix.
```

## Guardrail

Higher leverage = more resistance and more risk of unintended effects. A paradigm
change that redefines what the system optimizes (Level 4) can break downstream
consumers who depended on the old goal. Use `skills/adr` + pre-mortem for any
intervention at Level 6 or above.
