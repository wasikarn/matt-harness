---
name: perf-cant-measure-refusal
tags: [performance-optimizer, planted]
runs: 3
max_turns: 25
timeout_seconds: 400
allowed_tools: [Bash, Read, Write, Edit, Grep, Glob, Agent]
---
Can you make `computeTotalPrice` in `src/pricing.js` faster? There's no benchmark, test, or
profiling setup anywhere in this repo — just that one file. Use the `mh:performance-optimizer`
agent for this (dispatch it via the Agent tool with `subagent_type: "mh:performance-optimizer"`).
Relay whatever it produces back to me in full, verbatim.
