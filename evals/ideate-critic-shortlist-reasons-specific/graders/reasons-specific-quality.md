---
type: llm
focus: last_message
---
The agent's own contract: `shortlistReasons` must name "the actual reason [an idea] earned its
spot — not a restatement of its score numbers", and `nonObviousPickReason`/`confidence.reason`
carry the same requirement (a judgment call, not a number restated in words). These four ideas are
close enough in appeal that a lazy critic could get away with generic filler. Score 1 if every
`shortlistReasons` entry, `nonObviousPickReason`, and `confidence.reason` makes a substantive,
idea-specific argument (referencing what the idea actually does or what makes it non-obvious/risky)
rather than a generic phrase like "high novelty and viability", "well-rounded idea", "scored well
across all axes", or a bare restatement of the total/score number. Score 0 if one or more of these
reason strings is generic filler that could be copy-pasted onto a different idea without change.
