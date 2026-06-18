#!/bin/bash
# Fixture stub for audit #41 (doctrine gate seam). Carries ONLY the
# DOCTRINE_NAMES line in the REAL block-bash format, but DRIFTED on purpose:
# DBGATE is dropped, so this gate protects 7 files while doctrine-edit-gate.sh
# protects 8. audit #41 MUST report the set-drift. ponytail: a stub, not a real
# gate — the audit only reads this one line.
DOCTRINE_NAMES='(CLAUDE|METHODOLOGY|RTK|ACLI)\.md|settings\.json|\.mcp\.json|mcp-servers\.json'
