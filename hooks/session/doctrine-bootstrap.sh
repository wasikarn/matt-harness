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
MATTPOCOCK_SETTINGS="${HOME:-}/.claude/settings.json"
if [[ -n "${HOME:-}" && ! -d "$MATTPOCOCK_CACHE" ]]; then
  echo "<!-- kbg:mattpocock-preflight -->"
  echo "**kbg-harness:** the required companion plugin \`mattpocock-skills@mattpocock\` was not found installed. Several kbg skills/commands/hooks route to it by namespaced name (\`mattpocock-skills:<name>\`) and will fail if invoked. Install it: \`/plugin marketplace add mattpocock/skills\` then \`/plugin install mattpocock-skills@mattpocock\` — see README.md Quick Start step 4."
  echo "<!-- /kbg:mattpocock-preflight -->"
elif [[ -n "${HOME:-}" && -f "$MATTPOCOCK_SETTINGS" ]] && grep -q '"mattpocock-skills@mattpocock"[[:space:]]*:[[:space:]]*false' "$MATTPOCOCK_SETTINGS" 2>/dev/null; then
  # Installed (cache dir present) but disabled — a directory-only check would
  # stay silent here while every mattpocock-skills:<name> route still fails,
  # the exact dead-end this preflight exists to prevent.
  echo "<!-- kbg:mattpocock-preflight -->"
  echo "**kbg-harness:** the required companion plugin \`mattpocock-skills@mattpocock\` is installed but disabled. Several kbg skills/commands/hooks route to it by namespaced name (\`mattpocock-skills:<name>\`) and will fail until it's re-enabled: \`claude plugin enable mattpocock-skills@mattpocock\`."
  echo "<!-- /kbg:mattpocock-preflight -->"
fi

exit 0
