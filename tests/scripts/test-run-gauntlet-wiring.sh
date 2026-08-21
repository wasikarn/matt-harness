#!/usr/bin/env bash
# test-run-gauntlet-wiring.sh — a test file existing on disk with no test
# runner wired to it ships silently broken (2026-08-17 bug sweep:
# tests/skills/compress-docs/test_verify_preserved.py existed but was
# invoked nowhere — no CI, no Makefile, no pytest config, no gauntlet
# reference). Enumerates every test-*.sh / test_*.py / *.test.js file under
# tests/ AND scripts/ from disk (2026-08-22: tiered-pipeline.test.js sat in
# scripts/workflows/ with a .test.js name — doubly invisible to the original
# tests/-only, sh/py-only sweep — and shipped with no runner for a day) and
# asserts each is referenced in run_hook_tests()'s LIVE (non-comment)
# body — a hardcoded name list would only catch regressions on files someone
# remembered to list here; this catches any test file, present or future,
# that ships with no runner (2026-08-17 code-reviewer finding: the first cut
# of this test hardcoded 3 names and only proved itself against the one bug
# that prompted it).
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
REPO_ROOT="$HERE/../.."
GAUNTLET="$REPO_ROOT/scripts/run-gauntlet.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== run-gauntlet wiring self-test ==="

# Strip comment lines first: a wiring reference living only in a comment (or
# a disabled `if`/`fi` block) must not count as "wired".
BODY=$(awk '/^run_hook_tests\(\)/,/^}/' "$GAUNTLET" | grep -v '^[[:space:]]*#')

missing=()
while IFS= read -r f; do
  rel="${f#"$REPO_ROOT/"}"
  printf '%s\n' "$BODY" | grep -qF "$rel" || missing+=("$rel")
done < <(find "$REPO_ROOT/tests" "$REPO_ROOT/scripts" \( -name "test-*.sh" -o -name "test_*.py" -o -name "*.test.js" \) | sort)

if [ "${#missing[@]}" -eq 0 ]; then
  ok "run_hook_tests() wires every test-*.sh / test_*.py / *.test.js file found under tests/ and scripts/"
else
  bad "run_hook_tests() does NOT reference: ${missing[*]} — these ship with no runner"
fi

echo ""
echo "self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
