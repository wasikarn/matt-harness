# DOMAINS.md — Bounded contexts for kbg-harness

This file is referenced by the bounded-context dispatch rule in `~/.claude/CLAUDE.md`
and by `hooks/advisory/orchestrator-nudge.sh` path-overlap detection. Keep the
`## Path → Context` table in sync with `orchestrator-nudge.sh` `PATH_PATTERNS`.

## Contexts

| Context | Owns |
|---|---|
| `plugin-surface` | Auto-discovered plugin components: `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`, plus the two manifests under `.claude-plugin/`. |
| `doctrine` | L1 resident doctrine: `METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md`, `CLAUDE.md`, `DOMAINS.md`, `BOUNDARY.md`, `docs/adr/`. |
| `audit-eval` | Self-test and eval harness: `skills/harness-audit/`, `skills/harness-coverage/`, `skills/critical-eval/`, `tests/`, `eval/`. |
| `infra` | Scripts, CI, and packaging glue: `scripts/`, `git-hooks/`, `.github/`. |
| `docs` | Human-readable documentation outside doctrine: `docs/` (non-ADR), `README.md`, `CHANGELOG.md`. |

## Path → Context

| Path pattern | Context | Notes |
|---|---|---|
| `commands/` | Execution | User-facing action verbs (`/feature-dev`, `/fix-bug`, `/deep-dive`, `/ship-*`). |
| `skills/` (non-orchestrate/non-audit) | Execution | Work-doing skills (`/backend-dev`, `/acli`, `/semantic-code`, `/assert-presence`). |
| `skills/orchestrate/` | Orchestration | Workflow planning and dispatch (`/orchestrate`, `scripts/orchestrate-dispatch.py`). |
| `skills/inventory/` | Orchestration | Boundary regeneration and fleet accounting. |
| `skills/harness-audit/`, `skills/harness-coverage/`, `skills/critical-eval/` | Quality | Self-audit, coverage grid, eval fixtures. |
| `skills/review-pr/`, `skills/security-auditor/`, `skills/probe/` | Quality | Review and verification surfaces. |
| `tests/`, `eval/` | Quality | Regression fixtures and eval harness. |
| `skills/adr/`, `docs/` (non-ADR), `commands/address-review.md`, `commands/status-update.md`, `commands/post-mortem.md` | Communication | Documentation and status surfaces. |
| `skills/incident/`, `skills/hotfix/` | Emergency | Incident / hotfix response. |
| `agents/` | Implementation | Specialist subagent definitions. |
| `METHODOLOGY.md`, `RTK.md`, `ACLI.md`, `DBGATE.md`, `CLAUDE.md`, `DOMAINS.md`, `BOUNDARY.md`, `docs/adr/` | doctrine | Always-resident doctrine files. |
| `scripts/`, `git-hooks/`, `.github/` | infra | Deterministic automation and CI. |
| `README.md`, `CHANGELOG.md` | docs | Project-level human docs. |

## Invariants

- A change that touches only files within one context above should be done inline
  or by the context's owning skill/agent.
- A change that touches ≥2 contexts should be routed via `kbg:orchestrate` (or
  `/orchestrate` when the plugin is loaded), not serially inlined.
- `hooks/` changes always affect `audit-eval` (critical-hooks tests) and
  `plugin-surface` (registration) simultaneously — treat as cross-context.
