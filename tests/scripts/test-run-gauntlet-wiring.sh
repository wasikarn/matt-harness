#!/usr/bin/env bash
# test-run-gauntlet-wiring.sh — a test file on disk with no runner ships
# silently broken. hook_test_files() lists the layer's files by glob, so this
# asserts every test-*.sh / test_*.py under tests/ matches one of those globs.
# It runs only that listing function, never a test (running the runner from
# here recurses: a test that runs the gauntlet re-runs itself).
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
GAUNTLET="$ROOT/scripts/run-gauntlet.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== run-gauntlet wiring self-test ==="
body=$(sed -n '/^hook_test_files()/,/^}/p' "$GAUNTLET")
[ -n "$body" ] || { echo "  FAIL: hook_test_files() not found in run-gauntlet.sh" >&2; exit 1; }
ran=$(cd "$ROOT" && bash -c "
  $body
  hook_test_files")

missing=()
while IFS= read -r f; do
  rel="${f#"$ROOT/"}"
  printf '%s\n' "$ran" | /usr/bin/grep -qxF "$rel" || missing+=("$rel")
done < <(find "$ROOT/tests" \( -name "test-*.sh" -o -name "test_*.py" \) | sort)

if [ "${#missing[@]}" -eq 0 ]; then
  ok "hook_test_files() picks up every test-*.sh / test_*.py under tests/"
else
  bad "hook_test_files() does NOT list: ${missing[*]}"
fi
echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
