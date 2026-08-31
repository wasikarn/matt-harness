---
name: foo
description: "self-test fixture — bucket is capitalized (Review, not review); check 04 must not false-positive on case alone"
bucket: Review
---

# foo

Fixture body. `bucket: Review` is a case-variant of the valid `review`
bucket, not a real typo — this must stay silent, not WARN.
