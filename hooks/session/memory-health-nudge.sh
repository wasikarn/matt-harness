#!/usr/bin/env bash
# SessionStart: surface memory-lint findings (dangling links, orphans, index
# drift, near-budget) at session start.
#
# Restores the surfacing loop dropped in the 2026-06-27 "reset: rebuild from
# scratch" (c452102), which deleted the prior
# hooks/maintenance/memory-lint-check.sh without updating
# skills/memory-lint/SKILL.md — that doc claimed this hook was still running
# for ~6 weeks while it wasn't. See
# docs/research/agent-memory-engineering-2026-08-07.md (proposal A1): 87
# findings had accumulated silently on the live store before this was
# noticed. memory-lint.py itself was never broken — only the loop that makes
# anyone actually run it was gone.
#
# Advisory only. SessionStart stdout becomes injected session context, never
# a permissionDecision (cf. hooks/session/doctrine-bootstrap.sh); silent when
# clean, matching every other nudge in this fleet.
#
# Directory resolution: memory-lint.py's own memory_dir() resolves
# os.getcwd().replace("/", "-") — NOT git toplevel (a prior version of this
# hook used git-toplevel encoding; the current memory-lint.py's own comments
# flag that as a bug — it points at the wrong memory dir whenever CC launches
# from a subdirectory). This script never re-implements that encoding for the
# real lookup — it invokes memory-lint.py with no positional path argument
# and lets it resolve its own directory from the inherited cwd, so there is
# exactly one place that logic lives. The pwd-based substitution below is
# ONLY a cheap pre-check (a bash builtin fork, orders of magnitude cheaper
# than a python3 interpreter spawn) to skip spawning python3 in the common
# case (a project with no memory store at all); it
# does not need to be authoritative — but it must still resolve the same
# physical path os.getcwd() would, so `pwd -P` (not $PWD) is required: on
# macOS, /tmp and /var are symlinks into /private/…, so a project reached
# through one of those would silently never match without -P (confirmed via
# a manual fixture run against /tmp during this hook's own testing).
set -uo pipefail

LINT="${CLAUDE_PLUGIN_ROOT:-}/skills/memory-lint/scripts/memory-lint.py"
[ -f "$LINT" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

PHYSPWD="$(pwd -P)"
ENC="${PHYSPWD//\//-}"
MEMDIR="$HOME/.claude/projects/$ENC/memory"
[ -d "$MEMDIR" ] || exit 0

# Skip the python3 scan if nothing in the store changed since the last run.
CACHE="$HOME/.claude/state/memory-lint-cache-$ENC"
mkdir -p "$HOME/.claude/state" 2>/dev/null
if [ -f "$CACHE" ] && [ -z "$(find "$MEMDIR" -maxdepth 1 -type f -newer "$CACHE" 2>/dev/null | head -1)" ]; then
  exit 0
fi

if OUT=$(python3 "$LINT" 2>/dev/null); then
  touch "$CACHE" 2>/dev/null
else
  # Don't cache a crash as "scanned, nothing to report" — a stale touch here
  # would suppress every subsequent run's rescan (and any real findings)
  # until something in $MEMDIR changes again to bust the cache.
  OUT=""
fi

# memory-lint prints "… | findings: N" — emit only when N ≥ 1 (silent when clean).
printf '%s' "$OUT" | command grep -qE 'findings: [1-9]' || exit 0

printf '%s\n' \
  "[memory-lint] The memory store has findings (dangling links / orphans / index drift / near-budget):" \
  "$OUT" \
  "Run \`kbg:memory-lint\` for detail, or fix inline. Advisory only — not a gate."

# UNINDEXED findings conflate two states: an authoring oversight vs. the fold
# rule's own correct end-state (pointer removed, file kept — see
# skills/memory-lint/SKILL.md "UNINDEXED fold-vs-forgotten triage"). Only pay
# for the extra git-history scan (one `git log -S` per UNINDEXED file) when
# the findings above actually include one, and only speak up when there's a
# genuinely new candidate — folded-confirmed / ambiguous-pre-baseline files
# need no action and would just be noise every time the store changes.
if printf '%s' "$OUT" | command grep -q 'UNINDEXED:'; then
  CLASSIFY=$(python3 "$LINT" --classify-unindexed 2>/dev/null) || true
  NEVER_COUNT=$(printf '%s' "$CLASSIFY" | command grep -oE '^never-indexed \([0-9]+\)' | command grep -oE '[0-9]+')
  if [ -n "$NEVER_COUNT" ] && [ "$NEVER_COUNT" -gt 0 ]; then
    printf '%s\n' \
      "[memory-lint] UNINDEXED triage: $NEVER_COUNT of the UNINDEXED file(s) above look like real candidates (never-indexed, not a prior fold). Run \`memory-lint.py --classify-unindexed\` for the full breakdown before adding anything."
  fi
fi

exit 0
