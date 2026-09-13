---
name: perf-nested-loop-fix
tags: [performance-optimizer, clean]
runs: 3
max_turns: 25
timeout_seconds: 400
allowed_tools: [Bash, Read, Write, Edit, Grep, Glob, Agent]
---
`findDuplicates` in `src/dedupe.js` is a bottleneck when processing large lists — `bench.js`
reproduces it. Use the `mh:performance-optimizer` agent for this (dispatch it via the Agent tool
with `subagent_type: "mh:performance-optimizer"`). Run `node bench.js` before and after the fix so
the reported numbers are real. Relay whatever it produces back to me in full, verbatim.
