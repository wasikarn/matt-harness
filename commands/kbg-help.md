---
name: kbg-help
description: "kbg-harness quick reference: skills, commands, agents, validation, context tiers. Use for 'help', 'what can you do', 'list skills', 'kbg commands', 'ช่วยเหลือ', 'มีอะไรบ้าง'."
---

# /kbg-help — kbg-harness quick reference

Display this reference card. One-shot, read-only. Do not change mode, write files, or persist anything.

## Where do I start? (by stage)

You don't memorize surfaces — describe what you're doing and the harness auto-routes via each surface's `description:`. The table below is the **stable entry point** per stage; the full, always-current inventory of every surface is generated in `BOUNDARY.md`, and `kbg:inventory` lists every loadable surface when nothing here fits.

| Stage | Entry points |
|-------|--------------|
| **DEFINE** — idea, scope, research | `/ideate` · `kbg:decide` · `/deep-dive` |
| **PLAN** — spec, prioritize | `kbg:orchestrate` · `kbg:triage` · `kbg:decide` |
| **BUILD** — implement | `/ship-task` · `/fix-bug` · `kbg:backend-patterns` · `kbg:incident` |
| **VERIFY** — test, debug | `/ship-task` (acceptance gating) · `kbg:review-pr` (per-task validation) |
| **REVIEW** — QA gate | `kbg:review-pr` · `kbg:security-auditor` · `kbg:decide` |
| **SHIP** — merge, release | `/ship-task` (from scratch) · `kbg:ship-change` (already-scoped) · `/ship-merge` · `/ship-release` |

Two runtime routers do the live dispatch: **`kbg:orchestrate`** (a pile of tasks → prioritize + route) and **`kbg:triage`** (one issue → `/fix-bug`, `/ship-task`, `/deep-dive`, `kbg:decide` probe mode).

### ...and which specialist (agent) per stage

The 11-agent fleet is grouped by **discipline/ownership** (each agent owns one concern and defers cross-concern work) — *not* by lifecycle phase, which is what lets disciplines run in parallel. Viewed through the same stages, here is the role-per-phase lens for reaching for a specialist deliberately:

| Stage | Agent specialists |
|-------|-------------------|
| **DEFINE** | `spec-miner` (requirements/spec/AC mining) |
| **DESIGN** | `code-architect` (blueprint, interfaces, seams) |
| **BUILD** | `build-error-resolver` (auto-detects build system, fixes build/type errors) |
| **REVIEW** | `code-reviewer` (carries the comment-accuracy, type-design/illegal-states, and behavioral test-coverage lenses) · `typescript-reviewer` · `python-reviewer` · `security-reviewer` · `silent-failure-hunter` · `performance-optimizer` |
| **OPERATE** | `refactor-cleaner` (dead-code removal, behavior-preserving refactor) |
| **Cross-cutting** | `ideate-critic` (fresh-context critics/sensors) |

You rarely name an agent directly — `kbg:review-pr` and `kbg:orchestrate` spawn the right specialists for you. This lens is for when you want one on purpose.

## Which discovery surface?

| Need | Reach for |
|------|-----------|
| Don't know which skill/command covers a task | `kbg:inventory` |
| Full current inventory of every surface | `"${KBG_PLUGIN_ROOT}/BOUNDARY.md"` (auto-generated) — or the recipes under "Full inventory" below |
| Per-session token cost (live cost ledger) | `kbg:harness-audit --health` |
| Fleet audit (manifests, schema, staleness) | `bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" .` |
| Mental-model reference library (39 cc-thinking-skills + workflow-pattern map) | Read `"${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` via Bash, or run `kbg:inventory` to locate "reasoning-models" |

## Context tiers

| Tier | What's resident | How to reach |
|------|-----------------|--------------|
| **L1** | METHODOLOGY / RTK / ACLI / DBGATE + CLAUDE.md + MEMORY.md  + pointer to `"${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` | Injected every session automatically |
| **L2** | Individual skills, commands, agent specs | Invoke by name (`kbg:review-pr`, `/ship-task`) or skill-nudge keyword |
| **L3** | BOUNDARY.md + raw source (`skills/`, `agents/`, `commands/`, `hooks/`) + `docs/reference/reasoning-models.md` (incl. workflow-pattern mapping) | `kbg:inventory` lists every loadable surface when you don't know the right one |

## Validation shortcuts

These validation commands resolve paths from `${KBG_PLUGIN_ROOT}` and work from any CWD:

```bash
bash "${KBG_PLUGIN_ROOT}/git-hooks/pre-commit"                    # commit-time: syntax/lint + audit + affected evals
bash "${KBG_PLUGIN_ROOT}/scripts/run-gauntlet.sh"                 # push-time: full parallel gauntlet
bash "${KBG_PLUGIN_ROOT}/scripts/run-gauntlet.sh" --fast          # skip the slow critical-hooks suite
bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh"     # self-audit only (defaults to plugin root)
```

Critical-hooks behavioral suite and eval gate are pending rebuild (see `CLAUDE.md`) — not currently runnable, omitted above.

## Update the plugin after surface changes

If you add/modify/remove any skill, command, agent, hook, output-style, or theme:

1. Bump version in `.claude-plugin/plugin.json` **and** `.claude-plugin/marketplace.json`
2. Update description counts in both manifests (only when adding/removing)
3. `claude plugin validate --strict "${KBG_PLUGIN_ROOT}"`
4. Commit + push
5. `claude plugin update kbg@kobig`
6. Restart Claude Code

Skipping step 1 or 2 causes stale cache loads and `harness-audit` will CRIT-flag the mismatch.

## Load-bearing invariants

- **Autonomy invariant (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model):** no unattended self-repair loops. `kbg:recursive-improve` stops at a user `AskUserQuestion` gate before any mutation.
- **Inferential feedback is advisory:** sensors like `verification-gate.sh` journal only — they never emit a `permissionDecision`.
- **Cache-invalidation is manual:** version bump in both manifests + `claude plugin update kbg@kobig` + restart.

## Full inventory

Run these from any project CWD because `${KBG_PLUGIN_ROOT}` resolves to the plugin cache:

- Skills: `ls "${KBG_PLUGIN_ROOT}/skills" | sed '/^_lib$/d'` or `grep -r "^name:" "${KBG_PLUGIN_ROOT}/skills"/*/SKILL.md`
- Commands: `ls "${KBG_PLUGIN_ROOT}/commands"/*.md | xargs -n1 basename | sed 's|\.md||'`
- Agents: `ls "${KBG_PLUGIN_ROOT}/agents"/*.md | xargs -n1 basename | sed 's|\.md||'`
- Hooks: `jq '[.hooks[][].id]' "${KBG_PLUGIN_ROOT}/hooks/hooks.json"`

For deeper discovery, run `kbg:inventory`.
