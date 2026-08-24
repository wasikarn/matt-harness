#!/usr/bin/env bash
# 41. Thinking-skills promotion guard — STUBBED to a no-op PASS (2026-08-24, ticket 94).
#
# The check's whole premise was that no docs/reference/thinking-skills model may
# cross into the auto-discovered skills/ tree without deliberately clearing the
# evaluation-first bar reasoning-models.md documented ("External verification",
# 2026-07-14). Ticket 94 (spec 75, kbg-harness -> matt-harness migration) deleted
# docs/reference/thinking-skills/ outright (42-file vendored third-party plugin,
# operator-only reference surface) — there is no longer a source tree for
# anything to be promoted FROM, so the check has nothing left to verify.
#
# The file is kept (with its '# 41.' header intact) because audit.sh's
# split-integrity guard fail-closes on any gap in the 1..N check numbering.
# Closeout ticket 87 deletes the stubs and renumbers the fragments once.
:
