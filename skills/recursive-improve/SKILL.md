---
name: recursive-improve
description: "Cage: human-gated, anti-unattended harness loop. Use when the user asks to improve or audit the harness. Don't use for bug fixes or new surfaces."
disable-model-invocation: true
disable-model-invocation-reason: LOAD-BEARING safety invariant (the no-model-self-start rule in METHODOLOGY.md and CLAUDE.md §The operating model), NOT taste — guarded by audit #32 CRIT; do not weaken via the CLAUDE.md selection criterion
---

# Recursive Improve

Close METHODOLOGY Rule 4's loop ("loop until verified") on the harness itself: read the
signals the harness emits about its own health, propose the highest-leverage fixes, and —
only with the user's go-ahead — apply and verify them, one bounded iteration at a time.

This is the convergence step of harness-recursive-improvement (Phase 4). Phases 1–3 gave the
harness eyes (nudge telemetry, the review-pr marker, the verification journal); this skill is
the hand — but a hand the human always holds.

**The operating invariant (load-bearing — do not soften):** there is **no** autonomous,
multi-iteration, unattended mode — every iteration stops at an `AskUserQuestion` gate before any
mutation. The skill stays `disable-model-invocation: true` so the model cannot **self-start** it,
and the human is the loop's real stop condition at the per-mutation gate; the iteration cap is a
context-exhaustion backstop. The operating model is CLAUDE.md §The operating model (current) — read in Bash:
`cat "${KBG_PLUGIN_ROOT}/CLAUDE.md"`.

**When to use:** the user explicitly asks to improve / fix / audit the harness, or a session's
`verification_summary` posture (or a `harness-audit` finding) reveals a concrete gap worth a
deliberate cycle.

**When NOT to use:** a single named bug (`/fix-bug`), a new capability (`/ship`), or
anything unattended. If you cannot present the proposal to a human and wait, **stop** — do not
proceed plan-only into execution.

---

## Input Contract

- **Needs:** the harness's current self-health signals. The skill gathers them itself in
  Observe — the user does not paste anything.
- **When the user named a focus** ("improve the memory store", "the nudge keeps mis-firing"):
  scope Observe to that area; still run the full signal sweep so the proposal is grounded.
- **Defaults:** observe the whole harness; one cycle; the recommended candidate order is
  highest-leverage-first.

## Procedure

### 1. Observe — gather signals (read-only)

- Run `harness-audit` (the deterministic verifier): `bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"`
  → concrete CRIT / WARN / INFO findings. The audit exit count is the loop's branchable score —
  it is both the *that* (improvement is warranted) and the *what* (which `file:line` to fix).
- Read `MEMORY.md` for recorded decisions, deferred candidates, and regressions accepted in prior
  cycles — the durable WHY backlog the audit does not encode.
- Scan the session transcript for recent operator corrections or repeated workflows that signal a
  harness gap the audit doesn't catch.
- Take a witness pre-snapshot:
  `bash "${CLAUDE_SKILL_DIR}/scripts/inventory-witness.sh" /tmp/ri-BEFORE.md`
  → records the fleet/boundary state so Step 6 can attest exactly what the iteration changed.
- **Success criterion:** a written list of candidate findings, each anchored to a `file:line`, a
  MEMORY.md entry, or an audit finding id. If the audit is clean and no transcript/Memory signal
  surfaces → **say so and stop**: a clean harness is not an invitation to invent work (Rule 2).

### 2. Propose — decompose + rank (model judgment)

- Decompose findings into independently fixable candidates (`orchestrate` Rule 13 — inline, do
  not delegate to `kbg:orchestrate`). If you cannot name the boundary between two candidates, they
  are entangled — split further or sequence them.
- Rank by impact × cost × risk. State, per candidate: what changes, who executes (inline vs
  which agent), blast radius (low / medium / high), dependencies (none / chain).
- **Scope guard (advisory — doc-followed, not code-enforced):** each candidate should touch
  **≤ 5 files / ≤ 200 lines**. A candidate bigger than that is not a loop iteration — surface
  it and hand it to `/ship`; do not smuggle a large change through this ritual.
- **Success criterion:** a ranked candidate list ready to present, each within the scope guard
  or explicitly flagged as "too big — route to /ship".

### 3. ASK — the gate (mandatory)

- Present the ranked list, then **AskUserQuestion** single-select:
  "[N] candidates: [ranked list]. Blast radius: [low/med/high]. Dependencies: [none/chain].
  Recommended order: [...]. Approve?"
  - `Approve — execute in recommended order (Recommended when candidates are independent and blast radius is low)`
  - `Revise — drop / add / reorder (Recommended when scope or order is off)`
  - `Reject — keep as analysis only (Recommended when you want the findings without acting)`
- A planning request is **not** authorization to execute. **Denial ≠ approval.** If
  `AskUserQuestion` is denied (dontAsk / headless `-p`), render the same question as numbered
  prose and wait for an explicit reply; if no human can answer, **stop at analysis-only** — never
  fail open into execution.
- **Success criterion:** an explicit Approve (with the candidate set the user signed off on) or a
  Revise/Reject that loops back / ends.

### 4. Act — execute approved candidates

- Route each approved candidate to the cheapest correct executor (inline for trivial; the
  matching senior agent for specialized work — gated per `orchestrate`). Give each a **done-when**:
  an observable output, not a topic.
- **Repeated failure escalates, it does not retry (Rule 12 — escalate sub-rule).** A candidate's executor caps itself
  at one retry; on hitting the same failure it does **not** re-attempt — it records the candidate
  not-done with the verbatim failure signal (Rule 12) and surfaces it at Step 6. There is no
  failure counter, because Step 4 runs each candidate **once**: a "count to N" would presume a
  retry budget that does not exist and would normalize N silent unattended iterations. Escalate to
  the human gate instead of counting-then-retrying.
- Apply changes one candidate at a time so Verify can attribute the metric delta.
- **Success criterion:** each candidate's done-when is met, or it is recorded as not-done with a
  reason (no silent drop — Rule 12).

### 5. Verify — did it actually improve? (drift guard)

- Re-run `harness-audit` (`bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"`). Compare the CRIT/WARN
  counts to the Observe baseline.
- **Drift guard:** if no signal improved — audit finding count not down, and no other named metric
  moved — the iteration did **not** help. Do **not** report success. Surface the flat/negative delta
  and treat it as the rollback decision (Step 6). The audit exit count is the deterministic stop
  condition (score, not feel).
- Run the relevant deterministic check on any code touched: `bash scripts/run-gauntlet.sh`
  (plugin-validate + shell-lint + JSON-lint + harness-audit), `bash hooks/tests/test-gates.sh`
  (the 3 deny-gates), `bash -n` / `py_compile` on edited scripts.
- **Success criterion:** a measured before/after delta (improved, flat, or regressed) — stated, not
  assumed.

### 6. Surface — report + attest + capture (rollback lives here)

- Take the witness post-snapshot + diff:
  `bash "${CLAUDE_SKILL_DIR}/scripts/inventory-witness.sh" /tmp/ri-AFTER.md`
  then `diff /tmp/ri-BEFORE.md /tmp/ri-AFTER.md` → exactly what fleet state the iteration changed.
- **Rollback policy — surface + ask, never auto-revert.** A regression is a *signal*, not a silent
  failure (qmd-reindex precedent). If Verify showed flat/negative delta, present the before/after
  delta and the witness diff and **ask**: revert, tune, or accept-as-new-baseline. Capture the
  user's reason as a memory entry. Do not auto-revert and do not bury the regression.
- Emit the iteration report (Output Format below). Capture any durable WHY (a decision, a deferred
  candidate, a regression accepted) in memory.
- **Iteration cap: 5 per session** (soft — the human gates each iteration anyway; this is only a
  context-exhaustion backstop). If more candidates remain after the cap, surface them as a backlog
  and stop; do not silently continue.

## Output Format

```
recursive-improve — iteration <N> report
  observed:        <reader summary: gaps across N sessions> · <audit: C/W/I counts>
  proposed:        <N candidates>
  approved:        <N>   (user gate: approve | revise | reject)
  executed:        <N>   dropped: <N — and why>
  per candidate:
    - <name> · file:line | session | audit-id
        executor:  inline | <agent>
        done_when: <observable check>
        status:    done | not-done (<reason>)
        delta:     <metric moved? gaps N→M / audit X→Y / n/a>
  drift_guard:     improved | flat | regressed   (rollback: <none | reverted | tuned | accepted+why>)
  witness_diff:    <fleet changes, or "none">
  backlog:         <candidates past the cap / deferred, or "none">
```

## Failure Modes to Avoid

- **Proposing without observing.** Skipping Step 1 and inventing fixes that don't land. Always
  anchor each candidate to a reader gap, an audit finding, or a `file:line`.
- **Treating the gate as a formality.** "We can fix this" is not authorization. The Step 3
  `AskUserQuestion` is mandatory; denial is not approval; never fail open into execution.
- **Self-starting or going unattended.** What violates the invariant: a loop that **self-starts**
  (drops `disable-model-invocation`), uses a **model as its in-loop gate**, or runs **without the
  per-mutation human gate**. The human gate at each iteration is the bound, not a license to drop it.
- **Claiming success without a measured delta.** Step 5's drift guard exists because "I fixed it"
  is a hypothesis until the reader/audit confirms it. Flat delta = did not help.
- **Silent rollback.** Auto-reverting a regression hides the signal. Surface the delta and ask
  (Rule 12) — the regression is information.
- **Scope creep through the side door.** A candidate over ~5 files / 200 lines is a feature, not a
  loop iteration. Route it to `/ship`; do not let the ritual become an un-gated refactor.

## Integration Notes (Project-Specific)

- **METHODOLOGY:** Rule 4 (this skill *is* the loop-until-verified instrument for the harness) ·
  Rule 7 (drift guard picks the measured audit delta over the optimistic claim) · Rule 12
  (surface flat/negative deltas and regressions, never bury them) · Rule 13 (decompose → route →
  verify → combine, inline).
- **Composes:** `orchestrate` (the decompose/route/verify pattern, inlined) · `harness-audit`
  (both the candidate-detail signal and the deterministic verification metric — its exit count is
  the loop's branchable score) · the witness scripts under `inventory/` (pre/post attestation) ·
  `/ship` (escrow for over-scope candidates) · the harness-decay cadence
  (`docs/harness-decay-cadence.md`, the build-to-delete counterpart to this add/fix loop, and its
  `## Permission re-audit` section for tool-grant decay candidates).
- **Reads, never writes, the journal.** This skill does not emit a journal event. Iteration evidence
  is the witness BOUNDARY diff + a memory entry, not a journal stream (kept minimal per Rule 2 —
  revisit only if a durable per-iteration history is actually needed).
- **Origin & locked decisions:** metric = harness-audit findings (CRIT/WARN/INFO counts); cap = 5;
  rollback = surface + ask. The autonomous-vs-human-gated question is resolved: **human-gated at the
  per-mutation gate** — never model-gated, never self-launching (CLAUDE.md §The operating model).
