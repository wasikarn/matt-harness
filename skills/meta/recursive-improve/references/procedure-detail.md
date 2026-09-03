# Recursive Improve — procedure detail (Steps 3-6)

Moved verbatim from `SKILL.md` (progressive disclosure). Read this file when an
iteration reaches Step 3 — the gate wording, executor rules, drift guard, and rollback
policy below are load-bearing; the outline in `SKILL.md` is only the map.

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
- **Neither ask collapses, even when Step 2's ranking is unambiguous.** Never skip it because the
  ranking feels settled (rationale: `references/step-rationale.md`).
- A planning request is **not** authorization to execute. **A denial is not an approval.** If
  `AskUserQuestion` is denied under `--permission-mode dontAsk`, render the question(s) as
  numbered prose and stop — no live channel to wait on inside one headless dispatch. **Any
  headless invocation of this skill (scheduled or otherwise) must pass `--permission-mode
  dontAsk` explicitly** (why this flag is load-bearing: `references/step-rationale.md`). Per-ask:
  a denial on one (HIGH-alone or LOW/MED-batch) isn't a denial on the other — resolve
  independently. No human reachable → **stop at analysis-only**, never fail open. A later turn
  with an explicit reply resumes at this same gate, not Step 4.
- **Success criterion:** for each ask — an explicit Approve (with candidate(s) signed off), a
  Revise/Reject that loops back/ends, or (unreachable) the rendered question plus a
  stop-at-analysis-only statement. Only an Approve authorizes Step 4 for that ask's candidate(s);
  a HIGH denial/unreachable doesn't block an already-Approved LOW/MED batch, and vice versa.

### 4. Act — execute approved candidates

- Route each candidate to the cheapest correct executor — a haiku-model fixer for trivial work, a
  matching senior agent for specialized work, gated per `orchestrate`. Give each a **done-when** —
  an observable output, not a topic.
- **Repeated failure escalates, it does not retry.** A candidate's executor gets exactly **one**
  attempt; on failure it records not-done with the verbatim failure signal (surfaced at Step 6)
  and does not re-attempt — no failure counter, no retry, escalate to the human gate instead.
- Apply changes one candidate at a time so Verify attributes the metric delta.
- **Success criterion:** each candidate's done-when is met, or recorded not-done with a reason
  (no silent drop).

### 5. Verify — did it actually improve? (drift guard)

- **Executed, not assumed.** The audit re-run, deterministic checks, and Step 6's witness diff
  must be something this turn actually ran. If resuming from an earlier Act, label results as
  reported by that step — never phrase an inferred or already-given result as if you just ran it
  yourself.
- Re-run `harness-audit` — dispatched the same way as Step 1 (a foreground agent runs
  `bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"` and reports back). Compare the CRIT/WARN counts to
  the Observe baseline.
- **Drift guard:** if no signal improved — audit count not down, no other metric moved — the
  iteration did **not** help. Do **not** report success. Surface the flat/negative delta as the
  rollback decision (Step 6); the audit exit count is the deterministic stop condition (score,
  not feel).
- **Named bias guard — survivorship.** If the diff touched the verifier itself (`hooks/gates/**`,
  `hooks/hooks.json`, `skills/meta/harness-audit/**`, `checks/**`), a lower count could mean the
  check narrowed, not the defect fixed — read the diff before calling it "improved."
- Run the relevant deterministic check on touched code — dispatched, not run by main directly
  (`bash` isn't on main's read-only allowlist): a foreground `general-purpose` agent runs
  `bash scripts/run-gauntlet.sh` (plugin-validate + shell-lint + JSON-lint + harness-audit),
  `bash tests/hooks/test-gates.sh` (3 deny-gates), and `bash -n`/`py_compile` on edited scripts,
  then reports back the verbatim output (or its tail) for main to read and score — same executor
  framing as Step 4's "who executes (always an agent — note which)."
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
