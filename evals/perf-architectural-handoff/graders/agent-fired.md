---
type: regex
target: trace
match: not_contains
pattern: "Agent type '[^']*' not found\\. Available agents"
---
The specialized `mh:performance-optimizer` agent actually ran — no "agent type not found"
fallback to a generic agent happened.
