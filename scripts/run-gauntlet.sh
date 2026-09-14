#!/usr/bin/env bash
# run-gauntlet.sh — full validation gauntlet, 3 layers in parallel:
#   validate  claude plugin validate . --strict (marketplace.json) +
#             claude plugin validate .claude-plugin/plugin.json (plugin manifest —
#             `.` alone resolves to marketplace.json when both files sit in the
#             same .claude-plugin/, confirmed via --json's "target" field
#             2026-09-14, so plugin.json was never actually checked before this;
#             --strict is dropped here only because it would fail on a single
#             known-benign warning, "CLAUDE.md not loaded as project context" —
#             true and intentional, since METHODOLOGY.md is what ships via hooks)
#   lint      bash -n (+shellcheck if installed) on tracked .sh,
#             py_compile on tracked .py, JSON parse on tracked .json
#   tests     every tests/hooks/*.sh on disk + tests/skills/**/test*.sh
#             + tests/scripts/*.sh + tests/evals/*.sh + tests/skills/memory-lint python tests
# Wired to git-hooks/pre-push. harness-audit runs in pre-commit, not here.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
# Fixture tests below git-init/commit inside temp dirs. A caller invoking us
# as a git hook (pre-push, esp. from a linked worktree) has GIT_DIR etc. set
# in its env, which hijacks those git-init calls onto the real repo instead
# of the fixture dir. Clear them before the test layer runs.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
LOG="$(mktemp -d)"
trap 'trash "$LOG" 2>/dev/null || true' EXIT

run_validate() {
  claude plugin validate . --strict &&
  claude plugin validate .claude-plugin/plugin.json
}

existing() { local f; while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done; return 0; }

# Syntax layers skip the audit's known-bad fixtures, invalid on purpose (same rule as pre-commit).
lintable() { git ls-files "$@" ':(exclude)tests/skills/harness-audit/known-bad' | existing; }

run_lint() {
  local rc=0 f
  while IFS= read -r f; do
    bash -n "$f" || rc=1
  done < <(lintable '*.sh' 'git-hooks/*')
  if command -v shellcheck >/dev/null; then
    lintable '*.sh' 'git-hooks/*' | xargs shellcheck -S warning || rc=1
  fi
  while IFS= read -r f; do
    python3 -m py_compile "$f" || rc=1
  done < <(lintable '*.py')
  while IFS= read -r f; do
    python3 -m json.tool "$f" >/dev/null || { echo "invalid JSON: $f"; rc=1; }
  done < <(lintable '*.json')
  # Whole-tree home-path ban (pre-commit only sees staged blobs).
  # Env goes on xargs, not after it: BSD xargs treats `LC_ALL=C` as the command (exit 127,
  # once swallowed by 2>/dev/null). Hits are captured because xargs exits 123 on any batch
  # where grep found nothing, which an `if` on the pipeline would read as a miss.
  home_hits=$(git ls-files | /usr/bin/grep -vE '^(docs/(research|post-mortems|plans)/|CHANGELOG\.md$)' | existing \
       | LC_ALL=C xargs /usr/bin/grep -alE '/Users/[A-Za-z]|-Users-[A-Za-z]' 2>/dev/null || true)
  if [ -n "$home_hits" ]; then
    printf '%s\n' "$home_hits"; echo "hardcoded home path in tracked file(s) above"; rc=1
  fi
  return "$rc"
}

run_hook_tests() {
  local rc=0 t
  # Redirect the gate-verdict journal for the whole hook-test layer: several
  # suites (test-gates.sh alone has 165 deny/ask assertions) exercise gates
  # whose journal() call writes to $HOME/.local/share/kbg/metrics/
  # gate-decisions.jsonl by default. Without this, every local
  # run-gauntlet.sh/pre-push would silently append synthetic rows to the
  # operator's real journal, corrupting the analytics it exists to produce.
  # MH_GATE_JOURNAL_PATH is a narrow override (hooks/gates/_journal.py),
  # deliberately NOT a full HOME swap: an earlier version of this fix
  # exported a throwaway HOME for the whole test layer and broke
  # PyYAML-dependent tests (test-ste-lint.sh, harness-audit's YAML checks) --
  # PyYAML is resolved via the real $HOME's user site-packages, so replacing
  # HOME wholesale has far more blast radius than this one write path needs.
  local JOURNAL_TMP
  JOURNAL_TMP="$(mktemp -d)"
  trap 'trash "$JOURNAL_TMP" 2>/dev/null || true' RETURN
  export MH_GATE_JOURNAL_PATH="$JOURNAL_TMP/gate-decisions.jsonl"
  for t in tests/hooks/*.sh tests/skills/test*.sh tests/skills/*/test*.sh tests/scripts/test*.sh tests/evals/test*.sh; do
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
