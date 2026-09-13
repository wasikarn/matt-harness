---
type: llm
focus: last_message
---
The request is "give me the files/interfaces/build order for one new endpoint" — a file-by-file
implementation blueprint for a single feature, not a system-level review (API contracts, service
boundaries, data ownership, consistency, caching, reliability across an existing design). Score 1
if the response actually gives a concrete files/interfaces/build-order style answer for the new
endpoint (with or without mentioning `code-architect` by name) rather than producing a
system-level architecture review report (numbered findings on ownership/consistency/reliability,
security-handoff framing, etc.) as if this were a review request. Score 0 if it produces a
system-review-shaped report instead of answering the blueprint question asked.
