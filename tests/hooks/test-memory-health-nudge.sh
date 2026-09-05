#!/usr/bin/env bash
# memory-health-nudge unit tests. Isolates a fake $HOME and a fake project
# cwd so real ~/.claude/projects state is never touched; the hook derives its memory dir from `pwd -P` (physical path,
# slashes -> dashes) the same way memory-lint.py's own memory_dir() does, so
# fixtures must be planted at that exact computed path.
# Run standalone: bash tests/hooks/test-memory-health-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/memory-health-nudge.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kbg-memory-health-nudge-test.XXXXXX")
trap 'trash "$TMP" 2>/dev/null || true' EXIT

pass=0
fail=0

PROJECT_DIR="$TMP/project"
FAKE_HOME="$TMP/home"
mkdir -p "$PROJECT_DIR" "$FAKE_HOME/.claude/state"

PHYSPWD=$(cd "$PROJECT_DIR" && pwd -P)
ENC="${PHYSPWD//\//-}"
MEMDIR="$FAKE_HOME/.claude/projects/$ENC/memory"

init_memdir() {
  trash "$MEMDIR" 2>/dev/null || true
  mkdir -p "$MEMDIR"
}

write_memory() {
  local filename="$1" description="$2"
  cat > "$MEMDIR/$filename" <<EOF
---
name: ${filename%.md}
description: "$description"
metadata:
  type: project
---
n/a
EOF
}

run_hook() {
  # Clear the mtime-based skip-cache before every call so each scenario runs
  # for real, rather than depending on fixture writes landing in a later
  # mtime tick than the previous call's cache touch.
  rm -f "$FAKE_HOME/.claude/state"/memory-lint-cache-* 2>/dev/null
  ( cd "$PROJECT_DIR" && CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$FAKE_HOME" bash "$HOOK" )
}

run_hook_no_cache_clear() {
  # Deliberately does NOT clear the cache first — for testing what happens
  # across consecutive "sessions" against the same unmodified store, which
  # is the exact scenario the cache-persistence regression test below needs.
  ( cd "$PROJECT_DIR" && CLAUDE_PLUGIN_ROOT="$ROOT" HOME="$FAKE_HOME" bash "$HOOK" )
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | command grep -qF "$needle"; then
    echo "  ✅ CONTAINS \"$needle\": $desc"
    pass=$((pass + 1))
  else
    echo "  ❌ EXPECTED \"$needle\" in output but it was absent: $desc" >&2
    echo "     --- output ---" >&2
    printf '%s\n' "$haystack" | sed 's/^/     /' >&2
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | command grep -qF "$needle"; then
    echo "  ❌ UNEXPECTED \"$needle\" in output: $desc" >&2
    echo "     --- output ---" >&2
    printf '%s\n' "$haystack" | sed 's/^/     /' >&2
    fail=$((fail + 1))
  else
    echo "  ✅ ABSENT \"$needle\": $desc"
    pass=$((pass + 1))
  fi
}

echo "=== memory-health-nudge hook (SessionStart) ==="
echo ""

echo "--- baseline behavior ---"

init_memdir
# A lone unlinked memory trips the ORPHAN check by itself — cross-link two
# files so the store is genuinely clean (0 findings), not just index-clean.
cat > "$MEMDIR/topic-a.md" <<'EOF'
---
name: topic-a
description: "a fully indexed topic"
metadata:
  type: project
---
see [[topic-b]]
EOF
cat > "$MEMDIR/topic-b.md" <<'EOF'
---
name: topic-b
description: "another fully indexed topic"
metadata:
  type: project
---
see [[topic-a]]
EOF
printf '%s\n' \
  "- [topic-a](topic-a.md) — a fully indexed topic" \
  "- [topic-b](topic-b.md) — another fully indexed topic" > "$MEMDIR/MEMORY.md"
OUT=$(run_hook)
assert_not_contains "clean store stays fully silent" "[memory-lint]" "$OUT"

trash "$FAKE_HOME/.claude/projects" 2>/dev/null || true
OUT=$(run_hook)
assert_not_contains "no memory dir at all stays silent" "[memory-lint]" "$OUT"

echo ""
echo "--- UNINDEXED findings surface raw, no triage line ---"

init_memdir
write_memory "topic-a.md" "a fully indexed topic"
printf '%s\n' \
  "- [topic-a](topic-a.md) — a fully indexed topic" \
  "see [[missing-thing]] for more" > "$MEMDIR/MEMORY.md"
OUT=$(run_hook)
assert_contains "dangling link fires the main block" \
  "[memory-lint] The memory store has findings" "$OUT"

init_memdir
write_memory "plain-target.md" "unindexed and unreachable"
: > "$MEMDIR/MEMORY.md"
OUT=$(run_hook)
assert_contains "raw UNINDEXED finding surfaces" \
  "UNINDEXED: plain-target.md" "$OUT"
assert_not_contains "no triage line (triage mode removed)" \
  "UNINDEXED triage" "$OUT"

echo ""
echo "--- cache persistence: a dirty store keeps firing across sessions, a clean one doesn't ---"

init_memdir
rm -f "$FAKE_HOME/.claude/state"/memory-lint-cache-* 2>/dev/null
cat > "$MEMDIR/topic-a.md" <<'EOF'
---
name: topic-a
description: "has a dangling link, unresolved across every run below"
metadata:
  type: project
---
see [[nonexistent-target-xyz]]
EOF
printf '%s\n' "- [topic-a](topic-a.md) — has a dangling link" > "$MEMDIR/MEMORY.md"
OUT1=$(run_hook_no_cache_clear)
assert_contains "run 1: unresolved finding fires the nudge" \
  "[memory-lint] The memory store has findings" "$OUT1"
OUT2=$(run_hook_no_cache_clear)
# Regression test for the 2026-08-17 fix: the cache used to be touched after
# EVERY successful run, dirty or clean — so a real, still-unresolved finding
# fired once and then went silent on every later session until some
# unrelated file in $MEMDIR happened to get a newer mtime. Nothing changed
# between run 1 and run 2 here on purpose; the finding must still fire.
assert_contains "run 2 (nothing changed, finding still unresolved): must still fire, not go silent" \
  "[memory-lint] The memory store has findings" "$OUT2"
OUT3=$(run_hook_no_cache_clear)
assert_contains "run 3: still fires — confirms it's not a one-tick fluke" \
  "[memory-lint] The memory store has findings" "$OUT3"

# Once the store is genuinely clean, the cache should resume its normal job
# (skip the python3 rescan on an unchanged store) rather than rescan forever.
init_memdir
rm -f "$FAKE_HOME/.claude/state"/memory-lint-cache-* 2>/dev/null
write_memory "topic-a.md" "a fully indexed topic"
write_memory "topic-b.md" "another fully indexed topic"
cat > "$MEMDIR/topic-a.md" <<'EOF'
---
name: topic-a
description: "a fully indexed topic"
metadata:
  type: project
---
see [[topic-b]]
EOF
cat > "$MEMDIR/topic-b.md" <<'EOF'
---
name: topic-b
description: "another fully indexed topic"
metadata:
  type: project
---
see [[topic-a]]
EOF
printf '%s\n' \
  "- [topic-a](topic-a.md) — a fully indexed topic" \
  "- [topic-b](topic-b.md) — another fully indexed topic" > "$MEMDIR/MEMORY.md"
run_hook_no_cache_clear >/dev/null
CACHE_FILE=$(find "$FAKE_HOME/.claude/state" -name 'memory-lint-cache-*' 2>/dev/null | head -1)
if [ -n "$CACHE_FILE" ] && [ -f "$CACHE_FILE" ]; then
  echo "  ✅ PRESENT: a clean run still writes the cache (fast-path preserved)"
  pass=$((pass + 1))
else
  echo "  ❌ MISSING: a clean run should still write the cache" >&2
  fail=$((fail + 1))
fi

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
