# Ideate frames

The 15-frame pool for `mh:ideate` Phase 1. Pick 5 per run; see **Picking
frames** in `skills/ideate/SKILL.md` for the selection rule. The `code` and `design` tags
bias the picker toward engineering vantages for code-shaped problems; the
`wild` tag guarantees range.

Source: upstream `/tmp/adhd-repo/src/frames.ts:16-122`.

| Frame | Tags | Vantage |
|---|---|---|
| **hardware-eyes** | code, wild | Think in latency, memory layout, and physical constraints. Re-ask as a hardware/firmware problem. What does the bus topology, the cache, the timing budget tell you? |
| **regulator** | design, general | Audit for compliance and failure modes. What must be provable, traceable, or refusable here? |
| **ten-year-old** | general, wild | A curious 10-year-old who has never seen software. Naive but unencumbered approaches. Ignore convention. |
| **adversary** | code, design | Hostile competitor or attacker. Approaches that exploit, fail, or sabotage the obvious solution — then invert into ideas. |
| **biology** | code, wild | Transplant a mechanism from biology — immune systems, neural plasticity, cell signaling, evolution, gut flora. Force-fit it. |
| **logistics** | code, design | Steal from logistics: queues, batching, just-in-time, hub-and-spoke, returns, last-mile. Apply literally. |
| **game-design** | design, general | Game designer. What are the loops, rewards, friction, save-states, speedrun tricks? Treat the user/system as a player. |
| **markets** | design, wild | Treat the problem as a market. Buyers, sellers, market-makers. What does an auction, a futures contract, a clearing house look like here? |
| **inversion** | code, design, general | Ask the OPPOSITE question. If goal is X, brainstorm "how would we guarantee NOT-X" — then negate each answer back. |
| **extreme-zero** | code, general | No money, no team, one hour. Crudest version that still does the load-bearing thing. Hacks, hardcoded values, manual loops welcome. |
| **extreme-infinite** | design, wild | Infinite compute, infinite engineers, a decade. What is the maximalist version? What would only be possible at that scale? |
| **remove-assumption** | code, design, wild | Name the thing everyone treats as fixed (framework, database, request/response model, network). Imagine it is gone. What is possible? |
| **speedrunner** | code, wild | Find glitches, skips, out-of-bounds tricks, frame-perfect shortcuts. What is the abusive-but-legal path? |
| **ant-colony** | code, wild | No central planner. Many dumb agents, local rules, pheromone trails. How does the problem solve itself emergently? |
| **ops-3am** | code, design | On-call engineer woken at 3am when this breaks. What design would let you not get paged? Runbook-shaped solution. |
