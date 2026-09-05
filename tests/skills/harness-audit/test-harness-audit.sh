#!/usr/bin/env bash
# test-harness-audit.sh: self-test for harness-audit (maker-grades-own-work guard).
#
# audit.sh's fragment integrity guard catches LOST checks, not SILENT ones. Each
# known-bad fixture below is paired with a clean one; the matching check must
# FIRE on bad and stay SILENT on good. Covered: 04, 05, 20, 28, 29, plus a
# check-25 run under a $HOME with no plugin cache (pipefail-abort guard).
set -uo pipefail

HERE="$(cd -P "$(dirname "$0")" && pwd)"
AUDIT="$HERE/../../../skills/meta/harness-audit/scripts/audit.sh"
FIX="$HERE/known-bad"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  PASS: $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

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
# expect <id> <fixture> <crit-cond> <warn-cond> <label>: run and assert.
expect_silent() {
  run_check "$1" "$FIX/$2"
  if [ "$CRIT_FOUND" -eq 0 ] && [ "$WARN_FOUND" -eq 0 ]; then ok "check-$1 $2 silent"
  else bad "check-$1 $2 not silent (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}
expect_warn() {
  run_check "$1" "$FIX/$2"
  if [ "$WARN_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then ok "check-$1 $2 fires WARN (warn=$WARN_FOUND)"
  else bad "check-$1 $2 did NOT fire WARN (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}
expect_crit() {
  run_check "$1" "$FIX/$2"
  if [ "$CRIT_FOUND" -ge 1 ]; then ok "check-$1 $2 fires CRIT (crit=$CRIT_FOUND)"
  else bad "check-$1 $2 did NOT fire CRIT (crit=$CRIT_FOUND warn=$WARN_FOUND)"; fi
}

echo "=== harness-audit self-test ==="

# Check 04: agent bucket enum. Typos WARN; case variants, quoting, and trailing
# whitespace are not typos; whitespace-only is "missing", exactly one WARN.
expect_warn   04 check-04-bad-bucket-enum
expect_silent 04 check-04-good-bucket-enum
expect_silent 04 check-04-good-bucket-case-insensitive
expect_silent 04 check-04-good-bucket-trailing-whitespace
expect_silent 04 check-04-good-bucket-quoted
expect_warn   04 check-04-bad-bucket-missing
run_check 04 "$FIX/check-04-bad-bucket-whitespace-only"
if [ "$WARN_FOUND" -eq 1 ]; then
  ok "check-04 bad-bucket-whitespace-only fires exactly 1 WARN (missing, not unrecognized)"
else
  bad "check-04 bad-bucket-whitespace-only fired warn=$WARN_FOUND (want exactly 1)"
fi

# Check 05: trigger-pattern clause. WARN when a routing-length description has
# no "Use when" clause; silent at the desc_len==20 boundary.
expect_warn   05 check-05-bad-no-trigger
expect_silent 05 check-05-good-with-trigger
expect_silent 05 check-05-good-boundary-desc-len-20

# Check 20: description length (>1536 chars WARN) and the duplicate-surface twin.
expect_warn   20 check-20-bad-long-desc
expect_silent 20 check-20-good-short-desc
expect_warn   20 check-20-bad-duplicate-surface
expect_silent 20 check-20-good-duplicate-distinct

# Check 28: strict YAML frontmatter on the bucketed 2-level path.
expect_crit   28 check-28-bad-malformed-yaml
expect_silent 28 check-28-good-valid-yaml

# Check 29: agents/*.md descriptions are scanned; NEVER joins the imperative list.
run_check 29 "$FIX/check-29-bad"
if [ "$INFO_FOUND" -ge 1 ] && [ "$CRIT_FOUND" -eq 0 ]; then
  ok "check-29 bad fixture (NEVER in agent description) fires INFO (info=$INFO_FOUND)"
else
  bad "check-29 bad fixture did NOT fire INFO (crit=$CRIT_FOUND warn=$WARN_FOUND info=$INFO_FOUND)"
fi

# Check 25: must complete (print a Summary) on a $HOME with no plugin cache; an
# unguarded multi-level glob once aborted the whole audit under pipefail.
FAKE_HOME_NO_CACHE=$(mktemp -d)
CHECK25_OUT=$(HOME="$FAKE_HOME_NO_CACHE" bash "$AUDIT" "$HERE/../../.." --only 25 2>&1 || true)
[ -n "$FAKE_HOME_NO_CACHE" ] && trash "$FAKE_HOME_NO_CACHE" 2>/dev/null || true
if printf '%s\n' "$CHECK25_OUT" | grep -q "=== Summary"; then
  ok "check-25 survives a \$HOME with no plugin cache (no pipefail abort)"
else
  bad "check-25 aborted before printing a Summary against an empty-cache \$HOME:
$CHECK25_OUT"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  exit 1
fi
exit 0
