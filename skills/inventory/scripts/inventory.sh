#!/usr/bin/env bash
# inventory.sh — dynamic listing of Claude artifacts available HERE.
#
# Default: scan ~/.claude (global, what Claude Code actually loads) + the
# git root's .claude/ (project-local). Zero config — no env var, no arg
# required.
#
# Explicit override: pass a path as $1 to scan ONLY that path
# (useful for inspecting dotfiles source directly).
set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────
#
# fm_get / fm_has / fm_hook_desc come from
# scripts/_lib/frontmatter-helpers.sh (shared with audit.sh and
# inventory-boundary.sh). Call sites below use fm_get "$f" description for
# the single-line description value, and fm_hook_desc for hook comments
# (not YAML frontmatter — different shape, kept separate in the lib).

# Source the shared libraries.
# shellcheck source=../../../scripts/_lib/frontmatter-helpers.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/frontmatter-helpers.sh"
# shellcheck source=../../../scripts/_lib/err.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/_lib/err.sh"

# ── per-section printer ──────────────────────────────────────────────

print_section() {
  local heading="$1" path="$2" mode="$3"
  [ -d "$path" ] || return

  shopt -s nullglob
  local items=()
  case "$mode" in
    skill-dir)  for d in "$path"/[!_]*/; do items+=("${d%/}"); done ;;  # [!_]*/ skips _-prefixed scaffolds (e.g. _template), per install.sh/harness-audit
    md-file)    for f in "$path"/*.md "$path"/*/COMMAND.md; do [ -f "$f" ] && items+=("$f"); done ;;  # top-level *.md + one-level-nested */COMMAND.md (mirrors audit check 01's command glob; excludes nested references/*.md — pre-existing mis-citation of check 35 corrected 2026-08-25, ticket 87: 35 is dead-script-pointer-doc-rot, not the fleet-count glob)
    hook-file)  while IFS= read -r f; do items+=("$f"); done < <(find "$path" -type f \( -name '*.sh' -o -name '*.py' \) | sort) ;;  # recursive: real hooks live under gates/advisory/session/stop/tests, not flat in hooks/; .py included (worktree-guard.py)
  esac
  shopt -u nullglob

  [ ${#items[@]} -eq 0 ] && return

  echo ""
  echo "### $heading (${#items[@]})"
  for item in "${items[@]}"; do
    local name desc marker="◇"
    case "$mode" in
      skill-dir)  name=$(basename "$item");      desc=$(fm_get "$item/SKILL.md" description) ;;
      md-file)    name=$(basename "$item" .md); [ "$name" = "COMMAND" ] && name=$(basename "$(dirname "$item")"); desc=$(fm_get "$item" description) ;;
      hook-file)  name=$(basename "$item");      desc=$(fm_hook_desc "$item") ;;
    esac
    printf "  %s %-30s %s\n" "$marker" "$name" "${desc:-(no description)}"
  done
}

# ── per-source printer ───────────────────────────────────────────────

print_source() {
  local label="$1" base="$2"
  [ -d "$base" ] || return

  # Skip if nothing inside any of the 4 standard subdirs
  local any=0
  for sub in skills agents commands hooks; do
    [ -d "$base/$sub" ] && [ -n "$(ls -A "$base/$sub" 2>/dev/null)" ] && any=1
  done
  [ $any -eq 0 ] && return

  # Host-portable display: shorten the absolute $base to `<parent_bn>/<base_bn>`
  # so the artifact doesn't leak the host install dir. The scan still uses $base.
  local display="$base"
  local _parent_bn _base_bn
  _parent_bn="$(basename "$(dirname "$base")")"
  _base_bn="$(basename "$base")"
  if [ -n "$_parent_bn" ] && [ "$_parent_bn" != "." ] && [ "$_parent_bn" != "/" ]; then
    display="${_parent_bn}/${_base_bn}"
  fi

  echo ""
  echo "## $label"
  echo "_${display}_"
  print_section "Skills"   "$base/skills"   "skill-dir"
  print_section "Commands" "$base/commands" "md-file"
  print_section "Agents"   "$base/agents"   "md-file"
  print_section "Hooks"    "$base/hooks"    "hook-file"
}

# ── main ─────────────────────────────────────────────────────────────

echo "# Inventory"
echo "_Legend: ◇ plugin-delivered / project-local_"

# Explicit override mode
if [ -n "${1:-}" ]; then
  if [ ! -d "$1" ]; then
    err_die "not a directory: $1"
  fi
  # Host-portable: render the label as `Source: <parent_bn>/<basename>` so
  # the artifact doesn't leak the host install dir. print_source still
  # scans the absolute $1 path; only the human-readable label is shortened.
  _parent_bn="$(basename "$(dirname "$1")")"
  _label="Source: ${_parent_bn}/$(basename "$1")"
  print_source "$_label" "$1"
  exit 0
fi

# Dynamic mode — scan project-local + global
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$GIT_ROOT" ]; then
  print_source "Project-local — \`$(basename "$GIT_ROOT")/.claude\`" "$GIT_ROOT/.claude"
fi

print_source "Global — \`~/.claude\` (what Claude Code loads)" "$HOME/.claude"
