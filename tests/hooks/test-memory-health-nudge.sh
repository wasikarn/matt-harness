#!/usr/bin/env bash
# memory-health-nudge unit tests: focused on the --classify-unindexed wiring
# added on top of the pre-existing detector-findings nudge. Isolates a fake
# $HOME and a fake project cwd so real ~/.claude/projects state is never
# touched; the hook derives its memory dir from `pwd -P` (physical path,
# slashes -> dashes) the same way memory-lint.py's own memory_dir() does, so
# fixtures must be planted at that exact computed path.
# Run standalone: bash tests/hooks/test-memory-health-nudge.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/session/memory-health-nudge.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kbg-memory-health-nudge-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

PROJECT_DIR="$TMP/project"
FAKE_HOME="$TMP/home"
mkdir -p "$PROJECT_DIR" "$FAKE_HOME/.claude/state"

PHYSPWD=$(cd "$PROJECT_DIR" && pwd -P)
ENC="${PHYSPWD//\//-}"
MEMDIR="$FAKE_HOME/.claude/projects/$ENC/memory"

_git() { git -C "$MEMDIR" "$@" >/dev/null 2>&1; }

init_memdir() {
  rm -rf "$MEMDIR"
  mkdir -p "$MEMDIR"
}

init_git_repo() {
  _git init -q
  _git config user.email "test@example.com"
  _git config user.name "Test"
  _git config commit.gpgsign false
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

echo "--- baseline behavior (unaffected by the classify-unindexed addition) ---"

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
# topic-a/topic-b bodies carry no Why:/How-to-apply: fields, so this store
# also has template-gap > 0 (feedback/project template compliance) — this
# assertion doubles as coverage that template-gap alone never trips the gate.
assert_not_contains "clean store (incl. template-gap-only) stays fully silent" "[memory-lint]" "$OUT"

rm -rf "$FAKE_HOME/.claude/projects"
OUT=$(run_hook)
assert_not_contains "no memory dir at all stays silent" "[memory-lint]" "$OUT"

echo ""
echo "--- stale-only stays silent (staleness is permanent-by-design debt, same as template-gap) ---"

init_memdir
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
OLD=$(date -v-100d +%Y%m%d0000 2>/dev/null || date -d '100 days ago' +%Y%m%d0000)
touch -t "$OLD" "$MEMDIR/topic-a.md"
OUT=$(run_hook)
assert_not_contains "0 findings + 1 stale (>90d) file stays silent — a dormant-by-design 'settled audit' memory would otherwise re-trigger this forever" \
  "[memory-lint]" "$OUT"

echo ""
echo "--- classify-unindexed wiring ---"

init_memdir
write_memory "topic-a.md" "a fully indexed topic"
printf '%s\n' \
  "- [topic-a](topic-a.md) — a fully indexed topic" \
  "see [[missing-thing]] for more" > "$MEMDIR/MEMORY.md"
OUT=$(run_hook)
assert_contains "non-UNINDEXED finding (dangling link) still fires the main block" \
  "[memory-lint] The memory store has findings" "$OUT"
assert_not_contains "no UNINDEXED finding present -> no triage line" \
  "UNINDEXED triage" "$OUT"
# write_memory's fixture body carries no Why:/How-to-apply: fields, so this
# store also has template-gap > 0 — confirms the Template compliance section
# (and its file list) never reaches the emitted message even when the block
# fires for an unrelated reason.
assert_not_contains "template-gap noise stays out of the emitted block" \
  "Template compliance" "$OUT"

init_memdir
init_git_repo
write_memory "folded-target.md" "a finished audit"
printf '%s\n' "- [folded-target](folded-target.md) — a finished audit" > "$MEMDIR/MEMORY.md"
_git add -A && _git commit -q -m "add folded-target pointer"
: > "$MEMDIR/MEMORY.md"
_git add -A && _git commit -q -m "fold rule: drop stale index entry"
OUT=$(run_hook)
assert_contains "folded-confirmed UNINDEXED file still surfaces the raw finding" \
  "UNINDEXED: folded-target.md" "$OUT"
assert_not_contains "all-folded (0 never-indexed) -> no triage line (nothing actionable)" \
  "UNINDEXED triage" "$OUT"

init_memdir
init_git_repo
: > "$MEMDIR/MEMORY.md"
_git add -A && _git commit -q -m "baseline (predates the target file)"
write_memory "new-target.md" "written after the baseline commit"
OUT=$(run_hook)
assert_contains "a real never-indexed candidate triggers the triage line" \
  "UNINDEXED triage: 1 of the UNINDEXED file(s)" "$OUT"

init_memdir
write_memory "plain-target.md" "no git here"
: > "$MEMDIR/MEMORY.md"
OUT=$(run_hook)
assert_contains "no-git-history: raw UNINDEXED finding still surfaces" \
  "UNINDEXED: plain-target.md" "$OUT"
assert_not_contains "no-git-history has no never-indexed bucket -> no triage line" \
  "UNINDEXED triage" "$OUT"

echo ""
total=$((pass + fail))
echo "=== $pass/$total passed ==="
[[ "$fail" -eq 0 ]] && exit 0 || exit 1
