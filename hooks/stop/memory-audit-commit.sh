#!/usr/bin/env bash
# Stop: commit any dirty changes in the current project's memory store to its
# own git history. Restores a real audit trail / rollback path for the
# memory store, which previously had zero version control — see
# docs/research/agent-memory-engineering-2026-08-07.md proposal A4 (verified
# 2026-08-07: `git rev-parse --is-inside-work-tree` failed against the live
# store, confirmed, not assumed).
#
# Fires on Stop (per-turn, not once-per-session) — deliberately more
# frequent than a true "session boundary". `git add`+`commit` is cheap and a
# no-op when the tree is clean, so the extra granularity is a feature (finer
# rollback resolution), not a cost worth avoiding. Mirrors
# hooks/stop/cost-tracker.sh's own async:true wiring so a slow or failing
# git call never blocks turn completion.
#
# Requires the memory dir to ALREADY be a git repo (one-time, user-run
# `git init`) — this hook never runs `git init` itself. Initializing version
# control on a directory outside this repo is a decision the user makes
# once, not something a Stop hook does silently on their real data.
set -uo pipefail

PHYSPWD="$(pwd -P)"
ENC="${PHYSPWD//\//-}"
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR/.git" ] || exit 0   # not opted in — nothing to do

command -v git >/dev/null 2>&1 || exit 0

# Dirty check first (cheap) — skip the add/commit round-trip when clean.
if git -C "$MEMDIR" diff --quiet -- . 2>/dev/null \
  && git -C "$MEMDIR" diff --cached --quiet -- . 2>/dev/null \
  && [ -z "$(git -C "$MEMDIR" ls-files --others --exclude-standard 2>/dev/null)" ]; then
  exit 0
fi

git -C "$MEMDIR" add -A -- . 2>/dev/null
git -C "$MEMDIR" commit -m "auto-snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet 2>/dev/null

exit 0
