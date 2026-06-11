#!/usr/bin/env bash
# inventory-boundary.sh — canonical boundary map of agents, skills, and hooks.
# Extends inventory.sh with tool grants, mutation capability, and routing metadata.
# Usage: bash inventory-boundary.sh [<path>]
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared frontmatter library (claude/skills/_lib/fm.sh). The
# 4 in-line parsers this consolidates — extract_tools, extract_agent,
# extract_auto_invoke, plus the inline `awk /^description:/` blocks — are
# all replaced by fm_get / fm_has with a shared contract.
# shellcheck source=../../_lib/fm.sh
. "$SCRIPT_DIR/../../_lib/fm.sh"

# extract_auto_invoke is NOT a key reader — it checks for the presence of
# `disable-model-invocation:` and inverts the result (auto = absent,
# manual = present). Keep the function name and semantics so the boundary
# table output doesn't change; the body is now a one-liner over fm_has.
extract_auto_invoke() {
  local file="$1"
  [ -f "$file" ] || { echo "manual"; return; }
  if fm_has "$file" disable-model-invocation; then
    echo "manual"
  else
    echo "auto"
  fi
}

# Classify mutation capability
can_mutate() {
  local tools="$1"
  if echo "$tools" | grep -qwE '(Edit|Write|Bash)'; then
    echo "yes"
  else
    echo "no"
  fi
}

# ── print boundary map for one source ────────────────────────────────

print_boundary() {
  local label="$1" base="$2"
  [ -d "$base" ] || return

  # Agents
  if [ -d "$base/agents" ] && [ -n "$(ls -A "$base/agents" 2>/dev/null)" ]; then
    echo ""
    echo "## Agents — $label"
    echo "| Agent | Domain | Tools | Mutates |"
    echo "|---|---|---|---|"
    for f in "$base/agents"/*.md; do
      [ -f "$f" ] || continue
      local name desc tools mutates
      name=$(basename "$f" .md)
      desc=$(fm_get "$f" description)
      tools=$(fm_get "$f" tools)
      mutates=$(can_mutate "$tools")
      printf "| %s | %s | %s | %s |\n" "$name" "${desc:-—}" "${tools:-inherit-all}" "$mutates"
    done
  fi

  # Skills
  if [ -d "$base/skills" ] && [ -n "$(ls -A "$base/skills" 2>/dev/null)" ]; then
    echo ""
    echo "## Skills — $label"
    echo "| Skill | Description | Agent | Invoke |"
    echo "|---|---|---|---|"
    for d in "$base/skills"/[!_]*/; do  # [!_]*/ skips _-prefixed scaffolds (e.g. _template), per install.sh/harness-audit
      [ -d "$d" ] || continue
      local name desc agent invoke
      name=$(basename "$d")
      local skill_file="$d/SKILL.md"
      [ -f "$skill_file" ] || continue
      desc=$(fm_get "$skill_file" description)
      agent=$(fm_get "$skill_file" agent)
      invoke=$(extract_auto_invoke "$skill_file")
      printf "| %s | %s | %s | %s |\n" "$name" "${desc:-—}" "${agent:-inline}" "$invoke"
    done
  fi

  # Hooks (lightweight — just name + first comment)
  if [ -d "$base/hooks" ] && [ -n "$(ls -A "$base/hooks" 2>/dev/null)" ]; then
    echo ""
    echo "## Hooks — $label"
    echo "| Hook | Purpose |"
    echo "|---|---|"
    for f in "$base/hooks"/*; do
      [ -f "$f" ] || continue
      local name purpose
      name=$(basename "$f")
      purpose=$(awk '/^# /&&!/^# !/{sub(/^# /,"");print;exit}' "$f")
      printf "| %s | %s |\n" "$name" "${purpose:-—}"
    done
  fi

  # Output styles — registered via /output-style <name>; same frontmatter
  # contract as agents (name + description). Symlink integrity checked by
  # harness-audit §3c; this is the routing/selection reference.
  if [ -d "$base/output-styles" ] && [ -n "$(ls -A "$base/output-styles" 2>/dev/null)" ]; then
    echo ""
    echo "## Output styles — $label"
    echo "| Style | Description |"
    echo "|---|---|"
    for f in "$base/output-styles"/*.md; do
      [ -f "$f" ] || continue
      local name desc
      name=$(basename "$f" .md)
      desc=$(fm_get "$f" description)
      printf "| %s | %s |\n" "$name" "${desc:-—}"
    done
  fi
}

# ── main ─────────────────────────────────────────────────────────────

echo "# Boundary Map"
echo "_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: \`bash claude/skills/inventory/scripts/inventory-boundary.sh --repo-only > claude/BOUNDARY.md\`._"
echo "_Schema version: v3 (adds Output styles table; Mutates column reflects Edit/Write/Bash grant)._"

# Resolve repo root via git (robust to symlink paths like ~/.claude/skills/).
# Hardcoding `cd $SCRIPT_DIR/../../../..` breaks when SCRIPT_DIR itself is
# resolved through a symlink: bash's `cd` follows the symlink, so `..` math
# lands in the wrong place. `git rev-parse --show-toplevel` is symlink-safe.
GIT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
_repo_root="${GIT_ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
# Post-cutover the fleet lives at the repo root, not under claude/ (mirrors
# harness-audit's CLAUDE_DIR resolution at audit.sh:24-26). Use claude/ only when it exists.
if [ -d "$_repo_root/claude" ]; then REPO_CLAUDE="$_repo_root/claude"; else REPO_CLAUDE="$_repo_root"; fi

if [ "${1:-}" = "--repo-only" ]; then
  # Repo-scoped: only THIS repo's claude/ artifacts. Excludes plugins and
  # other globally-installed skills/agents under ~/.claude — this is the
  # committed canonical map the audit (#16) diffs the live source against.
  bash "$SCRIPT_DIR/inventory.sh" "$REPO_CLAUDE"
  print_boundary "Repo" "$REPO_CLAUDE"
elif [ -n "${1:-}" ]; then
  print_boundary "Source: $1" "$1"
else
  # Live-merged view: structural overview + project-local + global ~/.claude
  bash "$SCRIPT_DIR/inventory.sh"

  GIT_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$GIT_ROOT" ] && [ -d "$GIT_ROOT/.claude" ]; then
    print_boundary "Project-local" "$GIT_ROOT/.claude"
  fi

  if [ -d "$HOME/.claude" ]; then
    print_boundary "Global" "$HOME/.claude"
  fi
fi

echo ""
echo "---"
echo "_Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
