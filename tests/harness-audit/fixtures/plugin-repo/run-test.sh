#!/usr/bin/env bash
# test_plugin-repo.sh — prove F1 is silent when components ARE plugin-delivered.
# The fixture is a minimal repo (one agent/command/hook/output-style/skill)
# mirrored into a fake plugin cache (`_fake-plugin-cache/`). The audit is run
# with --plugin-cache pointed at that fake cache. The audit MUST report 0
# CRIT F1s — proves the plugin-aware F1 check actually works, not just
# suppressed the check entirely.
set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
AUDIT="$REPO_ROOT/skills/harness-audit/scripts/audit.sh"
FIXTURE="$REPO_ROOT/tests/harness-audit/fixtures/plugin-repo"
FAKE_CACHE="$FIXTURE/_fake-plugin-cache"

if [ ! -f "$AUDIT" ]; then
  echo "FAIL: audit.sh not found at $AUDIT" >&2
  exit 1
fi
if [ ! -d "$FAKE_CACHE" ]; then
  echo "FAIL: fake cache not found at $FAKE_CACHE" >&2
  exit 1
fi

out="$(bash "$AUDIT" "$FIXTURE" --plugin-cache "$FAKE_CACHE" 2>&1)"
crit_n=$(printf '%s\n' "$out" | sed -n 's/^Critical:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
# Assert on the loadability check's MESSAGE, not the positional finding-ID:
# findings are numbered F1/F2/... in emission order, so "CRIT F1" no longer
# means "the symlink/loadability check" — it means "the first crit, whatever it
# was" (an unrelated fixture wart would steal the F1 slot). Grep the stable
# message text instead.
load_n=$(printf '%s\n' "$out" | grep -c "not loadable")

if [ -z "$crit_n" ]; then
  echo "FAIL: audit did not produce a CRIT summary line" >&2
  printf '%s\n' "$out" | tail -5 >&2
  exit 1
fi
if [ "$load_n" -ne 0 ]; then
  echo "FAIL: expected 0 'not loadable' CRITs (plugin-delivered), got $load_n" >&2
  printf '%s\n' "$out" | grep "not loadable" >&2
  exit 1
fi

# Sanity: the plugin-cache context line should fire (proves the cache was
# detected, not just that the F1 count is 0 for some other reason). It is a
# header context line, not a finding — grep the line text, not an INFO tier.
if ! printf '%s\n' "$out" | grep -q "Plugin cache:.*F1 treats plugin-delivered"; then
  echo "FAIL: expected 'Plugin cache:' context line" >&2
  exit 1
fi

echo "PASS: plugin-repo reports 0 F1 CRITs (plugin-cache context line present)"
exit 0
