#!/usr/bin/env bash
# SessionStart: inject METHODOLOGY.md doctrine into the session context.
# Output goes to stdout → CC injects it as system context for the session.
set -uo pipefail

METHODOLOGY="${CLAUDE_PLUGIN_ROOT:-}/docs/METHODOLOGY.md"

if [[ -f "$METHODOLOGY" ]]; then
  echo "<!-- mh:doctrine-bootstrap -->"
  cat "$METHODOLOGY"
  echo "<!-- /mh:doctrine-bootstrap -->"
fi

# Required-companion-plugin preflight. Several of kbg's own skills, commands,
# and hooks route to mattpocock-skills:<name> by namespaced string with no
# runtime check — if that plugin isn't installed, each call site fails on its
# own, later, as an unrelated-looking dead end with no link back to the real
# cause. One check here, once, turns that into a single diagnostic up front.
#
# Resolution shared with check 51 (#92/T13, scripts/_lib/mattpocock-root.sh):
# highest-semver cache dir + a real-SKILL.md completeness probe, replacing
# this preflight's former bare `-d` directory test (which passed on a
# half-extracted cache — dir present, nothing usable inside it). If the lib
# itself can't be resolved (CLAUDE_PLUGIN_ROOT unset/invalid), skip this
# preflight silently rather than asserting a state the missing resolver
# can't back.
MATTPOCOCK_SETTINGS="${HOME:-}/.claude/settings.json"
MATT_LIB="${CLAUDE_PLUGIN_ROOT:-}/scripts/_lib/mattpocock-root.sh"
if [[ -n "${HOME:-}" && -f "$MATT_LIB" ]]; then
  # shellcheck source=../../scripts/_lib/mattpocock-root.sh
  . "$MATT_LIB"
  if ! resolve_mattpocock_root; then
    echo "<!-- mh:mattpocock-preflight -->"
    echo "**matt-harness:** the required companion plugin \`mattpocock-skills@mattpocock\` was not found installed (or its cache is incomplete). Several kbg skills/commands/hooks route to it by namespaced name (\`mattpocock-skills:<name>\`) and will fail if invoked. Install it: \`/plugin marketplace add mattpocock/skills\` then \`/plugin install mattpocock-skills@mattpocock\` — see README.md Quick Start step 4."
    echo "<!-- /mh:mattpocock-preflight -->"
  elif [[ -f "$MATTPOCOCK_SETTINGS" ]] && grep -q '"mattpocock-skills@mattpocock"[[:space:]]*:[[:space:]]*false' "$MATTPOCOCK_SETTINGS" 2>/dev/null; then
    # Installed (cache resolves) but disabled — resolving successfully would
    # stay silent here while every mattpocock-skills:<name> route still
    # fails, the exact dead-end this preflight exists to prevent.
    echo "<!-- mh:mattpocock-preflight -->"
    echo "**matt-harness:** the required companion plugin \`mattpocock-skills@mattpocock\` is installed but disabled. Several kbg skills/commands/hooks route to it by namespaced name (\`mattpocock-skills:<name>\`) and will fail until it's re-enabled: \`claude plugin enable mattpocock-skills@mattpocock\`."
    echo "<!-- /mh:mattpocock-preflight -->"
  fi
fi
unset MATT_LIB MATT_ROOT MATT_VER

# Dependency preflight (#93): the deny gates fail OPEN (with a per-call stderr
# note) when python3 is missing — announce that once, up front, so the
# degradation is visible at session start instead of being discovered
# mid-destructive-command. jq gates the cost tracker and several nudges the
# same way (they skip themselves silently per-event; this is their one
# announcement).
if ! command -v python3 >/dev/null 2>&1; then
  echo "<!-- mh:portability-preflight -->"
  echo "**matt-harness:** \`python3\` not found on PATH. Every deny gate (rm -rf / --no-verify / verifier-protect / worktree-guard / SQL-write ask / atlassian routing / maker-checker task-completion) is failing open with a stderr note — destructive-command protection is OFF until python3 is installed."
  echo "<!-- /mh:portability-preflight -->"
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "<!-- mh:portability-preflight -->"
  echo "**matt-harness:** \`jq\` not found on PATH. Cost tracking (hooks/stop/cost-tracker.sh) and several advisory nudges will skip themselves this session."
  echo "<!-- /mh:portability-preflight -->"
fi

exit 0
