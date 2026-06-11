# ADR 0002: Autonomy invariant — no autonomous or unattended self-repair loop

- **Status**: Accepted
- **Date**: 2026-06-12
- **Decider**: Owner

## Context

The harness ships a `recursive-improve` skill whose purpose is to run a
self-improvement cycle (observe verification + audit signals → propose ranked
candidates → ASK → act → verify → surface). The cycle is **iterative** by
design — it observes a session, proposes a change, asks, acts, verifies — and
could in principle be chained: the model's own improvement cycle could be the
trampoline for the next model's improvement cycle, indefinitely.

Three loop architectures were considered, in increasing order of autonomy:

- **L1 — Fully attended.** The user invokes `/kbg:recursive-improve` by hand
  for each cycle. Every Step 3 `AskUserQuestion` is real because the user is
  present. Bounded by user attention; does not scale.
- **L2 — Hooked, with human gate.** The cycle is wired to a hook (e.g. a
  `Stop` hook) but every iteration still requires a human `AskUserQuestion`
  before any mutation. The hook is a notification, not a trigger. This is
  the current `recursive-improve` shape (`SKILL.md:3-4, 17-23, 75-89`).
- **L3 — Scheduled, with model-as-gate.** The cycle runs on a cron
  (vendor `/loop` or `CronCreate`), and a fresh-context subagent decides
  whether each iteration is "done enough" to commit. No human in the loop
  except as the final reviewer. This is the "self-rewriter" pattern the
  corpus names (Evo, Opik Ollie flywheel, Ralph Wiggum cadence).
- **L4 — Fully autonomous.** No human in the loop at all. The model is its
  own gate, its own verifier, its own stopper. This is the speculative
  ceiling and the corpus's worst case (the "agent slop" risk).

The corpus's loop-engineering guides (Addy Osmani's *Loop Engineering*, the
*14-step roadmap*, the *How to Build a Self-Improving Loop* guide) all assume
**some** form of unattended cadence is the goal. They differ on which
architectural primitive unlocks the cadence (`/loop` vs cron vs decision-maker
in the body), but they converge on the assumption that **the loop's job is to
remove the human from the iteration**, with the human acting only as
occasional reviewer.

That assumption is the contested point. The harness already had a partial
policy before 2026-06-11 (`CONTEXT.md` §Invariants named the invariant in
prose, `recursive-improve/SKILL.md` had `disable-model-invocation: true`,
`METHODOLOGY.md` Rule 4 had the fresh-context verification sentence). The
round-1 / round-2 audits (PRs #11–#14) added 10 doc-edit tickets but never
codified the invariant as an irreversible decision. Round-2's fresh-context
drill-down (5-agent pipeline, 2026-06-12) found:

1. The invariant has **5 surfaces** (`CONTEXT.md:46-56`, `METHODOLOGY.md:67`,
   `recursive-improve/SKILL.md:3-4, 17-23, 127`, `harness-decay-cadence.md:54-67`,
   and the hooks themselves) — no audit check or ADR guarded it.
2. The corpus's autonomy primitives (`/loop`, `CronCreate`, Evo meta-loop,
   Ollie flywheel) are *not* in the harness's vocabulary by design, but the
   reasoning behind the rejection was not preserved anywhere as a load-bearing
   record.

The decision needs to be ADR-canonical so future contributors can find it
without reading all 5 surfaces, and so it can be cross-referenced from
`CONTEXT.md` and `harness-decay-cadence.md` (the two docs that name the
invariant in prose).

## Decision

Adopt **L2 (hooked, with human gate)** as the harness's *only* loop
architecture. The harness **MUST NOT** ship L3 or L4 loops. The invariant,
reproduced verbatim from `CONTEXT.md:46-56`:

> No autonomous or unattended self-repair loop, and no multi-iteration
> loop that runs without a human gate between iterations. Every
> self-improvement iteration stops at a human `AskUserQuestion` gate
> before any mutation, and `recursive-improve` stays
> `disable-model-invocation: true` so the model cannot self-start it.
> The gate is a deliberate **judgment-preservation** choice — not a
> capability gap to be closed as models improve; the same loop
> machinery preserves or destroys engineering judgment depending on
> operator intent, and the loop can't tell the difference.

Implementation (5 surfaces, all required):

1. **Canonical home** — `CONTEXT.md:46-56` (this ADR cross-references it).
2. **Doctrinal reinforcement** — `METHODOLOGY.md:67` (Rule 4 verification
   sentence + "every loop terminates at a human gate; the doctrine is
   the gate" corollary).
3. **Skill self-binding** — `skills/recursive-improve/SKILL.md:3-4`
   frontmatter `disable-model-invocation: true` + `:17-23` autonomy
   invariant block + `:75-89` Step 3 mandatory `AskUserQuestion` (not
   optional, not soft, "never fail open into execution").
4. **Decay-cadence hard guard** — `docs/harness-decay-cadence.md:54-67`
   "**never** auto-delete maker≠checker", "**no** auto-prune"; the
   invariant is the test by which decay findings are evaluated.
5. **Deterministic audit** — `skills/harness-audit/scripts/audit.sh`
   check #32 (added 2026-06-12 in commit `1d60b00`) is a CRIT-severity
   grep on `skills/recursive-improve/SKILL.md` for
   `disable-model-invocation: true` (exact-match, regression-guard
   against truthy typos like `: True`).

The 5-iteration soft cap in `recursive-improve/SKILL.md:127` is **not** a
primary enforcement surface — it is a context-exhaustion backstop. The
human gate at Step 3 is the load-bearing single point of enforcement.

## Consequences

### Foreclosed (these patterns will never ship in this harness)

- **L3 — scheduled with model-as-gate.** No `/loop` integration that calls
  `recursive-improve` without a fresh human gate at every iteration. The
  `disable-model-invocation: true` field exists precisely to prevent the
  model from *starting* such a loop, but even user-initiated `/loop` chains
  that hit `recursive-improve` still terminate at the per-iteration gate
  (verified by the round-2 autonomy drill-down, 2026-06-12).
- **L4 — fully autonomous.** No eval-optimizer unattended loop, no Evo
  meta-loop that rewrites the optimize loop, no Opik Ollie flywheel that
  traces-and-fixes-and-regression-locks without human review. The harness's
  `verification-gate.sh` is a *sensor* (per its own header: "Pure SENSOR: it
  journals but NEVER emits a `permissionDecision`"), never an autonomous
  actuator.
- **Auto-prune decay.** `harness-decay-cadence.md:10-11, 54-67` is
  explicit: "documents an existing practice; it adds **no new machinery**
  and **no auto-prune**". A decay finding is a candidate the human reviews,
  not a state the system transitions.
- **Trust-the-model verifier collapse.** The maker≠checker separation
  (METHODOLOGY Rule 4) is protected by the hard guard
  (`harness-decay-cadence.md:54-67`): "Decay reasoning must **never** retire
  a verifier on the argument that 'the model can verify its own work
  now.'" The reason is **vouchability and independence** — a fresh-context
  checker catches what the maker cannot see — not because the model is too
  weak to check. Lifting this guard is a category error, not a capability
  unlock.

### Made possible (these are the invariant's benefits)

- **Judgment preservation.** The operator's taste, intent, and accountability
  for the harness's output stay load-bearing. The loop can amplify a
  judgment, but it cannot substitute for one. (Per Osmani: "your taste is
  the edge".)
- **No agent-slop self-rewriter.** A self-rewriter that "improves" the harness
  into a state the operator no longer recognizes — and can no longer vouch
  for — is the worst-case failure mode of L3/L4 architectures. The
  invariant forecloses this category.
- **Reversibility.** Every change proposed by `recursive-improve` is gated
  before mutation; the operator can say "no" at any iteration. The loop
  is composed of bounded steps, not cumulative state.
- **Honest plugin delivery.** `kbg-harness` is a personal harness with
  the owner as the only user. The doctrine is mandatory (per
  `CONTEXT.md:40-44`); there is no anonymous-user surface to defend.
  The invariant is the load-bearing guarantee that "the operator's
  judgment is always the final reviewer", which is what makes a personal
  harness defensible at all.

### Documented trade-off (cost of the invariant)

- **Velocity.** L3/L4 architectures scale to thousands of iterations per
  day. L2 (this harness) is bounded by operator attention. The trade-off is
  explicit: the harness is slower than it could be, on purpose. The
  corpus's "single agent ~4x chat cost, multi-agent ~15x" numbers
  (Agentic Loops From ReAct to Loop Engineering 2026 Guide) are not the
  harness's target — the operator is the bound, not the budget.

- **Multi-machine continuity requires operator attention per machine.**
  The cross-machine state is the git repo itself (per `CONTEXT.md` and
  ADR 0001 §Consequences), not an active loop. Every machine that
  pulls a new commit gets the latest harness, but no machine runs an
  unattended improvement cycle.

## Rejected alternatives

- **L3 (scheduled, model-as-gate).** The corpus's
  recommended architecture. Rejected because the operator's judgment
  is the load-bearing input, and a model-as-gate substitutes
  "plausibility of completion" for "alignment with intent". A
  sub-agent that decides "this iteration is done" is not the same as
  the operator deciding "this iteration matches what I wanted". The
  invariant treats these as non-equivalent, and the corpus's
  compressed cost (15x chat) does not pay for the substitution.

- **L4 (fully autonomous).** The speculative ceiling. Rejected
  outright — it is the agent-slop self-rewriter, the failure mode
  this harness was designed to prevent. Rejection is not
  capability-bounded; it is principle-bounded. (The principle:
  "the loop can't tell the difference" — see CONTEXT.md §Invariants.)

- **Evo-style meta loop that rewrites the optimize loop.** From
  *Self-Evolving Autoresearch Workflow Loops*. Would require lifting
  the invariant. Rejected: a meta loop is the highest-autonomy
  architecture, and the same judgment-preservation argument applies
  with extra force (the loop would be rewriting its own gating
  logic, which the human can no longer vouch for).

- **Opik Ollie flywheel (trace→fix→regression-locked).** From
  *Your Agent Harness Should Repair Itself*. The self-repair
  surface in this harness is **advisory**: `verification-gate.sh`
  is a SENSOR (never a `permissionDecision`, per its header); the
  fix decision is human-gated. A flywheel that traces, fixes, and
  locks regressions would be a Layer-1 actuator, not a Layer-2
  sensor, and is foreclosed by the invariant.

- **Ralph Wiggum cadence (max 5 attempts, soft completion).** From
  *How to Build a Self-Improving Loop in Claude Code*. The
  `recursive-improve` skill honors a 5-iteration cap
  (`SKILL.md:127`), but the cap is a context-exhaustion backstop,
  not the primary gate. The Ralph cadence's "score 4/5 means
  done" completion is rejected because completion requires the
  operator, not a scorer.

- **Lifting the invariant "when models improve".** The most likely
  future challenge. Explicitly rejected in CONTEXT.md:52-54: "deliberate
  **judgment-preservation** choice — not a capability gap to be closed
  as models improve". A model that can "verify its own work" still
  cannot vouch for the operator's intent. The invariant is independent
  of model capability and will not be reopened on a "the model got
  better" argument.

## Mapping to Harness-Engineering Corpus Prescriptions

The 16 articles in `llm-wiki/raw/ai-agents/harness-engineering/` prescribe
production harness + loop-engineering capabilities. Many of those
prescriptions assume **L3/L4 autonomy** as the natural evolution. This
section maps each article's key prescription to the harness's chosen
alternative (the L2-equivalent) and records the divergence explicitly
so future readers do not mistake a principled rejection for a
backlog gap.

### Loop-Engineering Articles (10)

| # | Article | Prescription | Harness Alternative | Divergence Rationale |
|---|---------|-----------|---------------------|----------------------|
| 1 | **Agent Loops Clearly Explained** | Remove the human from the middle; model self-feeds results in a closed loop. | **L2 hooked loop** — every iteration stops at a human `AskUserQuestion` gate before mutation. | Judgment preservation: the operator, not the model, fills the gap between "spec feels complete" and "spec actually is." |
| 2 | **Agentic Loops From ReAct to Loop Engineering** | Trigger + verifiable goal; autonomy tiers (L1→L10); multi-agent orchestration. | **Trigger + verifiable goal convention** (`ACCEPTANCE.md`) + **multi-agent orchestration via `orchestrate` skill** with human gate. | Autonomy tiers exist in vocabulary (L1–L5 in `orchestrate/reference.md`) but harness-internal loops are locked at L2. Multi-agent orchestration is present but gated. |
| 3 | **AI is eating the AI Engineering Loop** | Continuous eval loop: traces → dataset → eval → ship. Full automation possible but warned against (agent slop). | **`run-baseline-eval.py`** for A/B probes + **human-gated `recursive-improve`** for harness changes. | The article itself warns that full automation = agent slop. The harness takes the warning seriously and stops at L2. |
| 4 | **How to Build a Self-Improving Loop** | Done = verified; write → run checks → fix → repeat up to 5 times (Ralph Wiggum cadence). | **`recursive-improve` 6-step cycle** with 5-iteration cap as context-exhaustion backstop, NOT primary gate. | The Ralph cadence treats the scorer as the gate; the harness treats the operator as the gate. The 5-iteration cap is a backstop, not a completion signal. |
| 5 | **Loop Engineering Isn't What You Think** | Comprehension debt, cognitive surrender; read what the loop ships. | **Autonomy invariant** (`CONTEXT.md:46-56`, `METHODOLOGY.md:67`) — every change is human-reviewed before it ships, preventing comprehension debt by construction. | The article warns that loops make comprehension debt grow faster; the harness prevents it by forbidding unattended shipping. |
| 6 | **Loop engineering the 14-step roadmap** | Replace yourself as prompter; 4-condition test before building. | **Operator remains the prompter** via `recursive-improve`'s mandatory Step 3 gate; 4-condition test not mechanized but operator judgment serves the same filter. | The harness does not seek to replace the operator; it amplifies the operator. The 4-condition test (cost, frequency, verifiability, reversibility) is advisory doctrine. |
| 7 | **Loop Engineering (Addy)** | 5 pieces + memory: automations (heartbeat), worktrees, skills, plugins, sub-agents. | **Automations delegated to host** (`/loop`, `/schedule`, `CronCreate` documented in `orchestrate/reference.md` L5); **worktrees, skills, sub-agents** are present and load-bearing. | The heartbeat is host-provided; the plugin documents routing but does not wire harness-internal loops to it. |
| 8 | **Loops What Every AI Engineer Needs to Know** | Loop = program prompting model; model as subroutine; token-cost awareness. | **Model-as-subroutine is foreclosed** (L3/L4 rejection). **Token-cost awareness** is doctrine (`METHODOLOGY` Rule 6, `orchestrate/reference.md`) but not enforced. | The model is not a subroutine in this harness; it is a co-worker that stops for human approval. |
| 9 | **Self-Evolving Autoresearch** | Evo meta-loop rewriting the optimize loop; self-evolving workflow. | **Explicitly rejected** — a meta-loop rewriting its own gating logic is the highest-autonomy architecture and violates judgment preservation. | See §Rejected alternatives — Evo-style meta loop. |
| 10 | **WTF Is a Loop?** | Boris: "I have loops running"; continuous orchestration overseeing threads/agents. | **`orchestrate` skill** provides the orchestration vocabulary, but every multi-agent workflow routes through human gates. | The harness implements the orchestration pattern without the unattended execution. |

### Production Harness Articles (5)

| # | Article | Prescription | Harness Alternative | Divergence Rationale |
|---|---------|-----------|---------------------|----------------------|
| 11 | **AI Agent Best Practices** | Provider-neutral harness: model proposes, harness executes with schema/permissions/budget/safety checks. | **`PreToolUse` hooks** (`block-dangerous-git.sh`, `secret-read-guard.sh`) + **`harness-audit` CRIT checks** enforce schema/safety, but **budget checks are doctrinal only** (not code-enforced). | The harness has strong safety enforcement but weak budget enforcement. |
| 12 | **Building a Production Agent Harness** | 3 responsibilities: investigate, fix, self-improve; memory outlives session; react to external events; recover from failures. | **Investigate/fix** via skills/commands; **memory** via `.scratch/`, `journals/`, `memory/`; **external-event reaction** via hooks (session-bound); **recovery** is human-triggered. | Self-improve is L2 (human-gated). Recovery is manual, not auto-repair. Memory is present but not checkpointed. |
| 13 | **Harness Engineering 2026 (1)** | Agent = Model + Harness; thin harness philosophy (build to delete). | **Thick harness** (27 skills, 27 agents, 8 commands, 14 hooks) with explicit justification: judgment preservation requires documentation thickness. | The harness does not subscribe to the "thin harness" camp; it is deliberately thick because the operator is the bound, not the budget. |
| 14 | **Harness Engineering 2026 (2)** | Managed agents: brain/hands/session decoupled; sprint contracts; self-evaluation. | **Sub-agent specialization** (27 agents) approximates managed agents but without the decoupled session layer. **Sprint contracts** approximated by `accept-task` + `ACCEPTANCE.md`. | The harness does not decouple the session layer (no durable event log replay). Self-evaluation is separated into maker≠checker roles. |
| 15 | **The Anatomy of an Agent Harness** | 12 components: orchestration loop, tools, memory, context, state, error handling, guardrails, feedback, verification, safety, lifecycle. | **Guardrails, sub-agents, memory, context engineering** are strong. **Orchestration loop, state recovery, error handling (circuit breakers), verification automation** are weak or absent. | The harness is strong on governance/documentation, weak on production runtime hardening. See gap-closure spec for remediation plan. |

### Self-Repair Article (1)

| # | Article | Prescription | Harness Alternative | Divergence Rationale |
|---|---------|-----------|---------------------|----------------------|
| 16 | **Your Agent Harness Should Repair Itself** | Close the loop: trace → diagnose → fix → verify → regression-lock (Opik Ollie flywheel). | **`verification-gate.sh` as read-only sensor** + **`recursive-improve` human-gated proposals**. No automatic fix, no regression-lock without operator review. | The self-repair surface is advisory; the fix decision is human-gated. A flywheel that traces, fixes, and locks regressions would be a Layer-1 actuator, foreclosed by the invariant. |

### Summary of Divergence Pattern

The harness diverges from the corpus on **one axis only**: **autonomy level**.
On every other axis (sub-agent specialization, verifiable goals, maker≠checker
separation, context engineering, documentation, guardrails), the harness
implements or strongly approximates the prescription. The divergence is not
"we didn't get to it"; it is **"we chose not to, and here is why."**

The gap-closure spec (`.scratch/harness-loop-audit-2026-06-12/GAP-CLOSURE-SPEC.md`)
distinguishes between:
- **Blocked by ADR 0002** — items that require L3/L4 autonomy; these are
  acknowledged divergences, not backlog.
- **Eligible for closure** — items that can be promoted from partial/absent to
  present without violating the autonomy invariant.

## Verification

The invariant is enforced by 3 pillars:

1. **Deterministic** — `audit.sh` check #32 (commit `1d60b00`,
   2026-06-12) is a CRIT-severity check that fails any audit run on
   a repo where `skills/recursive-improve/SKILL.md` is missing
   `disable-model-invocation: true` in frontmatter. Verified by
   3 tests in `test-critical-hooks.sh` (PP/QQ/RR — clean / violation /
   truthy-typo regression guard). This pillar is non-negotiable: the
   check is in CI.

2. **Doctrinal** — 4 docs cross-reference the invariant
   (`CONTEXT.md:46-56`, `METHODOLOGY.md:67`,
   `recursive-improve/SKILL.md:17-23`,
   `harness-decay-cadence.md:54-67`). Each doc uses the wording
   preserved in §Decision above (or a paraphrase that retains the
   "judgment-preservation" rationale). Drift between docs is bounded
   by §Decision as the canonical text.

3. **Social** — code review (the `code-reviewer` agent) and the
   `recursive-improve` ritual's own Step 3 `AskUserQuestion` gate
   catch any human-attempted bypass. The Pillar 1 check is the
   load-bearing guard; Pillars 2-3 are belt-and-braces on top.

Conformance: `claude plugin validate --strict .` passes (CI-grade).
Audit green bar: `0C/0W/26I exit 0` after the round-2 batch and
this ADR. The 26 I1 advisories (24 SKILL_MISSING + 1
PERM_BOOKMARK + 1 plugin-cache) are unrelated to the invariant;
they are tracked in the 2026-09 quarterly sweep.

The invariant is **irreversible**. This ADR is the canonical record
that "this decision will not be reopened on a capability argument".
A future contributor who wants to revisit the invariant must
amend this ADR (not just override a check), and the amendment
itself is human-gated by the same loop machinery the invariant
forecloses.
