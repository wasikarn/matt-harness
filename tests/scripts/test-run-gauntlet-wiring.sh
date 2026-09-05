#!/usr/bin/env bash
# test-run-gauntlet-wiring.sh — a test file on disk with no runner ships
# silently broken. run_hook_tests() uses globs, so this asserts every
# test-*.sh / test_*.py under tests/ matches one of those globs by running
# the function with a shim `bash`/`python3` that only records paths.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
GAUNTLET="$ROOT/scripts/run-gauntlet.sh"
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== run-gauntlet wiring self-test ==="
body=$(sed -n '/^run_hook_tests()/,/^}/p' "$GAUNTLET")
ran=$(cd "$ROOT" && bash -c "
  bash() { echo \"\$1\"; }; python3() { echo \"\$1\"; }
  $body
  run_hook_tests" | /usr/bin/grep -v '^---')

missing=()
while IFS= read -r f; do
  rel="${f#"$ROOT/"}"
  printf '%s\n' "$ran" | /usr/bin/grep -qxF "$rel" || missing+=("$rel")
done < <(find "$ROOT/tests" \( -name "test-*.sh" -o -name "test_*.py" \) | sort)

if [ "${#missing[@]}" -eq 0 ]; then
  ok "run_hook_tests() picks up every test-*.sh / test_*.py under tests/"
else
  bad "run_hook_tests() does NOT run: ${missing[*]}"
fi
echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
