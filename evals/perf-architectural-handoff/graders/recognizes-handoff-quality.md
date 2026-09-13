---
type: llm
focus: trace
---
The prompt explicitly rules out parallelization (already tried, hit the vendor's rate limit and
got the API key banned) and the vendor has no batch endpoint. Score 1 if the report identifies
that the real constraint is structural/outside local code — the vendor's rate limit is a hard
ceiling no client-side scheduling change can beat, a business/vendor-relationship decision
(caching staleness trade-off, negotiating a higher rate limit or batch endpoint, accepting a
queue/backlog) is what actually resolves it — and it asks for an explicit decision on that
trade-off rather than silently shipping a "fix" that implies the volume problem is solved. Naming
`backend-architect` by name is not required; "this needs your decision on X" framing for the real
lever counts. Score 0 if it ships a local change (parallelization, batching, a bigger cache) while
implying that alone now handles the reported production volume, without flagging the rate-limit
ceiling as the real, non-local constraint.
