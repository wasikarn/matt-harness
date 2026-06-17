---
name: kbg-help
description: "Quick reference card for kbg-harness skills, commands, validation pipeline, and context tiers. Use when the user asks 'help', 'what can you do', 'list skills', 'how do I use kbg', or 'kbg commands'. Don't use for: deep capability discovery (use kbg:harness-nav) or governance journal queries (use kbg:harness-health). One-shot display, read-only."
---

# /kbg-help — kbg-harness quick reference

Display this reference card. One-shot, read-only. Do not change mode, write files, or persist anything.

## Context tiers

| Tier | What's resident | How to reach |
|------|-----------------|--------------|
| **L1** | METHODOLOGY / RTK / ACLI / DBGATE + CLAUDE.md + MEMORY.md | Injected every session automatically |
| **L2** | Individual skills, commands, agent specs | Invoke by name (`kbg:review-pr`, `/ship-task`) or skill-nudge keyword |
| **L3** | BOUNDARY.md + raw source (`skills/`, `agents/`, `commands/`, `hooks/`) | `kbg:harness-nav` mines the inventory when you don't know the right surface |

## "I need the right tool" → `kbg:harness-nav`

When no skill name comes to mind, say what you want to do and invoke `kbg:harness-nav`. It teaches grep recipes over `skills/`, `commands/`, `agents/`, and `BOUNDARY.md` to find the nearest capability.

## Common workflow skills

| Skill | Use when |
|-------|----------|
| `kbg:clarify-first` | The scope is fuzzy before writing code |
| `kbg:accept-task` | You want to lock acceptance criteria before building |
| `kbg:ship-change` | Classify → implement → review → merge a change |
| `kbg:review-pr` | Code review before merge |
| `kbg:security-auditor` | Security audit of a high-stakes diff |
| `kbg:ideate` | Divergent ideation under 15 cognitive frames |
| `kbg:research-brief` | Research an external library or approach |
| `kbg:harness-health` | Query the governance journal / sensor staleness |
| `kbg:recursive-improve` | Iterative self-improvement (stops at a user gate) |

## Common commands

| Command | Use when |
|---------|----------|
| `/ship-task` | Full 9-step senior-engineer loop from scratch |
| `/team-plan` | Produce a multi-agent plan |
| `/team-build` | Execute a `/team-plan` with agents |
| `/wave-status` | Check build progress mid-flight |
| `/team-cleanup` | Teardown idle teammates after a build |
| `/pre-ship-verify` | Deterministic acceptance gating |
| `/pre-flight-plan-linter` | Lint a plan before `/team-build` |
| `/validate-and-fix` | Validate + fix loop |
| `/debug-debate` | Adversarial debug session |
| `/dismiss-stale` | Operator-only: dismiss sensor-staleness alert for 7 days |

## Validation shortcuts

Run from the repo root:

```bash
bash git-hooks/pre-commit                    # commit-time: syntax/lint + audit + affected evals
bash scripts/run-gauntlet.sh                 # push-time: full parallel gauntlet
bash scripts/run-gauntlet.sh --fast          # skip the slow critical-hooks suite
bash hooks/tests/test-critical-hooks.sh      # safety suite only
bash skills/harness-audit/scripts/audit.sh . # self-audit only
python3 eval/run-eval.py --dataset eval/datasets/ --regression --gate
```

## Update the plugin after surface changes

If you add/modify/remove any skill, command, agent, hook, output-style, or theme:

1. Bump version in `.claude-plugin/plugin.json` **and** `.claude-plugin/marketplace.json`
2. Update description counts in both manifests (only when adding/removing)
3. `claude plugin validate --strict .`
4. Commit + push
5. `claude plugin update kbg@kobig`
6. Restart Claude Code

Skipping step 1 or 2 causes stale cache loads and `harness-audit` will CRIT-flag the mismatch.

## Load-bearing invariants

- **Autonomy invariant (ADR 0002):** no unattended self-repair loops. `kbg:recursive-improve` stops at a user `AskUserQuestion` gate before any mutation.
- **Inferential feedback is advisory:** sensors like `verification-gate.sh` journal only — they never emit a `permissionDecision`.
- **Cache-invalidation is manual:** version bump in both manifests + `claude plugin update kbg@kobig` + restart.

## Full inventory

- Skills: `ls skills | sed '/^_lib$/d'` or `grep -r "^name:" skills/*/SKILL.md`
- Commands: `ls commands/*.md | sed 's|commands/||;s|\.md||'`
- Agents: `ls agents/*.md | sed 's|agents/||;s|\.md||'`
- Hooks: `jq '.hooks[].name' hooks/hooks.json`

For deeper discovery, run `kbg:harness-nav`.
