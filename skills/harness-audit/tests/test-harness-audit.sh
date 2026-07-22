#!/usr/bin/env bash
# test-harness-audit.sh — self-test for harness-audit (maker-grades-own-work guard).
#
# The audit's own fragment integrity guard catches LOST checks, not SILENT
# checks. The audit has shipped silent gaps before (v0.35.5 found real ones), so
# this pairs each known-bad fixture with a clean one and asserts the matching
# check FIRES on bad and is SILENT on good. Three checks (Rule 2 — fixtures
# cover the highest-silence-risk checks and prove the self-test mechanism; a
# full fleet-wide fixture suite is speculative):
#   39 — recursive-improve disable-model-invocation flag (CRIT)
#   40 — dead `kbg:` reference doc-rot (WARN; exit stays 0 — asserted via the
#        Warnings line, not the exit code)
#   49 — score-decision disable-model-invocation flag (CRIT; added 2026-07-23
#        alongside check 49 itself — the other safety-load-bearing instance of
#        the flag, previously unguarded)
set -uo pipefail

HERE="$(cd -P "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../scripts/audit.sh"
FIX="$HERE/known-bad"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  PASS: $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

# run_check <id> <fixture-root>: sets CRIT_FOUND / WARN_FOUND from the audit
# summary lines. Audit may exit non-zero on a CRIT fixture; capture via `|| true`.
CRIT_FOUND=0
WARN_FOUND=0
run_check() {
  local id="$1" root="$2" out c w
  out=$(bash "$AUDIT" "$root" --only "$id" 2>/dev/null || true)
  c=$(printf '%s\n' "$out" | sed -n 's/^Critical: //p')
  w=$(printf '%s\n' "$out" | sed -n 's/^Warnings: //p')
  CRIT_FOUND="${c:-0}"
  WARN_FOUND="${w:-0}"
}

echo "=== harness-audit self-test ==="

# Check 39 — CRIT must fire when the flag is missing, stay silent when present.
run_check 39 "$FIX/check-39-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-39 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-39 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 39 "$FIX/check-39-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-39 good fixture silent"
else
  bad "check-39 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 40 — WARN must fire on a dead kbg: ref, stay silent when it resolves.
run_check 40 "$FIX/check-40-bad"
if [ "$WARN_FOUND" -ge 1 ]; then
  ok "check-40 bad fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-40 bad fixture did NOT fire WARN (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 40 "$FIX/check-40-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-40 good fixture silent"
else
  bad "check-40 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 49 — CRIT must fire when the flag is missing, stay silent when present.
run_check 49 "$FIX/check-49-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-49 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-49 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 49 "$FIX/check-49-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-49 good fixture silent"
else
  bad "check-49 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0