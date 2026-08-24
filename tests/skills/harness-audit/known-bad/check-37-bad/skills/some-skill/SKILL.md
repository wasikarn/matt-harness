---
name: some-skill
description: "self-test fixture — cites a dead mh: ref so check 37 must fire WARN"
---

# Some Skill

Fixture body. It cites `mh:nonexistent-skill`, which resolves to no skill in
this fixture fleet (only `some-skill` exists), so check 37 emits a WARN for
doc-rot. Do not add a `nonexistent-skill` dir — that defeats the self-test.
