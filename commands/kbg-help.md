---
name: kbg-help
description: "kbg-harness quick reference: skills, commands, agents, validation, context tiers. Use for 'help', 'what can you do', 'list skills', 'kbg commands', 'ช่วยเหลือ', 'มีอะไรบ้าง'."
---

# /kbg-help — kbg-harness quick reference

Display this reference card. One-shot, read-only. Do not change mode, write files, or persist anything.

Skim the stage table first — it's the fastest way to find the right surface for what you're doing right now.

## Where do I start? (by stage)

You don't need to memorize every surface — describe what you're doing, and the harness routes you via each surface's `description:`. This table is the **stable entry point** per stage. For the full, always-current list, see `BOUNDARY.md`, or run `kbg:inventory` when nothing here fits.

| Stage | Entry points |
|-------|--------------|
| **DEFINE** — idea, scope, research | `/ideate` · `kbg:decide` · `mattpocock-skills:research` |
| **PLAN** — spec, prioritize | `kbg:orchestrate` · `mattpocock-skills:triage` · `kbg:decide` |
| **BUILD** — implement | `/ship` · `/fix-bug` · `kbg:backend-patterns` · `kbg:incident` |
| **VERIFY** — test, debug | `/ship` (acceptance gating) · `kbg:review-pr` (per-task validation) |
| **REVIEW** — QA gate | `kbg:review-pr` · `kbg:security-auditor` · `kbg:decide` |
| **SHIP** — merge, release | `/ship` (blank-slate or already-scoped, Phase 0 asks which) · `/ship-merge` (reviewed PR) · `/ship-release` (version/tag cut) |

Two runtime routers do the live dispatch: **`kbg:orchestrate`** (a pile of tasks → prioritize + route) and **`mattpocock-skills:triage`** (one issue → `/fix-bug`, `/ship`, `mattpocock-skills:research`, `kbg:decide` probe mode).

### ...and which specialist (agent) per stage

The 12-agent fleet is grouped by what each one **owns** — not by project phase — so they can run in parallel without stepping on each other's concerns. Viewed through the same stages anyway, here's the lens for reaching for a specialist on purpose:

| Stage | Agent specialists |
|-------|-------------------|
| **DEFINE** | `spec-miner` (requirements/spec/AC mining) |
| **DESIGN** | `code-architect` (blueprint, interfaces, seams) |
| **BUILD** | `build-error-resolver` (auto-detects build system, fixes build/type errors) |
| **REVIEW** | `code-reviewer` (carries the comment-accuracy, type-design/illegal-states, and behavioral test-coverage lenses) · `typescript-reviewer` · `python-reviewer` · `flutter-reviewer` · `security-reviewer` · `silent-failure-hunter` · `performance-optimizer` |
| **OPERATE** | `refactor-cleaner` (dead-code removal, behavior-preserving refactor) |
| **Cross-cutting** | `ideate-critic` (fresh-context critics/sensors) |

You rarely name an agent directly — `kbg:review-pr` and `kbg:orchestrate` spawn the right specialists for you. This lens is for when you want one on purpose.

## Which discovery surface?

| Need | Reach for |
|------|-----------|
| Don't know which skill/command covers a task | `kbg:inventory` |
| Don't know how surfaces chain together, or which on-ramp fits | `/ask-kbg` |
| Full current inventory of every surface | `"${KBG_PLUGIN_ROOT}/BOUNDARY.md"` (auto-generated) — or the recipes under "Full inventory" below |
| Per-session token cost (live cost ledger — usage, not file size) | `kbg:harness-audit --health` |
| SKILL.md body size / whether it needs a token-optimizer pass | `kbg:harness-audit` default mode, check 42 (INFO, fleet-relative threshold) |
| Fleet audit (manifests, schema, staleness) | `bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" .` |
| Mental-model reference library (39 cc-thinking-skills + workflow-pattern map) | Read `"${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` via Bash, or run `kbg:inventory` to locate "reasoning-models" |

## Context tiers

| Tier | What's resident | How to reach |
|------|-----------------|--------------|
| **L1** — always loaded | METHODOLOGY + CLAUDE.md + MEMORY.md + pointer to `"${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` | Injected every session automatically |
| **L2** — load by name | Individual skills, commands, agent specs | Invoke by name (`kbg:review-pr`, `/ship`) or skill-nudge keyword |
| **L3** — full inventory, on demand | BOUNDARY.md + raw source (`skills/`, `agents/`, `commands/`, `hooks/`) + `docs/reference/reasoning-models.md` (incl. workflow-pattern mapping) | `kbg:inventory` lists every loadable surface when you don't know the right one |

## Validation shortcuts

These validation commands resolve paths from `${KBG_PLUGIN_ROOT}` and work from any CWD:

```bash
bash "${KBG_PLUGIN_ROOT}/git-hooks/pre-commit"                    # commit-time: syntax/lint + CRITICAL harness-audit
bash "${KBG_PLUGIN_ROOT}/scripts/run-gauntlet.sh"                 # push-time: full parallel gauntlet (validate + lint + JSON + audit + hook suites)
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

- **No unattended self-repair.** `kbg:recursive-improve` stops at a user `AskUserQuestion` gate before any mutation — the model never self-starts a repair loop. *(CLAUDE.md §Architecture calls this the no-model-self-start rule.)*
- **Advisory sensors never gate.** Sensors like `verification-gate.sh` journal only — they inform, they never emit a `permissionDecision` that blocks anything.
- **Cache invalidation is manual.** Editing a file changes nothing until you bump both manifests, run `claude plugin update kbg@kobig`, and restart.

## Full inventory

Run these from any project CWD because `${KBG_PLUGIN_ROOT}` resolves to the plugin cache:

- Skills: `ls "${KBG_PLUGIN_ROOT}/skills" | sed '/^_lib$/d'` or `grep -r "^name:" "${KBG_PLUGIN_ROOT}/skills"/*/SKILL.md`
- Commands: `ls "${KBG_PLUGIN_ROOT}/commands"/*.md | xargs -n1 basename | sed 's|\.md||'`
- Agents: `ls "${KBG_PLUGIN_ROOT}/agents"/*.md | xargs -n1 basename | sed 's|\.md||'`
- Hooks: `jq '[.hooks[][].id]' "${KBG_PLUGIN_ROOT}/hooks/hooks.json"`

For deeper discovery, run `kbg:inventory`.
