#!/usr/bin/env bash
# test-observer-contract.sh — GH #443: scripts/check-observer-contract.sh passes the real
# hooks/mod/cost-ledger.ts and fails a known-bad module (extra hooks, $.ui.ask, a deny, a rewrite),
# naming each violation. Runs the real `claude plugin validate`; without the CLI only the static
# layer runs, and the hook/call rows are skipped.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
CHECK="$ROOT/scripts/check-observer-contract.sh"
BAD="$HERE/fixtures/observer-contract/bad"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== observer contract on hooks/mod/cost-ledger.ts ==="
out="$(bash "$CHECK" "$ROOT" 2>&1)" && ok "the real module passes" || bad "the real module failed: $out"

out="$(bash "$CHECK" "$BAD" 2>&1)" && bad "the known-bad module passed" || ok "the known-bad module fails"
expect() { case "$out" in *"$1"*) ok "names: $1" ;; *) bad "missing '$1' in: $out" ;; esac; }
expect "deny/ask/rewrite in source:"
expect "deny:"
expect "next({"
if command -v claude >/dev/null; then
  expect "registers tool.call{tool=Bash}"
  expect "registers prompt.submit"
  expect "calls \$.ui.ask"
else
  echo "  SKIP: hook/call rows (no claude CLI)"
fi

echo "  ($pass passed, $fail failed)"
[ "$fail" -eq 0 ]
