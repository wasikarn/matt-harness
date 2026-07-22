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
Before building, answer all three:

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
| a db write | `hooks/gates/db-write-gate.sh` — `permissionDecision: ask` on non-SELECT `mcp__tathep-db__execute_sql*` calls; no-op when tathep-db isn't configured | `docs/harness-decay-cadence.md` §"Irreversible-action class" |
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
| Bug report → fix | `kbg:silent-failure-hunter` + the root-cause-not-symptom reflex (`ponytail@ponytail`, a separate installed plugin, not kbg-native) — covered by Rule 3's general reflex; no bug-report-*specific* rung or nudge yet, deliberately deferred (METHODOLOGY Rule 2), revisit if a symptom-patch incident surfaces |

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