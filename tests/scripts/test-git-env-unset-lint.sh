#!/usr/bin/env bash
# test-git-env-unset-lint.sh — every test that builds a sandbox repo (`git init`) or writes a git
# identity (`config user.name|email`) must clear the GIT_* variables a git hook exports, either with its
# own `unset GIT_...` line or by sourcing tests/_lib/harness.sh (which does). An exported GIT_DIR
# overrides the sandbox's cwd, so a direct run from a hook shell re-targets the real repo and can leave
# `Test <test@example.com>` in its shared config (found 2026-09-29, see test-git-identity-leak.sh, GH #234).
# run-gauntlet.sh already unsets them for its children; this guards every other way of running a test.
set -uo pipefail
HERE="$(cd -P "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
pass=0; fail=0
ok()  { pass=$((pass + 1)); echo "  PASS: $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL: $1" >&2; }

echo "=== tests that create git repos clear GIT_* ==="

checked=0
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  case "$rel" in tests/_lib/harness.sh) ;; tests/_lib/*|tests/scripts/test-git-env-unset-lint.sh) continue ;; esac
  /usr/bin/grep -qE 'git( -[cC] [^ ]+)* init|config user\.(name|email)' "$f" || continue
  checked=$((checked + 1))
  if /usr/bin/grep -q '^unset GIT_' "$f" || /usr/bin/grep -q '^\(source\|\.\) .*_lib/harness\.sh' "$f" \
    || /usr/bin/grep -q 'source "\$.*_lib/harness\.sh"' "$f"; then
    ok "$rel clears GIT_*"
  else
    bad "$rel builds a git sandbox but neither unsets GIT_* nor sources tests/_lib/harness.sh"
  fi
done < <(find "$ROOT/tests" -type f -name '*.sh' | sort)

[ "$checked" -ge 5 ] && ok "lint saw $checked repo-building test files (not vacuous)" \
  || bad "lint saw only $checked repo-building test files; the pattern no longer matches"

echo "=== Summary: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
