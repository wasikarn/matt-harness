---
name: ideate-critic-rank-verbatim
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
  "problem": "Reduce the size of our client-side JS bundle without dropping any current feature.",
  "ideas": [
    {"id": "i1", "frameId": "build-eng", "frameLabel": "Build engineer", "text": "Enable route-based code splitting so each page only loads the JS it needs.", "rationale": "build-eng: lazy-load by route"},
    {"id": "i2", "frameId": "lib-author", "frameLabel": "Library author", "text": "Audit dependencies for smaller drop-in replacements of the heaviest packages.", "rationale": "lib-author: swap heavy deps"},
    {"id": "i3", "frameId": "perf-eng", "frameLabel": "Performance engineer", "text": "Turn on tree-shaking and verify no barrel-file imports are defeating it.", "rationale": "perf-eng: eliminate dead code"},
    {"id": "i4", "frameId": "product-eng", "frameLabel": "Product engineer", "text": "Move rarely-used admin-only features behind a separately-loaded chunk.", "rationale": "product-eng: split by usage frequency"}
  ],
  "options": {"clustersMin": 3, "clustersMax": 6, "topK": 2, "maxDepth": 8}
}
```
