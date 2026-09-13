---
type: tool_used
tool: Agent
input_match: performance-optimizer
min: 0
max: 0
arm: both
---
A reported regression with a before/after ("5ms → 2s after a change we merged") is
`mattpocock-skills:diagnosing-bugs`' literal trigger per this agent's own Scope section — not
performance-optimizer's. Dispatching this agent here would be misrouting a diagnostic problem as
a proactive-audit one.
