---
name: foo
description: "self-test fixture — bucket is a typo of a valid value so check 04 must WARN"
bucket: reveiw
---

# foo

Fixture body. `bucket: reveiw` is a typo of the valid `review` bucket — it
passes the existing non-empty check silently today, which is exactly the gap
this fixture proves. Do not fix the typo — that defeats the self-test.
