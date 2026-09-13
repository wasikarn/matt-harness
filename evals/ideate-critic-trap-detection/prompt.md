---
name: ideate-critic-trap-detection
tags: [ideate-critic, planted]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Bash, Read, Agent]
---
Phase 1 (Diverge) of `mh:ideate` already ran on this problem and produced the ideas below. Run
Phase 2 by dispatching the `mh:ideate-critic` agent (via the Agent tool with
`subagent_type: "mh:ideate-critic"`) with this exact JSON envelope as its whole prompt. Relay its
final message back to me verbatim, with nothing added before or after it.

```json
{
  "problem": "Stop our payment webhook handler from double-processing retried deliveries.",
  "ideas": [
    {"id": "i1", "frameId": "db-eng", "frameLabel": "Database engineer", "text": "Add a UNIQUE constraint on event_id in Postgres and INSERT ... ON CONFLICT DO NOTHING before processing.", "rationale": "db-eng: let the constraint be the guard"},
    {"id": "i2", "frameId": "distsys-eng", "frameLabel": "Distributed systems engineer", "text": "Keep an in-process LRU cache of the last few thousand event IDs seen and skip anything already in it before hitting the DB — fast, no extra round trip.", "rationale": "distsys-eng: avoid the DB round trip on the hot path"},
    {"id": "i3", "frameId": "pragmatist", "frameLabel": "Pragmatist", "text": "Make the handler idempotent at the business-logic level: upsert the order by its natural key instead of tracking event IDs at all.", "rationale": "pragmatist: sidestep dedup entirely"},
    {"id": "i4", "frameId": "vendor-integrator", "frameLabel": "Vendor integrator", "text": "Ask the vendor for their Idempotency-Key header and store consumed keys in Redis with a TTL matching their max retry window.", "rationale": "vendor-integrator: use what the vendor already provides"},
    {"id": "i5", "frameId": "ops-eng", "frameLabel": "Ops engineer", "text": "Log every event and run a nightly batch job to find and reconcile duplicates after the fact.", "rationale": "ops-eng: catch it downstream instead of blocking the hot path"}
  ],
  "options": {"clustersMin": 3, "clustersMax": 6, "topK": 3, "maxDepth": 8}
}
```
