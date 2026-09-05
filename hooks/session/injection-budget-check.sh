#!/usr/bin/env bash
# SessionStart: cap total injected context from kbg's own SessionStart hooks.
#
# Scope: doctrine-bootstrap.sh + memory-health-nudge.sh only.
# command-root-anchor.sh writes to $CLAUDE_ENV_FILE, not stdout, so it
# contributes 0 bytes here. Claude Code's
# own native MEMORY.md load is separate and out of scope -- kbg's hooks don't
# control it (#100).
#
# Re-invokes doctrine-bootstrap.sh and memory-health-nudge.sh to measure
# their REAL stdout size rather than a static estimate, which would silently
# drift the moment either script's output logic changes. No shared
# per-session state file fits this -- accepting a real, measured cost instead: on a
# dirty memory store (findings present, the common case -- memory-lint's own
# cache only ever caches a CLEAN result), this doubles memory-health-nudge.sh's
# python3 memory-lint.py scan, measured ~225ms on this repo's live store
# (2026-08-25) on top of that same scan's real registered SessionStart
# invocation -- not negligible, the accepted price of measuring real output
# instead of a static estimate that would silently drift. WARNs, never
# truncates: injected doctrine/advisory text is load-bearing, not safe to
# cut blind.
set -uo pipefail

# 8KB. docs/METHODOLOGY.md is capped at 4KB (injected whole, v1.0.0), which
# leaves headroom for a dirty-memory-store nudge (observed up to ~2.6KB)
# plus preflight messages before warning.
CAP=8192

ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$ROOT" ] || exit 0

DOCTRINE_SCRIPT="$ROOT/hooks/session/doctrine-bootstrap.sh"
NUDGE_SCRIPT="$ROOT/hooks/session/memory-health-nudge.sh"
[ -f "$DOCTRINE_SCRIPT" ] || exit 0
[ -f "$NUDGE_SCRIPT" ] || exit 0

DOCTRINE_OUT=$(bash "$DOCTRINE_SCRIPT" 2>/dev/null)
NUDGE_OUT=$(bash "$NUDGE_SCRIPT" 2>/dev/null)

DOCTRINE_BYTES=$(printf '%s' "$DOCTRINE_OUT" | wc -c | tr -d ' ')
NUDGE_BYTES=$(printf '%s' "$NUDGE_OUT" | wc -c | tr -d ' ')
TOTAL=$((DOCTRINE_BYTES + NUDGE_BYTES))

if [ "$TOTAL" -gt "$CAP" ]; then
  PCT=$((TOTAL * 100 / CAP))
  echo "<!-- mh:injection-budget-check -->"
  echo "[session-budget] OVER-BUDGET: kbg's own SessionStart injection is ${TOTAL}B (${PCT}% of the ${CAP}B cap) -- doctrine-bootstrap.sh (${DOCTRINE_BYTES}B) + memory-health-nudge.sh (${NUDGE_BYTES}B) combined. Does not include Claude Code's own native MEMORY.md load. Trim docs/METHODOLOGY.md or resolve outstanding memory-lint findings to bring this down."
  echo "<!-- /mh:injection-budget-check -->"
fi

exit 0
