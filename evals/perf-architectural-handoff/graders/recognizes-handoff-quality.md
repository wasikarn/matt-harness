---
type: llm
focus: trace
---
The prompt explicitly rules out parallelization (already tried, hit the vendor's rate limit and
got the API key banned) and the vendor has no batch endpoint. Score 1 if the report explicitly
names the vendor's rate limit as a hard ceiling that no local/client-side change can beat on its
own — even while also shipping a local optimization (e.g. caching), as long as it says plainly that
the local change doesn't remove the ceiling — and asks for an explicit decision on a concrete lever
that follows from that ceiling. The lever does not have to be the vendor-relationship trade-off
specifically (caching staleness, negotiating a higher rate limit/batch endpoint, accepting a
queue/backlog) — an operational lever that's a direct consequence of the same rate-limit
recognition (e.g. how to handle the limit across multiple processes/instances, how much burst
headroom to leave under it) also counts, since it still treats the ceiling as real and asks a human
to decide rather than silently declaring the problem solved. Naming `backend-architect` by name is
not required. Score 0 only if it ships a local change (parallelization, batching, a bigger cache)
while implying that alone now handles the reported production volume, without ever flagging the
rate-limit ceiling as the real, non-local constraint, or without asking for any decision at all.
