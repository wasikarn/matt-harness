#!/usr/bin/env bash
# test_symlink-farm.sh — prove F1 still fires when neither symlink nor plugin
# delivery is present. The fixture is a minimal repo with one agent/command/
# hook/output-style/skill that is NOT symlinked into ~/.claude/ and NOT present
# in the (empty) plugin cache. The audit MUST report >=5 CRIT F1s (one per
# kind) — proves the F1 check is alive and not silently disabled.
set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
AUDIT="$REPO_ROOT/skills/harness-audit/scripts/audit.sh"
FIXTURE="$REPO_ROOT/skills/harness-audit/tests/fixtures/symlink-farm-repo"
EMPTY_CACHE="$REPO_ROOT/skills/harness-audit/tests/fixtures/empty-plugin-cache"

if [ ! -f "$AUDIT" ]; then
  echo "FAIL: audit.sh not found at $AUDIT" >&2
  exit 1
fi
if [ ! -d "$FIXTURE" ]; then
  echo "FAIL: fixture not found at $FIXTURE" >&2
  exit 1
fi

out="$(bash "$AUDIT" "$FIXTURE" --plugin-cache "$EMPTY_CACHE" 2>&1)"
crit_n=$(printf '%s\n' "$out" | sed -n 's/^Critical:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
# Assert on the loadability check's MESSAGE, not the positional finding-ID.
# Findings are numbered F1/F2/... in emission order, so the five loadability
# CRITs land on F1..F5 (not five "F1"s) — grep the stable "not loadable" text.
# Total CRIT may include unrelated findings (e.g. command missing 'name:'); we
# scope to the loadability message to keep the test about F1's liveness.
load_n=$(printf '%s\n' "$out" | grep -c "not loadable")

if [ -z "$crit_n" ] || [ -z "$load_n" ]; then
  echo "FAIL: audit did not produce a CRIT summary line" >&2
  printf '%s\n' "$out" | tail -5 >&2
  exit 1
fi
if [ "$load_n" -lt 5 ]; then
  echo "FAIL: expected >=5 'not loadable' CRITs (one per kind), got $load_n" >&2
  printf '%s\n' "$out" | grep "not loadable" >&2
  exit 1
fi

# Also assert each kind fires individually (regression guard — a future edit
# might accidentally skip a kind). Match the kind + loadability message, any ID.
for kind in skill hook agent command "output-style"; do
  if ! printf '%s\n' "$out" | grep -q "${kind} '[^']*' not loadable"; then
    echo "FAIL: expected 'not loadable' CRIT for kind='$kind', not found" >&2
    exit 1
  fi
done

echo "PASS: symlink-farm-repo fires $load_n 'not loadable' CRITs (>=5 expected, all 5 kinds covered)"
exit 0
