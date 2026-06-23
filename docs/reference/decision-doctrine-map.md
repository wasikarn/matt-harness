# Decision-Doctrine Map

Single entry point mapping a **decision situation** → the **reasoning scaffold** to
reach for → the **owning L1/L2 doctrine rule** that governs it. The doctrine is
present (L1-injected every session by `doctrine-bootstrap.sh`) but scattered
across 6+ files; this page is the discoverability index that makes
"thinking/decision doctrine must not be missed" auditable on one page.

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

| Situation | Scaffold | Owning doctrine |
|---|---|---|
| scope vague / assumptions unstated | `clarify-first` | METHODOLOGY Rule 1 (Think Before Coding) |
| read-only analysis of a design choice before committing | `probe` | METHODOLOGY Rule 1 |
| a **reversible** choice worth a Judgment-Ladder pass | `decide` | RTK (risk/gate) + `judgment-ladder.md` |
| an **irreversible** / long-horizon commitment under contested diagnosis | `strategize` | RTK + `strategic-judgment.md` |
| audit existing reasoning (plan, ADR, RFC) for hidden assumptions | `critical-eval` | RTK |
| disprove a confident output in fresh context before committing | `doubt-driven` (external) | METHODOLOGY Rule 1 |
| a mutation or ship under autonomy (L3/L4/L5) | the **computational** gate (gauntlet / push-gate), never the model | ADR 0002–0005 (autonomy invariant); model is veto-only |
| writing to a doctrine/caged file | doctrine-edit-gate (interactive) / cage-deny (loop) | ADR 0003 (cage); `cage.txt` |
| a db write | `db-write-gate.sh` | DBGATE.md |
| an Atlassian (Jira/Confluence) operation | the Atlassian MCP contract | ACLI.md |

## Who owns which doctrine surface

See `DOMAINS.md` → **Doctrine Ownership** for the per-file split (METHODOLOGY =
process + thinking-loop; RTK = risk/gate; ACLI = Atlassian-contract; DBGATE =
db-write; `docs/adr/` = autonomy decisions, cage-protected).

## Vendored thinking-skills (L3 reference, NOT promoted)

The 39 TJ Boudreaux thinking skills are vendored at `docs/reference/thinking-skills/`
as reference catalog — kept on-demand, **not** auto-loaded, **not** promoted to L2
invokable skills. Their own replication-gated eval shows zero of 39 clear an accuracy
bar; promoting them would couple kbg to unproven scaffolds (METHODOLOGY Rule 2).