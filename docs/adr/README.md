# Architecture Decision Records

ADRs capture decisions that are costly to reverse — the *why* behind a structural
choice, the alternatives weighed, and the status over time. New ones are authored
with the [`adr`](../../skills/adr) skill (its "Maintain" step keeps this index current).

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-personal-harness-as-plugin.md) | Personal-harness-as-plugin (Option A) | Accepted | 2026-06-10 |
| [0002](0002-autonomy-invariant.md) | Autonomy invariant — no autonomous or unattended self-repair loop (judgment-preservation choice) | Accepted (superseded for architecture + operating model by 0006; principle preserved) | 2026-06-12 |
| [0002-addendum](0002-addendum-deferred-items.md) | Deferred items mapping (10 SYNTHESIS rows where L2 alternative is shipped) | Accepted (ratchet retired by 0006; items deferred on 0002 surviving principle) | 2026-06-12 |
| [0002-addendum](0002-addendum-passive-capture.md) | Passive learning-capture (capture-half human-gated; ECC inverse axis) | Accepted (unaffected by 0006) | 2026-06-21 |
| [0002-addendum](0002-addendum-push-gate-create-not-ship.md) | Push-gate: `gh pr create`/`ready` are review-prep, not ship | Accepted (superseded by 0006; moot) | 2026-06-24 |
| [0002-addendum](0002-addendum-push-gate-review-rigor.md) | Push-gate review-rigor (observe-flag, not enforce-deny) | Accepted (superseded by 0006; moot) | 2026-06-23 |
| [0003](0003-l3-bounded-autonomy.md) | L3 bounded autonomy — human-gated by run + push, not by mutation (supersedes 0002's architecture; principle preserved) | Superseded by 0006 | 2026-06-21 |
| [0004](0004-l4-autonomy.md) | L4 self-driving harness — autonomy within the cage floor (self-launch + model-gate + auto-inject; auto-push dropped, Gate 2 kept) | Superseded by 0006 | 2026-06-22 |
| [0005](0005-l5-auto-push.md) | L5 — auto-push/auto-merge (the human leaves the push loop; gauntlet-gated ship, supersedes 0004's "keep Gate 2") | Superseded by 0006 | 2026-06-22 |
| [0005-addendum](0005-addendum-manual-push-precondition-waiver.md) | Waive N≥20-cycle precondition for MANUAL-armed-push | Accepted (superseded by 0006; moot) | 2026-06-22 |
| [0006](0006-ecc-aligned-operating-model.md) | ECC-aligned operating model (retires the L3/L4/L5 bounded-autonomy ratchet; preserves 0002 judgment-preservation principle) | Accepted | 2026-06-25 |
