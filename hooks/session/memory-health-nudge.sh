#!/usr/bin/env bash
# SessionStart: surface memory-lint findings (dangling links, orphans, index
# drift, near-budget) at session start. Advisory only — SessionStart stdout is
# injected session context, never a permissionDecision; silent when clean.
#
# Directory resolution lives in memory-lint.py's own memory_dir(); this hook
# invokes it with no positional path so there is exactly one place that logic
# lives. The pwd-based substitution below is only a cheap pre-check to skip
# spawning python3 when the project has no memory store at all. It must still
# resolve the same physical path os.getcwd() would, so `pwd -P` (not $PWD) is
# required: on macOS /tmp and /var are symlinks into /private/…, and a project
# reached through one of those would silently never match without -P.
set -uo pipefail

# Unset/relative HOME: skip silently, same guard as hooks/stop/cost-tracker.sh
# (M8) -- under set -u an unset HOME used to crash this hook.
if [ -z "${HOME:-}" ] || [[ "$HOME" != /* ]]; then
  exit 0
fi

PHYSPWD="$(pwd -P)"
ENC="${PHYSPWD//\//-}"
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR" ] || exit 0

# H6 (harness gap-audit, 2026-09-20): memory-audit-commit.sh's Stop hook
# writes this marker when git add/commit fails, so the memory store's
# version control silently stops updating. Surfaced here, once per session,
# every session until a later successful commit clears the marker (same
# posture as the M9 crash line below). Runs BEFORE the lint-script/python3
# gates: the Stop hook needs neither to write the marker, so exiting on them
# first used to hide it (2026-09-21 deep-audit finding).
FAILMARKER="$HOME/.claude/state/memory-audit-commit-fail-$ENC"
if [ -f "$FAILMARKER" ]; then
  printf '%s\n' \
    "[memory-lint] the memory store's auto-commit failed and is not currently versioned:" \
    "$(cat "$FAILMARKER" 2>/dev/null)" \
    "Fix the underlying git issue in the memory store, then it will resolve on the next successful commit."
fi

LINT="${CLAUDE_PLUGIN_ROOT:-}/skills/meta/memory-lint/scripts/memory-lint.py"
[ -f "$LINT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# Skip the python3 scan if nothing changed since the last clean run. -maxdepth 1
# matches collect_state()'s non-recursive listdir; _archive/ never feeds the detector.
CACHE="$HOME/.claude/state/memory-lint-cache-$ENC"
mkdir -p "$HOME/.claude/state" 2>/dev/null
if [ -f "$CACHE" ] && [ -z "$(find "$MEMDIR" -maxdepth 1 -type f -newer "$CACHE" 2>/dev/null | head -1)" ]; then
  exit 0
fi

# Exit code = finding count, so only a traceback on stderr means a real crash.
ERRLOG=$(mktemp "${TMPDIR:-/tmp}/kbg-memlint-err.XXXXXX" 2>/dev/null) || ERRLOG=""
CRASHED=0
if [ -n "$ERRLOG" ]; then
  OUT=$(python3 "$LINT" 2>"$ERRLOG")
  if command grep -q '^Traceback' "$ERRLOG" 2>/dev/null; then
    OUT=""
    CRASHED=1
  fi
  rm -f "$ERRLOG" 2>/dev/null
else
  OUT=$(python3 "$LINT" 2>/dev/null) || true
fi

# M9 (harness gap-audit, 2026-09-20): a crash used to fall through this whole
# function silently -- OUT="" never matches the "findings: [1-9]" emit gate
# below, so the operator had no way to tell "clean store" from "the check
# itself broke" across every session until someone happened to run it by
# hand. Surface it once per session (never cached, so it keeps firing until
# fixed, same posture as a real dirty-store finding).
if [ "$CRASHED" -eq 1 ]; then
  printf '%s\n' "[memory-lint] session-start check crashed — memory findings are unknown this session. Run \`mh:memory-lint\` manually to see the real error."
  exit 0
fi

# Cache only a clean, non-crashed run — a dirty store must keep firing every
# session until fixed (regression test in tests/hooks/test-memory-health-nudge.sh).
if ! printf '%s' "$OUT" | command grep -qE 'findings: [1-9]'; then
  touch "$CACHE" 2>/dev/null
fi

# Emit only when "findings: N" has N >= 1.
printf '%s' "$OUT" | command grep -qE 'findings: [1-9]' || exit 0

printf '%s\n' \
  "[memory-lint] The memory store has findings (dangling links / orphans / index drift / near-budget):" \
  "$OUT" \
  "Run \`mh:memory-lint\` for detail, or dispatch a fixer. Advisory only — not a gate."

exit 0
