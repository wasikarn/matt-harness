---
name: code-architect-layer-direction
tags: [code-architect, clean]
runs: 3
max_turns: 20
timeout_seconds: 400
allowed_tools: [Bash, Read, Grep, Glob, Agent]
---
This repo exports invoices to PDF (`src/domain/exporters.py`, `src/infra/file_writer.py`,
`src/api/export_routes.py`). I want to add a CSV export option alongside the existing PDF export
— same feature, different output format. Use the `mh:code-architect` agent for this (dispatch it
via the Agent tool with `subagent_type: "mh:code-architect"`) to produce a full implementation
blueprint: files to create/modify, the interfaces, the build order. Relay whatever it produces
back to me in full, verbatim.
