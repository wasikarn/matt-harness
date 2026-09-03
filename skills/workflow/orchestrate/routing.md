# Orchestrate — routing tables

On-demand companion to `SKILL.md` and `reference.md`. Load when triaging a task set: the three prioritization matrices, the agent-fleet mapping, and the worked triage example. Split out of `reference.md` 2026-09-03 (`docs/research/orchestrate-cost-optimization-2026-09-03.md`, candidate #1).

## Full routing tables

### Eisenhower (Urgency × Important)

| Item shape | Security? | Level | Path |
|---|---|---|---|
| Urgent + important, tightly coupled / needs back-and-forth | — | L2 | **single-agent** (one foreground fixer, F9 short form) — main asks the user first, then dispatches |
| Urgent + important, specialized + time-critical | — | L3 | **dispatch immediately**, tight done-when |
| Specialized work (matches an agent's domain) | — | L3 | **dispatch** to that agent ↓ |
| Important, not urgent | — | L3 | **schedule** — or dispatch `code-architect` (or run `mattpocock-skills:research`) for deep prep |
| Urgent, not important, bounded + verifiable | — | **L4** | **scripted execution** — pipeline/batch via bash runner |
| Urgent, not important, trivial | — | L2 | **single-agent** (one foreground fixer, F9 short form) — a wave costs more (guardrail) |
| Neither | — | — | **drop** — mark `wontfix` |

### Impact × Effort (no genuine time pressure)

| Item shape | Security? | Level | Path |
|---|---|---|---|
| High impact + low effort | — | L2 | **single-agent** (one foreground fixer, F9 short form) — quick wins, do now |
| High impact + high effort | — | L3 | **schedule** — dispatch `code-architect` (or run `mattpocock-skills:research`) for deep prep before build |
| Low impact + low effort | — | L3 | **delegate** to the right agent, or **single-agent** (one foreground fixer, F9 short form) if trivial — batch similar items |
| Low impact + high effort | — | — | **drop** — thankless task / money pit; mark `wontfix` unless user insists |

### Value × Risk (architecture decisions, framework adoption, release bets)

| Item shape | Security? | Level | Path |
|---|---|---|---|
| High value + low risk | — | L3 | **do first** — dispatch `code-architect` for design, then build |
| High value + high risk | — | L3 | **mitigate then do** — run `mattpocock-skills:research` to de-risk, prototype, or ADR before committing |
| Low value + low risk | — | L3 | **do last** — batch with similar items; delegate if bounded |
| Low value + high risk | — | — | **avoid** — mark `wontfix` unless forced by external constraint |

**Security override — all three matrices above:** any item touching auth, secrets, credentials, crypto, input validation, or dependencies routes to `security-reviewer first` (L3) regardless of quadrant — the write agent takes it only after security findings land.

**No numeric scoring.** Value×Risk is intentionally a binary classifier (high/low), not a weighted decision matrix with 1–5 scores. Numeric scores introduce false precision and weight-manipulation risk here. If N≥3 alternatives need ranking, apply `mh:score-decision`'s Ranking mode (weighted-sum + per-option fatal-weakness floor, METHODOLOGY Rule 14) inline rather than scoring this binary matrix numerically — the skill itself is `disable-model-invocation: true`, so a formal artifact needs the operator to run `/mh:score-decision` directly.

**Insufficient-data fallback.** A binary high/low call still needs enough signal to call it — if there's no basis to place value or risk at all (novel domain, zero comparable precedent), say so explicitly rather than forcing a bucket to get a routing answer, and route through `mattpocock-skills:research` or `code-architect` to generate the missing signal first, then re-classify. This is narrower than a merely contested estimate — a disputed-but-real signal still has a low/high position on the binary scale and should be classified there, not routed around; `score-decision`'s `ข้อมูลไม่เพียงพอ` block-condition draws the same line (reserved for zero basis, not disagreement over a real one) even though its remedy differs (it blocks the score outright; this table routes to generate the missing signal instead).

**"Schedule" in the matrices above = temporal deferral** (do later, human-led) — *not* autonomous execution. Recurrence is an orthogonal axis: if an item is **recurring + unattended-safe** (any quadrant), route it to **L5 (Autonomous / Recurring Execution)** below instead of redoing it by hand each cycle.

**Tasks sourced from a Jira ticket:** when a task routed to `code-architect` **or directly to a write-capable implementation agent** cites a ticket, dispatch `requirement-analyst` first (ticket text only — read-only, never fetches itself; fetch it yourself via `jira-acli:acli` if that plugin is installed, otherwise via the Atlassian MCP or by pasting the ticket text) and fold its `functional_requirements` / `business_trace` / `open_questions` into the receiving agent's dispatch prompt. Grounds the work in a checked requirement analysis instead of the ticket's raw prose — a dispatch-order convention rather than a structural step. Covers both routes: a task that needs a design step first, and one clear enough to skip straight to implementation — the ticket doesn't stop being unchecked prose just because the design step got skipped. (`hooks/advisory/flow-nudge.sh` fires a deterministic reminder for the direct-to-implementation case — a `TP-*` key plus implementation intent in the same prompt — so this convention isn't relying on the dispatcher remembering it fresh each session.)

Agent fleet → domain (the 12-agent survivor set): `security-reviewer` (auth/secrets/OWASP) · `silent-failure-hunter` (error-handling audit) · `blind-spot-hunter` (post-review adversarial hunt for the emergent/interaction defects that survived normal review — cross-file composition, framework auto-behavior, data-flow-asymmetry seams; traces each to an earned severity and clears decoys; runs AFTER the normal review pass, read-only, advisory-never-a-gate) · `code-architect` (new design/system design) · `plan-reviewer` (adversarial pre-code plan review — requirement coverage, architecture fit, risks, failure modes, edge cases, execution order, testability, operability; fresh-context, run BEFORE implementing a consequential plan) · `requirement-analyst` (senior-level requirement analysis of a Jira ticket/Confluence spec/PRD/pasted text handed to it as text — ambiguities, missing ACs, edge cases, dependencies, readiness verdict; never fetches from Jira/Confluence itself) · `ideate-critic` (fresh-context critic for `mh:ideate`; skill-invoked, see below) · `typescript-reviewer` (TS narrowing/`any`/strict drift) · `performance-optimizer` (bottlenecks/bundle size/memory leaks/render issues) · `nextjs-reviewer` (Next.js App Router — rendering/caching model, Server Actions, middleware, route handlers, metadata API, image/font optimization) · `summarizer` (condenses any text/doc/transcript into clear, filler-free output — BLUF structure, source-fidelity, information-density calibration) · `backend-architect` (API contract design, service boundaries, data ownership, consistency model, caching/queueing, reliability, scalability — design-first, cross-language, defers framework/DB specifics to the `*-patterns` skills). Build/typecheck failures and dead-code cleanup have no dedicated agent since the 2026-09-01 dead-weight sweep (zero lifetime dispatches each) — route a failing build to `mattpocock-skills:diagnosing-bugs` or a fixer agent; route dead-code passes to `/mattpocock-skills:improve-codebase-architecture` findings + a fixer agent for the deletions. Accessibility audits go to a general-purpose agent reading `skills/patterns/accessibility/SKILL.md`.

### Skill-invoked critics (NOT user-dispatched via mh:orchestrate)

These agents are invoked directly by a skill body, not by the user via `mh:orchestrate`. They are fresh-context judges that reduce LLM-judge-circularity for expensive generation skills. Like sensors, they are **read-only** and **advisory only** — they score and report, they do not write or block.

- `ideate-critic` — Fresh-context critic for `mh:ideate`. Scores, clusters, and deepens the output of ideate Phase 1 (Diverge) so the critic pass does not run on the same host-context that just generated the ideas. Invoked by `skills/workflow/ideate/SKILL.md` Phase 2. Uses the 3-axis rubric `novelty*0.35 + viability*0.40 + fit*0.25` per `agents/ideate-critic.md`.

### Full triage example

Supplementary detail for `SKILL.md`'s Example section.

Input: "prod /orders is 500ing; refactor auth for readability; a reviewer wants a signups CSV; should we move to pnpm; a contractor asked about a dark-mode toggle, no rush"

| Task | Quadrant | Route | Agent | Done-when | Status |
|---|---|---|---|---|---|
| prod 500s | Q1 urgent + important, specialized | sequential: Builder fixes → Validator confirms | `general-purpose` (Builder, gated) → the matching per-language reviewer (Validator, ungated) | root cause fixed, committed, and validator confirms errors gone (verdict on record) | dispatched (pending confirm) |
| auth refactor | Q2 + touches auth | sequential: `security-reviewer` first (security precedence) → then a write-capable agent (clarity-only scope) | `security-reviewer` → `general-purpose` (write-capable) — both gated | security-reviewer verdict on record + refactor merged, tests green | deferred (confirm before each) |
| signups CSV | Q3 urgent, not important | single-agent (one foreground fixer, F9 short form) — trivial query; a wave costs more (guardrail) | `general-purpose` (one fixer, gated) | CSV delivered | dispatched |
| pnpm move | Q2 important, not urgent | parallel: research via `mattpocock-skills:research` — compare + report, don't migrate | `mattpocock-skills:research` | trade-off brief filed (staged: the actual reversible-choice call is made under METHODOLOGY Rule 1 once the data exists, not back through this matrix) | deferred |
| dark-mode toggle | Q4 neither urgent nor important | drop | none | n/a | dropped — mark `wontfix`; outside current roadmap |

**Why each row landed where it did** (evidence for the quadrant call, the alternative route considered and rejected, and the fact that would flip the pick — deferred rows also get a revisit trigger):

- **prod 500s** — Evidence: the 500 error rate is the urgency signal itself (paged, not merely observed). Alternative rejected: single-agent, no validator — root-causing a prod incident under load is the "specialized + time-critical" case L3 exists for, not L2's tightly-coupled back-and-forth. Falsifying fact: if the 500s stop before dispatch completes, this drops to Q3/single-agent — confirm still-failing before dispatching, don't dispatch on a stale symptom.
- **auth refactor** — Evidence: "for readability" names no incident or deadline — Important-not-urgent by elimination, nothing marks it urgent. Alternative rejected: routing straight to a write-capable agent without `security-reviewer` first — rejected because it touches auth (Security override, above). Revisit trigger: re-triage at the next security sprint even if nothing new has surfaced — a deferred security-adjacent item doesn't get to age out silently. Falsifying fact: a live auth vulnerability report un-defers this into Q1 immediately, no sprint wait needed.
- **signups CSV** — Evidence: "a reviewer wants" is a one-off ask, not a recurring need. Alternative rejected: a validation chain for it — the query itself is the whole task, so a chain costs more than one fixer (the L2 guardrail row). Falsifying fact: if this recurs weekly, it reclassifies to L5 (Autonomous/Recurring, below) instead of a one-off single-agent pick each time.
- **pnpm move** — Evidence: no deadline stated, but "should we" is a genuine open decision, not busywork. Alternative rejected: making the build/adopt call now — the trade-off data doesn't exist yet, so `mattpocock-skills:research` has to generate it first. Revisit trigger: once the research brief lands, the call is made under METHODOLOGY Rule 1 (triad + `advisor()`), not back through this matrix. Falsifying fact: a stated deadline this blocks would promote it out of "not urgent."
- **dark-mode toggle** — Evidence: "no rush" plus a non-team requester (contractor) — neither important (not on the roadmap) nor urgent. Alternative rejected: scheduling it (L3) — a low-value item still costs a future triage pass, so drop beats defer here. Falsifying fact: the toggle entering the actual roadmap would flip this from drop to a real Important/Impact quadrant — this drop isn't a standing "no," it's a verdict on today's roadmap only.

Every *write-capable* leg dispatched here (Builder/Fixer roles — holds Bash or Edit/Write) needs the single AskUserQuestion gate before the batch goes out; prod-500s' Validator confirm step (the per-language reviewer) is ungated per SKILL.md's Gating rules table and doesn't need a separate ask. CSV: one `general-purpose` fixer, gated. Dark-mode dropped.

**Boundary with the decision doctrine (METHODOLOGY Rule 1):** orchestrate decides *whether and
how to spend effort* on an ask — before that ask is understood as a bounded decision. It doesn't
reason through a trade-off itself. Once triage lands on "this needs research or a call between
≥2 viable options," that call belongs to Rule 1 (triad + `advisor()`,
`mattpocock-skills:grilling` for a hard/contested call), not to orchestrate. A multi-task inbox
routes through orchestrate first; a single, already-bounded question is answered directly under
Rule 1.

**Boundary with `/mattpocock-skills:wayfinder` (user-invoked):** orchestrate resolves a flat, in-session task list
in one pass, with no cross-session persistence. If a triaged item needs multi-session tracking
(can't close today), that's `/mattpocock-skills:wayfinder`'s job — it charts a persistent map of decision tickets on
an external tracker. Name it as the next step and stop there — `/mattpocock-skills:wayfinder` carries
`disable-model-invocation: true`, so only the user can start it (type `/mattpocock-skills:wayfinder`).
