---
name: perf-numbers-match-fix
tags: [performance-optimizer, planted]
runs: 3
max_turns: 25
timeout_seconds: 400
allowed_tools: [Bash, Read, Write, Edit, Grep, Glob, Agent]
---
`Leaderboard.currentMin()` in `src/leaderboard.js` re-sorts the whole array on every call —
`bench.js` reproduces the slowdown. Optimize it. Use the `mh:performance-optimizer` agent for this
(dispatch it via the Agent tool with `subagent_type: "mh:performance-optimizer"`). Run
`node bench.js` before and after. Relay whatever it produces back to me in full, verbatim.
