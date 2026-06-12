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
# Host-agnostic regenerator (absolute paths removed 2026-06-11): the script's
# own location is the only path needed; output dir is whatever the caller wants.
# Cache path stays literal because it IS host-relative (under $HOME) — that's
# the only stable form across machines for that one command.
echo "_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: \`bash <kbg-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md\` where \`<kbg-harness>\` is the kbg-harness repo root and \`<dotfiles>\` is the target repo root (or from the plugin cache: \`bash ~/.claude/plugins/cache/kobig/kbg/\$(ls ~/.claude/plugins/cache/kobig/kbg/ | sort -V | tail -1)/skills/inventory/scripts/inventory-boundary.sh --repo-only\`)._"
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
  # Host-portable label: use repo-relative tail so the artifact doesn't leak
  # the host install dir. The scan still uses the absolute $1.
  _label_bn="$(basename "$(dirname "$1")")/$(basename "$1")"
  print_boundary "Source: $_label_bn" "$1"
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

# Cross-references to repo-level conventions. Added in Phase 3 (F6).
# These point at docs/ that don't fit the regenerator's "fleet inventory"
# model (they're convention references, not loadable artifacts) but are
# referenced from BOUNDARY.md readers.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF'

---

## Cross-references

- **[Agent tool patterns: allowlist vs denylist](../../docs/agent-tool-patterns.md)** — kbg-harness convention is `tools:` (allowlist) for new agents; reserve `disallowedTools:` (denylist) for cases where the allowlist would exceed 6-7 tools or the team explicitly opts into implicit-inheritance. The `Mutates` column above reflects `Edit`/`Write`/`Bash` grants.
XREF
fi

# Team-ready blocks + Agent Teams section (D1 + D4 closure, 2026-06-12).
# D4 specifies Module Boundaries + Quick Context + Verification block so
# agent teams load shared conventions at runtime. D1 specifies the
# Agent Teams opt-in env var. Both live here, OUTSIDE the regenerator's
# scope, so the next `inventory-boundary.sh --repo-only` regen preserves
# them. Pattern mirrors F6's Cross-references block above.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF2'

---

## Team-ready blocks

When spawning a teammate (via `/team-build` or any agent-team dispatch), inject these shared conventions so teammates load the same module map + verification recipe.

### Module Boundaries
- `agents/` — 27 senior-specialist agents
- `skills/` — 27 workflow skills
- `commands/` — 11 slash commands
- `hooks/` — 38 hook scripts
- `output-styles/` — 1 TECH-LEAD-THAI
- `eval/` — dataset + regression + CI gate (Phase 1)

### Quick Context
- **Stack:** Bash + Python 3 + jq; kbg-harness is a Claude Code plugin (plugin.json v0.1.3)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** `bash hooks/tests/test-critical-hooks.sh` (201/0 expected)
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/kobig/kbg/<version>/` (rebuilt on `claude plugin update kbg@kobig`)

### Verification
- `bash skills/harness-audit/scripts/audit.sh .` — 0C/0W expected (26 I = schema-rot INFO, non-blocking)
- `claude plugin validate --strict .` — exit 0
- `bash hooks/tests/test-critical-hooks.sh` — 201/0 expected
- `python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate` — exit 0

---

## Agent Teams

Opt-in via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Plugin does NOT auto-enable experimental features.

**What it unlocks:**
- `/team-plan <feature>` — Steps 1-3: brain dump + research + ≥10 Q&A → `.claude/tasks/<slug>.md`
- `/team-build <plan-file>` — Steps 4-7: contract chain + wave execution + post-build validation
- TaskCompleted test-claim gate (`hooks/task-lifecycle.sh`, exit 2 + stderr per vendor spec)
- F9 spawn-prompt template in `skills/orchestrate/SKILL.md` (the "what/where/focus/deliverable" quad + FILES YOU OWN / UPSTREAM CONTRACTS schema)
XREF2
fi
