---
name: autonomous-loops
description: "Choose an autonomous-loop architecture for a task, then dispatch to native Workflow / /loop / Cron. From simple sequential pipelines to RFC-driven multi-agent DAG orchestration."
metadata:
  origin: ECC
---

# Autonomous Loops Skill

> Compatibility note (v1.8.0): `autonomous-loops` is retained for one release.
> The canonical skill name is now `continuous-agent-loop`. New loop guidance
> should be authored there, while this skill remains available to avoid
> breaking existing workflows.

Pick the right architecture, then dispatch via native Claude Code tools.

## When to Use

- Setting up autonomous development workflows that run without human intervention
- Choosing the right loop architecture for your problem (simple vs complex)
- Building CI/CD-style continuous development pipelines
- Running parallel agents with merge coordination
- Implementing context persistence across loop iterations
- Adding quality gates and cleanup passes to autonomous workflows

## Loop Pattern Spectrum

From simplest to most sophisticated:

| Pattern | Complexity | Dispatch Mechanism | Best For |
|---------|-----------|-----------|----------|
| Sequential Pipeline | Low | `claude -p` chain or `Bash` script | Daily dev steps, scripted workflows |
| NanoClaw REPL | Low | Interactive REPL | Persistent sessions |
| Infinite Agentic Loop | Medium | `Task` tool parallel + waves | Spec-driven parallel generation |
| Continuous Claude PR Loop | Medium | `claude -p` + `gh` PR loop | Multi-day iterative projects with CI gates |
| De-Sloppify Pattern | Add-on | Extra `claude -p` pass | Quality cleanup after any Implementer step |
| Ralphinho / RFC-Driven DAG | High | Workflow tool / multi-agent DAG | Large features, multi-unit parallel work with merge queue |

> **Native alternatives:** `claude -p` is the platform non-interactive flag;
> the `Workflow` tool (scriptable JS orchestrator) replaces bespoke
> DAG scripts; `/loop` + `ScheduleWakeup` replace cron-style continuous
> loops. Prefer those over re-implementing the orchestration layer.

---

## 1. Sequential Pipeline

The simplest loop. Chain non-interactive `claude -p` calls. Each call is a focused step with a clear prompt. Order matters; exits propagate; clean up between steps with `SHARED_TASK_NOTES.md` or filesystem state.

**Native alternative:** a Bash script with `set -e`.

## 2. NanoClaw REPL

Session-aware REPL that wraps `claude -p` with persistence. Use when you need interactive exploration with state continuity.

## 3. Infinite Agentic Loop

Two-prompt system: an orchestrator that parses a spec, scans outputs, then deploys parallel sub-agents per wave (3–5 concurrent, uniqueness assigned by orchestrator not by agent). Use for spec-driven generation with many variations.

**Native alternative:** the `Task` tool with `parallel` or the `Workflow` tool.

## 4. Continuous Claude PR Loop

Production shell loop: branch → `claude -p` → optional reviewer pass → commit → push → PR → wait CI → auto-fix → merge. Bound by `--max-runs` / `--max-cost` / `--max-duration` / completion signal.

**Native alternative:** `/loop` + `ScheduleWakeup` for cron-style cadence; `gh pr merge` for landing.

## 5. De-Sloppify Pattern

Add-on pass. Separate context, focused cleanup: remove type-system tests, redundant runtime checks, framework-behavior tests. Never add negative instructions to the Implementer — add a separate pass.

## 6. Ralphinho / RFC-Driven DAG

Most sophisticated. Decompose RFC into a dependency DAG; route units through tiered quality pipelines (research → plan → implement → test → review); land via merge queue with eviction. Each stage in a separate context to eliminate author bias.

**Native alternative:** the `Workflow` tool (`agent()` / `parallel()` / `pipeline()` / `phase()`) is the canonical way to script DAG orchestration. Cross-unit merge logic still needs custom merge-queue logic.

---

## Choosing the Right Pattern

```
Is the task a single focused change?
├─ Yes → Sequential Pipeline or NanoClaw
└─ No → Is there a written spec/RFC?
         ├─ Yes → Do you need parallel implementation?
         │        ├─ Yes → Ralphinho (DAG orchestration)
         │        └─ No → Continuous Claude (iterative PR loop)
         └─ No → Do you need many variations of the same thing?
                  ├─ Yes → Infinite Agentic Loop (spec-driven generation)
                  └─ No → Sequential Pipeline with de-sloppify
```

### Combining Patterns

1. **Sequential Pipeline + De-Sloppify** — the most common combination.
2. **Continuous Claude + De-Sloppify** — add a `--review-prompt` with cleanup directive each iteration.
3. **Any loop + Verification** — use the `verification-loop` skill as a gate before commits.
4. **Tier-based model routing** — simple fixes → Haiku; architectural work → Opus; default to Sonnet. Routing works inside any loop.

---

## Anti-Patterns

1. **Infinite loops without exit conditions** — always cap with `--max-runs`, `--max-cost`, `--max-duration`, or completion signal.
2. **No context bridge between iterations** — each `claude -p` starts fresh. Bridge via `SHARED_TASK_NOTES.md` or filesystem state.
3. **Retrying the same failure** — capture error context and feed it forward; don't blind-retry.
4. **Negative instructions instead of cleanup passes** — model becomes hesitant; add a separate de-sloppify pass.
5. **All agents in one context window** — separate concerns into distinct agent processes; the reviewer must not be the author.
6. **Ignoring file overlap in parallel work** — if two parallel agents might edit the same file, you need a merge strategy.

---

## Live Docs

For current Claude Code non-interactive flags (`claude -p`), Workflow tool API, and `/loop` syntax, see [Claude Code docs](https://docs.claude.com/en/docs/claude-code) via context7.
