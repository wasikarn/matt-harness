---
name: ideate-search
description: "self-test fixture — the safety flag is deliberately OMITTED so check 58 fires CRIT"
---

# ideate search

Fixture body. The disable-model-invocation frontmatter flag is missing on purpose so
check 58 finds it absent and emits a CRIT. Do not add that flag to this fixture —
that defeats the self-test. Note: this body avoids spelling out the flag's literal
key=value form so a substring grep does not match the prose.
