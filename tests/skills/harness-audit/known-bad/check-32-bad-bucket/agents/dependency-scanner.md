---
name: dependency-scanner
description: "self-test fixture — name has no reviewer substring, but bucket: review must still trigger the read-only invariant"
bucket: review
tools: Read, Edit
---

# dependency-scanner

Fixture body. The name matches no reviewer/analyzer/... substring, but
`bucket: review` declares it a reviewer anyway. It grants `Edit`, so check 32
must fire CRIT via the bucket-based path, not just the name-substring path.
Do not rename the agent or drop the bucket field — that defeats the self-test.
