---
name: score-decision
description: "self-test fixture — the safety flag is deliberately OMITTED so check 45 fires CRIT"
---

# Score a Decision

Fixture body. The on-demand-only frontmatter flag is missing on purpose so
the check finds nothing in the first 20 lines and emits a CRIT. Do not add that
flag to this fixture — that defeats the self-test.
