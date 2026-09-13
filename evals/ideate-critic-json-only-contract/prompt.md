---
name: ideate-critic-json-only-contract
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
  "problem": "Cut our CI pipeline's median wall-clock time in half without reducing test coverage.",
  "ideas": [
    {"id": "i1", "frameId": "infra-eng", "frameLabel": "Infra engineer", "text": "Split the test suite across more parallel shards and cache dependency installs between runs.", "rationale": "infra-eng: throughput via horizontal split"},
    {"id": "i2", "frameId": "compiler-eng", "frameLabel": "Compiler engineer", "text": "Add incremental test selection: only run tests whose transitive dependency graph touches the changed files.", "rationale": "compiler-eng: build-graph thinking"},
    {"id": "i3", "frameId": "product-eng", "frameLabel": "Product engineer", "text": "Move slow end-to-end tests to a nightly run instead of every PR, keep PRs to unit + a smoke subset.", "rationale": "product-eng: optimize for the common case"},
    {"id": "i4", "frameId": "sre", "frameLabel": "SRE", "text": "Move CI to bigger, more expensive runners so each test file finishes faster.", "rationale": "sre: throw more compute at it"},
    {"id": "i5", "frameId": "infra-eng", "frameLabel": "Infra engineer", "text": "Pre-warm a container image with all dependencies baked in instead of installing them each run.", "rationale": "infra-eng: eliminate repeated setup cost"}
  ],
  "options": {"clustersMin": 3, "clustersMax": 6, "topK": 3, "maxDepth": 8}
}
```
