#!/bin/bash
# SessionStart: memory-lint-check — surface memory-store drift at session start.
#
# The file-based memory store lives OUTSIDE the dotfiles repo
# (~/.claude/projects/<enc>/memory/), so the pre-commit gate that enforces
# harness-audit/shellcheck never covers it. memory-lint was therefore
# manual-invoke only — dangling [[links]] and MEMORY.md load-budget creep
# accumulated silently until someone remembered to run it. This wires the same
# "auto-run the audit at a checkpoint" pattern (cf. pre-commit → harness-audit)
# onto the memory store: run memory-lint each SessionStart, surface ONLY when
# there are findings (silent when clean).
#
# Advisory only — SessionStart cannot block; it injects a hint the model/user
# acts on. Fires for any project that has both a git root and a memory store;
# silently skips everything else (cheap pre-checks before invoking python).
#
# Bypass:
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=memory-lint-check

set -uo pipefail
export LC_ALL=C

HOOK_ID="memory-lint-check"
source "$(dirname "$0")/../_lib.sh"
hook_init "$HOOK_ID" || exit 0
_sensor_heartbeat

# Resolve the current project's memory dir the same way memory-lint.py does:
# git toplevel with '/' → '-', under ~/.claude/projects/<enc>/memory.
CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$ROOT" ] || exit 0
ENC=${ROOT//\//-}
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR" ] || exit 0          # project has no memory store → nothing to lint

# Resolve from repo root (hook lives at <repo>/hooks/maintenance/memory-lint-check.sh)
REPO_ROOT=$(cd -P "$(dirname "$0")/../.." && pwd)
LINT="$REPO_ROOT/skills/memory-lint/scripts/memory-lint.py"
[ -f "$LINT" ] || exit 0            # skill not present in repo → skip
command -v python3 >/dev/null 2>&1 || exit 0

# Skip Python subprocess if no memory file is newer than our last-run sentinel.
CACHE="$HOME/.claude/state/memory-lint-cache"
mkdir -p "$HOME/.claude/state"
if [ -f "$CACHE" ] && [ -z "$(find "$MEMDIR" -maxdepth 1 -type f -newer "$CACHE" 2>/dev/null | head -1)" ]; then
  exit 0
fi

OUT=$(python3 "$LINT" "$MEMDIR" 2>/dev/null) || true
touch "$CACHE"  # stamp after run so next startup skips until a memory file changes

# memory-lint prints "… | findings: N" — emit only when N ≥ 1 (silent when clean).
printf '%s' "$OUT" | command grep -qE 'findings: [1-9]' || exit 0

printf '%s\n' \
  "[memory-lint-check] Memory store has findings (dangling links / orphans / index drift / near-budget):" \
  "$OUT" \
  "Address before they accumulate — invoke the memory-lint skill for detail, or fix inline. Hook hint, not a directive (METHODOLOGY Rule 5)." \
  "Bypass: CLAUDE_DISABLED_HOOKS=memory-lint-check"

exit 0
