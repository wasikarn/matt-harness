#!/usr/bin/env bash
# 59. Bounded auto-loop decision script contract — STUBBED to a no-op PASS (2026-08-24, ticket 82).
#
# The check asserted should-continue-loop.sh existed, was invoked by
# review-pr-finish/SKILL.md, and kept its fail-closed field reads (ADR 0009's
# computational continue/stop decision). The review pipeline — the script, the
# skill that invoked it, and the loop itself — was retired in the matt-harness
# migration (spec ticket 75; `mattpocock-skills:code-review` is the review
# surface now), so there is no auto-loop left for the ADR's contract to bind.
#
# The file is kept (with its '# 59.' header intact) because audit.sh's
# split-integrity guard fail-closes on any gap in the 1..N check numbering.
# Closeout ticket 87 deletes the stubs and renumbers the fragments once.
:
