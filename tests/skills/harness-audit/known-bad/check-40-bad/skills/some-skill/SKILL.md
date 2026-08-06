---
name: some-skill
description: "self-test fixture — cites a dead kbg: ref so check 40 must fire WARN"
---

# Some Skill

Fixture body. It cites `kbg:nonexistent-skill`, which resolves to no skill in
this fixture fleet (only `some-skill` exists), so check 40 emits a WARN for
doc-rot. Do not add a `nonexistent-skill` dir — that defeats the self-test.