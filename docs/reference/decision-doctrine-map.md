# Decision-Doctrine Map

Single entry point mapping a **decision situation** → the **reasoning scaffold** to
reach for → the **owning doctrine rule** that governs it. The core doctrine is
injected every session by `doctrine-bootstrap.sh` (`METHODOLOGY.md`), but the
full picture is scattered across 6+ files; this page is the discoverability
index that makes "thinking/decision doctrine must not be missed" auditable on
one page.

The reasoning scaffolds are framing tools, **not** a proven accuracy boost — see
`reasoning-models.md` for the honesty caveat. Pick by **reversibility**, the axis
the Staff-Engineer Thinking Loop implies.

**`kbg:decide` is de-scoped from the default path (2026-07-02).** It was originally
presented here as the bound mechanism for most rows below. Measured evidence said
otherwise: 0 invocations across 182 real production sessions and this repo's own
dogfooding session, against 55 `advisor()` calls and 100 calls to other `kbg:` skills
in the same corpus — `advisor()` + inline reasoning is what's actually load-bearing.
The skill still exists (`skills/decide/SKILL.md`, not deleted) for the genuinely hard,
contested-diagnosis case; it's no longer the default row for routine non-trivial
decisions.

## Decision-sizing triad (run before any non-trivial act)

Owned by **METHODOLOGY.md Rule 1, sub-rule "Size the decision before acting"**.
Before building, answer all three (paraphrased here for discoverability —
sync-seam: this restates METHODOLOGY.md Rule 1's wording, no machine-check
ties the two; if Rule 1's phrasing changes, re-check this block):

1. **One-way door?** — if reversing is expensive, surface options + the fact that
   would flip the call. Don't pick silently.
2. **Blast radius** — name what downstream breaks and what this couples to.
3. **Riskiest assumption** — state it, verify it before building on it.

Match rigor to stakes; trivial/lookup tasks skip the triad.

## Situation → Scaffold → Owning rule

| Situation | Scaffold | Bound to (real surface) | Owning doctrine |
|---|---|---|---|
| any non-trivial decision — pressure-test before committing | triad + `advisor()` | `advisor()` tool — measured load-bearing (55 calls across 182 real sessions vs. 0 for `kbg:decide` in the same corpus) | METHODOLOGY Rule 1 |
| closing a consequential / hard-to-reverse decision | revisit trigger + progress metric | stated in the closing message — no dedicated artifact required | METHODOLOGY Rule 1 |
| genuinely hard, contested diagnosis — reasoning needs building from scratch, not just pressure-testing | `kbg:decide` (clarify/probe/decide/critique/strategize) | `skills/decide/SKILL.md` — on-demand, not a routine step | METHODOLOGY Rule 1 + `judgment-ladder.md` / `strategic-judgment.md` |
| disprove a confident output in fresh context before committing | `doubt-driven` (external) | spawn a fresh-context skeptic with no view of the work — not a `kbg:decide` mode, canonical instance is the adversarial pass in `kbg:review-pr` | METHODOLOGY Rule 1 |
| a mutation or ship | the harness **denies the irrecoverable set computationally** (`hooks/gates/irrecoverable.sh` — destructive Bash/git/SQL patterns) and **advises on the rest** (`hooks/advisory/flow-nudge.sh`); the **operator is the authority at every irreversible boundary** | `CLAUDE.md`'s Operating model (under §Architecture) |
| editing the code that judges the model (a gate, `hooks.json`, or the audit verifier) | `hooks/gates/verifier-protect.sh` — `permissionDecision: ask`, no env-var bypass | `CLAUDE.md`'s "Why — the unifying crux" (verifier-separation) |
| a db write | `hooks/gates/db-write-gate.sh` — `permissionDecision: ask` on non-SELECT `mcp__<server>__execute_sql*` calls, any server; no-op when no such MCP server is configured | `docs/harness-decay-cadence.md` §"Irreversible-action class" |
| an Atlassian (Jira/Confluence) operation | route through `jira-acli`'s skills (`jira-acli:acli`, `jira-acli:jira-content`, `jira-acli:confluence-content`) per `~/.claude/CLAUDE.md`; `hooks/advisory/jira-route-nudge.sh` reminds on a Jira/Confluence-shaped prompt (non-blocking — the Atlassian MCP tool schemas are the documented fallback for jira-acli's own closed-gap list) | n/a |
| approve / reject / rank / score a consequential decision | `kbg:score-decision` — stated criteria + weights, pass threshold + fatal-weakness floor | `skills/score-decision/SKILL.md` | METHODOLOGY Rule 14 |

## Interrogate the incoming claim (Rule 3)

Owned by **METHODOLOGY.md Rule 3**. A requirement, bug report, idea, diff, or task
prompt is a claim to test before you act on it — the general principle stays in
Rule 3 (kept tight, it's injected every session); this table is the per-claim
routing, kept here to avoid bloating the injected copy. All surfaces are
kbg-native (this plugin's own fleet) unless noted.

| Incoming claim → action | kbg-native critical-thinking surface |
|---|---|
| Requirement → build | `kbg:requirement-analyst` — ambiguity/gap/edge-case/testability sweep, readiness verdict |
| Diff → merge | `kbg:review-pr` (adversarial Phase 3.5/3.6), `kbg:blind-spot-hunter`, `kbg:ship-merge`'s score gate |
| Idea → spec | `kbg:ideate-critic` (`/ideate` Phase 2 fresh-context critic) |
| Task prompt → dispatch | `kbg:task-prep` + `kbg:task-prep-checker` (Opus fresh-context verifier) |
| Task/requirement → plan authoring | `kbg:code-architect` — codebase-grounded blueprint (pattern analysis, layer-direction check, DI-style check, test-impact check) for a multi-file or architectural plan-mode draft; its output format (Design Decisions, Trade-offs, Build Sequence, Risks, Success Criteria) is the plan. Named in METHODOLOGY Rule 1's plan-mode section since v0.68.297 — doctrine text only, no deterministic hook (a `PostToolUse:EnterPlanMode` hook was considered and rejected: Shift+Tab, the common entry path, never calls that tool, so the hook would miss most real entries) |
| Plan → implement | `kbg:plan-reviewer` — adversarial pre-code plan review across 8 lenses (requirement coverage, assumptions/missing work, architecture fit, risk/failure modes, edge cases, execution order/dependencies, testing/verification, operability/reversibility); severity-earned findings + fatal-weakness-floor verdict. Heavier and on-demand than `advisor()` — for a consequential plan (multi-file, one-way door, unfamiliar subsystem), not routine. Since v0.68.3, `hooks/advisory/plan-review-nudge.sh` (`PostToolUse:ExitPlanMode`) fires this reminder automatically the moment a plan is approved — deterministic trigger, not a memory-recall dependency |
| Implementation → verify | `kbg:compliance-audit` — plan-as-ground-truth conformance check (fresh-context verifiers, `MISSING` as a first-class verdict, pre-declared-vs-independently-found deviation reconciliation); distinct from `review-pr`'s diff-as-ground-truth quality/security lenses. `disable-model-invocation: true` — the user runs it, not the model. Since v0.68.138, `hooks/advisory/compliance-audit-nudge.sh` (`PostToolUse:Bash`, on a `git commit`) reminds the model to tell the user this option exists when a plan was approved earlier the same session — deterministic trigger, not a memory-recall dependency |
| Bug report → fix | `kbg:silent-failure-hunter` + the root-cause-not-symptom reflex (`ponytail@ponytail`, a separate installed plugin, not kbg-native) — covered by Rule 3's general reflex; no bug-report-*specific* rung or nudge yet, deliberately deferred (METHODOLOGY Rule 2), revisit if a symptom-patch incident surfaces. Narrower and unrelated to this deferral: `flow-nudge.sh`'s *generic* plan-first nudge now also fires on a complex/systemic bug fix (bug-language + breadth-language co-occurrence, e.g. "race condition ... across every service") since 2026-08-05 — see `docs/research/plan-mode-nudge-audit-2026-08-05.md`. That's Rule 1's plan-mode criteria applying to a bug fix like any other code edit, not a bug-report-specific route; this row's deferral still stands. |

## Who owns which doctrine surface

Per-file split: `METHODOLOGY.md` = process + thinking-loop (Rules 1, 2, 3, 4, 13, 14);
`CLAUDE.md` (doctrine home) = architecture + operating model + autonomy invariant,
guarded by `hooks/gates/verifier-protect.sh`, not a file-based cage (the L3–L5
bounded-autonomy cage was retired in the v0.6.0 reset). The prior RTK/ACLI/DBGATE
per-topic doctrine split described here did not survive that reset — there is no
current equivalent for risk/gate, Atlassian-contract, or db-write doctrine as
standalone files.

## Vendored thinking-skills (on-demand reference, NOT promoted)

The 39 TJ Boudreaux thinking skills are vendored at `docs/reference/thinking-skills/`
as reference catalog — kept on-demand, **not** auto-loaded, **not** promoted to a
skill under `skills/`. Their own replication-gated eval shows zero of 39 clear an accuracy
bar; promoting them would couple kbg to unproven scaffolds (METHODOLOGY Rule 2).