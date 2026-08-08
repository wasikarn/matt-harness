#!/usr/bin/env bash
# SessionStart: inject METHODOLOGY.md doctrine into the session context.
# Output goes to stdout → CC injects it as system context for the session.
set -uo pipefail

METHODOLOGY="${CLAUDE_PLUGIN_ROOT:-}/docs/METHODOLOGY.md"

if [[ -f "$METHODOLOGY" ]]; then
  echo "<!-- kbg:doctrine-bootstrap -->"
  cat "$METHODOLOGY"
  echo "<!-- /kbg:doctrine-bootstrap -->"
fi

# Required-companion-plugin preflight. Several of kbg's own skills, commands,
# and hooks route to mattpocock-skills:<name> by namespaced string with no
# runtime check — if that plugin isn't installed, each call site fails on its
# own, later, as an unrelated-looking dead end with no link back to the real
# cause. One check here, once, turns that into a single diagnostic up front.
MATTPOCOCK_CACHE="${HOME:-}/.claude/plugins/cache/mattpocock/mattpocock-skills"
if [[ -n "${HOME:-}" && ! -d "$MATTPOCOCK_CACHE" ]]; then
  echo "<!-- kbg:mattpocock-preflight -->"
  echo "**kbg-harness:** the required companion plugin \`mattpocock-skills@mattpocock\` was not found installed. Several kbg skills/commands/hooks route to it by namespaced name (\`mattpocock-skills:<name>\`) and will fail if invoked. Install it: \`/plugin marketplace add mattpocock/skills\` then \`/plugin install mattpocock-skills@mattpocock\` — see README.md Quick Start step 4."
  echo "<!-- /kbg:mattpocock-preflight -->"
fi

exit 0
