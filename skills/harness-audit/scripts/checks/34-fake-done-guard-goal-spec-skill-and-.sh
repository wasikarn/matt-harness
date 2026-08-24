#!/usr/bin/env bash
# 34. Fake-done guard (ship verifier) — STUBBED to a no-op PASS (2026-08-24, ticket 86).
#
# The check's whole premise was verifying `commands/ship/COMMAND.md` carried a
# verify step (arXiv 2606.09863, "confident closing language" as a false proxy
# for verified completion). `commands/ship/` was deleted in the matt-harness
# migration (spec ticket 75; `mattpocock-skills:implement` is now the
# implementation surface, ending at "Once done, use /code-review... Commit
# your work" — no ship-shaped verify-step contract of its own to check).
#
# The file is kept (with its '# 34.' header intact) because audit.sh's
# split-integrity guard fail-closes on any gap in the 1..N check numbering.
# Closeout ticket 87 deletes the stubs and renumbers the fragments once.
:
