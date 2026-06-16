# ADR 0002 — Addendum: Deferred Items Mapping

- **Status**: Accepted (extends [ADR 0002](0002-autonomy-invariant.md))
- **Date**: 2026-06-12
- **Decider**: Owner
- **Scope**: Cross-references the 10 SYNTHESIS audit items that are
  deferred (not shipped, not on the roadmap) because shipping them
  would require either amending ADR 0002 (forbidden) or depending on
  vendor primitives the harness cannot lift.

## Context

[ADR 0002](0002-autonomy-invariant.md) §"Summary of Divergence Pattern"
and §"Mapping to Harness-Engineering Corpus Prescriptions" record
that **the harness's biggest absence is deliberate** — every
capability that requires an autonomous/self-driving loop is rated
absent or vendor-only at the plugin layer, and that's a principled
trade-off, not a backlog gap.

After the 2026-06-12 audit and the loop-engineering closure work,
10 SYNTHESIS items land in this category. Without an explicit
mapping, the next audit (or a new contributor) will re-flag these
as "missing" and waste cycles re-debating decisions that are
already made. This addendum is the **one-stop reference** for
"Why is X absent / partial?" answers, with the specific shipped
alternative for each.

## The mapping

| SYNTHESIS # | Title | Defer reason | Alternative shipped |
|---|---|---|---|
| #5 | `goal-primitive-stop-condition` | L3 territory (autonomous run-until-true with pause/resume requires model-as-gate) | `ACCEPTANCE.md` stop-condition contract — the contract layer is present, the autonomous executor is foreclosed |
| #21 | `machine-readable-feature-list` | L3 territory (a held-out eval dataset requires an L3 evaluator to use it for auto-selection) | `docs/agents/verification-trail.md` (P1.3) — the schema is richer than a feature list, and the eval-harness reads it directly |
| #32 | `worktree-isolation-parallel-agents` | Vendor primitive (worktree lifecycle is owned by `claude-code`, not by the plugin) | F8.5 bounded-fan-out gate in `commands/team-build.md` Step 6 (5 agents per wave, queue the rest) + per-wave contract chain in `skills/orchestrate/SKILL.md` § Bounded fan-out. Surfaced as `f8_5_overflow_warnings` in `scripts/orchestrate-dispatch.py` |
| #34 | `typed-tool-registry` | Vendor primitive (per-tool schema + risk class is owned by the host model) | `skills/orchestrate/SKILL.md` documents the agent-tool-grant shape; agents carry `tools:` frontmatter allowlists that are functionally equivalent at the plugin layer |
| #35 | `mcp-connectors-act-in-real-tools` | Vendor primitive (MCP transport + connector registration is host-owned) | `hooks/db-write-gate.sh` gates the one cross-vendor path the plugin owns (DB writes); other MCP connectors (atlassian, qmd, code-review-graph) inherit the vendor's reachability model |
| #40 | `loop-edits-own-shape-as-data` | L4 territory (concurrent meta-observer rewriting loop shape is the highest-autonomy architecture) | `recursive-improve` skill (P2.1 + P2.2) — human-gated single-cycle self-improvement, with stall detection and comprehension-debt ceiling as backstops |
| #44 | `minimize-tool-surface` | Would shrink host capabilities (the agent's tool grant is set by the operator's host config, not by the plugin) | Agents carry explicit `tools:` allowlists in frontmatter (e.g., `code-reviewer` denies `Edit`/`Write`/`Bash`); `agent-creator` enforces the allowlist at agent-spawn time |
| #45 | `build-to-delete-thin-harness` | L4 territory (component-off testing + auto-deletion is a closed loop the operator hasn't authorized) | `docs/harness-decay-cadence.md` (P1.2) — quarterly human-run component review, with `decommission` and `assert-presence` witnesses for tamper-evident state |
| #47 | `durable-checkpointed-state-recovery` | L4 territory (auto-recovery from a crashed session is unattended self-repair) | Journaled events in `.scratch/<slug>/` (session-scoped) + `docs/harness-decay-cadence.md` § Permission re-audit; cross-machine state continuity is out-of-scope by design (per `CONTEXT.md:46-58`) |
| #50 | `self-improving-harness-via-prs` | L4 territory, ADR 0002 forbids (harness rewriting its own source without human gate) | `recursive-improve` skill — human-gated proposal-then-ASK-then-act cycle; the operator, not the model, opens the PR |

## Why a separate addendum (not a section in ADR 0002)

Three reasons:

1. **ADR 0002 is the canonical record of the invariant decision.**
   Adding 10 defer mappings as §X.Y sections in the invariant ADR
   would dilute the "judgment preservation" thesis. The invariant
   says "we will not implement autonomous loops"; the addendum
   says "for these 10 specific items, here is what we shipped
   instead." Different concerns, different docs.

2. **The addendum changes over time; the invariant doesn't.** When
   the next audit surfaces new defer items (or an existing item
   gets re-categorized), only this addendum needs editing. ADR 0002
   stays at the 21KB it is now, and the `claude plugin validate
   --strict` green bar is unaffected.

3. **The cross-link is unidirectional.** ADR 0002 references this
   addendum in §"Mapping" footnote; this addendum references
   ADR 0002 in §Context. A single source of truth for the decision,
   with the defer table as a derived view.

## Cross-references

- **Source spec callouts**: `.scratch/harness-loop-audit-2026-06-12/GAP-CLOSURE-SPEC.md`
  has inline `> AUTONOMY-DEFER` / `> VENDOR-DEFER` blocks at §1.1 (Deferred
  table for #5), §2.2 (deferred for #46), and §4.5 (deferred for #32).
- **SYNTHESIS cross-link**: `.scratch/harness-loop-audit-2026-06-12/SYNTHESIS.md:166-176`
  §"Critical Architectural Decision" — pointer added in P4.
- **Harness-audit contract**: Audit check #16 (fleet-drift) surfaces
  any divergence between this addendum and the live audit table;
  audit checks #32 (recursive-improve disable-model-invocation) and
  §3 (the autonomy-invariant doctrine) remain the load-bearing
  enforcement.
- **`.scratch/harness-loop-audit-2026-06-12/SYNTHESIS.md`** rows
  187/203/214/216/217/222/226/227/228/232 — the source rows this
  addendum is derived from. If a row's status changes from Absent /
  Partial to Present, the corresponding entry here becomes stale;
  the human-gated audit re-baseline (P4) is the trigger to update.

## Verification

Conformance: `claude plugin validate --strict .` passes (the addendum
is a doc-only change, not a manifest-affecting one). Audit green bar
`0C/0W/26I exit 0` is unchanged. The addendum is itself load-bearing
not for enforcement — the load-bearing enforcement is ADR 0002's
audit check #32 + the doctrine cross-references — but for **preventing
re-discovery**. A future contributor asking "why is X absent?" lands
on this addendum before spending time re-debating it.

The addendum is **a derived view, not a contract**. The contracts
remain ADR 0002 (the invariant) and the individual `scripts/` +
`skills/` + `commands/` shipped components. If a row in the mapping
above is wrong, the fix is: update the audit, update the addendum
to match — but do NOT weaken the invariant to make the addendum
fit.
