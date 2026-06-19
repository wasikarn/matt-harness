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
set -uo pipefail

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || exit 0   # only act when running as an installed plugin

INPUT=$(cat 2>/dev/null || true)
# shellcheck disable=SC2034  # HOOK_ID + SID read by _sensor_heartbeat in _lib.sh (cross-file)
HOOK_ID="doctrine-bootstrap"
# shellcheck disable=SC1090
source "$ROOT/hooks/_lib.sh" 2>/dev/null || true
# shellcheck disable=SC2034
SID=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_id","nosid"))' 2>/dev/null) || SID="nosid"
_sensor_heartbeat 2>/dev/null || true

# Coexistence guard — skip if the symlinked CLAUDE.md still imports doctrine.
# Read once to avoid TOCTOU: the file could change between grep and cat.
CLAUDE_MD_CONTENT=""
if [ -r "$HOME/.claude/CLAUDE.md" ]; then
  CLAUDE_MD_CONTENT=$(cat "$HOME/.claude/CLAUDE.md") || exit 0
fi
if printf '%s' "$CLAUDE_MD_CONTENT" | grep -qs '@METHODOLOGY.md'; then
  exit 0
fi

doctrine=""
for name in METHODOLOGY RTK ACLI DBGATE; do
  f="$ROOT/$name.md"
  [ -f "$f" ] || continue
  doctrine+="$(cat "$f")"$'\n\n---\n\n'
done
[ -n "$doctrine" ] || exit 0

# Runtime-resolved catalog pointer. ${CLAUDE_PLUGIN_ROOT} (here $ROOT) expands ONLY in the
# hook shell — never in skill/command/doctrine prose the model reads (code.claude.com/docs/en/
# plugins-reference § Environment variables). So this is the one place the absolute,
# version-proof cache path can be handed to the model: a bare/relative `docs/...` link in
# injected doctrine resolves against the user's project CWD and breaks when the plugin runs
# in another repo. The path points at the installed plugin copy (cache), not the working tree.
doctrine+="Reasoning-models catalog — the named mental models kbg already applies (honesty caveat: none is a proven accuracy boost; one measurably hurt accuracy). When a task explicitly calls for one of these frames, run Bash cat \"$ROOT/docs/reference/reasoning-models.md\"; do not open it unprompted. The file contains Bash-only recipes because the path variable expands only in shell context. The 39 verbatim-vendored thinking-skill files live under $ROOT/docs/reference/thinking-skills/."$'\n'

# JSON-escape via python3 (already required by other hooks). Bail safe if absent.
ctx="$(printf '%s' "$doctrine" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null)" || exit 0
[ -n "$ctx" ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$ctx"
exit 0
