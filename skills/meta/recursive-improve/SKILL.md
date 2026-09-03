---
name: recursive-improve
description: "Cage: human-gated, anti-unattended harness loop."
disable-model-invocation: true
disable-model-invocation-reason: LOAD-BEARING safety invariant (the no-model-self-start rule, CLAUDE.md's Operating model under the Architecture section), NOT taste — guarded by audit #36 CRIT; do not weaken via the CLAUDE.md selection criterion
model: inherit
effort: xhigh
---

# Recursive Improve

Closes METHODOLOGY Rule 4's loop ("loop until verified") on the harness itself: read the
harness's own health signals, propose the highest-leverage fixes, and — only with the user's
go-ahead — apply and verify them, one bounded iteration at a time.

Convergence step of harness-recursive-improvement (Phase 4) — this skill is the hand, always held
by a human (rationale: `references/step-rationale.md`).

**The operating invariant (load-bearing — do not soften):** there is **no** autonomous,
multi-iteration, unattended mode — every iteration stops at an `AskUserQuestion` gate before any
mutation. The skill stays `disable-model-invocation: true` so the model cannot **self-start** it,
and the human is the loop's real stop condition at the per-mutation gate; the iteration cap is a
context-exhaustion backstop. See the Operating model doctrine (canonical source; CLAUDE.md's
Architecture section holds only a summary + pointer): `cat "${MH_PLUGIN_ROOT}/docs/reference/operating-model.md"`.

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

- Run `harness-audit` — dispatched, not run by main directly (`bash` isn't on main's read-only
  allowlist): a foreground agent runs `bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"` and reports
  back CRIT/WARN/INFO findings — the loop's branchable score, both whether to act and what
  (`file:line`) to fix.
- Read the gate-verdict journal: `bash "${CLAUDE_SKILL_DIR}/scripts/gate-journal-summary.sh"` →
  per-gate ask/deny/defer counts (frequency signal only, no free-text reason — read the actual
  gate source before proposing a change). Absence from the summary ≠ not-wired; cross-check
  `hooks/pretooluse-table.json` (why: `references/step-rationale.md`).
- Read `MEMORY.md` for recorded decisions, deferred candidates, and prior-cycle accepted
  regressions — the durable WHY backlog the audit doesn't encode.
- Scan feedback-memory clusters: `python3 "${CLAUDE_SKILL_DIR}/scripts/feedback-surface-scan.py"`
  → repo surfaces (skill/hook/script/doc) mentioned by 2+ `type: feedback` memories in prose —
  where human correction has already repeated. Still read the actual memory files before
  proposing an edit (why heuristic-not-convention: `references/step-rationale.md`).
- Scan the session transcript for operator corrections or repeated workflows signaling a gap the
  audit doesn't catch.
- Take a witness pre-snapshot: `bash "${CLAUDE_SKILL_DIR}/scripts/inventory-witness.sh"
  /tmp/ri-BEFORE.md` — so Step 6 can attest exactly what changed.
- **Success criterion:** a written candidate list, each anchored to a `file:line`, a MEMORY.md
  entry, or an audit finding id. Clean audit + no signal → **say so and stop** (Rule 2).

### 2. Propose — decompose + rank (model judgment)

- Decompose findings into independently fixable candidates (`orchestrate` Rule 13 — route each to a
  fixer agent directly, don't delegate to `mh:orchestrate`). Can't name the boundary between two
  candidates? They're entangled — split or sequence them.
- Rank by impact, cost, and risk. State per candidate: what changes, who executes (always an
  agent — note which), blast radius (low/med/high — e.g. `hooks/gates/**` = high, doc-only = low),
  dependencies (none/chain). **If the touched surface is unclear, the candidate hasn't cleared
  the scope guard below — treat it as "too big — route to /mattpocock-skills:implement"; don't guess a blast-radius
  tier to get it past the gate.**
- **Named bias guard — anchoring.** The first finding scanned isn't necessarily highest-impact;
  rank the full set before committing to an order, don't just work top-to-bottom. Escalation
  options: `references/step-rationale.md`.
- **Scope guard (advisory — doc-followed, not code-enforced):** each candidate should touch
  **≤ 5 files / ≤ 200 lines** — bigger than that is not a loop iteration, hand it to
  `/mattpocock-skills:implement`. **No override lets a bigger candidate execute through this loop
  even when it looks mechanical and low-risk** — a human decides with full context instead. (File
  count is a risk proxy, not the risk itself: `references/step-rationale.md`.)
- **Cross-iteration evasion guard.** Before ranking a new candidate, check it against Step 6's
  routed-to-`/mattpocock-skills:implement` memory entries for root-cause overlap with anything previously excluded on
  scope grounds — if it shares a root cause with a deferred systemic finding, name that
  explicitly at the gate instead of as ordinary new work. Why: `references/step-rationale.md`.
- **Success criterion:** a ranked candidate list ready to present, each within the scope guard
  or explicitly flagged as "too big — route to /mattpocock-skills:implement".

### 3. ASK — the gate (mandatory)

Read `references/procedure-detail.md` (Step 3) before presenting the ask: HIGH-blast-radius
candidates get their own separate `AskUserQuestion`, never folded into the LOW/MED batch; a
denial is not an approval; no human reachable → stop at analysis-only, never fail open.

### 4. Act — execute approved candidates

Read `references/procedure-detail.md` (Step 4) when routing: cheapest correct executor, one
attempt per candidate (repeated failure escalates to the gate, never retries), one candidate
at a time with a done-when.

### 5. Verify — did it actually improve? (drift guard)

Read `references/procedure-detail.md` (Step 5) before scoring: re-run `harness-audit` and the
gauntlet dispatched (executed this turn, not assumed); a flat delta did **not** help; a diff
that touched the verifier itself may have narrowed the check, not fixed the defect.

### 6. Surface — report + attest + capture (rollback lives here)

Read `references/procedure-detail.md` (Step 6) before reporting: witness post-snapshot + diff,
rollback = surface + ask (never auto-revert), capture durable WHY in memory, iteration cap 5
per session (soft — context-exhaustion backstop only).

## Output Format

Template: `references/output-format.md`. Field disambiguation
(`not-done`/`routed_to_implement`/`dropped`/`drift_guard: n/a`): `references/output-format-disambiguation.md`.

## Failure Modes to Avoid

- **Proposing without observing** — anchor every candidate to a reader gap, audit finding, or `file:line`.
- **Treating the gate as a formality** — Step 3's `AskUserQuestion` is mandatory; denial ≠ approval; never fail open.
- **Self-starting or unattended** — dropping `disable-model-invocation` or the per-mutation human gate.
- **Claiming success without a measured delta** — Step 5's drift guard: flat delta did not help.
- **Silent rollback** — auto-reverting hides the signal; surface + ask (Step 6).
- **Scope creep through the side door** — a >5-file/>200-line candidate here instead of `/mattpocock-skills:implement`.

## Integration Notes (Project-Specific)

Full METHODOLOGY/composes-with/journal-handling detail: `references/step-rationale.md`.

- **Origin & locked decisions:** metric = harness-audit findings (CRIT/WARN/INFO counts); cap = 5;
  rollback = surface + ask; gating = **human-gated at the per-mutation gate**, never model-gated,
  never self-launching.
