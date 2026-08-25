#!/usr/bin/env bash
# sync-fleet-counts.sh — patch the "N skills · M agents" pair into the
# handful of structured locations that carry it verbatim ("commands" dropped
# 2026-08-25, #112 — commands/ retired for good). Mirrors
# inventory-boundary.sh's existing pattern (a small standalone script under
# skills/inventory/scripts/, run manually — not wired into a hook).
#
# Sync-seam: the 4 anchors below mirror the _check_triple anchors in
# skills/meta/harness-audit/scripts/checks/44-fleet-count-locations.sh — an edit to
# one location list should prompt a check of the other.
#
# Scoped to ONLY these 2 locations, each patched via its own anchor line, not
# a blind whole-file regex — README.md carries a *different* project's
# "N skills · M agents" line (a comparison table entry) a few
# lines away from kbg's own; a file-wide substitution would corrupt it.
#
# Usage: bash sync-fleet-counts.sh [<repo-root>]
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${1:-$(cd -P "$SCRIPT_DIR/../../.." && pwd)}"

# shellcheck source=../../../scripts/_lib/err.sh
. "$SCRIPT_DIR/../../../scripts/_lib/err.sh"

[ -f "$REPO_ROOT/.claude-plugin/plugin.json" ] || err_die "not a matt-harness checkout (no .claude-plugin/plugin.json under $REPO_ROOT)"

# Live counts — duplicates check-01's / check-44's methodology directly (3
# short finds); not worth a shared lib for this size.
SKILLS=$(find "$REPO_ROOT/skills" -name SKILL.md -not -path '*/_*' -not -path '*-workspace/*' | wc -l | tr -d ' ')
AGENTS=$(find "$REPO_ROOT/agents" -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ')
TRIPLE="${SKILLS} skills · ${AGENTS} agents"

# <file> <anchor> — replace the "N skills · M agents" substring
# on the one line matching <anchor>, leave every other line untouched.
_sync_triple() {
  local f="$1" anchor="$2" tmp
  [ -f "$f" ] || { echo "skip (not found): ${f#"$REPO_ROOT"/}"; return 0; }
  grep -qF -- "$anchor" "$f" || { echo "skip (anchor '$anchor' not found): ${f#"$REPO_ROOT"/}"; return 0; }
  tmp=$(mktemp)
  awk -v anchor="$anchor" -v triple="$TRIPLE" '
    index($0, anchor) {
      sub(/[0-9]+ skills · [0-9]+ agents/, triple)
    }
    { print }
  ' "$f" > "$tmp"
  mv "$tmp" "$f"
  echo "synced: ${f#"$REPO_ROOT"/} (anchor '$anchor')"
}

# .claude-plugin manifests dropped 2026-08-22 — descriptions reworded to
# count-free feature text (sync-seam: mirrors check 44's location list).
_sync_triple "$REPO_ROOT/README.md" "real current fleet:"
_sync_triple "$REPO_ROOT/README.md" "| kbg-native |"

echo "live fleet: $TRIPLE"
