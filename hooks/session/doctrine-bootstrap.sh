#!/usr/bin/env bash
# SessionStart: inject METHODOLOGY.md doctrine into the session context.
# Output goes to stdout → CC injects it as system context for the session.
set -uo pipefail

METHODOLOGY="${CLAUDE_PLUGIN_DIR}/docs/METHODOLOGY.md"

if [[ -f "$METHODOLOGY" ]]; then
  echo "<!-- kbg:doctrine-bootstrap -->"
  cat "$METHODOLOGY"
  echo "<!-- /kbg:doctrine-bootstrap -->"
fi

exit 0
