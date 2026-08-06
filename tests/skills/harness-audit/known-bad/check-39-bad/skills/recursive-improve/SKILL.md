---
name: recursive-improve
description: "self-test fixture — the safety flag is deliberately OMITTED so check 39 fires CRIT"
---

# Recursive Improve

Fixture body. The no-model-self-start frontmatter flag is missing on purpose so
the check finds nothing in the first 20 lines and emits a CRIT. Do not add that
flag to this fixture — that defeats the self-test. Note: this body avoids spelling
out the flag's literal key=value form so the grep does not match the prose.