#!/usr/bin/env bash
# shellcheck disable=SC1091
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-harness-audit-fixtures.sh — wire the two standalone harness-audit
# fixture runners into the gate suite so they cannot rot unobserved.
#
# Both fixtures exercise the F1 loadability check (plugin-repo: silent when a
# component IS plugin-delivered; symlink-farm-repo: fires when it is neither
# symlinked nor cached). They were orphaned — not sourced by any suite — and
# silently broke when finding-IDs became sequential (F1 = "first crit", no
# longer "the symlink check"). Sourcing them here is the regression guard.
#
# Each run-test.sh calls exit, so they are run as SUBPROCESSES (not sourced).
# PASS/FAIL come from the parent suite (this file is sourced by
# test-critical-hooks.sh, sharing its counters).

echo
echo "--- harness-audit fixture runners ---"

_AUDIT_FIXTURES="$(dirname "$0")/../../tests/harness-audit/fixtures"
for _ft in plugin-repo symlink-farm-repo; do
  _rt="$_AUDIT_FIXTURES/$_ft/run-test.sh"
  if [ ! -f "$_rt" ]; then
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit-fixture" "$_ft (run-test.sh missing)"
    continue
  fi
  if _ft_out=$(bash "$_rt" 2>&1); then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "audit-fixture" "$_ft"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "audit-fixture" "$_ft"
    printf '       %s\n' "$_ft_out"
  fi
done
