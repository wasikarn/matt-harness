---
type: regex
pattern: 'step 6|whole-picture'
match: contains
target: last_message
flags: i
---
Cheap presence check that the report names the whole-picture/step-6 pass at all, alongside the
llm grader that judges whether the test-fixture coupling was handled correctly.
