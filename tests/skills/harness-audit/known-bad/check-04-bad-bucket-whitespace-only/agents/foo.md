---
name: foo
description: "self-test fixture — bucket value is whitespace-only; must WARN missing, not unrecognized"
bucket:    
---

# foo

Fixture body. `bucket:` above has only trailing spaces after the colon, no
real value (deliberate — do not add one). After trimming this collapses to
empty, so it must fire "missing bucket:", not "unrecognized bucket: '   '".
