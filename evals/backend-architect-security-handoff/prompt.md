---
name: backend-architect-security-handoff
tags: [backend-architect, planted]
runs: 3
max_turns: 20
timeout_seconds: 400
allowed_tools: [Bash, Read, Grep, Glob, Agent]
---
We're about to launch order search for our support team (`src/search/search_service.py`,
`src/support/routes.py`). Review the overall design before launch — how it fits with the rest of
the order system, the caching approach, anything else that stands out. Use the
`mh:backend-architect` agent for this (dispatch it via the Agent tool with
`subagent_type: "mh:backend-architect"`). Relay whatever it produces back to me in full, verbatim.
