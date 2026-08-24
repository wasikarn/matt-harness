#!/usr/bin/env bash
# 57. Convergence merge-gate contract — STUBBED to a no-op PASS (2026-08-24, ticket 82).
#
# The check asserted hooks/gates/convergence-merge-gate.sh stayed registered in
# hooks.json and kept its fast-path, `clean` read, and sys.exit(2) deny. The
# gate (and the review-pr state files it read) was retired with the review
# pipeline in the matt-harness migration (spec ticket 75; ship-merge's own
# in-flow gates are the remaining merge-door protection), so both halves of
# the contract are gone by design, not neutered.
#
# The file is kept (with its '# 57.' header intact) because audit.sh's
# split-integrity guard fail-closes on any gap in the 1..N check numbering.
# Closeout ticket 87 deletes the stubs and renumbers the fragments once.
:
