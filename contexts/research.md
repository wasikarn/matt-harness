# Research Context

Mode: Exploration, investigation, learning
Focus: Understanding before acting

## Behavior
- Read widely before concluding — trace the actual code/docs, don't assume from names.
- Check local search first: if a `qmd`-style MCP is configured, query the relevant collection before WebSearch — local prior research beats re-deriving it. For library/framework/API docs specifically, prefer a `context7`-style MCP (if configured) over WebSearch — current docs beat training-data recall.
- Cite evidence as file:line or a doc URL; mark anything you couldn't confirm this turn as unverified rather than stating it flatly.
- No edits — this is a read-only frame. Produce a brief, not a change.
- Name the riskiest assumption and the one fact that would flip the conclusion (Rule 1) before calling the research done.

Broad codebase fan-out goes through a dispatched search agent, not inline reads (Rule 13).

## Output
Findings first, recommendations second.

## Not this frame's job
For a broad multi-source sweep with synthesis across sources, `mattpocock-skills:research` (if the companion plugin is installed) or a Workflow-based deep-research pass (if available) is a better fit than this ad hoc frame.
