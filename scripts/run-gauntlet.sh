#!/usr/bin/env bash
# run-gauntlet.sh — full validation gauntlet, 3 layers in parallel:
#   validate  claude plugin validate . --strict
#   lint      bash -n (+shellcheck if installed) on tracked .sh,
#             py_compile on tracked .py, JSON parse on tracked .json
#   tests     every tests/hooks/*.sh on disk + tests/skills/**/test*.sh
#             + tests/scripts/*.sh + tests/skills/memory-lint python tests
# Wired to git-hooks/pre-push. harness-audit runs in pre-commit, not here.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
LOG="$(mktemp -d)"
trap 'trash "$LOG" 2>/dev/null || true' EXIT

run_validate() { claude plugin validate . --strict; }

existing() { local f; while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done; return 0; }

run_lint() {
  local rc=0 f
  while IFS= read -r f; do
    bash -n "$f" || rc=1
  done < <(git ls-files '*.sh' 'git-hooks/*' | existing)
  if command -v shellcheck >/dev/null; then
    git ls-files '*.sh' 'git-hooks/*' | existing | xargs shellcheck -S warning || rc=1
  fi
  while IFS= read -r f; do
    python3 -m py_compile "$f" || rc=1
  done < <(git ls-files '*.py' | existing)
  while IFS= read -r f; do
    python3 -m json.tool "$f" >/dev/null || { echo "invalid JSON: $f"; rc=1; }
  done < <(git ls-files '*.json' | existing)
  # Whole-tree home-path ban (pre-commit only sees staged blobs).
  if git ls-files | /usr/bin/grep -vE '^(docs/(research|post-mortems|plans)/|CHANGELOG\.md$)' | existing \
       | xargs LC_ALL=C /usr/bin/grep -alE '/Users/[A-Za-z]|-Users-[A-Za-z]' 2>/dev/null \
       | /usr/bin/grep -vE '^(git-hooks/pre-commit|scripts/run-gauntlet\.sh)$'; then
    echo "hardcoded home path in tracked file(s) above"; rc=1
  fi
  return "$rc"
}

run_hook_tests() {
  local rc=0 t
  for t in tests/hooks/*.sh tests/skills/test*.sh tests/skills/*/test*.sh tests/scripts/test*.sh; do
    [ -f "$t" ] || continue
    echo "--- $t"
    bash "$t" 2>&1 || rc=1
  done
  for t in tests/skills/memory-lint/test_*.py; do
    [ -f "$t" ] || continue
    echo "--- $t"
    python3 "$t" 2>&1 || rc=1
  done
  return "$rc"
}

run_validate >"$LOG/validate" 2>&1 & p1=$!
run_lint >"$LOG/lint" 2>&1 & p2=$!
run_hook_tests >"$LOG/tests" 2>&1 & p3=$!

fail=0
report() {
  local name="$1" pid="$2"
  if wait "$pid"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"; fail=1
    tail -n 40 "$LOG/$name" | sed 's/^/      /'
  fi
}
report validate "$p1"
report lint "$p2"
report tests "$p3"
[ "$fail" -eq 0 ] && echo "gauntlet: all layers passed" || echo "gauntlet: FAILED" >&2
exit "$fail"
