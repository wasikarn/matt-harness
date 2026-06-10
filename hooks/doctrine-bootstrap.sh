#!/usr/bin/env bash
# doctrine-bootstrap.sh — SessionStart hook (plugin mode only)
#
# Injects always-on doctrine (METHODOLOGY / RTK / ACLI / DBGATE) into the
# session via hookSpecificOutput.additionalContext. This reproduces, for the
# plugin delivery path, what the `@import` chain in claude/CLAUDE.md provides
# in symlink-farm mode.
#
# DOUBLE-LOAD GUARD: during symlink<->plugin coexistence the live
# ~/.claude/CLAUDE.md is still a symlink to claude/CLAUDE.md, which @imports the
# four doctrine files. Injecting here too would load doctrine twice. So if the
# live CLAUDE.md still carries the @import, this hook stays silent. After cutover
# (imports removed or symlink gone) the guard passes and this becomes the sole
# doctrine loader.
#
# Fails safe: any error exits 0 without output — a SessionStart hook must never
# brick a session.
set -euo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || exit 0   # only act when running as an installed plugin

# Coexistence guard — skip if the symlinked CLAUDE.md still imports doctrine.
if grep -qs '@METHODOLOGY.md' "$HOME/.claude/CLAUDE.md"; then
  exit 0
fi

doctrine=""
for name in METHODOLOGY RTK ACLI DBGATE; do
  f="$ROOT/$name.md"
  [ -f "$f" ] || continue
  doctrine+="$(cat "$f")"$'\n\n---\n\n'
done
[ -n "$doctrine" ] || exit 0

# JSON-escape via python3 (already required by other hooks). Bail safe if absent.
ctx="$(printf '%s' "$doctrine" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)" || exit 0
[ -n "$ctx" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$ctx"
