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
#        the flag, previously unguarded). Also carries a prose-mention
#        regression fixture (check-49-bad-prose-mention, added the same day
#        by a `compliance-audit` adversarial pass) proving checks 39/49 are
#        frontmatter-scoped, not a raw substring grep.
set -uo pipefail

HERE="$(cd -P "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../../../skills/harness-audit/scripts/audit.sh"
FIX="$HERE/known-bad"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  PASS: $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

# run_check <id> <fixture-root>: sets CRIT_FOUND / WARN_FOUND from the audit
# summary lines. Audit may exit non-zero on a CRIT fixture; capture via `|| true`.
CRIT_FOUND=0
WARN_FOUND=0
INFO_FOUND=0
run_check() {
  local id="$1" root="$2" out c w i
  out=$(bash "$AUDIT" "$root" --only "$id" 2>/dev/null || true)
  c=$(printf '%s\n' "$out" | sed -n 's/^Critical: //p')
  w=$(printf '%s\n' "$out" | sed -n 's/^Warnings: //p')
  i=$(printf '%s\n' "$out" | sed -n 's/^Info: *//p')
  CRIT_FOUND="${c:-0}"
  WARN_FOUND="${w:-0}"
  INFO_FOUND="${i:-0}"
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

# Regression test — a `compliance-audit` adversarial pass (2026-07-23) found
# the raw `head -20 | grep -qF` form (checks 39/49's original shape)
# false-negatives when the literal flag string appears only in prose (e.g.
# `description:`) with the real key absent. Both checks were fixed to use
# frontmatter-scoped `fm_get` instead; this fixture proves the fix.
run_check 49 "$FIX/check-49-bad-prose-mention"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-49 prose-mention regression fixture still fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-49 prose-mention regression fixture did NOT fire CRIT — the frontmatter-scoping fix has regressed (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 25 — pipefail-abort regression guard. The plugin-cache glob added
# 2026-08-09 (v0.68.231) once shipped with no directory guard: on a $HOME
# with no ~/.claude/plugins/cache yet, the unmatched multi-level glob failed
# its own `[ -d ]` test and, under `set -euo pipefail` in a sourced check,
# silently aborted the whole audit mid-run (no "=== Summary ===" line at
# all). Fixed with a scoped nullglob toggle; this fixture proves the fix by
# running check 25 in isolation against a $HOME with zero plugin cache dirs
# and asserting the run completes (prints a Summary) instead of aborting.
FAKE_HOME_NO_CACHE=$(mktemp -d)
CHECK25_OUT=$(HOME="$FAKE_HOME_NO_CACHE" bash "$AUDIT" "$HERE/../../.." --only 25 2>&1 || true)
rm -rf "$FAKE_HOME_NO_CACHE"
if printf '%s\n' "$CHECK25_OUT" | grep -q "=== Summary"; then
  ok "check-25 survives a \$HOME with no plugin cache (no pipefail abort)"
else
  bad "check-25 aborted before printing a Summary against an empty-cache \$HOME — nullglob regression:
$CHECK25_OUT"
fi

# Check 55 — mattpocock-skills integration refs (A refs resolve / B flag
# claims / C coverage ledger / D gated-ref phrasing). The check reads the
# mattpocock plugin cache from $KBG_MATT_CACHE when set (fixture override;
# real runs default to ~/.claude/plugins/cache/mattpocock/mattpocock-skills).
export KBG_MATT_CACHE="$FIX/check-55-bad/fake-matt-cache"
run_check 55 "$FIX/check-55-bad"
if [ "$WARN_FOUND" -ge 3 ] && [ "$INFO_FOUND" -ge 1 ]; then
  ok "check-55 bad fixture fires A+B+C WARNs and D INFO (warn=$WARN_FOUND info=$INFO_FOUND)"
else
  bad "check-55 bad fixture did NOT fire all sub-checks (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND; need warn>=3 info>=1)"
fi
export KBG_MATT_CACHE="$FIX/check-55-good/fake-matt-cache"
run_check 55 "$FIX/check-55-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -eq 0 ]; then
  ok "check-55 good fixture silent"
else
  bad "check-55 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
# Graceful skip: no mattpocock cache at all → INFO note only, never WARN/CRIT,
# and the run completes (same class of guard as the check-25 nullglob test).
export KBG_MATT_CACHE="$FIX/check-55-good/no-such-cache"
run_check 55 "$FIX/check-55-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -ge 1 ]; then
  ok "check-55 gracefully skips when no mattpocock cache exists (info=$INFO_FOUND)"
else
  bad "check-55 missing-cache run not a graceful skip (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
unset KBG_MATT_CACHE

echo ""
echo "self-test: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0