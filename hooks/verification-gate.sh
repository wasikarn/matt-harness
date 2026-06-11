#!/bin/bash
# verification-gate — SessionEnd verification-doctrine sensor (advisory).
#
# Reports the session's `verification_tier` posture from the per-feature trails
# at <project>/.scratch/*/verification-trail.md (schema: docs/agents/verification-trail.md),
# and journals a `verification_summary` event
# (JOURNAL-SCHEMA.md) so Phase 4 has a session-tagged ground-truth feed.
#
# Pure SENSOR: it journals but NEVER emits a permissionDecision — that keeps it on
# the audit side of the gate↔evidence separation (harness-audit #29). Non-blocking:
# always exit 0 so a broken summary never blocks session end (matches
# session-summary.sh). Trails-only by design — journal verdict events are not
# session-scopable (they carry the journaler's hook-id, not the session UUID), so
# this gate reads the trails the model writes, which are the reliable signal.
#
# Bypass (matches session-summary.sh):
#   export CLAUDE_HOOK_PROFILE=off
#   export CLAUDE_DISABLED_HOOKS=verification-gate

set -uo pipefail
export LC_ALL=C

HOOK_ID="verification-gate"
source "$(dirname "$0")/_lib.sh"
hook_init "$HOOK_ID" || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$ROOT/.scratch" ] || exit 0

features=0 tdd=0 analyzer=0 notrail=0 gaps=0
gap_slugs=""

while IFS= read -r f; do
  [ -n "$f" ] || continue
  features=$((features + 1))
  local_tier=$(sed -nE 's/^[[:space:]-]*verification_tier:[[:space:]]*([^[:space:]]+).*/\1/p' "$f" | head -1)
  reason=$(sed -nE 's/^[[:space:]-]*optout_reason:[[:space:]]*(.*)$/\1/p' "$f" | head -1)
  slug=$(basename "$(dirname "$f")")

  # blank reason = empty, or a placeholder (n/a | none | -)
  blank_reason=0
  case "$(printf '%s' "$reason" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    ""|"n/a"|"none"|"-") blank_reason=1 ;;
  esac

  case "$local_tier" in
    tdd-provenance) tdd=$((tdd + 1)) ;;
    analyzer-pass)  analyzer=$((analyzer + 1)) ;;
    no-trail)
      notrail=$((notrail + 1))
      # a no-trail with no named reason is the one fully-reliable verification gap
      if [ "$blank_reason" = 1 ]; then gaps=$((gaps + 1)); gap_slugs="${gap_slugs:+$gap_slugs, }$slug"; fi
      ;;
    *)
      # malformed/undeclared tier — also a gap (the trail exists but says nothing)
      gaps=$((gaps + 1)); gap_slugs="${gap_slugs:+$gap_slugs, }$slug"
      ;;
  esac
done < <(find "$ROOT/.scratch" -maxdepth 2 -type f -name verification-trail.md 2>/dev/null)

# No trails this session = nothing to verify (research/chat sessions are common).
# Stay silent and journal nothing, so the journal does not fill with empty
# summaries at every session end (RUNAWAY noise — governance-summary.py).
[ "$features" -gt 0 ] || exit 0

printf '[%s] session verification: %d feature(s) with a trail — %d tdd-provenance, %d analyzer-pass, %d no-trail.\n' \
  "$HOOK_ID" "$features" "$tdd" "$analyzer" "$notrail"
if [ "$gaps" -gt 0 ]; then
  printf '[%s] ⚠️ %d gap(s) (no-trail without a reason, or undeclared tier): %s.\n' "$HOOK_ID" "$gaps" "$gap_slugs"
fi
printf '[%s] Advisory only — hook hint, not a directive (METHODOLOGY Rule 5). Bypass: CLAUDE_DISABLED_HOOKS=%s\n' \
  "$HOOK_ID" "$HOOK_ID"

# Derive the session's posture — ONE of the "Five Honest Exit Reasons"
# (Production Pipeline corpus: complete / blocked / stalled / degrading / timeout).
# Priority order, first match wins:
#   - gaps > 0     → "degrading"  (no-trail without a reason, or undeclared tier)
#   - features > 0 → "complete"   (trails exist; the gaps branch above already caught the bad case)
#   - features == 0 → unreachable here (we exit 0 above when features==0)
# `blocked` (per-trail status marker) and `timeout` (wall-clock correlation) are
# intentionally deferred — they require out-of-scope trail/status work. The 2-case
# derivation (degrading | complete) covers the most common sessions without
# breaking the contract (the field is additive; the consumer can add the others
# later without a schema break).
if [ "$gaps" -gt 0 ]; then
  exit_reason="degrading"
else
  exit_reason="complete"
fi

# Journal the summary as the Phase-4 ground-truth feed. Run in a subshell so a
# journal_append failure (it exits 2 fail-loud on missing jq / bad mint) cannot
# terminate this SessionEnd hook — its stderr still surfaces, but the gate must
# never block session end. stdout (the minted id) is discarded; this hook's
# stdout is the human-facing advisory above.
fields=$(printf '{"features":%d,"tdd_provenance":%d,"analyzer_pass":%d,"no_trail":%d,"gaps":%d,"exit_reason":"%s"}' \
  "$features" "$tdd" "$analyzer" "$notrail" "$gaps" "$exit_reason")
( journal_append "$HOOK_ID" "verification_summary" "$fields" >/dev/null ) || true

exit 0
