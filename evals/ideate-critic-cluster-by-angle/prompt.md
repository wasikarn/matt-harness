---
name: ideate-critic-cluster-by-angle
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
  "problem": "A product page's inventory lookup hits a slow downstream API on every single page view.",
  "ideas": [
    {"id": "i1", "frameId": "perf-eng", "frameLabel": "Performance engineer", "text": "Cache each product's inventory response for 30 seconds in Redis, keyed by product ID.", "rationale": "perf-eng: cache the hot read"},
    {"id": "i2", "frameId": "backend-eng", "frameLabel": "Backend engineer", "text": "Store the inventory API's response in Redis under a per-product-ID key with a 30-second TTL before returning it to the page.", "rationale": "backend-eng: TTL cache keyed by product"},
    {"id": "i3", "frameId": "caching-specialist", "frameLabel": "Caching specialist", "text": "Put a 30-second TTL cache in front of the inventory endpoint, keyed by product ID and backed by Redis, so repeat views within the window skip the downstream call.", "rationale": "caching-specialist: standard read-through cache"},
    {"id": "i4", "frameId": "data-eng", "frameLabel": "Data engineer", "text": "Denormalize the current inventory count directly onto the product row, and keep it updated via an event stream whenever inventory changes upstream — the page never calls the inventory API at all.", "rationale": "data-eng: push-based denormalization instead of pull-based lookup"},
    {"id": "i5", "frameId": "api-eng", "frameLabel": "API engineer", "text": "Batch inventory lookups for every product shown on a page into a single downstream call instead of one call per product.", "rationale": "api-eng: cut the number of calls, not their cost"}
  ],
  "options": {"clustersMin": 3, "clustersMax": 6, "topK": 3, "maxDepth": 8}
}
```
