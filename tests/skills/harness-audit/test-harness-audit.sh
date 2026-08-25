#!/usr/bin/env bash
# test-harness-audit.sh — self-test for harness-audit (maker-grades-own-work guard).
#
# The audit's own fragment integrity guard catches LOST checks, not SILENT
# checks. The audit has shipped silent gaps before (v0.35.5 found real ones), so
# this pairs each known-bad fixture with a clean one and asserts the matching
# check FIRES on bad and is SILENT on good. Three checks (Rule 2 — fixtures
# cover the highest-silence-risk checks and prove the self-test mechanism; a
# full fleet-wide fixture suite is speculative):
#   36 — recursive-improve disable-model-invocation flag (CRIT)
#   37 — dead `mh:` reference doc-rot (WARN; exit stays 0 — asserted via the
#        Warnings line, not the exit code)
#   45 — score-decision disable-model-invocation flag (CRIT; added 2026-07-23
#        alongside check 45 itself — the other safety-load-bearing instance of
#        the flag, previously unguarded). Also carries a prose-mention
#        regression fixture (check-45-bad-prose-mention, added the same day
#        by a `compliance-audit` adversarial pass) proving checks 36/45 are
#        frontmatter-scoped, not a raw substring grep.
# (Check numbers above renumbered 2026-08-25, ticket 87, from the pre-cleanup
# 39/40/49/55 — the old numbers this test used before the 8 stubbed checks
# were deleted and the survivors renumbered 1..56.)
set -uo pipefail

HERE="$(cd -P "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../../../skills/meta/harness-audit/scripts/audit.sh"
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

# Check 36 — CRIT must fire when the flag is missing, stay silent when present.
run_check 36 "$FIX/check-36-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-36 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-36 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 36 "$FIX/check-36-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-36 good fixture silent"
else
  bad "check-36 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 37 — WARN must fire on a dead mh: ref, stay silent when it resolves.
run_check 37 "$FIX/check-37-bad"
if [ "$WARN_FOUND" -ge 1 ]; then
  ok "check-37 bad fixture fires WARN (warn=$WARN_FOUND)"
else
  bad "check-37 bad fixture did NOT fire WARN (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 37 "$FIX/check-37-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-37 good fixture silent"
else
  bad "check-37 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Check 45 — CRIT must fire when the flag is missing, stay silent when present.
run_check 45 "$FIX/check-45-bad"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-45 bad fixture fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-45 bad fixture did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi
run_check 45 "$FIX/check-45-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then
  ok "check-45 good fixture silent"
else
  bad "check-45 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"
fi

# Regression test — a `compliance-audit` adversarial pass (2026-07-23) found
# the raw `head -20 | grep -qF` form (checks 36/45's original shape)
# false-negatives when the literal flag string appears only in prose (e.g.
# `description:`) with the real key absent. Both checks were fixed to use
# frontmatter-scoped `fm_get` instead; this fixture proves the fix.
run_check 45 "$FIX/check-45-bad-prose-mention"
if [ "$CRIT_FOUND" -ge 1 ]; then
  ok "check-45 prose-mention regression fixture still fires CRIT (crit=$CRIT_FOUND)"
else
  bad "check-45 prose-mention regression fixture did NOT fire CRIT — the frontmatter-scoping fix has regressed (crit=$CRIT_FOUND warn=$WARN_FOUND)"
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
trash "$FAKE_HOME_NO_CACHE" 2>/dev/null || true
if printf '%s\n' "$CHECK25_OUT" | grep -q "=== Summary"; then
  ok "check-25 survives a \$HOME with no plugin cache (no pipefail abort)"
else
  bad "check-25 aborted before printing a Summary against an empty-cache \$HOME — nullglob regression:
$CHECK25_OUT"
fi

# Check 50 — mattpocock-skills integration refs (A refs resolve / B flag
# claims / C coverage ledger / D gated-ref phrasing). The check reads the
# mattpocock plugin cache from $MH_MATT_CACHE when set (fixture override;
# real runs default to ~/.claude/plugins/cache/mattpocock/mattpocock-skills).
export MH_MATT_CACHE="$FIX/check-50-bad/fake-matt-cache"
run_check 50 "$FIX/check-50-bad"
if [ "$WARN_FOUND" -ge 3 ] && [ "$INFO_FOUND" -ge 2 ]; then
  ok "check-50 bad fixture fires A+B+C WARNs and D INFOs incl. marker-masking regression (warn=$WARN_FOUND info=$INFO_FOUND)"
else
  bad "check-50 bad fixture did NOT fire all sub-checks (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND; need warn>=3 info>=2 — info=1 means the free-text-marker masking regressed)"
fi
# Manifest-drift regression (adversarial finding 2026-08-10): plugin.json's
# skills array in an unrecognized format (object entries) must FAIL CLOSED —
# a parse-blind WARN — never a vacuous sub-check-C pass. Same fixture also
# carries a duplicate ledger row, which must fire its own WARN.
export MH_MATT_CACHE="$FIX/check-50-bad-manifest-drift/fake-matt-cache"
run_check 50 "$FIX/check-50-bad-manifest-drift"
if [ "$WARN_FOUND" -ge 2 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-50 manifest-drift fixture fails closed (parse-blind + duplicate-row WARNs, warn=$WARN_FOUND)"
else
  bad "check-50 manifest-drift fixture did NOT fail closed (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND; need warn>=2 — 0 means sub-check C went vacuously green on a drifted manifest)"
fi
export MH_MATT_CACHE="$FIX/check-50-good/fake-matt-cache"
run_check 50 "$FIX/check-50-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -eq 0 ]; then
  ok "check-50 good fixture silent"
else
  bad "check-50 good fixture not silent (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
# Graceful skip: no mattpocock cache at all → INFO note only, never WARN/CRIT,
# and the run completes (same class of guard as the check-25 nullglob test).
export MH_MATT_CACHE="$FIX/check-50-good/no-such-cache"
run_check 50 "$FIX/check-50-good"
if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ] && [ "$INFO_FOUND" -ge 1 ]; then
  ok "check-50 gracefully skips when no mattpocock cache exists (info=$INFO_FOUND)"
else
  bad "check-50 missing-cache run not a graceful skip (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi
unset MH_MATT_CACHE

# Check 39 — grep -c pipefail-abort regression guard (2026-08-17 bug sweep).
# `_count=$(grep -c ... 2>/dev/null)` with no `|| true` dies under set -e when
# the pattern legitimately has zero matches — the exact doc-rot condition this
# check exists to WARN about, so the crash hides the one case it should catch.
# Same class of guard as the check-25 test above: assert the run completes
# (prints a Summary) instead of aborting mid-source.
FAKE39=$(mktemp -d)
mkdir -p "$FAKE39/skills/workflow/orchestrate" "$FAKE39/docs"
cat > "$FAKE39/skills/workflow/orchestrate/SKILL.md" <<'EOF'
# orchestrate
no matching content in this fixture
EOF
cat > "$FAKE39/docs/common-mistakes.md" <<'EOF'
Self-check: `grep -c "this-pattern-does-not-exist-anywhere" "skills/workflow/orchestrate/SKILL.md"`
EOF
CHECK39_OUT=$(bash "$AUDIT" "$FAKE39" --only 39 2>&1 || true)
trash "$FAKE39" 2>/dev/null || true
if printf '%s\n' "$CHECK39_OUT" | grep -q "=== Summary"; then
  ok "check-39 survives a zero-match self-check pattern (no pipefail abort)"
else
  bad "check-39 aborted before printing a Summary on a zero-match pattern — grep -c/set -e regression:
$CHECK39_OUT"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0