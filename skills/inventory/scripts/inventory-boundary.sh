#!/usr/bin/env bash
# inventory-boundary.sh — canonical boundary map of agents, skills, and hooks.
# Extends inventory.sh with tool grants, mutation capability, and routing metadata.
# Usage: bash inventory-boundary.sh [<path>]
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared libraries.
# shellcheck source=../../_lib/frontmatter-helpers.sh
. "$SCRIPT_DIR/../../_lib/frontmatter-helpers.sh"
# shellcheck source=../../_lib/err.sh
. "$SCRIPT_DIR/../../_lib/err.sh"

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
      desc=$(fm_get "$f" description --block)
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
      desc=$(fm_get "$skill_file" description --block)
      agent=$(fm_get "$skill_file" agent)
      invoke=$(extract_auto_invoke "$skill_file")
      printf "| %s | %s | %s | %s |\n" "$name" "${desc:-—}" "${agent:-inline}" "$invoke"
    done
  fi

  # Hooks (lightweight — just name + first comment). Recursive: real hooks
  # live under gates/advisory/session/stop/tests, not flat in hooks/ — a
  # shallow glob only ever matched hooks.json (see inventory.sh hook-file mode).
  if [ -d "$base/hooks" ] && [ -n "$(ls -A "$base/hooks" 2>/dev/null)" ]; then
    echo ""
    echo "## Hooks — $label"
    echo "| Hook | Purpose |"
    echo "|---|---|"
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      local name purpose
      name=$(basename "$f")
      purpose=$(awk '/^# /&&!/^# !/{sub(/^# /,"");print;exit}' "$f")
      printf "| %s | %s |\n" "$name" "${purpose:-—}"
    done < <(find "$base/hooks" -type f -name '*.sh' | sort)
  fi

  # Output styles — registered via /output-style <name>; same frontmatter
  # contract as agents (name + description). Loadability checked by
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
      desc=$(fm_get "$f" description --block)
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

# Resolve repo root via git (works regardless of where the script is invoked from).
# `git rev-parse --show-toplevel` is path-safe for any working tree layout.
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

# Task sizing guidance + file ownership boundary table (added with task-sizing skill).
# Placed here so it survives regeneration via heredoc, just like F6 Cross-references.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF3'

---

## Task sizing guidance

Derived from the task-sizing guidance + article `agent-teams-best-practices`. Apply at `kbg:orchestrate` plan time, before fan-out dispatch.

### The 5-6 rule
5-6 tasks per agent is the sweet spot. < 3 = under-utilization; > 8 = context thrashing. This is per-agent, not per-plan.

### Size heuristics
| Dimension | Too small | Too big | Just right |
|-----------|-----------|---------|------------|
| Description | < 30 chars, or "just run X" | Vague novel | 1 concrete sentence |
| Files | No files assigned | > 3 files owned | 1-2 files |
| Criteria | None listed | > 2 criteria | 1-2 criteria |
| Dependencies | 0 (island task) | > 2 upstream tasks | 1 max |
| Estimate | < 15 min | > 4 hours | 2-4 hours |

### Wave balancing
- **Wave 1:** 3-5 tasks (foundational setup — schemas, contracts, migrations).
- **Wave 2+:** 2-4 tasks each (implementation layers that consume prior contracts).
- **Total waves:** 3-5. More = plan is too coarse; fewer = use `/ship` (single-agent) instead.
- **F8.5 hard cap:** > 5 tasks in any wave → split or merge. Clamp in code, not prose.

### Splitting oversized tasks
1. **Interface-first split:** extract API contract / type definition as Wave 1.
2. **Layer split:** backend → frontend → integration → tests (one task per layer).
3. **File split:** one task per file when files are independent. Never split a single file across two agents.

### Merging undersized tasks
1. Same file + same owner → merge.
2. "Update docs after X" → merge into X's task.
3. No files + no criteria → drop or merge.

---

## File ownership boundary table

Canonical file patterns per agent. Assign each file to exactly one agent in an `orchestrate` dispatch plan to prevent silent overwrites. This table lists the live 12-agent fleet — keep it in sync with `agents/` (harness-audit check 12 verifies orchestrate references every agent).

| Agent | Canonical file patterns | Mutates | Notes |
|---|---|---|---|
| `code-architect` | `architecture/`, `*.md` (design docs) | yes | Blueprints, not implementation — but `tools:` grants Bash (Bash can mutate) |
| `code-reviewer` | any file | yes | Read-only review *by intent* (comment-accuracy / type-design / test-coverage lenses) — `tools:` grants Bash (Bash can mutate) |
| `typescript-reviewer` | `*.ts`, `*.tsx`, `*.js`, `*.jsx` | yes | Read-only TS/JS review *by intent* — type safety, async correctness — `tools:` grants Bash (Bash can mutate) |
| `python-reviewer` | `*.py`, `pyproject.toml` | yes | Read-only Python review *by intent* — PEP 8, idioms, type hints — `tools:` grants Bash (Bash can mutate) |
| `flutter-reviewer` | `*.dart`, `lib/`, `pubspec.yaml` | yes | Read-only Dart/Flutter review *by intent* — widgets, state mgmt, Dart idioms — `tools:` grants Bash (Bash can mutate) |
| `security-reviewer` | `auth/`, `secrets/`, `config/`, `security/`, `iam/`, `crypto/` | yes | Vulnerability detection — `tools:` Read/Bash/Grep/Glob (Bash can mutate; no Edit/Write) |
| `silent-failure-hunter` | any file | yes | Read-only error-handling audit *by intent* — `tools:` grants Bash (Bash can mutate) |
| `spec-miner` | any file → `.scratch/specs/` | yes | Extracts behavioral specs (Write + Bash) |
| `refactor-cleaner` | any file | yes | Dead-code removal / deprecation scope (Edit/Bash) |
| `build-error-resolver` | any file with build/type errors | yes | Minimal-diff build/type fixes (Edit/Bash) |
| `performance-optimizer` | any file | yes | Bottleneck + bundle + memory fixes (Edit/Bash) |
| `ideate-critic` | none (read-only) | no | Fresh-context critic for `/ideate` Phase 2 (Read only — no Bash) |

XREF3
fi

# Cross-references to repo-level conventions. Added in Phase 3 (F6).
# These point at docs/ that don't fit the regenerator's "fleet inventory"
# model (they're convention references, not loadable artifacts) but are
# referenced from BOUNDARY.md readers.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF'

---

## Cross-references

- **[Agent tool patterns: allowlist vs denylist](docs/agent-tool-patterns.md)** — kbg-harness convention is `tools:` (allowlist) for new agents; reserve `disallowedTools:` (denylist) for cases where the allowlist would exceed 6-7 tools or the team explicitly opts into implicit-inheritance. The `Mutates` column above reflects `Edit`/`Write`/`Bash` grants.
- **[@0xCodez 14-step harness roadmap](https://x.com/0xCodez/article/2066867539305459732)** — external framing (2026-06-16): harness → loop → self-improving system. Useful for onboarding; kbg keeps the 3-floor vocabulary but rejects the article's L3/L4 unattended-loop conclusion per the no-model-self-start rule (CLAUDE.md's Operating model under §Architecture). Keep/discard analysis is in [[0xcodez-harness-roadmap]] memory.
- **[Sydney Runkle — The Art of Loop Engineering](https://x.com/sydneyrunkle/article/2066928783534289358)** — LangChain's 4-loop stack: agent loop, verification loop, event-driven loop, hill-climbing loop (2026-06-16). Good vocabulary for L1/L2 + human-in-the-loop; kbg rejects the L3/L4 unattended conclusion per the no-model-self-start rule (CLAUDE.md's Operating model under §Architecture). Keep/discard analysis is in [[sydney-runkle-loop-engineering]] memory.
XREF
fi

# Repo context block (D4 closure, 2026-06-12; team framing shed 2026-06-26).
# Module Boundaries + Quick Context + Verification so any reader (or a freshly
# spawned subagent) loads the same module map + verification recipe. Lives
# here, OUTSIDE the regenerator's scope, so the next `inventory-boundary.sh
# --repo-only` regen preserves it. Pattern mirrors F6's Cross-references block.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF2'

---

## Repo context

Module map + verification recipe for the harness. Inject these conventions when a freshly spawned subagent needs the same onboarding map the lead already holds.

### Module Boundaries
For live per-layer counts, read the auto-generated inventory header at the top of this file (regenerated by `inventory-boundary.sh`) — it is the single source of truth; do not hardcode counts here (they drift).
- `agents/` — specialist subagents (.md each)
- `skills/` — workflow skills (SKILL.md per directory; `_lib` is a shared shell library, not an invokable skill)
- `commands/` — slash commands
- `hooks/` — gates/ (deny) · advisory/ (journal) · session/ (inject) · stop/ (cost)
- `output-styles/` — staff-eng (sole live-response register)
- `themes/` — catppuccin-mocha

### Quick Context
- **Stack:** Bash + Python 3 + jq; kbg-harness is a Claude Code plugin (version in `.claude-plugin/plugin.json`)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** critical-hooks behavioral suite and eval gate are pending rebuild (removed in the v0.6.0 reset) — see `CLAUDE.md`'s Validation section
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/kobig/kbg/<version>/` (rebuilt on `claude plugin update kbg@kobig`)

### Verification
- `bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" "${KBG_PLUGIN_ROOT}"` — 0C/0W expected (INFO findings are non-blocking)
- `claude plugin validate --strict "${KBG_PLUGIN_ROOT}"` — exit 0
- critical-hooks behavioral suite + eval gate: pending rebuild, not currently runnable
XREF2
fi

# Trigger phrases for harness use cases (added 2026-06-12).
# Maps common user requests to the correct command/skill/agent.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF4'

---

## Trigger phrases

Map user intent → harness dispatch. Use these trigger phrases in `commands/`, `skills/`, and agent `description:` frontmatter so the flow nudge (`hooks/advisory/flow-nudge.sh`) routes correctly.

### Decisions & debate
| User says | Dispatch | Why |
|---|---|---|
| "pros and cons", "which is better", "should we use X or Y" | `kbg:decide` critique mode | Skeptic + Steel-man + Synthesis stress-test |
| "what should I work on", "prioritize these", "plan this pile of work" | `kbg:orchestrate` skill | Prioritize + route to cheapest correct executor |

### Single-task workflows
| User says | Dispatch | Why |
|---|---|---|
| "build one feature", "implement X", "scope this change" | `/ship` | Classify → implement → review → merge |
| "fix this bug", "debug this" | `/fix-bug` | Bug ceremony |
| "address review feedback" | `/address-review` | PR review response |
| "ship it", "merge this" | `/ship-merge` | Pre-merge gate |
| "release now", "cut a release" | `/ship-release` | Release ceremony |

### Research & analysis
| User says | Dispatch | Why |
|---|---|---|
| "research this", "deep dive on X", "how does Y work" | `/deep-dive` | Brain dump + Q&A + plan |
| "review this PR", "check this code" | `kbg:review-pr` skill | Multi-lens PR review |
| "audit the harness", "check health" | `kbg:harness-audit` skill | Self-audit |

### Incident & post-mortem
| User says | Dispatch | Why |
|---|---|---|
| "incident", "alerts firing", "monitors red" | `kbg:incident` skill | Live incident response |
| "post-mortem", "writeup after incident" | `/post-mortem` | Incident documentation |
| "save my session", "hand off" | `kbg:handoff` | Session state capture |

XREF4
fi

# Reference docs cross-link (added 2026-06-18).
# Points at the non-loadable reasoning-models catalog and its vendored
# thinking-skills library so BOUNDARY.md readers can find the L3 reference
# surface without adding a new invokable skill.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF5'

---

## Reference docs

These files live in the plugin cache, not the project CWD. Read them via Bash with `KBG_PLUGIN_ROOT` (exported by `hooks/session/command-root-anchor.sh`), not as relative markdown links.

- **Reasoning-models catalog** — `cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` — 39 vendored cc-thinking-skills mental models and the kbg surface that applies (or deliberately does not apply) each.
- **Vendored thinking-skills library** — `cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/README.md"` — verbatim upstream copies of the 39 mental-model SKILL.md files, kept under `docs/` so they are never auto-discovered as invokable skills.

XREF5
fi
