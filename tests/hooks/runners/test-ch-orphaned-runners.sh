#!/usr/bin/env bash
# shellcheck disable=SC1091
source "$(dirname "$0")/test-critical-hooks-lib.sh"
# test-ch-orphaned-runners — wires standalone test runners that NO suite sourced
# into the gate, so they can't rot silently (the exact failure that bit the 2
# harness-audit fixture runners: a runner breaks, nothing notices, the gate stays
# green). Each is run as a SUBPROCESS (they call `exit`), and PASS/FAIL is shared
# with the parent test-critical-hooks.sh that sources this file.
#
# Convention reminder: a `tests/hooks/runners/test-ch-*.sh` file is auto-noticed in
# review (the suite sources every one); a bare `test-*.sh` / `run-tests.sh` is invisible.
# These 10 were the invisible kind — now gated here.
# shellcheck disable=SC2034

echo
echo "--- orphaned test runners (subprocess) ---"
_ORPHAN_REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
for _ot in \
  tests/hooks/runners/test-auto-review-nudge.sh \
  tests/hooks/runners/test-cleanup-bak-ttl.sh \
  tests/hooks/runners/test-nudge.sh \
  tests/hooks/runners/test-review-pr-ledger.sh \
  tests/hooks/runners/test-review-pr-marker.sh \
  tests/hooks/runners/test-trigger-pattern.sh \
  scripts/locks/test-lock-system.sh \
  scripts/mailbox/test-mailbox.sh \
  tests/acli/run-tests.sh \
  tests/memory-lint/run-tests.sh ; do
  _rp="$_ORPHAN_REPO/$_ot"
  _label="${_ot##*/}"
  if [ ! -f "$_rp" ]; then
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "orphan-runner" "$_ot (missing)"
    continue
  fi
  if _ot_out=$(cd "$_ORPHAN_REPO" && bash "$_rp" 2>&1); then
    PASS=$((PASS+1)); printf '  ✅ %-22s %s\n' "orphan-runner" "$_label"
  else
    FAIL=$((FAIL+1)); printf '  ❌ %-22s %s\n' "orphan-runner" "$_label"
    printf '       %s\n' "$_ot_out" | tail -3
  fi
done
