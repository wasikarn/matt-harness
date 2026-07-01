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
| scope vague / assumptions unstated | `clarify-first` | `kbg:decide` clarify mode | METHODOLOGY Rule 1 (Think Before Coding) |
| read-only analysis of a design choice before committing | `probe` | `kbg:decide` probe mode | METHODOLOGY Rule 1 |
| a **reversible** choice worth a Judgment-Ladder pass | `decide` | `kbg:decide` decide mode (default) | METHODOLOGY Rule 1 + `judgment-ladder.md` |
| an **irreversible** / long-horizon commitment under contested diagnosis | `strategize` | `kbg:decide` strategize mode | METHODOLOGY Rule 1 + `strategic-judgment.md` |
| audit existing reasoning (plan, ADR, RFC) for hidden assumptions | `critical-eval` | `kbg:decide` critique mode | METHODOLOGY Rule 1 |
| disprove a confident output in fresh context before committing | `doubt-driven` (external) | spawn a fresh-context skeptic with no view of the work — not a `kbg:decide` mode, canonical instance is the adversarial pass in `kbg:review-pr` | METHODOLOGY Rule 1 |
| a mutation or ship | the harness **denies the irrecoverable set computationally** (`hooks/gates/irrecoverable.sh` — destructive Bash/git/SQL patterns) and **advises on the rest** (`hooks/advisory/flow-nudge.sh`); the **operator is the authority at every irreversible boundary** | `CLAUDE.md`'s Operating model (under §Architecture) |
| editing the code that judges the model (a gate, `hooks.json`, or the audit verifier) | `hooks/gates/verifier-protect.sh` — `permissionDecision: ask`, no env-var bypass | `CLAUDE.md`'s "Why — the unifying crux" (verifier-separation) |
| a db write | no dedicated gate exists today — candidate for a future `hooks/gates/` addition | `docs/harness-decay-cadence.md` §"Irreversible-action class" |
| an Atlassian (Jira/Confluence) operation | the Atlassian MCP tool schemas (`mcp__*atlassian*`) — no dedicated kbg contract doc exists today | n/a |

## Who owns which doctrine surface

Per-file split: `METHODOLOGY.md` = process + thinking-loop (Rules 1, 2, 4, 13, 14);
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