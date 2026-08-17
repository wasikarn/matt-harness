`not-done` covers two distinct cases — the reason text is what makes it unambiguous, not the
enum: never entered Act (gate came back unreachable/reject, or this candidate wasn't selected
this iteration) versus entered Act and failed (retry cap spent, per Step 4's escalate-not-retry
rule). Say which one happened in the reason string every time.

**`routed_to_ship`, `dropped`, and a gate-unreachable stop are three different things — keep
them apart.** `routed_to_ship` counts candidates that never reached Step 3 at all, because
Step 2's scope guard excluded them before any ask — they are not part of the Step-3 candidate
set `proposed` reflects being offered, and they are not `dropped`; they go straight to
`backlog` with their full member-file list (Step 6). `dropped` counts only candidates that
*were* offered at Step 3 and were then explicitly excluded by the human via Revise, with the
gate actually reachable and answered — never use it for a gate-unreachable/reject stop. When
the gate comes back unreachable/reject, every offered candidate carries into `backlog`
untouched, pending a later turn's explicit reply, so that case is `dropped: 0`, not
`dropped: N`. Use `drift_guard: n/a (Verify not reached)` for the same never-executed case — the
three-value enum presupposes Verify actually ran; don't force a flat/improved/regressed read
onto a turn where nothing did.
