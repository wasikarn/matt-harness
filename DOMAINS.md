# DOMAINS.md — Bounded contexts for kbg-harness

This file is referenced by the bounded-context dispatch rule in `~/.claude/CLAUDE.md`
and by `hooks/advisory/orchestrator-nudge.sh` path-overlap detection. The
`## Path → Context` table below mirrors `orchestrator-nudge.sh` `PATH_PATTERNS`
**token-for-token** — the hook is the source of truth (edit `PATH_PATTERNS`
first, then mirror here). Drift is machine-checked by `harness-audit` check #37,
so the two can no longer silently diverge.

## Contexts

| Context | Owns |
|---|---|
| `plugin-surface` | Auto-discovered plugin components: `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`, plus the two manifests under `.claude-plugin/`. |
| `doctrine` | L1 resident doctrine: `METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md`, `CLAUDE.md`, `DOMAINS.md`, `BOUNDARY.md`, `docs/adr/`. |
| `audit-eval` | Self-test and eval harness: `skills/harness-audit/`, `skills/harness-coverage/`, `skills/critical-eval/`, `tests/`, `eval/`. |
| `infra` | Scripts, CI, and packaging glue: `scripts/`, `git-hooks/`, `.github/`. |
| `docs` | Human-readable documentation outside doctrine: `docs/` (non-ADR), `README.md`, `CHANGELOG.md`. |

## Path → Context

_The `Context` column here is the orchestrator-nudge **routing label** — the hook
fires when a prompt's file paths span ≥2 labels. This is a finer-grained map than
the 5 bounded-contexts in `## Contexts` above (e.g. it splits work-doing skills
into Execution / Implementation / Integration); the two models serve different
consumers and do not share vocabulary by design. Tokens below are the literal
`PATH_PATTERNS` keys, not slash-prefixed skill invocations._

| Path pattern(s) | Context | Notes |
|---|---|---|
| `commands/feature-dev`, `commands/fix-bug`, `commands/deep-dive`, `skills/migrate`, `skills/perf`, `skills/research-brief`, `skills/types-first`, `skills/task-sizing`, `skills/tech-humanize` | Execution | User-facing action verbs + work-doing skills. |
| `skills/backend-dev`, `agents/`, `app/`, `src/`, `packages/`, `services/`, `lib/` | Implementation | Code that ships behavior + the agents that write it. |
| `skills/ship-change`, `skills/orchestrate`, `skills/inventory` | Orchestration | Workflow planning, dispatch, fleet accounting. |
| `skills/harness-audit`, `skills/harness-coverage`, `skills/critical-eval`, `skills/review-pr`, `skills/security-auditor`, `skills/probe`, `tests/`, `eval/` | Quality | Self-audit, coverage, review, verification, fixtures. |
| `skills/adr`, `commands/address-review`, `commands/status-update`, `commands/post-mortem`, `docs/` | Communication | Documentation and status surfaces. |
| `skills/incident`, `skills/hotfix`, `runbooks/` | Emergency | Incident / hotfix response. |
| `skills/acli`, `skills/assert-presence`, `skills/decommission`, `skills/memory-lint`, `skills/semantic-code`, `commands/ship-merge`, `commands/ship-release`, `commands/ship-task`, `.scratch/` | Integration | External systems, release, decommission, scratch I/O. |
| `METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md`, `CLAUDE.md`, `DOMAINS.md`, `BOUNDARY.md`, `docs/adr/` | doctrine | Always-resident doctrine files. |
| `scripts/`, `git-hooks/`, `.claude-plugin/` | infra | Deterministic automation, CI, manifests. |
| `README.md`, `CHANGELOG.md` | docs | Project-level human docs. |

## Invariants

- A change that touches only files within one context above should be done inline
  or by the context's owning skill/agent.
- A change that touches ≥2 contexts should be routed via `kbg:orchestrate` (or
  `/orchestrate` when the plugin is loaded), not serially inlined.
- `hooks/` changes always affect `audit-eval` (critical-hooks tests) and
  `plugin-surface` (registration) simultaneously — treat as cross-context.
