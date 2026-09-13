---
name: ideate-critic-shortlist-reasons-specific
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
  "problem": "Onboarding a new engineer currently takes 2 weeks before their first PR ships; cut that down.",
  "ideas": [
    {"id": "i1", "frameId": "docs-eng", "frameLabel": "Docs engineer", "text": "Write a single golden-path setup doc that takes a new hire from laptop to running the app locally in under an hour, and keep it tested in CI so it never rots.", "rationale": "docs-eng: one trustworthy doc beats scattered tribal knowledge"},
    {"id": "i2", "frameId": "platform-eng", "frameLabel": "Platform engineer", "text": "Provide a pre-configured cloud dev environment (one click, browser-based) so local setup is never the bottleneck.", "rationale": "platform-eng: remove the environment entirely"},
    {"id": "i3", "frameId": "eng-manager", "frameLabel": "Engineering manager", "text": "Pair every new hire with a dedicated onboarding buddy for their first two weeks who is explicitly freed from other deadlines.", "rationale": "eng-manager: people process, not tooling"},
    {"id": "i4", "frameId": "tech-lead", "frameLabel": "Tech lead", "text": "Curate a list of 3-5 small, well-scoped 'good first issue' tickets per team, refreshed monthly, so new hires always have a real but bounded first task waiting.", "rationale": "tech-lead: remove the search for what to work on"}
  ],
  "options": {"clustersMin": 3, "clustersMax": 6, "topK": 3, "maxDepth": 8}
}
```
