#!/usr/bin/env bash
# tests/docs/run-doc-tests.sh — docs-as-tests: the manifest description prose
# counts must match the actual component counts (CLAUDE.md cache-invalidation
# invariant). The plugin.json/marketplace.json descriptions embed prose counts
# ("29 senior-specialist agents", "39 workflow skills", "22 commands",
# "14 lifecycle events"); if a component is added/removed and the count is not
# bumped in BOTH manifests, the plugin cache stale-loads (audit #31.2 catches
# version mismatch, but nothing catches the prose-count drift). The harness
# audit checks component LOADABILITY, not the prose count — this suite closes
# that doc↔code drift gap. Docs-as-tests: a documentation claim that is itself
# verified by a test runner, so doc drift from code fails the gauntlet.
#
# Exit 0 = all doc claims match reality; 1 = drift detected.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }

# Actual component counts (mirror the plugin loader's discovery). skills are
# discovered as skills/<name>/SKILL.md (one per dir, maxdepth 2).
count_agents=$(ls "$ROOT"/agents/*.md 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
count_skills=$(find "$ROOT"/skills -maxdepth 2 -name SKILL.md 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
count_commands=$(ls "$ROOT"/commands/*.md 2>/dev/null | /usr/bin/wc -l | tr -d ' ')
count_events=$(jq '.hooks | keys | length' "$ROOT"/hooks/hooks.json 2>/dev/null)

# The prose counts live in the plugin.json description (marketplace.json carries
# the same text; we check the canonical one — the count-parity between the two
# manifests' VERSION is audit #31.2's job, not here).
desc=$(jq -r '.description' "$ROOT"/.claude-plugin/plugin.json 2>/dev/null)
[ -z "$desc" ] && { no "could not read plugin.json description"; echo "SUITE PASS=$PASS FAIL=$FAIL"; exit 1; }

# Extract the number immediately preceding each known phrase and compare to the
# actual count. Robust to wording changes around the number (only the
# "<n> <phrase>" adjacency is pinned).
claim() { printf '%s' "$desc" | /usr/bin/grep -oE "[0-9]+ $1" | /usr/bin/grep -oE '^[0-9]+' | head -1; }

c_agents=$(claim "senior-specialist agents")
c_skills=$(claim "workflow skills")
c_commands=$(claim "commands")
c_events=$(claim "lifecycle events")

[ "$c_agents" = "$count_agents" ] && ok "agents: desc=$c_agents actual=$count_agents" \
  || no "agents: desc=$c_agents actual=$count_agents — bump \"N senior-specialist agents\" in BOTH manifest descriptions"
[ "$c_skills" = "$count_skills" ] && ok "skills: desc=$c_skills actual=$count_skills" \
  || no "skills: desc=$c_skills actual=$count_skills — bump \"N workflow skills\" in BOTH manifest descriptions"
[ "$c_commands" = "$count_commands" ] && ok "commands: desc=$c_commands actual=$count_commands" \
  || no "commands: desc=$c_commands actual=$count_commands — bump \"N commands\" in BOTH manifest descriptions"
[ "$c_events" = "$count_events" ] && ok "lifecycle-events: desc=$c_events actual=$count_events" \
  || no "lifecycle-events: desc=$c_events actual=$count_events — bump \"N lifecycle events\" in BOTH manifest descriptions"

echo
echo "SUITE PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ] && exit 0 || exit 1