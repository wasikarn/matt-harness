---
name: handoff
description: Compact the current conversation into a handoff document for the next agent. Use when ending a session. Don't use for end-user updates.
metadata.origin: matt-pocock
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
disable-model-invocation-reason: writes a handoff document to the OS temp dir — the model must not decide to summarize on its own
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

1. verify the handoff doc lets a fresh session resume unaided — confirm it names the current state + the next action.
   If the doc drifts into narrative or omits the next action, the handoff fails: never hand off without a concrete resume point.
