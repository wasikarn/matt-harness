# ADR 0008 — Decommission the agent-teams feature

Date: 2026-06-26
Status: Accepted
Supersedes: — (narrows the surface set ADR 0006's operating model governs; no
principle change)

## Context

kbg shipped an `agent-teams` feature gated behind Anthropic's
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` flag. Its user-facing surface was four
slash commands — `/team-plan`, `/team-build`, `/team-cleanup`, `/wave-status` —
plus an agent-teams doctrine woven through the `orchestrate` skill (F8
lead-coordinator doctrine, F9 spawn-template framing, a 3–5 teammate sweet-spot,
and a builder→validator framing tied to `/team-build`).

The feature had no stability: persistent teammates blocked session exit, the
env-var gate was an experimental flag Anthropic could change beneath us, and the
doctrine entangled the general `orchestrate` skill with the team-specific
command set. Operating on it surfaced repeated hangs and teardown failures. The
operator decision (2026-06-26): remove the feature entirely rather than keep
patching an unstable experimental surface.

## Decision

Remove the `agent-teams` feature in full — the env-var-gated commands AND the
doctrine entanglement — and reframe `orchestrate` as pure inline-Agent
orchestration.

### Removed

- The four commands: `/team-plan`, `/team-build`, `/team-cleanup`, `/wave-status`
  (and their directory sub-trees: `commands/team-plan/references/*`,
  `commands/team-plan/scripts/task_size_check.py`, `commands/team-build/
  references/per-task-validation.md`).
- The `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env-var documentation in
  `docs/reference/env-vars.md`.
- The `agent-teams` / `team-plan` / `team-build` / `wave-status` / `team-cleanup`
  keywords from the plugin manifests.
- The agent-teams doctrine from `skills/orchestrate/SKILL.md`: the F8
  lead-coordinator doctrine, the F9 teammate spawn-template framing, the 3–5
  teammate sweet-spot, and the builder→validator framing tied to `/team-build`.
  Reframed as inline-Agent orchestration (the orchestrating lead dispatches
  subagents in waves and reviews their output).
- The `/team-build` allow-list markers from `hooks/gates/agent-spawn-gate.sh`
  (`ALLOW_PATTERNS` now matches dispatch markers only: `plan_slug:`, `task_id:`,
  `orchestrate`, `workflow`, `teardown`, `taskstop`). The "team workflow"
  allow-reason reframed to "approved dispatch allow-list".

### Kept as shared infrastructure (NOT team-specific)

The task board and lifecycle observability are general infrastructure used by
`skills/progressive-refine`, `hooks/lifecycle/task-lifecycle.sh` (F7 test-claim
gate), `scripts/task_board_lib.{sh,py}`, and audit check #46. These survive
unchanged:

- `~/.claude/tasks/<slug>/board.json` and the task-board library.
- `hooks/lifecycle/task-lifecycle.sh` and its `TeammateIdle` / `TaskCreated` /
  `TaskCompleted` event handling, the F7 test-claim gate, the
  `teammate_teardown_ready` advisory, and the `~/.claude/team-events/*.jsonl`
  journal. `TeammateIdle` / `teammate` is Claude Code's own event vocabulary
  (the hook is wired into settings.json under those event names); it is kept as
  the shared-infra data model, not as agent-teams doctrine. Only the dangling
  `/team-build` command references in the hook's comments were reframed.
- The F8.5 fan-out cap / F8.4 under-parallelized advisory in
  `scripts/orchestrate-dispatch.py` + `scripts/orchestrate/planner.py` — these
  are deterministic coordination-as-code, tested by
  `eval/regressions/orchestrate-dispatch-schema.json`. Their emission strings
  (`F8.5 OVERFLOW`, `F8.4 UNDER-PARALLELIZED`) and the `teammate` wording in the
  under-parallelized advisory are stable behavioral contracts left intact.

`agent-spawn-gate.sh`'s behavioral reason strings ("persistent teammates",
"Background teammates") likewise use the CC event vocabulary and were kept
consistent with `task-lifecycle.sh`; only the doctrinal "team workflow" allow
wording was reframed.

## Consequences

- **One-way door, intentionally.** A shipped feature was removed. Operators
  with `/team-build` in muscle memory must move to `kbg:orchestrate` (inline
  Agent dispatch with the spawn-prompt template and validation chain) or to
  `scripts/plan-linter.py` for pre-flight plan validation. The CHANGELOG entry
  for 0.7.0 names the replacements.
- **Re-addition guard.** This ADR is the durable rationale a future session must
  overcome before re-introducing an agent-teams surface. The instability was the
  reason, not a transient bug; re-adding the feature without resolving the
  persistence/teardown instability would repeat the failure. Any re-introduction
  requires a new ADR superseding this one and a stability story for persistent
  teammates.
- **No contract break for kept infra.** `task-lifecycle.sh`, the task board,
  `orchestrate-dispatch.py`, and `progressive-refine` are byte-identical in
  behavior; only command-reference comments and prose were reframed. The
  regression evals (`agent-spawn-gate-incident.json`,
  `orchestrate-dispatch-schema.json`, `bounded-agent-spawning.json`) were
  reconciled to the reframed surfaces and verified against live hook/script
  output.
- **Component-count drop.** 17 → 13 slash commands; manifests, README, and
  `inventory-boundary.sh` XREF counts updated. `BOUNDARY.md` regenerated.