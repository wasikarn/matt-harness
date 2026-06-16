---
name: hotfix
description: "Use this skill for emergency production fixes requiring immediate code change. Trigger when user says 'production is down', 'critical bug', 'hotfix', 'emergency patch', 'P0', 'outage', or any production-wide incident. Rollback-first, severity-gated SLA, timeboxed execution. Do NOT use for: non-urgent bugs (use /fix-bug), subset-affecting issues, new features, or when rollback/kill-switch suffices."
---

# Hotfix

Ship a critical fix fast. This is a compressed version of `/fix-bug` + `kbg:review-pr` + `/ship-merge` with gates removed for speed. **Rollback first, fix forward second.**

This skill produces a structured hotfix plan for the main agent to execute inline. It does not dispatch sub-agents — the main agent holds full context and acts with surgical speed.

> **Why this skill is model-invokable (no `disable-model-invocation`) despite reaching `gh pr merge --admin`:** it is a *capability the operator reaches for under an incident* — invoked off an explicit "production is down / P0" request where speed is the whole point and a user-only gate would defeat it. The irreversible prod merge is reached only after the in-skill severity + review gates and runs through Bash, which carries its own guards. The safety here comes from those gates, not from making the skill user-only. (The non-urgent twin `/fix-bug` *is* user-only — there, deliberate timing is the right default.)

## Core Principles

- **Stop the bleeding first.** Rollback or kill-switch is always faster than code. Only hotfix when rollback is impossible or insufficient.
- **Severity drives speed.** P0 = ship in <15 min. P1 = <1 hr. P2 = <4 hr.
- **Smallest possible change.** One file, one line if possible. No refactors, no cleanups.
- **Server-side merge only.** Never `git merge` locally + push. Use `gh pr merge --admin`.
- **Post-merge watch, not hope.** Verify CI + monitor for 10 minutes. Be ready to revert.

---

## Severity Classification

Infer from user input or ask explicitly.

| Tier | User Says | MTTM Target | Merge Gate |
|------|-----------|-------------|------------|
| **P0** | "down", "outage", "exploit", "data loss", "P0" | <15 min | Zero Block items. Skip non-Critical review. `--admin` merge immediately after fix + 1 reviewer. |
| **P1** | "critical", "security patch", "broken", "P1" | <1 hr | Fast review (code-reviewer + conditional security-reviewer). Minimal regression test. `--admin` merge. |
| **P2** | "degraded", "slow", "SLO breach", "P2" | <4 hr | Standard fast review. Full regression test. Prefer normal `/ship-merge` if CI is green; `--admin` only if CI is flaky. |

**Default if unclear:** Assume P1. Do not waste time debating — pick one and move.

---

## Phase Overview

| Phase | Goal | Gate |
|-------|------|------|
| 0 | Rollback / kill-switch first | Resolves? STOP. Subset scope? Decline |
| 1 | Reproduce in <5 min | No repro → abort to `/fix-bug` |
| 2 | Smallest surgical fix | >3 files / structural rework → abort |
| 3 | Fast review (parallel) | Block items unresolved → abort |
| 4 | Server-side merge via `gh pr merge --admin` | Never merge locally + push |
| 5 | Post-merge verify + monitor | CI fails / symptoms return → revert |
| 6 | Schedule `/post-mortem` | Within 24h (P0/P1) or 72h (P2) |

## Handoff Reference

| Phase | Action | When |
|---|---|---|
| 0 → 1 | Rollback or kill-switch check | Before any code change |
| 1 → 2 | Fix inline | After repro confirmed ≤5 min |
| 2 → 3 | Launch `code-reviewer` (+ `security-reviewer` if needed) | After fix + regression test |
| 3 → 4 | Commit + push + `gh pr merge --admin --squash --delete-branch` | After zero Block findings |
| 4 → 5 | `gh run watch` + repro against prod | After merge |
| 5 → 6 | Tell user to schedule `/post-mortem` | After verify passes |

See [reference.md](reference.md) for: full Phase 0–6 procedures, output format (ledger), anti-patterns, and METHODOLOGY alignment.

## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
