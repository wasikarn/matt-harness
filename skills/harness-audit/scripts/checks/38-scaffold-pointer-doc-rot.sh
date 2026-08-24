#!/usr/bin/env bash
# 38. Scaffold-pointer doc-rot — STUBBED to a no-op PASS (2026-08-24, ticket 79).
#
# The check's whole premise was parsing skills/decide/SKILL.md's `## Mode: <word>`
# headings to validate that citations like `kbg:decide <word> mode` in the doctrine
# docs resolved to a real mode. skills/decide was deleted in the matt-harness
# migration (spec ticket 75; `mattpocock-skills:grilling` is now the adversarial
# pressure-testing surface), so every surviving mode citation would WARN as
# unresolvable — the citations themselves were swept in the same ticket.
#
# The file is kept (with its '# 38.' header intact) because audit.sh's
# split-integrity guard fail-closes on any gap in the 1..N check numbering.
# Closeout ticket 87 deletes the stubs and renumbers the fragments once.
:
