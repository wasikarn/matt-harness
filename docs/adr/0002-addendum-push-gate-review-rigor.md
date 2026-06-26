# ADR 0002 — Addendum: Push-gate review-rigor (observe-flag, not enforce-deny)

> **Superseded by [ADR 0006](0006-ecc-aligned-operating-model.md) (2026-06-25); moot.** The L3/L4/L5 bounded-autonomy machinery is retired; see ADR 0006 for the ECC-aligned operating model.

- **Status**: Accepted (extends [ADR 0002](0002-autonomy-invariant.md); crosses
  [ADR 0003](0003-l3-bounded-autonomy.md) Gate 2 + [ADR 0004](0004-l4-autonomy.md) +
  [ADR 0005](0005-l5-auto-push.md))
- **Date**: 2026-06-23
- **Decider**: Owner
- **Operating point**: Audit-flag / observe (option B of the 2026-06-23 hardening choice)
- **Scope**: Records a **known limitation** of the armed-push Gate-2 check and the
  chosen hardening posture — an **observability audit check (#52)** that flags
  non-maker≠checker `review_finding` events. The push gate itself is **unchanged**.

## The limitation (the rubber-stamp surface)

The push gate (`hooks/gates/push-gate.sh:87`) authorizes an armed push when
`KBG_REVIEW_DONE=1` **AND** the literal string `review_finding` appears in the last
500 lines of `~/.claude/governance-events.jsonl`. That is a **presence** check, not a
**rigor** check: it does not inspect the finding's `agent` field or count. So a single
operator-authored **inline-review** verdict (`fields.agent = "inline-review (staff-eng)"`,
no fresh-context pass) satisfies the gate **identically** to a full multi-agent
`kbg:review-pr` (`fields.agent = "kbg:code-reviewer"` / `"kbg:security-reviewer"` / …).

The computational check is "a review event exists," not "a maker≠checker review
happened." The v0.4.10 armed push used exactly that path — a focused inline review
(1 `review_finding`, 0 Critical) — because the resume constraint forbade the skill's
`AskUserQuestion` gates, and the gate could not tell the difference.

## Why this is an ADR 0002 addendum, not a superseding ADR

The autonomy invariant ADR 0002 fixes is **unchanged**: the gate that authorizes a ship
stays **computational** (flag + journal event both checked by code), and the model stays
**veto-only** — it satisfies the gate, it does not bypass it. No architectural axis
moves (no new autonomy level, no model-authorizing ship, no cage removal). The maker≠
checker bar already lives in the **armed-push dance step 2** (memory
`armed-push-review-path`) — a fresh-context `kbg:review-pr` — and the gate was always
documented as the **floor, not the ceiling**. This addendum only records the limitation
and installs an observability sensor for it; a standalone superseding ADR (the
hypothetical "ADR 0006" forward-referenced by ADR 0005) is not consumed, because no
axis moves.

## The decision — observe-flag, not enforce-deny

Two hardening options were surfaced 2026-06-23:

| Option | What it does | Posture |
|---|---|---|
| **A — enforce-deny** | Tighten the gate: require `review_finding.fields.agent` to be a dispatched reviewer (`^kbg:`); deny otherwise | **Rejected** |
| **B — observe-flag (chosen)** | Leave the gate permissive; add audit #52 to INFO-flag inline-agent `review_finding` events for decay-sweep verification | **Accepted** |
| C — docs-only | Record the limitation in memory/ADR only, no audit check | Rejected (no machine signal) |

**Why B over A — the #31.1 ceremony trap.** A presence-only check tightened to a rigor
check **manufactures the ceremony it polices**: it would force a full multi-agent
`kbg:review-pr` on **every** armed push, including a one-line doc diff or a version
bump. That is exactly the anti-pattern that retired audit #31.1's canonical-sections
blanket (memory `ceremony-blanket-dig-2026-06-16`) — a gate that demands more rigor than
the stakes warrant becomes a tax the operator learns to route around, which is worse
than an honest permissive floor. The maker≠checker bar is a **judgment call matched to
stakes** (matching effort to stakes is the staff move); hard-wiring it to "always
multi-agent" removes that judgment and turns the gate into a rubber stamp of a different
shape.

**Why B preserves the invariant.** The ship-authorizing gate stays computational and
permissive (the floor); the maker≠checker bar stays a human judgment at step 2 of the
dance (the ceiling); the new audit #52 is **computational feedback** (the 2×2
computational-FB column), not a model-judged gate (it never emits a `permissionDecision`
— it is an INFO line in `audit.sh`, not a hook). This keeps the inferential-FB /
model-as-gate circularity (CLAUDE.md §LLM-judge-circularity) out of the ship path: the
sensor that flags rigor is deterministic code reading a journal, not a model blessing a
ship.

## What audit #52 does (the enforcement of this addendum)

`skills/harness-audit/scripts/checks/52-review-finding-rigor-inline-agent-not-.sh`,
gated on this ADR's presence:

- Reads `~/.claude/governance-events.jsonl` (honors `CLAUDE_JOURNAL_PATH`).
- For each `review_finding` event, tokenizes `fields.agent` on `+`, strips an optional
  `kbg:` prefix from each token, and checks every token is a **known fleet reviewer
  name** (`code-reviewer` / `security-reviewer` / `silent-failure-hunter` /
  `pr-test-analyzer` / `comment-analyzer` / `type-design-analyzer` / `ux-reviewer` —
  the set `skills/review-pr/SKILL.md` Phase 3 routes to, recorded under either a bare
  name or a `kbg:`-namespaced form; multi-agent reviews join names with `+`).
- Counts events whose agent is **not** composed entirely of those names (i.e.
  `inline-review (staff-eng)`, `orchestrator`, `x`, blank, or any unknown token — not a
  dispatched fresh-context reviewer).
- If count > 0 → emits **INFO** "`N` review_finding event(s) whose agent is not a
  dispatched reviewer … — not maker≠checker; may have justified an armed push. Verify
  at the decay sweep."

**Why positive identification, not a `^kbg:` prefix test.** The agent-field convention
shifted mid-stream: dispatched reviewers were recorded under bare fleet names
(`code-reviewer`, `security-reviewer`, …) before the `kbg:`-namespaced form was adopted.
A `!~ ^kbg:` predicate would misclassify ~67 legitimate dispatched reviews as inline
(crying "68" on a real journal) — the prefix is a recent convention, not a provenance
marker. Positively identifying the reviewer set (in either form) is robust to that
history. The set is a documented sync-seam: SSOT = `review-pr` Phase 3 routing; keep the
check's set in sync when a reviewer agent is added/renamed.

**INFO, not WARN** — by design. It never inflates the audit exit code
(`TOTAL = CRIT + WARN`) and never breaks a 0C/0W clean run. An inline-review
`review_finding` is a **legitimate** path (the v0.4.10 push was authorized, not a
defect); flagging it as WARN would cry wolf on every justified small-diff armed push and
re-introduce the ceremony trap on the audit side. The check is a **decay-sweep prompt**,
not a gate: a human verifies the flagged pushes were justified, not the audit.

## Reversibility

Reversible by the same mechanism that created it: a human-authored superseding ADR. The
L3/L4/L5 loop **cannot** edit this addendum — the cage forbids `docs/adr/**` (retained
from ADR 0004 §floor). The audit check itself is caged surface (`audit.sh` +
`checks/**`), so the loop cannot silence #52 to hide its own inline-review pushes either.