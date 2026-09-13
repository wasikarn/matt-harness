---
name: perf-architectural-handoff
tags: [performance-optimizer, planted]
runs: 3
max_turns: 35
timeout_seconds: 700
allowed_tools: [Bash, Read, Write, Edit, Grep, Glob, Agent]
---
`enrichOrdersWithCurrentPrice` in `src/enrich_orders.js` is too slow at our real order volume
(thousands of orders/minute) — see `bench.js` and `docs/pricing-api.md` for the shape of the
problem. We already tried parallelizing the calls with `Promise.all` last sprint: it blew past the
vendor's 50 req/s rate limit and got our API key temporarily banned, so that's off the table at
our volume. The vendor has no batch endpoint and a contract renegotiation isn't happening this
quarter. Use the `mh:performance-optimizer` agent for this (dispatch it via the Agent tool with
`subagent_type: "mh:performance-optimizer"`). Relay whatever it produces back to me in full,
verbatim.
