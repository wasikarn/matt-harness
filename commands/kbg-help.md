---
name: kbg-help
description: "Quick reference card for kbg-harness skills, commands, agents, validation pipeline, and context tiers. Use when the user asks 'help', 'what can you do', 'list skills', 'how do I use kbg', or 'kbg commands', or when the user says 'ช่วยเหลือ', 'มีอะไรบ้าง', 'ใช้ kbg ยังไง'. Don't use for: deep capability discovery (use kbg:harness-nav) or governance journal queries (use kbg:harness-health). One-shot display, read-only."
---

# /kbg-help — kbg-harness quick reference

Display this reference card. One-shot, read-only. Do not change mode, write files, or persist anything.

## Where do I start? (by stage)

You don't memorize surfaces — describe what you're doing and the harness auto-routes via each surface's `description:`. The table below is the **stable entry point** per stage; the full, always-current inventory of every surface is generated in `BOUNDARY.md`, and `kbg:harness-nav` mines it when nothing here fits.

| Stage | Entry points |
|-------|--------------|
| **DEFINE** — idea, scope, research | `kbg:ideate` · `kbg:clarify-first` · `kbg:research-brief` (or `/deep-dive`) |
| **PLAN** — spec, prioritize, team | `kbg:orchestrate` · `kbg:triage` · `/team-plan` → `/team-build` |
| **BUILD** — implement | `/feature-dev` · `/fix-bug` · `kbg:backend-dev` · `kbg:hotfix` |
| **VERIFY** — test, debug | `/validate-and-fix` · `/debug-debate` · `/pre-ship-verify` |
| **REVIEW** — QA gate | `kbg:review-pr` · `kbg:security-auditor` · `kbg:critical-eval` |
| **SHIP** — merge, release | `/ship-task` (from scratch) · `kbg:ship-change` (already-scoped) · `/ship-merge` · `/ship-release` |

Two runtime routers do the live dispatch: **`kbg:orchestrate`** (a pile of tasks → prioritize + route) and **`kbg:triage`** (one issue → `/fix-bug`, `/feature-dev`, `/deep-dive`, `kbg:probe`).

### ...and which specialist (agent) per stage

The 29-agent fleet is grouped by **discipline/ownership** (each agent owns one concern and defers cross-concern work) — *not* by lifecycle phase, which is what lets disciplines run in parallel. Viewed through the same stages, here is the role-per-phase lens for reaching for a specialist deliberately:

| Stage | Agent specialists |
|-------|-------------------|
| **DEFINE** | `product-analyst` (requirements/AC) · `code-explorer` (trace existing code) · `researcher` (external options) |
| **DESIGN** | `code-architect` (blueprint) · `type-design-analyzer` (contracts/encapsulation) |
| **BUILD** | `backend-engineer` · `frontend-engineer` · `mobile-engineer` · `data-engineer` · `ml-engineer` · `platform-engineer` · `devops-engineer` · domain: `i18n-specialist` · `compliance-engineer` · `finops-engineer` |
| **VERIFY** | `test-engineer` (write tests) · `pr-test-analyzer` (coverage gaps) |
| **REVIEW** | `code-reviewer` · `security-reviewer` · `silent-failure-hunter` · `comment-analyzer` · `ux-reviewer` · `code-simplifier` |
| **OPERATE** | `incident-commander` (live incident) · `maintenance-engineer` (debt/refactor post-ship) |
| **Cross-cutting** | `technical-writer` · `api-doc-specialist` (docs, any stage) · `ideate-critic` · `inferential-structural-judge` (fresh-context critics/sensors) |

You rarely name an agent directly — `kbg:review-pr` and `/team-build` spawn the right specialists for you. This lens is for when you want one on purpose.

## Which discovery surface?

| Need | Reach for |
|------|-----------|
| Don't know which skill/command covers a task | `kbg:harness-nav` |
| Full current inventory of every surface | `"${KBG_PLUGIN_ROOT}/BOUNDARY.md"` (auto-generated) — or the recipes under "Full inventory" below |
| Read-only governance journal / verdicts / silent sensors | `kbg:harness-health` |
| 12-cell coverage decay grid (quarter-end) | `kbg:harness-coverage` |
| Fleet audit (manifests, schema, staleness) | `bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh" .` |
| Mental-model reference library (39 cc-thinking-skills + workflow-pattern map) | Read `"${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` via Bash, or run `kbg:harness-nav` and search for "reasoning-models" |

## Context tiers

| Tier | What's resident | How to reach |
|------|-----------------|--------------|
| **L1** | METHODOLOGY / RTK / ACLI / DBGATE + CLAUDE.md + MEMORY.md  + pointer to `"${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"` | Injected every session automatically |
| **L2** | Individual skills, commands, agent specs | Invoke by name (`kbg:review-pr`, `/ship-task`) or skill-nudge keyword |
| **L3** | BOUNDARY.md + raw source (`skills/`, `agents/`, `commands/`, `hooks/`) + `docs/reference/reasoning-models.md` (incl. workflow-pattern mapping) | `kbg:harness-nav` mines the inventory when you don't know the right surface |

## Validation shortcuts

These validation commands resolve paths from `${KBG_PLUGIN_ROOT}` and work from any CWD:

```bash
bash "${KBG_PLUGIN_ROOT}/git-hooks/pre-commit"                    # commit-time: syntax/lint + audit + affected evals
bash "${KBG_PLUGIN_ROOT}/scripts/run-gauntlet.sh"                 # push-time: full parallel gauntlet
bash "${KBG_PLUGIN_ROOT}/scripts/run-gauntlet.sh" --fast          # skip the slow critical-hooks suite
bash "${KBG_PLUGIN_ROOT}/tests/hooks/runners/test-critical-hooks.sh"      # safety suite only
bash "${KBG_PLUGIN_ROOT}/skills/harness-audit/scripts/audit.sh"     # self-audit only (defaults to plugin root)
python3 "${KBG_PLUGIN_ROOT}/eval/run-eval.py" --dataset "${KBG_PLUGIN_ROOT}/eval/datasets/" --regression --gate
```

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

- **Autonomy invariant (ADR 0002):** no unattended self-repair loops. `kbg:recursive-improve` stops at a user `AskUserQuestion` gate before any mutation.
- **Inferential feedback is advisory:** sensors like `verification-gate.sh` journal only — they never emit a `permissionDecision`.
- **Cache-invalidation is manual:** version bump in both manifests + `claude plugin update kbg@kobig` + restart.

## Full inventory

Run these from any project CWD because `${KBG_PLUGIN_ROOT}` resolves to the plugin cache:

- Skills: `ls "${KBG_PLUGIN_ROOT}/skills" | sed '/^_lib$/d'` or `grep -r "^name:" "${KBG_PLUGIN_ROOT}/skills"/*/SKILL.md`
- Commands: `ls "${KBG_PLUGIN_ROOT}/commands"/*.md | xargs -n1 basename | sed 's|\.md||'`
- Agents: `ls "${KBG_PLUGIN_ROOT}/agents"/*.md | xargs -n1 basename | sed 's|\.md||'`
- Hooks: `jq '.hooks[].name' "${KBG_PLUGIN_ROOT}/hooks/hooks.json"`

For deeper discovery, run `kbg:harness-nav`.
