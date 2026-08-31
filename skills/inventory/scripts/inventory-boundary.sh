#!/usr/bin/env bash
# inventory-boundary.sh — canonical boundary map of agents, skills, and hooks.
# Extends inventory.sh with tool grants, mutation capability, and routing metadata.
# Usage: bash inventory-boundary.sh [<path>]
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the shared libraries.
# shellcheck source=../../../scripts/_lib/frontmatter-helpers.sh
. "$SCRIPT_DIR/../../../scripts/_lib/frontmatter-helpers.sh"
# shellcheck source=../../../scripts/_lib/err.sh
. "$SCRIPT_DIR/../../../scripts/_lib/err.sh"

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

  # Agents — grouped by `bucket:` frontmatter key (v5), same pattern as Skills below.
  if [ -d "$base/agents" ] && [ -n "$(ls -A "$base/agents" 2>/dev/null)" ]; then
    echo ""
    echo "## Agents — $label"
    local _agent_rows=()
    for f in "$base/agents"/*.md; do
      [ -f "$f" ] || continue
      local name desc tools mutates bucket
      name=$(basename "$f" .md)
      desc=$(fm_get "$f" description --block)
      tools=$(fm_get "$f" tools)
      mutates=$(can_mutate "$tools")
      bucket=$(fm_get "$f" bucket)
      _agent_rows+=("${bucket:-unbucketed}"$'\t'"$name"$'\t'"${desc:-—}"$'\t'"${tools:-inherit-all}"$'\t'"$mutates")
    done
    if [ "${#_agent_rows[@]}" -gt 0 ]; then
      local _cur_abucket=""
      while IFS=$'\t' read -r b n d t m; do
        [ -n "$b" ] || continue
        if [ "$b" != "$_cur_abucket" ]; then
          [ -n "$_cur_abucket" ] && echo ""
          echo "### $b"
          echo "| Agent | Domain | Tools | Mutates |"
          echo "|---|---|---|---|"
          _cur_abucket="$b"
        fi
        printf "| %s | %s | %s | %s |\n" "$n" "$d" "$t" "$m"
      done < <(printf '%s\n' "${_agent_rows[@]}" | sort -s -t$'\t' -k1,1)
    fi
  fi

  # Commands
  if [ -d "$base/commands" ] && [ -n "$(ls -A "$base/commands" 2>/dev/null)" ]; then
    echo ""
    echo "## Commands — $label"
    echo "| Command | Description |"
    echo "|---|---|"
    for f in "$base/commands"/*.md "$base/commands"/*/COMMAND.md; do  # top-level *.md + one-level-nested */COMMAND.md, mirrors inventory.sh md-file mode
      [ -f "$f" ] || continue
      local name desc
      name=$(basename "$f" .md)
      [ "$name" = "COMMAND" ] && name=$(basename "$(dirname "$f")")
      desc=$(fm_get "$f" description --block)
      printf "| %s | %s |\n" "$name" "${desc:-—}"
    done
  fi

  # Skills — grouped by bucket, derived from the skill's own directory path
  # (skills/<bucket>/<name>/SKILL.md), not bucket: frontmatter — the folder
  # move (2026-08-25) made the path the single source of truth, frontmatter
  # dropped to avoid a two-places-that-can-drift risk. One pass collects
  # "bucket<TAB>row..." tuples, a stable sort by bucket groups them without
  # needing an associative array (kbg's other scripts assume portable bash,
  # not bash-4+ only).
  if [ -d "$base/skills" ] && [ -n "$(ls -A "$base/skills" 2>/dev/null)" ]; then
    echo ""
    echo "## Skills — $label"
    local _skill_rows=()
    for d in "$base/skills"/[!_]*/ "$base/skills"/[!_]*/[!_]*/; do  # [!_]*/ skips _-prefixed scaffolds (e.g. _template), per install.sh/harness-audit; second term covers a bucketed skill dir (skills/<bucket>/<name>/)
      [ -d "$d" ] || continue
      local name desc agent invoke bucket
      name=$(basename "$d")
      case "$name" in *-workspace) continue ;; esac  # gitignored skill-workspace scratch dirs (skill-creator eval workspaces, review-fixtures's working dir) -- never real skills
      local skill_file="$d/SKILL.md"
      [ -f "$skill_file" ] || continue
      desc=$(fm_get "$skill_file" description --block)
      agent=$(fm_get "$skill_file" agent)
      invoke=$(extract_auto_invoke "$skill_file")
      local _parent
      _parent="$(dirname "${d%/}")"
      if [ "$_parent" = "$base/skills" ]; then
        bucket="unbucketed"  # flat skills/<name>/SKILL.md, one level deep — no bucket dir
      else
        bucket=$(basename "$_parent")
      fi
      _skill_rows+=("$bucket"$'\t'"$name"$'\t'"${desc:-—}"$'\t'"${agent:-inline}"$'\t'"$invoke")
    done
    if [ "${#_skill_rows[@]}" -gt 0 ]; then
      local _cur_bucket=""
      while IFS=$'\t' read -r b n d a i; do
        [ -n "$b" ] || continue
        if [ "$b" != "$_cur_bucket" ]; then
          [ -n "$_cur_bucket" ] && echo ""
          echo "### $b"
          echo "| Skill | Description | Agent | Invoke |"
          echo "|---|---|---|---|"
          _cur_bucket="$b"
        fi
        printf "| %s | %s | %s | %s |\n" "$n" "$d" "$a" "$i"
      done < <(printf '%s\n' "${_skill_rows[@]}" | sort -s -t$'\t' -k1,1)
    fi
  fi

  # Hooks (lightweight — just name + first comment paragraph). Recursive: real
  # hooks live under gates/advisory/session/stop, not flat in hooks/ — a
  # shallow glob only ever matched hooks.json (see inventory.sh hook-file mode).
  # .py included (worktree-guard.py) — hooks aren't all bash. The Hooks
  # table also lists hook-behavioral tests under tests/hooks/ (post-2026-08-06
  # consolidation): same fm_hook_desc contract, kept in the Hooks table because
  # they are test harnesses for hooks, not standalone tests.
  # Two independent guards (vs the prior brace-group ||): each branch
  # checks its own dir presence + non-empty before contributing. If one
  # tree is absent, that branch contributes nothing instead of silently
  # no-op'ing the entire Hooks table.
  local _hooks_dirs=()
  if [ -d "$base/hooks" ] && [ -n "$(ls -A "$base/hooks" 2>/dev/null)" ]; then
    _hooks_dirs+=("$base/hooks")
  fi
  if [ -d "$base/tests/hooks" ] && [ -n "$(ls -A "$base/tests/hooks" 2>/dev/null)" ]; then
    _hooks_dirs+=("$base/tests/hooks")
  fi
  if [ "${#_hooks_dirs[@]}" -gt 0 ]; then
    echo ""
    echo "## Hooks — $label"
    echo "| Hook | Purpose |"
    echo "|---|---|"
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      local name purpose
      name=$(basename "$f")
      purpose=$(fm_hook_desc "$f")
      printf "| %s | %s |\n" "$name" "${purpose:-—}"
    done < <(find "${_hooks_dirs[@]}" -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null | sort)
  fi

  # Output styles — registered via /output-style <name>; same frontmatter
  # contract as agents (name + description). Loadability checked by
  # harness-audit's 3c; this is the routing/selection reference.
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
echo "_Canonical routing + capability reference (repo-scoped). Regenerate after agent/skill changes: \`bash <matt-harness>/skills/inventory/scripts/inventory-boundary.sh --repo-only > <dotfiles>/claude/BOUNDARY.md\` where \`<matt-harness>\` is the matt-harness repo root and \`<dotfiles>\` is the target repo root (or from the plugin cache: \`bash ~/.claude/plugins/cache/wasikarn/mh/\$(ls ~/.claude/plugins/cache/wasikarn/mh/ | sort -V | tail -1)/skills/inventory/scripts/inventory-boundary.sh --repo-only\`)._"
echo "_Schema version: v5 (Skills and Agents tables now grouped by \`bucket:\` frontmatter key under \`### <bucket>\` subheads, replacing the single flat table each; v4 added Commands table and dropped the redundant inventory.sh bulleted-list dump in --repo-only mode — tables are now the sole listing, matching skills/inventory/reference.md's documented \"Boundary map\" contract; Hooks Purpose column now a full comment paragraph via fm_hook_desc, not a truncated first line)._"

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
  # No inventory.sh call here (2026-07-15): its bulleted list duplicated
  # print_boundary's tables 1:1 (same entities, same descriptions) — ~2,900+
  # tokens of dead weight in the committed BOUNDARY.md. Tables are a strict
  # superset (extra columns) now that Commands has one too, so the list added
  # nothing print_boundary doesn't already cover.
  _boundary_base="$REPO_CLAUDE"
  print_boundary "Repo" "$REPO_CLAUDE"
elif [ -n "${1:-}" ]; then
  # Host-portable label: use repo-relative tail so the artifact doesn't leak
  # the host install dir. The scan still uses the absolute $1.
  _label_bn="$(basename "$(dirname "$1")")/$(basename "$1")"
  _boundary_base="$1"
  print_boundary "Source: $_label_bn" "$1"
else
  # Live-merged view: structural overview + project-local + global ~/.claude
  bash "$SCRIPT_DIR/inventory.sh"

  # $GIT_ROOT already resolved above (same $SCRIPT_DIR -> same result; no need to re-spawn git).
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
  # Drift guard for the hardcoded "File ownership boundary table" below: unlike
  # the "## Agents — $label" table above (built dynamically from agents/*.md),
  # this table's rows are a hand-authored literal — the Canonical-file-patterns
  # and Notes columns are domain knowledge that isn't in agent frontmatter, so
  # it can't be generated the same way. Found 2026-08-19 during a deep-audit:
  # the table's own text claimed "harness-audit check 12 verifies orchestrate
  # references every agent" as if that covered this table too — it doesn't;
  # check 12 only checks skills/workflow/orchestrate/SKILL.md + reference.md, never
  # BOUNDARY.md. This stderr comparison at least surfaces a stale table the
  # moment someone next regenerates, instead of it silently drifting again the
  # way the "12-agent fleet"/"60 checks" text did. It is NOT a CI gate (stderr
  # only, not part of the generated BOUNDARY.md content, and not a numbered
  # harness-audit check — adding one would hit audit.sh's fail-closed
  # contiguous check-numbering guard, out of scope for this fix).
  _xref3_table_agents=(code-architect typescript-reviewer python-reviewer
    security-reviewer silent-failure-hunter performance-optimizer ideate-critic
    backend-architect blind-spot-hunter
    nextjs-reviewer requirement-analyst summarizer plan-reviewer)
  if [ -d "$_boundary_base/agents" ]; then
    for _af in "$_boundary_base/agents"/*.md; do
      [ -f "$_af" ] || continue
      _an=$(basename "$_af" .md)
      _found=0
      for _ta in "${_xref3_table_agents[@]}"; do [ "$_ta" = "$_an" ] && _found=1 && break; done
      [ "$_found" = 1 ] || echo "inventory-boundary.sh: WARN — agent '$_an' missing from the hardcoded File ownership boundary table (BOUNDARY.md will list it above but not in that table)" >&2
    done
    for _ta in "${_xref3_table_agents[@]}"; do
      [ -f "$_boundary_base/agents/$_ta.md" ] || echo "inventory-boundary.sh: WARN — File ownership boundary table lists '$_ta' but agents/$_ta.md no longer exists" >&2
    done
  fi
  cat <<'XREF3'

---

## Task sizing guidance

Derived from the task-sizing guidance + article `agent-teams-best-practices`. Apply at `mh:orchestrate` plan time, before fan-out dispatch.

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
- **Total waves:** 3-5. More = plan is too coarse; fewer = use `/mattpocock-skills:implement` (single-agent) instead.
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

Canonical file patterns per agent. Assign each file to exactly one agent in an `orchestrate` dispatch plan to prevent silent overwrites. This table is a hand-maintained literal, not generated from `agents/*.md` — keep it in sync by hand when an agent is added or removed. Not covered by harness-audit check 12 (that check only verifies `skills/workflow/orchestrate/SKILL.md` + `reference.md`, not this table or `BOUNDARY.md`) — `inventory-boundary.sh` prints a stderr warning at regen time if this table and `agents/` disagree, but that's advisory, not a CI gate.

| Agent | Canonical file patterns | Mutates | Notes |
|---|---|---|---|
| `code-architect` | `architecture/`, `*.md` (design docs) | yes | Blueprints, not implementation — but `tools:` grants Bash (Bash can mutate) |
| `typescript-reviewer` | `*.ts`, `*.tsx`, `*.js`, `*.jsx` | yes | Read-only TS/JS review *by intent* — type safety, async correctness — `tools:` grants Bash (Bash can mutate) |
| `python-reviewer` | `*.py`, `pyproject.toml` | yes | Read-only Python review *by intent* — PEP 8, idioms, type hints — `tools:` grants Bash (Bash can mutate) |
| `security-reviewer` | `auth/`, `secrets/`, `config/`, `security/`, `iam/`, `crypto/` | yes | Vulnerability detection — `tools:` Read/Bash/Grep/Glob (Bash can mutate; no Edit/Write) |
| `silent-failure-hunter` | any file | yes | Read-only error-handling audit *by intent* — `tools:` grants Bash (Bash can mutate) |
| `performance-optimizer` | any file | yes | Bottleneck + bundle + memory fixes (Edit/Bash) |
| `ideate-critic` | none (read-only) | no | Fresh-context critic for `mh:ideate` Phase 2 (Read only — no Bash) |
| `backend-architect` | `api/`, `services/` (design docs) | yes | API contracts, service boundaries — design-first — `tools:` grants Bash (Bash can mutate) |
| `blind-spot-hunter` | any file | yes | Read-only adversarial hunt for emergent defects *by intent*, post-review — `tools:` grants Bash (Bash can mutate) |
| `nextjs-reviewer` | Next.js App Router files (`app/`, `pages/`, middleware, route handlers) | yes | Read-only framework review *by intent* — `tools:` grants Bash (Bash can mutate) |
| `requirement-analyst` | none (read-only) | no | Requirement analysis from tickets/specs (Read/Glob/Grep only — no Bash) |
| `summarizer` | none (read-only) | no | Condenses text/docs/transcripts (Read/Glob/Grep only — no Bash) |
| `plan-reviewer` | none (read-only) | yes | Adversarial pre-code plan review *by intent* — `tools:` grants Bash (Bash can mutate) |

XREF3

# Cross-references to repo-level conventions. Added in Phase 3 (F6).
# These point at docs/ that don't fit the regenerator's "fleet inventory"
# model (they're convention references, not loadable artifacts) but are
# referenced from BOUNDARY.md readers.
  cat <<'XREF'

---

## Cross-references

- **[Agent tool patterns: allowlist vs denylist](docs/agent-tool-patterns.md)** — matt-harness convention is `tools:` (allowlist) for new agents; reserve `disallowedTools:` (denylist) for cases where the allowlist would exceed 6-7 tools or the team explicitly opts into implicit-inheritance. The `Mutates` column above reflects `Edit`/`Write`/`Bash` grants.
- **[@0xCodez 14-step harness roadmap](https://x.com/0xCodez/article/2066867539305459732)** — external framing (2026-06-16): harness → loop → self-improving system. Useful for onboarding; kbg keeps the 3-floor vocabulary but rejects the article's L3/L4 unattended-loop conclusion per the no-model-self-start rule (CLAUDE.md's Operating model, under the Architecture section). Keep/discard analysis is in [[0xcodez-harness-roadmap]] memory.
- **[Sydney Runkle — The Art of Loop Engineering](https://x.com/sydneyrunkle/article/2066928783534289358)** — LangChain's 4-loop stack: agent loop, verification loop, event-driven loop, hill-climbing loop (2026-06-16). Good vocabulary for L1/L2 + human-in-the-loop; kbg rejects the L3/L4 unattended conclusion per the no-model-self-start rule (CLAUDE.md's Operating model, under the Architecture section). Keep/discard analysis is in [[sydney-runkle-loop-engineering]] memory.
XREF

# Repo context block (D4 closure, 2026-06-12; team framing shed 2026-06-26).
# Module Boundaries + Quick Context + Verification so any reader (or a freshly
# spawned subagent) loads the same module map + verification recipe. Lives
# here, OUTSIDE the regenerator's scope, so the next `inventory-boundary.sh
# --repo-only` regen preserves it. Pattern mirrors F6's Cross-references block.
  cat <<'XREF2'

---

## Repo context

Module map + verification recipe for the harness. Inject these conventions when a freshly spawned subagent needs the same onboarding map the lead already holds.

### Module Boundaries
For live per-layer counts, read the auto-generated inventory header at the top of this file (regenerated by `inventory-boundary.sh`) — it is the single source of truth; do not hardcode counts here (they drift).
- `agents/` — specialist subagents (.md each)
- `skills/` — workflow skills (SKILL.md per directory; `_lib` is a shared shell library, not an invokable skill) — `commands/` retired as a surface type 2026-08-25, #112, every command converted to a skill
- `hooks/` — gates/ (deny) · advisory/ (journal) · session/ (inject) · stop/ (cost)
- `output-styles/` — crisp (sole live-response register)
- `themes/` — catppuccin-mocha

### Quick Context
- **Stack:** Bash + Python 3 + jq; matt-harness is a Claude Code plugin (version in `.claude-plugin/plugin.json`)
- **Entry:** `.claude-plugin/plugin.json` (manifest), `skills/` (skill auto-discovery)
- **Tests:** harness-audit (64 checks) + a 14-file hook behavioral suite, run in parallel by `scripts/run-gauntlet.sh` — see `CLAUDE.md`'s Validation section. The old critical-hooks suite + eval dataset gate were deleted, not rebuilt, in the 2026-06-27 reset (`c452102`). (Check/test counts here are hand-maintained — keep in sync with `ls skills/meta/harness-audit/scripts/checks/*.sh | wc -l` and the test list in `scripts/run-gauntlet.sh`.)
- **DB:** none (read-only data via inventory scripts)
- **Cache:** `~/.claude/plugins/cache/wasikarn/mh/<version>/` (rebuilt on `claude plugin update mh@wasikarn`)

### Verification
- `bash "${MH_PLUGIN_ROOT}/skills/meta/harness-audit/scripts/audit.sh" "${MH_PLUGIN_ROOT}"` — 0C/0W expected (INFO findings are non-blocking)
- `claude plugin validate --strict "${MH_PLUGIN_ROOT}"` — exit 0
- `bash "${MH_PLUGIN_ROOT}/scripts/run-gauntlet.sh"` — full parallel gauntlet (validate + lint + JSON + audit + 14-file hook suite)
XREF2

# Trigger phrases for harness use cases (added 2026-06-12).
# Maps common user requests to the correct command/skill/agent.
  cat <<'XREF4'

---

## Trigger phrases

Map user intent → harness dispatch. Use these trigger phrases in `skills/` and agent `description:` frontmatter so the flow nudge (`hooks/advisory/flow-nudge.sh`) routes correctly.

### Decisions & debate
| User says | Dispatch | Why |
|---|---|---|
| "what should I work on", "prioritize these", "plan this pile of work" | `mh:orchestrate` skill | Prioritize + route to cheapest correct executor |

### Single-task workflows
| User says | Dispatch | Why |
|---|---|---|
| "build one feature", "implement X", "scope this change" | `/mattpocock-skills:implement` | Implement a spec/tickets with TDD where possible → `mattpocock-skills:code-review` → commit |
| "fix this bug", "debug this" | `mattpocock-skills:diagnosing-bugs` | Feedback loop → hypothesize → instrument → fix + regression test |
| "address review feedback" | `mh:address-review` | PR review response |
| "ship it", "merge this" | `mh:ship-merge` | Pre-merge gate |
| "release now", "cut a release" | `mh:ship-release` | Release ceremony |

### Research & analysis
| User says | Dispatch | Why |
|---|---|---|
| "research this", "deep dive on X", "how does Y work" | `mattpocock-skills:research` | Brain dump + Q&A + plan |
| "review this PR", "check this code" | `mattpocock-skills:code-review` skill | Standards + spec review since the kbg review pipeline retired (2026-08-24 #82) |
| "audit the harness", "check health" | `mh:harness-audit` skill | Self-audit |

### Incident & post-mortem
| User says | Dispatch | Why |
|---|---|---|
| "incident", "alerts firing", "monitors red" | `mh:incident` skill | Live incident response |
| "post-mortem", "writeup after incident" | `mh:post-mortem` | Incident documentation |
| "save my session", "hand off" | `/mattpocock-skills:handoff` | Session state capture |

XREF4

# Reference docs cross-link (added 2026-06-18).
# Points at the non-loadable reasoning-models catalog so BOUNDARY.md readers
# can find the L3 reference surface without adding a new invokable skill.
# (The vendored thinking-skills library this used to also point at was removed
# 2026-08-24, ticket 94 — operator-only reference surface with no bearing on a
# plugin user's session; reasoning-models.md now points to the upstream repo
# for full write-ups instead of a local vendored copy.)
  cat <<'XREF5'

---

## Reference docs

These files live in the plugin cache, not the project CWD. Read them via Bash with `MH_PLUGIN_ROOT` (exported by `hooks/session/command-root-anchor.sh`), not as relative markdown links.

- **Reasoning-models catalog** — `cat "${MH_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` — 39 named cc-thinking-skills mental models and the kbg surface that applies (or deliberately does not apply) each; points to the upstream repo for full write-ups.

XREF5
fi
