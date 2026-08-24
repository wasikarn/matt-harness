#!/usr/bin/env bash
# 32. Reasoning-models index drift — STUBBED to a no-op PASS (2026-08-24, ticket 94).
#
# The check's whole premise was diffing the unified 39-model table in
# docs/reference/reasoning-models.md against the vendored thinking-*/SKILL.md
# directories under docs/reference/thinking-skills/skills/. Ticket 94 (spec 75,
# kbg-harness -> matt-harness migration) deleted docs/reference/thinking-skills/
# outright (42-file vendored third-party plugin, operator-only reference
# surface) — there is no longer a local vendored tree to diff the catalog
# against, so the check has nothing left to compare. reasoning-models.md itself
# survives as a pure reference table (kbg surface -> named model), no longer
# claiming to vendor the upstream skill files locally.
#
# The file is kept (with its '# 32.' header intact) because audit.sh's
# split-integrity guard fail-closes on any gap in the 1..N check numbering.
# Closeout ticket 87 deletes the stubs and renumbers the fragments once.
:
