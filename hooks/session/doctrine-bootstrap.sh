#!/usr/bin/env bash
# SessionStart: inject docs/METHODOLOGY.md whole into the session context.
# Output goes to stdout → CC injects it as system context for the session.
set -uo pipefail

METHODOLOGY="${CLAUDE_PLUGIN_ROOT:-}/docs/METHODOLOGY.md"

if [[ -f "$METHODOLOGY" ]]; then
  echo "<doctrine>"
  cat "$METHODOLOGY"
  echo "</doctrine>"
fi

# Dependency preflight (#93): the deny gates fail OPEN (with a per-call stderr
# note) when python3 is missing — announce that once, up front, so the
# degradation is visible at session start instead of being discovered
# mid-destructive-command. jq gates the cost tracker the same way (it skips
# itself silently per-event; this is its one announcement).
if ! command -v python3 >/dev/null 2>&1; then
  echo "<!-- mh:portability-preflight -->"
  echo "**matt-harness:** \`python3\` not found on PATH. Every gate (irrecoverable / subagent-git-guard / task-complete-separation / test-integrity / config-write-guard) is failing open with a stderr note — destructive-command protection is OFF until python3 is installed."
  echo "<!-- /mh:portability-preflight -->"
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "<!-- mh:portability-preflight -->"
  echo "**matt-harness:** \`jq\` not found on PATH. Cost tracking (hooks/stop/cost-tracker.sh) will skip itself this session."
  echo "<!-- /mh:portability-preflight -->"
fi

exit 0
