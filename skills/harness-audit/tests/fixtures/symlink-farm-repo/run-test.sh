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
ec=$?
crit_n=$(printf '%s\n' "$out" | sed -n 's/^Critical:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
f1_n=$(printf '%s\n' "$out" | grep -c "CRIT F1")

# Expectation: 5 F1 CRITs (one per kind: agent, command, hook, output-style,
# skill). Total CRIT may include other findings from the audit (e.g. command
# missing 'name:' field, output-style missing name/description) — we only
# assert on F1 count to keep the test scoped to the fix.
if [ -z "$crit_n" ] || [ -z "$f1_n" ]; then
  echo "FAIL: audit did not produce a CRIT summary line" >&2
  printf '%s\n' "$out" | tail -5 >&2
  exit 1
fi
if [ "$f1_n" -lt 5 ]; then
  echo "FAIL: expected >=5 F1 CRITs (one per kind), got $f1_n" >&2
  printf '%s\n' "$out" | grep "CRIT F1" >&2
  exit 1
fi

# Also assert each kind fires individually (regression guard — a future edit
# might accidentally skip a kind).
for kind in skill hook agent command "output-style"; do
  if ! printf '%s\n' "$out" | grep -q "CRIT F1: ${kind} '"; then
    echo "FAIL: expected F1 for kind='$kind', not found" >&2
    exit 1
  fi
done

echo "PASS: symlink-farm-repo fires $f1_n F1 CRITs (>=5 expected, all 5 kinds covered)"
exit 0
