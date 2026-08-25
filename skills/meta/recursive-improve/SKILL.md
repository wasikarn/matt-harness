---
name: recursive-improve
description: "Cage: human-gated, anti-unattended harness loop. Use when the user asks to improve or audit the harness. Don't use for bug fixes or new surfaces."
disable-model-invocation: true
disable-model-invocation-reason: LOAD-BEARING safety invariant (the no-model-self-start rule, CLAUDE.md's Operating model under the Architecture section), NOT taste — guarded by audit #36 CRIT; do not weaken via the CLAUDE.md selection criterion
model: inherit
effort: xhigh
---

# Recursive Improve

Closes METHODOLOGY Rule 4's loop ("loop until verified") on the harness itself: read the
harness's own health signals, propose the highest-leverage fixes, and — only with the user's
go-ahead — apply and verify them, one bounded iteration at a time.

Convergence step of harness-recursive-improvement (Phase 4): Phases 1–3 gave the harness eyes
(nudge telemetry, the verification journal); this skill is the hand — a
hand the human always holds.

**The operating invariant (load-bearing — do not soften):** there is **no** autonomous,
multi-iteration, unattended mode — every iteration stops at an `AskUserQuestion` gate before any
mutation. The skill stays `disable-model-invocation: true` so the model cannot **self-start** it,
and the human is the loop's real stop condition at the per-mutation gate; the iteration cap is a
context-exhaustion backstop. See the Operating model doctrine (self-contained excerpt of
CLAUDE.md's Architecture section): `cat "${MH_PLUGIN_ROOT}/docs/reference/operating-model.md"`.

**When to use / not:** the user asks to improve/fix/audit the harness, or a session's
`verification_summary` posture (or a `harness-audit` finding) reveals a concrete gap — not for a
single named bug (`mattpocock-skills:diagnosing-bugs`), a new capability (`/mattpocock-skills:implement`), or anything unattended. Can't present
the proposal to a human and wait? **Stop** — don't proceed plan-only into execution.

---

## Input Contract

- **Needs:** none pasted — the skill gathers the harness's self-health signals itself in Observe.
- **When the user named a focus** (e.g. "improve the memory store"): scope Observe there, but
  still run the full signal sweep so the proposal stays grounded.
- **Defaults:** whole harness, one cycle, highest-leverage-first order.

## Procedure

### 1. Observe — gather signals (read-only)

- Run `harness-audit`: `bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"` → CRIT/WARN/INFO findings —
  the loop's branchable score, both whether to act and what (`file:line`) to fix.
- Read `MEMORY.md` for recorded decisions, deferred candidates, and prior-cycle accepted
  regressions — the durable WHY backlog the audit doesn't encode.
- Scan the session transcript for operator corrections or repeated workflows signaling a gap the
  audit doesn't catch.
- Take a witness pre-snapshot: `bash "${CLAUDE_SKILL_DIR}/scripts/inventory-witness.sh"
  /tmp/ri-BEFORE.md` — so Step 6 can attest exactly what changed.
- **Success criterion:** a written candidate list, each anchored to a `file:line`, a MEMORY.md
  entry, or an audit finding id. Clean audit + no signal → **say so and stop** (Rule 2: a clean
  harness isn't an invitation to invent work).

### 2. Propose — decompose + rank (model judgment)

- Decompose findings into independently fixable candidates (`orchestrate` Rule 13 — inline, don't
  delegate to `mh:orchestrate`). Can't name the boundary between two candidates? They're
  entangled — split or sequence them.
- Rank by impact, cost, and risk. State per candidate: what changes, who executes (inline or
  agent), blast radius (low/med/high — e.g. `hooks/gates/**` = high, doc-only = low),
  dependencies (none/chain). **If the touched surface is unclear, the candidate hasn't cleared
  the scope guard below — treat it as "too big — route to /mattpocock-skills:implement"; don't guess a blast-radius
  tier to get it past the gate.**
- **Named bias guard — anchoring.** The first finding scanned isn't necessarily highest-impact;
  rank the full set before committing to an order, don't just work top-to-bottom. Escalation
  options: `references/step-rationale.md`.
- **Scope guard (advisory — doc-followed, not code-enforced):** each candidate should touch
  **≤ 5 files / ≤ 200 lines** — bigger than that is not a loop iteration, hand it to `/mattpocock-skills:implement`;
  don't smuggle a large change through. (File count is a proxy for risk, not the risk itself —
  `references/step-rationale.md`.) **There is no override that lets a >5-file/>200-line
  candidate execute through this loop even when you judge it mechanical and low-risk; it still
  routes to `/mattpocock-skills:implement`, where a human decides with full context, not this ritual.**
- **Cross-iteration evasion guard.** Before ranking a new candidate, check it against Step 6's
  routed-to-`/mattpocock-skills:implement` memory entries for root-cause overlap with anything previously excluded on
  scope grounds — if it shares a root cause with a deferred systemic finding, name that
  explicitly at the gate instead of as ordinary new work. Why: `references/step-rationale.md`.
- **Success criterion:** a ranked candidate list ready to present, each within the scope guard
  or explicitly flagged as "too big — route to /mattpocock-skills:implement".

### 3. ASK — the gate (mandatory)

- **If every candidate's blast radius is LOW/MED, present the ranked list in one
  AskUserQuestion** single-select: "[N] candidates: [ranked list]. Blast radius: [low/med,
  cited]. Dependencies: [none/chain]. Recommended order: [...]. Approve?"
- **If any candidate's blast radius is HIGH, ask about it with its own separate
  AskUserQuestion call — not folded into a combined ask with LOW/MED candidates.** First, a
  single-select on the HIGH item(s) alone: "[HIGH candidate]. Blast radius: high — [what it
  touches]. Approve / Revise / Reject?" Then a second, separate single-select for the remaining
  LOW/MED candidates as a batch, using the template above. A human approving the LOW/MED batch
  must not be able to approve the HIGH item through the same click — that's the actual
  protection this rule exists for.
- Revise/Reject read the same on both asks; only Approve's wording differs (batch-shaped claims
  like "execute in recommended order" don't hold for a single HIGH candidate):
  - LOW/MED batch ask: `Approve — execute in recommended order (best when candidates are independent and blast radius is low)`
  - HIGH-alone ask: `Approve — execute this candidate (best when you've weighed the blast radius and still want it to run)`
  - `Revise — drop / add / reorder (best when scope or order is off)`
  - `Reject — keep as analysis only (best when you want the findings without acting)`
  Multiple HIGH candidates still share one single-select (bundling is fine — none is being
  smuggled past a LOW/MED item) — but don't reuse the LOW/MED batch's "recommended order"
  framing; name each HIGH candidate on its own line.
- **Neither ask collapses, even when Step 2's ranking is unambiguous.** This gate is
  authorization, not information-gathering — an unambiguous ranking answers "what's best," not
  "do you approve." If the answer feels settled enough to skip, that feeling is exactly what the
  invariant above exists to override. (Contrast: `references/step-rationale.md`.)
- A planning request is **not** authorization to execute. **A denial is not an approval.** If
  `AskUserQuestion` is denied (dontAsk / headless `-p`), render the question(s) as numbered prose
  and stop — the question(s) go on record, not an active poll loop; there's no live channel to
  wait on inside one headless dispatch. Per-ask: a denial on one (HIGH-alone or LOW/MED-batch)
  isn't a denial on the other — resolve independently. No human reachable → **stop at
  analysis-only**, never fail open. A later turn with an explicit reply resumes at this same
  gate, not Step 4.
- **Success criterion:** for each ask — an explicit Approve (with candidate(s) signed off), a
  Revise/Reject that loops back/ends, or (unreachable) the rendered question plus a
  stop-at-analysis-only statement. Only an Approve authorizes Step 4 for that ask's candidate(s);
  a HIGH denial/unreachable doesn't block an already-Approved LOW/MED batch, and vice versa.

### 4. Act — execute approved candidates

- Route each candidate to the cheapest correct executor (inline for trivial; a matching senior
  agent for specialized work, gated per `orchestrate`). Give each a **done-when** — an observable
  output, not a topic.
- **Repeated failure escalates, it does not retry** (the escalate-not-retry principle — trying
  the same candidate again after a failure is guessing, not fixing, so retrying isn't on the
  table). A candidate's executor gets exactly **one** attempt; on hitting a failure it records
  not-done with the verbatim failure signal, surfaced at Step 6, and does not re-attempt. No
  failure counter, because there's nothing to count — a retry-count would normalize silent
  unattended iterations. Escalate to the human gate instead.
- Apply changes one candidate at a time so Verify attributes the metric delta.
- **Success criterion:** each candidate's done-when is met, or recorded not-done with a reason
  (no silent drop).

### 5. Verify — did it actually improve? (drift guard)

- **Executed, not assumed.** The audit re-run, deterministic checks, and Step 6's witness diff
  must be something this turn actually ran. If resuming from an earlier Act, label results as
  reported by that step — never phrase an inferred or already-given result as if you just ran it
  yourself.
- Re-run `harness-audit` (`bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"`). Compare the CRIT/WARN
  counts to the Observe baseline.
- **Drift guard:** if no signal improved — audit count not down, no other metric moved — the
  iteration did **not** help. Do **not** report success. Surface the flat/negative delta as the
  rollback decision (Step 6); the audit exit count is the deterministic stop condition (score,
  not feel).
- **Named bias guard — survivorship.** If the candidate's diff touched the verifier itself
  (`hooks/gates/**`, `hooks/hooks.json`, `skills/meta/harness-audit/**`, `checks/**`), a lower count
  could mean the check narrowed, not the defect fixed — apply extra scrutiny (read the diff,
  don't trust the count) before calling it "improved."
- Run the relevant deterministic check on touched code: `bash scripts/run-gauntlet.sh`
  (plugin-validate + shell-lint + JSON-lint + harness-audit), `bash tests/hooks/test-gates.sh`
  (3 deny-gates), `bash -n`/`py_compile` on edited scripts.
- **Success criterion:** a measured before/after delta (improved, flat, or regressed) — stated,
  not assumed.

### 6. Surface — report + attest + capture (rollback lives here)

- Take the witness post-snapshot + diff: `bash "${CLAUDE_SKILL_DIR}/scripts/inventory-witness.sh"
  /tmp/ri-AFTER.md` then `diff /tmp/ri-BEFORE.md /tmp/ri-AFTER.md` — exactly what fleet state
  changed.
- **Rollback policy — surface + ask, never auto-revert.** A regression is a *signal*, not a
  silent failure (why: `references/step-rationale.md`). On flat/negative delta, present it with
  the witness diff and **ask**: revert, tune, or accept-as-new-baseline; capture the reason as a
  memory entry — don't bury the regression. **Accept-as-new-baseline isn't permanent** — name a
  re-open condition in that entry (e.g. "revisit if this `file:line` resurfaces").
- Emit the iteration report (Output Format below), and capture any durable WHY (a decision, a
  deferred candidate, a regression accepted) in memory. **A candidate routed to `/mattpocock-skills:implement` for
  exceeding the scope guard must be captured with its full member-file list** — Step 2's evasion
  guard checks later candidates against it.
- **Iteration cap: 5 per session** (soft — the human gates each iteration anyway; only a
  context-exhaustion backstop). Past the cap, surface remaining candidates as a backlog and stop.

## Output Format

The Step 6 iteration-report template lives in `references/output-format.md` — read it before
emitting the report. See `references/output-format-disambiguation.md` for
`not-done`/`routed_to_implement`/`dropped`/`drift_guard: n/a` — easy to conflate, worked cases there.

## Failure Modes to Avoid

- **Proposing without observing** — skip Step 1; anchor every candidate to a reader gap, audit
  finding, or `file:line`.
- **Treating the gate as a formality** — Step 3's `AskUserQuestion` is mandatory; denial ≠
  approval; never fail open.
- **Self-starting or unattended** — dropping `disable-model-invocation`, model-as-gate, or
  skipping the per-mutation human gate.
- **Claiming success without a measured delta** — Step 5's drift guard: flat delta did not help.
- **Silent rollback** — auto-reverting hides the signal; surface + ask (Step 6).
- **Scope creep through the side door** — routing a >5-file/>200-line candidate here instead of
  `/mattpocock-skills:implement` (Step 2).

## Integration Notes (Project-Specific)

Full METHODOLOGY/composes-with/journal-handling detail: `references/step-rationale.md`.

- **Origin & locked decisions:** metric = harness-audit findings (CRIT/WARN/INFO counts); cap = 5;
  rollback = surface + ask; gating = **human-gated at the per-mutation gate**, never model-gated,
  never self-launching.
