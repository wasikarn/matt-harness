---
name: perf
description: "Performance regressions and bottlenecks. Trigger on latency spikes, throughput drops, memory leaks/growth, CPU saturation, slow queries, cache misses/CI, cold starts, resolver/ETL timeouts, or reported slowness. Don't use for: production outages (kbg:incident/kbg:hotfix), functional bugs without perf symptoms (/fix-bug), architectural redesigns (/deep-dive, code-architect), or capacity planning."
---

# Perf

Performance work is measurement work. If you can't reproduce the numbers, you can't fix them.

**When to use:** Latency spikes, throughput drops, memory growth, CPU saturation, user-reported slowness.

**When NOT to use:** Production outages (service is down or severely degraded — use kbg:incident), architectural redesigns, capacity planning. If users report slowness but the service is still up, this is a performance regression, not an incident.

---

## Procedure

1. **Measure** — Baseline vs current. Reproduce with numbers. Scope: endpoint, query, function, or system-wide?
   - Metrics: latency (p50/p95/p99), throughput, resource (CPU/RAM/disk/network), saturation (queues, pools, contention).

2. **Profile** — Find the hot spot.
   - CPU: `perf`, `py-spy`, `node --prof`, `go tool pprof`
   - Memory: heap dumps, allocation tracking
   - I/O: query logs, network captures
   - Contention: thread dumps, mutex waits
   Output: top 3 hot spots with confidence.
   - Use database-specific tools (`EXPLAIN ANALYZE`, `pg_stat_statements`, etc.) as needed, but don't overfit the skill to one database or runtime.

3. **Hypothesize** — For each hot spot: "What change would make this fast?" Generate 2–4 testable hypotheses. Rank by expected impact × cost.

4. **Validate** — Spike fix in isolation. Measure before/after under identical load. Falsification rule: if the spike does not improve the primary metric by >50%, discard the hypothesis and move to the next. Do not proceed to implementation without a validated hypothesis.

5. **Implement** — Minimal change + regression guard. The guard must be load-bearing: it must fail if the regression recurs. Acceptable forms: benchmark asserting the metric, load test asserting latency/throughput under synthetic load, memory test asserting growth rate, or monitoring alert on the primary metric with a tight threshold. Document trade-offs.

   **Rollback vs Forward Fix decision:**
   - If root cause is identified AND the fix is <1 hour to validate → forward fix.
   - If root cause is unknown OR the fix requires migration / feature flag flip → rollback first, investigate in parallel.

6. **Verify** — Deploy to representative environment (canary, staging with mirrored traffic, or production with 1% traffic). Measure under real load. Check for regressions in other metrics. Monitor 24 hours for standard issues, or 1 week for subtle ones (memory leaks, gradual degradation). Rollback immediately if the primary metric does not improve or if any secondary metric degrades beyond its threshold.

Done.

## Constraints

- Measure first, hypothesize second.
- Profile before optimizing.
- One change at a time.
- Every fix needs a regression guard.
- Know which metric you're optimizing and what you'll trade.

## METHODOLOGY

- **Rule 1:** Phase 1 measurement exists because "optimize" without a number is random motion.
- **Rule 4:** Each phase produces a number or a decision.
- **Rule 10:** Phase 4 validation before Phase 5 implementation.
- **Rule 12:** If fix doesn't improve the metric, rollback.

## Related

- `/diagnose` — issue might be correctness, not performance
- `kbg:incident` — live production incident
- `kbg:hotfix` — fix must ship under incident conditions
- `/fix-bug` — performance issue caused by functional bug
- `/deep-dive` — bottleneck requires architectural redesign

**Named models** (cc-thinking-skills): profile → find the one bottleneck → fix that is *theory-of-constraints*; the ">50% improvement or discard" rule is the *scientific method*'s falsification gate. Catalog: `docs/reference/reasoning-models.md` (absolute path injected each session).
