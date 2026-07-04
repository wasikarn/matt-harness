---
name: latency-critical-systems
description: Diagnosis + design for latency-sensitive systems, realtime dashboards, market data, streaming, queues, caches, HFT-like infra. Use when designing/reviewing/debugging them. Don't use for batch or offline.
metadata:
  origin: ECC
tools: Read, Write, Edit, Bash, Grep, Glob
---

# Latency Critical Systems

Use this skill when the user cares about realtime behavior, hot paths, streaming
freshness, or execution speed. This includes HFT-like infrastructure, but the
skill is engineering-focused. It does not authorize live trading or financial
advice.

## Split The Metrics

Do not collapse everything into "fast." Track:

- p50, p95, and p99 latency;
- throughput;
- freshness age;
- queue depth;
- cache hit rate;
- provider/API response time;
- browser render time;
- correctness under load;
- failure and retry behavior.

## Map The Hot Path

Write the path from user/event to final visible state:

```text
source event -> provider API -> ingest worker -> queue -> cache -> edge route
-> client stream -> browser render -> user-visible state
```

Then measure each segment separately.

## Optimization Order

1. Remove unnecessary round trips.
2. Cache stable reads with freshness metadata — and guard the re-warm: a hot key's TTL expiry triggers a thundering herd where every concurrent miss rebuilds the same value. Gate the recompute with a single-flight lock (`SETNX`/`nx` mutex) so only one request rebuilds, or use probabilistic early refresh (XFetch) to spread rebuilds and shrink the herd without a lock; unguarded cache-aside rots p99 on every TTL tick.
3. Batch small calls and writes.
4. Move compute closer to the data or the user.
5. Split hot and cold paths.
6. Apply backpressure before queues grow unbounded.
7. Use streaming only when it improves freshness or user experience.
8. Add canaries for stale data, degraded providers, and bad cache state.

## Verification

Use live readbacks when a deployed surface exists:

- HTTP timing and response headers;
- provider freshness timestamp;
- queue or job state;
- edge/cache state;
- browser verification for actual UI freshness;
- logs around retries and degraded mode.

For market-data or execution-adjacent paths, also verify orderbook age, VWAP
assumptions, provider status, and kill-switch behavior before calling the path
ready.

## Guardrails

- Do not optimize latency by dropping required validation.
- Do not hide stale data behind fast cache hits.
- Do not claim millisecond behavior from client labels without measurement.
- Do not run live orders, destructive migrations, or customer-impacting deploys
  without an explicit approval gate.
- Keep secrets and private payloads out of logs and benchmark artifacts.
- No per-event allocation in the hot path — per-event closures and object literals become GC pressure under load; at a load spike the GC pause can be the p99 source, not the round-trip. Profile with `--trace-gc` (Node) / the JVM/Go/.NET equivalent before attributing p99 to the network segment.

1. confirm the latency budget holds under realistic load — verify the p99 stays inside the SLO across the canary window.
   If a fix drifts the bottleneck elsewhere or the canary shows degraded providers, avoid declaring victory — never close without a green canary run.
