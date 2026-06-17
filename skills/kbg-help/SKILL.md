---
name: kbg-help
description: "Detailed reference card for kbg-harness: context tiers (L1/L2/L3), skill/command index, validation pipeline, plugin cache-invalidation, and load-bearing invariants. Use when the user asks for help, 'what can kbg do', 'how do I use the harness', or 'explain kbg'. Don't use for: deep capability discovery (use kbg:harness-nav) or governance journal queries (use kbg:harness-health). One-shot display, read-only."
---

# kbg:help — kbg-harness reference card

Display this reference card when invoked. One-shot, read-only. Do not switch modes, write flag files, or persist anything.

## Context hierarchy

Context loads in three tiers — **L1** always-resident doctrine (METHODOLOGY/RTK/ACLI/DBGATE + CLAUDE.md + MEMORY.md), **L2** on-demand SKILL.md / command / agent specs, **L3** BOUNDARY.md + raw source (`skills/`, `agents/`, `commands/`, `hooks/`). Full table: [`CLAUDE.md` § Context hierarchy](../../CLAUDE.md).

**Navigation rule:** prefer L2 over L3. L2 is one read; L3 is many. Reach for `kbg:harness-nav` only when L2 (skill-nudge or direct invoke) did not surface the right capability.

## Finding the right capability

| Need | Reach first |
|------|-------------|
| Don't know which skill/command covers a task | `kbg:harness-nav` |
| Want a read-only view of governance journal / sensors | `kbg:harness-health` |
| Want a fleet-level audit (manifests, schema, staleness) | `bash skills/harness-audit/scripts/audit.sh .` |

## Workflow skills

| Skill | Trigger | What it does |
|-------|---------|--------------|
| `kbg:clarify-first` | `kbg:clarify-first` | Scope a fuzzy task before writing code |
| `kbg:accept-task` | `kbg:accept-task` | Lock acceptance criteria before building |
| `kbg:ship-change` | `kbg:ship-change` | Classify → implement → review → merge |
| `kbg:review-pr` | `kbg:review-pr` | Multi-pass code review |
| `kbg:security-auditor` | `kbg:security-auditor` | Security audit of high-stakes diff |
| `kbg:ideate` | `kbg:ideate` | Divergent ideation under 15 cognitive frames |
| `kbg:research-brief` | `kbg:research-brief` | Research an external library or approach |
| `kbg:orchestrate` | `kbg:orchestrate` | Render a workflow DAG into waves (deterministic plan emitter) |
| `kbg:harness-audit` | `kbg:harness-audit` | Run the fleet self-audit |
| `kbg:harness-coverage` | `kbg:harness-coverage` | 2×2×3 coverage grid read-only report |
| `kbg:harness-health` | `kbg:harness-health` | Governance journal / sensor staleness query |
| `kbg:recursive-improve` | `kbg:recursive-improve` | Iterative self-improvement — stops at a user gate |

## Commands (user-verb surface)

| Command | Trigger | What it does |
|---------|---------|--------------|
| `/ship-task` | `/ship-task` | Full 9-step senior-engineer loop from scratch |
| `/team-plan` | `/team-plan` | Produce a multi-agent plan |
| `/team-build` | `/team-build` | Execute a `/team-plan` with agents |
| `/wave-status` | `/wave-status` | Real-time build progress, waves, locks, ETA |
| `/team-cleanup` | `/team-cleanup` | Teardown idle teammates after a build |
| `/pre-flight-plan-linter` | `/pre-flight-plan-linter` | Lint a plan before `/team-build` |
| `/pre-ship-verify` | `/pre-ship-verify` | Deterministic acceptance gating |
| `/validate-and-fix` | `/validate-and-fix` | Validate + fix loop |
| `/debug-debate` | `/debug-debate` | Adversarial debug session |
| `/address-review` | `/address-review` | Address PR review feedback |
| `/dismiss-stale` | `/dismiss-stale` | Operator-only: dismiss sensor-staleness alert for 7 days |

## Validation pipeline

The harness validation runs in parallel where possible.

### Commit-time

```bash
bash git-hooks/pre-commit
```

Runs three layers in parallel: syntax/lint, `harness-audit`, and affected eval fixtures.

### Push-time / manual gauntlet

```bash
bash scripts/run-gauntlet.sh        # full parallel gauntlet
bash scripts/run-gauntlet.sh --fast # skip the slow critical-hooks suite
```

Four layers run in parallel:

| Layer | Command | What it checks |
|-------|---------|----------------|
| Plugin manifest | `claude plugin validate --strict .` | Manifest schema, component counts |
| Harness audit | `bash skills/harness-audit/scripts/audit.sh .` | Schema, manifest drift, sensor staleness |
| Critical hooks | `bash tests/hooks/runners/test-critical-hooks.sh` | PreToolUse + TaskCompleted safety gates |
| Eval gate | `python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate` | Dataset fixtures + regression fixtures |

### Run one layer in isolation

```bash
bash tests/hooks/runners/test-critical-hooks.sh
bash skills/harness-audit/scripts/audit.sh .
python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate --workers 4
```

## Plugin cache invalidation

When you add/modify/remove any plugin-delivered surface (agent, skill, command, hook, output-style, theme):

1. Bump version in **both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
2. Update description counts in both manifests (only when **adding/removing** a component)
3. `claude plugin validate --strict .`
4. Commit + push
5. `claude plugin update kbg@kobig`
6. Restart Claude Code

Skipping step 1 or 2 causes the plugin cache to stale-load the old version, and `harness-audit` (check #31.2) will CRIT-flag the mismatch.

## Load-bearing invariants

- **Autonomy invariant (ADR 0002):** no unattended self-repair loops. Every self-improvement iteration stops at a human `AskUserQuestion` gate before any mutation. `kbg:recursive-improve` carries `disable-model-invocation: true` so the model cannot self-start it.
- **Inferential feedback is advisory:** inferential-FB sensors (`verification-gate.sh`, `fabrication-verdict-log.sh`, `inferential-structural-judge`) journal only. They never emit a `permissionDecision`.
- **Computational feedback enforces:** the critical-hooks suite + `audit.sh` are the computational-FB layer that actually fails the build.
- **Manual cache invalidation:** the plugin cache at `~/.claude/plugins/cache/kobig/kbg/<version>/` is updated only by `claude plugin update kbg@kobig` followed by a restart.

## Full inventory commands

```bash
# Skills
ls skills | sed '/^_lib$/d'

# Commands
ls commands/*.md | sed 's|commands/||;s|\.md||'

# Agents
ls agents/*.md | sed 's|agents/||;s|\.md||'

# Hooks
jq '.hooks[].name' hooks/hooks.json
```

## What this skill does NOT do

- Does NOT modify the harness, manifests, or journal.
- Does NOT invoke other skills automatically.
- Does NOT replace `kbg:harness-nav` for deep capability discovery.
- Does NOT replace `kbg:harness-health` for journal queries.
