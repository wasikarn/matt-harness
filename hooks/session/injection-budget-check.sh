#!/usr/bin/env bash
# SessionStart: cap total injected context from kbg's own SessionStart hooks.
#
# Scope: kbg's 3 SessionStart hooks only. command-root-anchor.sh writes to
# $CLAUDE_ENV_FILE, not stdout, so it contributes 0 bytes here. Claude Code's
# own native MEMORY.md load is separate and out of scope -- kbg's hooks don't
# control it (#100).
#
# Re-invokes doctrine-bootstrap.sh and memory-health-nudge.sh to measure
# their REAL stdout size rather than a static estimate, which would silently
# drift the moment either script's output logic changes. No shared
# per-session state file fits this (checked dispatch-single.sh and
# skill-usage-telemetry.sh) -- the extra python3/cat spawn this costs is
# negligible next to the rest of SessionStart. WARNs, never truncates:
# injected doctrine/advisory text is load-bearing, not safe to cut blind.
set -uo pipefail

# 24KB. Measured healthy-session total ~18KB (doctrine-bootstrap.sh dominant
# at ~15.8KB, mostly docs/METHODOLOGY.md's own size) -- this leaves headroom
# for a dirty-memory-store nudge (observed up to ~2.6KB) plus preflight
# messages before warning.
CAP=24576

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
