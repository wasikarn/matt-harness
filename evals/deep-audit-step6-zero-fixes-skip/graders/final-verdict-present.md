---
type: regex
pattern: 'Final Verdict'
match: contains
target: last_message
flags: i
---
Sanity check that the report actually completed and produced a Final Verdict line.
