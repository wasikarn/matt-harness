#!/bin/bash
# Fixture stub for audit #41 (doctrine gate seam). Carries ONLY the doctrine
# case-glob in the REAL doctrine-edit format — the FULL 8-name set. The sibling
# block-bash stub drops DBGATE, so #41 must flag the seam (and name DBGATE in
# the diff). ponytail: a stub, not a real gate — the audit only reads this line.
case "$BASE" in
  CLAUDE.md|METHODOLOGY.md|RTK.md|ACLI.md|DBGATE.md|settings.json|.mcp.json|mcp-servers.json)
    : ;;
esac
