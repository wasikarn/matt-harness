---
name: foo
description: "self-test fixture — bucket value is YAML-quoted; check 04 must still recognize it"
bucket: "review"
---

# foo

Fixture body. `fm_get` strips the surrounding quotes; this must stay silent.
