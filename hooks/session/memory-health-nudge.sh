#!/usr/bin/env bash
# SessionStart: surface memory-lint findings (dangling links, orphans, index
# drift, near-budget) at session start. Advisory only — SessionStart stdout is
# injected session context, never a permissionDecision; silent when clean.
#
# Directory resolution lives in scripts/_lib/memory-dir.py -- the resolver
# shared with memory-lint.py and memory-audit-commit.sh, so this precedence
# lives in exactly one place (2026-09-28: previously this hook derived ENC
# from raw `pwd -P`, which resolves to the WRONG, worktree-local directory
# from inside a linked worktree -- the shared resolver keys off
# --git-common-dir instead, which is the same path across every worktree of
# one repo).
set -uo pipefail

# Unset/relative HOME: skip silently, same guard as hooks/stop/cost-tracker.sh
# (M8) -- under set -u an unset HOME used to crash this hook.
if [ -z "${HOME:-}" ] || [[ "$HOME" != /* ]]; then
  exit 0
fi

# H6 (harness gap-audit, 2026-09-20): memory-audit-commit.sh's Stop hook
# writes one such marker per attempt when git add/commit fails (or a lock
# wait times out), so the memory store's version control silently stopping
# is surfaced. Per-attempt, PID-suffixed markers (2026-09-28, worktree-per-
# session support): a single shared marker let one session's own successful
# cleanup silently erase a DIFFERENT, still-in-flight session's diagnostic
# once multiple worktrees could race on this shared store -- glob the whole
# set instead of reading one fixed path. Surfaced every session until a
# later successful commit clears the superseded ones (memory-audit-commit.sh
# only ever deletes a marker strictly older than its own lock-acquisition
# time, never a concurrent one).
#
# The marker glob uses the same ENC the writer names markers with: the shared
# resolver's `--enc` (git-common-dir, autoMemoryDirectory, or
# CLAUDE_CODE_PROJECT_DIR_NAME), so a marker written from any linked worktree
# is found (GH #328; a `pwd -P` ENC missed it there even with python3).
# The marker check must not depend on python3 or CLAUDE_PLUGIN_ROOT (2026-09-21
# deep-audit finding), so without them it falls back to a bash-only `pwd -P`
# ENC: right for a main checkout, it can only under-report from a worktree or
# under autoMemoryDirectory. The lint pass below runs only on the resolver ENC.
ENC=""
_MEMDIR_RESOLVER="${CLAUDE_PLUGIN_ROOT:-}/scripts/_lib/memory-dir.py"
if command -v python3 >/dev/null 2>&1 && [ -r "$_MEMDIR_RESOLVER" ]; then
  ENC="$(python3 "$_MEMDIR_RESOLVER" --enc 2>/dev/null)" || ENC=""
fi
_MARKER_ENC="$ENC"
if [ -z "$_MARKER_ENC" ]; then
  _MARKER_ENC="$(pwd -P)"
  _MARKER_ENC="${_MARKER_ENC//\//-}"
fi
FAILMARKERS=("$HOME"/.claude/state/memory-audit-commit-fail-"$_MARKER_ENC"-*)
if [ -e "${FAILMARKERS[0]}" ]; then
  printf '%s\n' "[memory-lint] the memory store's auto-commit failed and is not currently versioned:"
  for _m in "${FAILMARKERS[@]}"; do
    # Line 1 is the writer's machine-read acquisition_ts= record; keep it out
    # of model context. Pure bash, so this works without grep or python3.
    while IFS= read -r _line || [ -n "$_line" ]; do
      [[ "$_line" == acquisition_ts=* ]] || printf '%s\n' "$_line"
    done < "$_m" 2>/dev/null
  done
  printf '%s\n' "Fix the underlying git issue in the memory store, then it will resolve on the next successful commit."
fi

[ -n "$ENC" ] || exit 0
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR" ] || exit 0

LINT="${CLAUDE_PLUGIN_ROOT:-}/skills/meta/memory-lint/scripts/memory-lint.py"
[ -f "$LINT" ] || exit 0

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
