---
name: foo
description: "self-test fixture — bucket has trailing whitespace; check 04 must not false-positive on incidental whitespace"
bucket: review 
---

# foo

Fixture body. The `bucket:` line above ends in a trailing space (deliberate
— do not strip it, that defeats the self-test). This must stay silent, not
WARN.
