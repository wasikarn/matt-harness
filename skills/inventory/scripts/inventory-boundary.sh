#!/usr/bin/env bash
# inventory-boundary.sh — canonical boundary map of agents, skills, and hooks.
# Extends inventory.sh with tool grants, mutation capability, and routing metadata.
# Usage: bash inventory-boundary.sh [<path>]
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared libraries.
# shellcheck source=../../_lib/fm.sh
. "$SCRIPT_DIR/../../_lib/fm.sh"
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

Derived from `skills/task-sizing/SKILL.md` and article `agent-teams-best-practices`. Apply at `/team-plan` time, before `/team-build` dispatch.

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
- **Total waves:** 3-5. More = plan is too coarse; fewer = use `/feature-dev` instead.
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

Canonical file patterns per agent. Assign each file to exactly one agent in a `/team-build` plan to prevent silent overwrites.

| Agent | Canonical file patterns | Notes |
|---|---|---|
| `api-doc-specialist` | `openapi/`, `docs/api/`, `sdk/`, `swagger/` | |
| `backend-engineer` | `api/`, `middleware/`, `models/`, `routes/`, `services/`, `tests/` | |
| `code-architect` | `docs/adr/`, `architecture/`, `*.md` (design docs) | Blueprints, not implementation |
| `code-explorer` | any file | Read-only trace |
| `code-reviewer` | any file | Read-only review |
| `code-simplifier` | any file | Post-impl refinement; Edit/Write/Bash |
| `comment-analyzer` | any file | Read-only comment audit |
| `compliance-engineer` | `docs/compliance/`, `policies/`, `data-retention/`, `gdpr/`, `hipaa/` | |
| `data-engineer` | `migrations/`, `etl/`, `analytics/`, `warehouse/`, `dbt/`, `spark/` | Beyond OLTP |
| `devops-engineer` | `.github/`, `docker/`, `k8s/`, `terraform/`, `helm/`, `ci/` | |
| `finops-engineer` | `infra/cost/`, `budgets/`, `docs/finops/` | Read-only + Bash for cost queries |
| `frontend-engineer` | `src/components/`, `src/pages/`, `styles/`, `public/`, `assets/`, `src/hooks/` | |
| `i18n-specialist` | `locales/`, `translations/`, `i18n/`, `src/i18n/`, `l10n/` | |
| `incident-commander` | `docs/incidents/`, `runbooks/`, `alerts/`, `oncall/` | Read-only + coordination |
| `maintenance-engineer` | any file | Refactor / deprecation scope |
| `ml-engineer` | `ml/`, `models/`, `features/`, `pipelines/`, `serving/`, `inference/` | |
| `mobile-engineer` | `ios/`, `android/`, `mobile/`, `react-native/`, `flutter/` | |
| `platform-engineer` | `platform/`, `proto/`, `gateway/`, `mesh/`, `grpc/`, `event-bus/` | |
| `pr-test-analyzer` | any file | Read-only test-coverage audit |
| `product-analyst` | `docs/requirements/`, `prd/`, `user-stories/` | Read-only + Bash |
| `researcher` | any file | Read-only research |
| `security-reviewer` | `auth/`, `secrets/`, `config/`, `security/`, `iam/`, `crypto/` | Read-only audit |
| `silent-failure-hunter` | any file | Read-only error-handling audit |
| `technical-writer` | `docs/`, `README*`, `CHANGELOG*`, `*.md`, `guides/`, `runbooks/` | |
| `test-engineer` | `tests/`, `*.test.*`, `*.spec.*`, `test_*.py`, `e2e/`, `integration/` | |
| `type-design-analyzer` | any file | Read-only type audit |
| `ux-reviewer` | `src/components/`, `src/pages/`, `e2e/ux/`, `a11y/` | Read-only UX audit |

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

- **[Agent tool patterns: allowlist vs denylist](../../docs/agent-tool-patterns.md)** — kbg-harness convention is `tools:` (allowlist) for new agents; reserve `disallowedTools:` (denylist) for cases where the allowlist would exceed 6-7 tools or the team explicitly opts into implicit-inheritance. The `Mutates` column above reflects `Edit`/`Write`/`Bash` grants.
- **[@0xCodez 14-step harness roadmap](https://x.com/0xCodez/article/2066867539305459732)** — external framing (2026-06-16): harness → loop → self-improving system. Useful for onboarding; kbg keeps the 3-floor vocabulary but rejects the article's L3/L4 unattended-loop conclusion per ADR 0002. Keep/discard analysis is in [[0xcodez-harness-roadmap]] memory.
- **[Sydney Runkle — The Art of Loop Engineering](https://x.com/sydneyrunkle/article/2066928783534289358)** — LangChain's 4-loop stack: agent loop, verification loop, event-driven loop, hill-climbing loop (2026-06-16). Good vocabulary for L1/L2 + human-in-the-loop; kbg rejects the L3/L4 unattended conclusion per ADR 0002. Keep/discard analysis is in [[sydney-runkle-loop-engineering]] memory.
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
- `agents/` — 29 senior-specialist agents
- `skills/` — 38 workflow skills
- `commands/` — 21 slash commands
- `hooks/` — 43 hook scripts
- `output-styles/` — 1 SENIOR-ENGINEER
- `eval/` — dataset + regression + CI gate (Phase 1)

### Quick Context
- **Stack:** Bash + Python 3 + jq; kbg-harness is a Claude Code plugin (version in `.claude-plugin/plugin.json`)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** `bash tests/hooks/runners/test-critical-hooks.sh` (expect 0 failures)
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/kobig/kbg/<version>/` (rebuilt on `claude plugin update kbg@kobig`)

### Verification
- `bash skills/harness-audit/scripts/audit.sh .` — 0C/0W expected (INFO findings are non-blocking)
- `claude plugin validate --strict .` — exit 0
- `bash tests/hooks/runners/test-critical-hooks.sh` — expect 0 failures
- `python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate` — exit 0

---

## Agent Teams

Opt-in via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Plugin does NOT auto-enable experimental features.

**What it unlocks:**
- `/team-plan <feature>` — Steps 1-3: brain dump + research + ≥10 Q&A → `.claude/tasks/<slug>.md`
- `/team-build <plan-file>` — Steps 4-7: contract chain + wave execution + post-build validation
- TaskCompleted test-claim gate (`hooks/lifecycle/task-lifecycle.sh`, exit 2 + stderr per vendor spec)
- F9 spawn-prompt template in `skills/orchestrate/SKILL.md` (the "what/where/focus/deliverable" quad + FILES YOU OWN / UPSTREAM CONTRACTS schema)
XREF2
fi

# Trigger phrases for agent-teams use cases (added 2026-06-12).
# Maps common user requests to the correct command/skill/agent.
if [ "${1:-}" = "--repo-only" ] || [ -n "${1:-}" ]; then
  cat <<'XREF4'

---

## Trigger phrases

Map user intent → harness dispatch. Use these trigger phrases in `commands/`, `skills/`, and agent `description:` frontmatter so the orchestrator nudge (`hooks/orchestrator-nudge.sh`) routes correctly.

### Planning & execution
| User says | Dispatch | Why |
|---|---|---|
| "plan this for the team", "multi-agent plan", "team plan: X" | `/team-plan` | Steps 1-3: brain dump + Q&A + structured plan |
| "build the plan", "execute the plan", "ship the team plan" | `/team-build` | Steps 4-7: contract chain + wave execution |
| "where are we", "status of the build", "is the team done" | `/wave-status` | Reads task board, reports wave progress |
| "clean up the team", "remove old plans", "stale tasks" | `/team-cleanup` | Reaps locks, heartbeats, archives old boards |
| "validate this task", "did the teammate do it right" | `/validate-and-fix` | B→V1→F→V2 validation chain on one task |
| "lint the plan", "is this plan ready" | `/pre-flight-plan-linter` | Structural validation before `/team-build` |
| "pros and cons", "which is better", "should we use X or Y" | `/debug-debate` | Advocate + Skeptic + Synthesizer debate |

### Single-task workflows
| User says | Dispatch | Why |
|---|---|---|
| "build one feature", "implement X" | `/feature-dev` | Single-agent ceremony |
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
| "what should I work on", "prioritize these" | `kbg:orchestrate` skill | Prioritize + route |

### Incident & post-mortem
| User says | Dispatch | Why |
|---|---|---|
| "incident", "alerts firing", "monitors red" | `kbg:incident` skill | Live incident response |
| "post-mortem", "writeup after incident" | `/post-mortem` | Incident documentation |
| "status update", "what did we ship" | `/status-update` | Status report |

### Agent-team troubleshooting
| User says | Dispatch | Why |
|---|---|---|
| "agent went idle", "teammate stopped" | `/wave-status` → `/team-build` re-dispatch | Heartbeat check + re-claim |
| "merge conflict", "two agents touched same file" | `scripts/plan-linter.py` + `/team-plan` revision | Ownership violation |
| "validation failed but it says done" | `/validate-and-fix` | F7 gate + re-validator |
| "context exhausted", "out of tokens" | `/team-build` fresh-session gate | Context budget preservation |

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
