#!/usr/bin/env bash
# memory-audit-commit unit tests. Isolates a fake $HOME and a fake project
# cwd so real ~/.claude/projects state is never touched; the hook derives its
# memory dir from `pwd -P` (physical path, slashes -> dashes), same as
# memory-health-nudge.sh and memory-lint.py's own memory_dir().
# Run standalone: bash tests/hooks/test-memory-audit-commit.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/stop/memory-audit-commit.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kbg-memory-audit-commit-test.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

pass=0
fail=0

PROJECT_DIR="$TMP/project"
FAKE_HOME="$TMP/home"
mkdir -p "$PROJECT_DIR" "$FAKE_HOME/.claude/state"

PHYSPWD=$(cd "$PROJECT_DIR" && pwd -P)
ENC="${PHYSPWD//\//-}"
MEMDIR="$FAKE_HOME/.claude/projects/$ENC/memory"
FAILMARKER="$FAKE_HOME/.claude/state/memory-audit-commit-fail-$ENC"

init_memdir() {
  trash "$MEMDIR" 2>/dev/null || true
  mkdir -p "$MEMDIR"
  ( cd "$MEMDIR" && git init -q && git config user.email "t@example.com" && git config user.name "t" )
}

run_hook() {
  ( cd "$PROJECT_DIR" && HOME="$FAKE_HOME" bash "$HOOK" )
}

check() {
  local desc="$1" ok="$2"
  if [ "$ok" -eq 0 ]; then
    echo "  ✅ $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ $desc" >&2
    fail=$((fail + 1))
  fi
}

echo "=== memory-audit-commit hook (Stop) ==="
echo ""

echo "--- baseline: clean commit succeeds, no marker ---"
init_memdir
rm -f "$FAILMARKER"
echo "n/a" > "$MEMDIR/topic.md"
run_hook
ok=1; [ -z "$(git -C "$MEMDIR" status --porcelain)" ] && ok=0
check "dirty .md file gets committed" "$ok"
ok=1; [ ! -f "$FAILMARKER" ] && ok=0
check "no failure marker on a successful commit" "$ok"

echo ""
echo "--- H6 (2026-09-20): a failed git add/commit now writes a marker instead of failing silently ---"
init_memdir
rm -f "$FAILMARKER"
echo "n/a" > "$MEMDIR/topic2.md"
# A stale index.lock deterministically makes git add fail, regardless of
# git version or global config on the host running this test.
touch "$MEMDIR/.git/index.lock"
run_hook
ok=1; [ -f "$FAILMARKER" ] && ok=0
check "git add failure writes the marker" "$ok"
ok=1; command grep -qi "index.lock" "$FAILMARKER" 2>/dev/null && ok=0
check "marker captures the real git stderr" "$ok"
ok=1; [ -n "$(git -C "$MEMDIR" status --porcelain)" ] && ok=0
check "the .md file is still uncommitted after the failure" "$ok"

echo ""
echo "--- marker clears on the next successful commit ---"
rm -f "$MEMDIR/.git/index.lock"
run_hook
ok=1; [ ! -f "$FAILMARKER" ] && ok=0
check "marker is cleared once the commit succeeds" "$ok"
ok=1; [ -z "$(git -C "$MEMDIR" status --porcelain)" ] && ok=0
check "the previously-stuck file is now committed" "$ok"

echo ""
echo "--- untouched behavior: not opted in / clean tree still no-op silently ---"
trash "$MEMDIR" 2>/dev/null || true
rm -f "$FAILMARKER"
OUT=$(run_hook)
ok=1; [ -z "$OUT" ] && ok=0
check "no memory dir at all -> silent no-op" "$ok"
ok=1; [ ! -f "$FAILMARKER" ] && ok=0
check "no marker written when not opted in" "$ok"

init_memdir
OUT=$(run_hook)
ok=1; [ -z "$OUT" ] && ok=0
check "clean tree (nothing to commit) -> silent no-op" "$ok"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
