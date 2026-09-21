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

# Unset/relative HOME: skip silently, same guard as hooks/stop/cost-tracker.sh
# (M8) -- under set -u an unset HOME used to crash this hook on the line below.
if [ -z "${HOME:-}" ] || [[ "$HOME" != /* ]]; then
  exit 0
fi

PHYSPWD="$(pwd -P)"
ENC="${PHYSPWD//\//-}"
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR/.git" ] || exit 0   # not opted in — nothing to do

command -v git >/dev/null 2>&1 || exit 0

# H6 marker path (see below). Resolved before the clean-tree exit so a clean
# store also clears a stale marker: nothing to commit means no failure, e.g.
# after the operator committed by hand (2026-09-21 deep-audit finding).
FAILMARKER="$HOME/.claude/state/memory-audit-commit-fail-$ENC"

# Dirty check first (cheap) — skip the add/commit round-trip when clean.
# One `git status --porcelain` covers unstaged, staged, and untracked in a
# single call (same three states the old diff/diff-cached/ls-files trio
# checked separately). -unormal pins untracked-file reporting on regardless
# of any status.showUntrackedFiles=no set globally or in this repo — the old
# `ls-files --others` path always reported untracked files, so silently
# deferring to that config here would turn this hook into a no-op for new
# memory files on a machine with that setting.
#
# Scoped to '*.md' rather than '.' (repo convention is "stage by explicit
# name, never -A") — this directory's entire designed content is memory .md
# files the assistant writes, so the glob covers everything the hook is
# meant to commit (verified: git's glob pathspec recurses into subdirs like
# _archive/, and also stages deletions of tracked .md files, not just adds).
# A non-.md file dropped here by hand for the user's own reference is never
# swept in.
if [ -z "$(git -C "$MEMDIR" status --porcelain -unormal -- '*.md' 2>/dev/null)" ]; then
  rm -f "$FAILMARKER" 2>/dev/null
  exit 0
fi

# H6 (harness gap-audit, 2026-09-20): both git calls used to redirect stderr
# and never check an exit code -- any commit precondition failing (missing
# user.name, GPG signing unavailable, a stale index.lock from a concurrent
# session on this shared tree) silently stopped versioning the memory store
# forever, with no signal until someone happened to check by hand. Now
# writes a marker file memory-health-nudge.sh surfaces at next SessionStart
# (same "keep firing every session until fixed" posture as its M9 crash
# marker), cleared on the next successful commit.
mkdir -p "$HOME/.claude/state" 2>/dev/null

ADD_ERR=$(git -C "$MEMDIR" add -- '*.md' 2>&1)
ADD_RC=$?
if [ "$ADD_RC" -ne 0 ]; then
  printf 'git add failed (exit %s): %s\n' "$ADD_RC" "$ADD_ERR" > "$FAILMARKER" 2>/dev/null
  exit 0
fi

COMMIT_ERR=$(git -C "$MEMDIR" commit -m "auto-snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet 2>&1)
COMMIT_RC=$?
if [ "$COMMIT_RC" -ne 0 ]; then
  printf 'git commit failed (exit %s): %s\n' "$COMMIT_RC" "$COMMIT_ERR" > "$FAILMARKER" 2>/dev/null
  exit 0
fi

rm -f "$FAILMARKER" 2>/dev/null
exit 0
