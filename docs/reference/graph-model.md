# Orchestration Graph Model

Formalizes matt-harness's existing dispatch/verification structure as an explicit graph — nodes,
typed edges, anchors — instead of leaving it scattered across `skills/orchestrate/SKILL.md`,
`BOUNDARY.md`, and per-skill "Boundary with X" notes. **This document adds no new mechanism.** It
names what already runs today; where prior art (GraphBit, LangGraph) enforces something kbg only
enforces by prompt discipline, that gap is stated plainly, not silently closed.

**Origin and honesty check.** Triggered by a Thai-language summary of an eigent.ai blog post
("Graph Engineering for AI Agents") claiming graph-based multi-loop orchestration is a distinct
discipline with 4 named failure modes and an "anchors" concept. Full grounding research:
`docs/research/graph-engineering-agent-systems-2026-07-27.md`. Short version of that research's
verdict: the underlying intuitions (verifier-generator asymmetry, specification gaming, goal
misgeneralization, MAS coordination conflict, concept drift) are all real and separately
well-studied — but the eigent.ai post's own 4-way taxonomy repackages them under new labels rather
than contributing new science, and "typed edges" isn't even a term that post uses (it traces to an
academic paper, GraphBit, arXiv:2605.13848). This doc borrows the useful vocabulary and discards
the marketing framing.

## Nodes

matt-harness's node inventory is already tracked, auto-generated, and canonical in `BOUNDARY.md` —
this doc doesn't duplicate that table, it names the node *types* the edges below connect.

| Node type | Defined in | Computational role |
|---|---|---|
| Skill | `skills/*/SKILL.md` | Loaded on-demand by Claude Code's own description-matching; carries `allowed-tools` (pre-approval only, not a hard ceiling) |
| Agent | `agents/*.md` | Dispatched via the `Agent` tool; carries a hard `tools:` allowlist — the real authorization boundary (`skills/orchestrate/SKILL.md` lines 24–32) |
| Command | `commands/*.md` | User-invoked slash command; some carry `disable-model-invocation: true` (model-uninvocable, user-only) |
| Gate | `hooks/gates/*.sh` | Deterministic verifier node — runs on a `PreToolUse`/`WorktreeCreate` hook, returns a branchable score, can deny |
| Advisory sensor | `hooks/advisory/*.sh` | Journal-only node — never emits `permissionDecision`, never blocks |

## Typed edges

The relationship vocabulary already in active use, made explicit. "Mechanical" means a tool or
hook enforces the edge; "prompt-discipline" means a human (the lead) is trusted to honor it, with
no runtime check that they did.

| Edge | Definition | Where implemented | Enforcement |
|---|---|---|---|
| `routes-to` | Orchestrator → executor, one of 4 typed values | `skills/orchestrate/SKILL.md` lines 360–370 (`inline`/`parallel`/`sequential`/`drop`) | Prompt-discipline — the lead picks the Route cell by matrix judgment; nothing validates the choice against the matrix mechanically |
| `depends-on` | Downstream task requires an upstream task's verified output before it may run | Builder→Validator→Fixer→Re-validator chain (`SKILL.md` lines 108–153); `addBlockedBy` / `board.json`'s `depends_on` field | **Ordering** is mechanical (`gate:task:complete-separation`, `hooks/gates/task-complete-separation.sh`, blocks a subagent from self-marking `completed`) — but the **payload** crossing the edge (task 2 needs task 1's exact files, task 3 needs the validator's verdict text verbatim) is prompt-discipline: the lead manually copies the right content into the next spawn prompt (`SKILL.md` lines 145–151, "Upstream contract propagation"). No schema checks that the copy was complete or correct. |
| `verifies` | A gate or sensor checks an action/artifact against a deterministic rule | `hooks/gates/*.sh` → the Bash call, git operation, or task-completion claim it inspects | Mechanical by construction — this is the one edge type kbg enforces the same way GraphBit enforces typed edges (a non-LLM engine decides, not the model) |
| `hands-off-to` | One skill's scope ends and names the skill that owns the next piece | The "Boundary with X" prose sections — currently only 2 in the whole fleet, both in `skills/orchestrate/reference.md` (boundary with the decision doctrine, METHODOLOGY Rule 1; boundary with `/mattpocock-skills:wayfinder`, user-invoked) | Prompt-discipline only — this edge exists purely as prose a human/model reads, not a structure anything queries or validates. Sparse: worth naming as under-instrumented rather than assuming it's systematic. |

## Anchors — what's real, what's missing

The eigent.ai post's actual claim (verified against a direct fetch, not the Thai summary):
"a graph without anchors is just a more elaborate echo chamber." Checked against what kbg
actually has:

**Real:**

- `hooks/gates/*.sh` — deterministic shell checks (Bash pattern matching, git state, task
  `agent_type` field) that a model cannot talk its way past. `task-complete-separation.sh` is
  the clearest instance: a subagent's `agent_type` is fixed at spawn and can't self-declare
  `completed` — only the main session can, closing the maker-grades-own-work loop (CLAUDE.md's
  "unifying crux," under §Architecture).
- `harness-audit`'s deterministic checks and the fixture-based improve/optimize loop's live
  re-verification step (re-running a fixed prompt against the edited surface and diffing the
  result) are the closest thing kbg has to a held-out eval set.

**Missing:** none of the above ties to anything *outside* the harness's own state. A held-out
eval set the harness didn't author, or a real usage metric (which skills actually reduce rework,
say), would be a true external anchor in the eigent.ai sense. Today's anchors check "did this
action violate an internal rule" — not "did this actually work, according to something the
harness can't rewrite." Whether closing this gap is worth it depends on whether matt-harness's
domain (a Claude Code plugin, evaluated mostly via fixture loops) has a real equivalent of
"banked revenue" to anchor against — an open question, not resolved by this doc.

**Related, already-designed-but-shelved:** `docs/research/sensor-staleness-notifier-design.md`
(2026-06-15) addresses a narrower, adjacent problem — detecting when an *existing* sensor stops
firing at all (a coverage gap, not a quality signal), which maps to the eigent.ai post's
"measurement decay" failure mode specifically, not the external-anchor gap above. Status: design
only ("awaiting HOOK-1 / AUDIT-1 / CMD-1 / FIX-1"), never built — no proven incident has forced it
since. Listed here so a future pass doesn't re-derive the same design from scratch.

## Known limitation against prior art

GraphBit's typed edges are enforced by a Rust engine at runtime: a node cannot run until its
typed input exists, checked mechanically. kbg's `depends-on` edge enforces *ordering* the same
way (the gate above) but not *payload correctness* — nothing catches the lead pasting an
incomplete or wrong upstream artifact into the next spawn prompt. This is a deliberate trade-off,
not an oversight: matt-harness is a prompt-driven fleet governed by Rule 13 (orchestrators
delegate; they don't implement tooling), not a compiled DAG engine, so building a schema-validator
for spawn-prompt payloads would be new infrastructure against no proven failure yet (Rule 2). Name
it here so a future author doesn't assume it's already mechanically checked.

## Relationship to existing docs

- **`BOUNDARY.md`** — the canonical, auto-generated node inventory (agents/commands/hooks with
  tools/mutates columns). This doc adds the edge/anchor layer on top; it doesn't replace or
  duplicate BOUNDARY.md's tables.
- **`docs/reference/decision-doctrine-map.md`** — already does the same situation→mechanism→owning-rule
  shape this doc generalizes, scoped to decision doctrine specifically rather than the whole
  orchestration graph. Read that file for the decision-routing edges this doc doesn't re-list.
- **`docs/research/graph-engineering-agent-systems-2026-07-27.md`** — full primary-source grounding
  (~22 citations: LangGraph, AutoGen, CrewAI, GraphBit, Anthropic's own multi-agent engineering
  post, DeepMind's specification-gaming taxonomy, goal-misgeneralization and LLM-judge-bias papers)
  for every claim made above.
