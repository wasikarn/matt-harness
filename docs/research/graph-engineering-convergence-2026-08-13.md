# Graph Engineering (Greg Isenberg / vibecodingthailand) → kbg convergence map (2026-08-13)

## Question

*Graph Engineering: แตกงานเป็นกราฟให้ Claude Code กับ Codex ทำตาม แทนการทำทุกอย่างในแชทเดียว* (vibecodingthailand, 2026-08-09; raw at `~/llm-wiki/raw/Graph Engineering ...แชทเดียว.md`; source clip: Greg Isenberg, *Why Graph Engineering will 10x your Claude/Codex*). Its thesis: a single model in one chat both produces and scores its own work — "the writer and the reviewer are the same person" — so big tasks should be decomposed into an **agent graph** (not a knowledge graph) that separates maker from checker and puts human approval where a miss is expensive.

This is kbg-harness's own operating-model crux, arriving as a popular blog. The question is whether the article adds anything kbg doesn't already implement — and the honest answer is: **almost nothing to build.** This doc records the convergence so the external articulation is citable later, and names the two framings that are genuinely sharper than kbg's current wording (both stay optional, neither shipped).

## The article's load-bearing ideas

- **Maker ≠ checker.** The heart of its "Diamond Pattern": fan out producers → an independent skeptic reviews → only passing parts continue → synthesize → human approval. "Separating the checker from the producer is impossible in one chat."
- **Three primitives:** job (one step) / arrow (what follows) / state (shared record flowing through every step).
- **Approval-gate strength ∝ blast radius.** Loose gate for internal memos; tight gate for email-to-customer, deploy, production data, refund.
- **Smallest graph that improves quality.** More agents ≠ better — they can add noise ("several AIs confidently repeating the same wrong idea") and burn coordination budget. Stop when the answer is good enough.
- **Maturity ladder:** L1 manual lanes (no code, human carries state) → L2 file trails (each step writes a file) → L3 orchestrated (LangGraph / n8n / AutoGen, with state checkpoints, branching, human-approval nodes).
- **"Walk the graph by hand 3 rounds before automating."** If the hand-walked version doesn't produce clearly better work, automation just produces mediocre work faster.
- **Iceberg / moat.** After each round, leftover notes/evidence/drafts/decision-traces accumulate and feed the next round — the durable value, not the shipped output.
- **"It doesn't decide for you; it produces better evidence for deciding."**

## Convergence map — every element already in kbg

Verified against `skills/orchestrate/SKILL.md` (not from memory of the fleet):

| Article element | kbg implementation | Gap |
|---|---|---|
| Maker ≠ checker (core) | ARCHITECTURE crux + **`gate:task:complete-separation`** (`hooks/gates/task-complete-separation.sh`, `PreToolUse:TaskUpdate`): a subagent calling `TaskUpdate(status="completed")` is blocked at exit 2 — **the maker cannot computationally mark its own work done**; only the main session can. Plus `ship-merge` own-branch Critical-score cap (automation-bias guard against same-session self-review). | **None — kbg goes further** (article = process discipline; kbg = hard hook gate) |
| Diamond (fan-out → skeptic → fan-in → human gate) | orchestrate Step 4 parallel dispatch + **validation chain** (Builder → Validator → Fixer → Re-validator, the Validator a fresh-context independent read-only agent) + Step 5 "verify results, then combine" + Step 4 `AskUserQuestion` gate | Composed and used; not named "diamond" |
| Job / arrow / state | orchestrate dispatch graph (job) + `TaskCreate`/`addBlockedBy` + `.scratch/<task>/verdict.md` + `board.json` (state) + `addBlockedBy` edges (arrow) | Implicit; not named as graph primitives |
| Gate strength ∝ blast radius | Four-tier ladder: **Ungated** (read-only agents) / **Gated-AskUserQuestion** (write-capable agents) / **deny gates** (irrecoverable, `hooks/gates/irrecoverable.sh`) / `disable-model-invocation` (external writes: `ship-merge`, `wiki-ingest`, …) + confirm-before-push | None — already a 4-tier ladder |
| Smallest graph / more agents ≠ better | Fan-out hard cap 5 + "prefer 2-4; treat a 5-without-grouping wave as a consolidate signal" + "more agents is never the goal; the fewest that keep each one's reasoning out of the main thread" | None — enforced as a cap, not just stated |
| "Stop when good enough" / don't graph what one chat handles | **Fast Path Gate**: single bounded task (<30 lines, <2K tokens, deterministically verifiable, not auth/secrets) → execute inline, skip all orchestration | None |
| Maturity ladder | kbg lives at L2/L3 (verdict files = file trails; `Task`/`Agent` + `orchestrate` + `Workflow` = orchestrated) | None |
| Iceberg / moat | `docs/research/` + the memory store + `.scratch/<task>/verdict.md` = the accumulating trail | None |
| "Produces evidence, doesn't decide for you" | Advisory sensors journal but never emit `permissionDecision`; orchestrate "stops at get-the-data, doesn't make the call" → routes the reversible-choice call to `kbg:decide` | None — identical posture |

The one point worth underlining: the article's strongest claim — "separating the checker from the producer is impossible in one chat" — is stated as a workflow insight. kbg closes it **computationally**: `gate:task:complete-separation` makes self-completion a hard exit-2 deny, and the subagent's `agent_type` is fixed at spawn so it can't be forged. That is the same principle in a stronger form.

## Two framings sharper than kbg's current wording (optional, not shipped)

1. **Naming the diamond.** kbg composes to the shape (validation chain + parallel dispatch + independent validator + human gate) but never labels it. A one-line note in `orchestrate` ("the validation chain + parallel dispatch composes the Diamond Pattern: fan-out producers → independent validator → combine → human gate") would aid recall. **Not shipped:** it's a label on structure that already works, and adding it touches a runtime-loaded skill (version bump + pre-commit gate) for a naming aid — the cost isn't worth the marginal recall benefit unless the name is actually wanted in the fleet. Available on request.

2. **"Walk by hand 3 rounds before automating."** A genuinely sharp process discipline the article states explicitly and kbg does not. **Not shipped as doctrine** for two reasons: (a) it targets *recurring* work (a weekly job you'd hand-walk three times before wiring LangGraph); kbg sessions are predominantly one-shot, where the analog — plan-mode + Fast Path + propose-then-dispatch, "think before you fan out" — already exists. (b) The literal "three hand-walks" rule has no evidence in kbg's context; adding unverified process doctrine is the same class of move the verify-before-ship rule (CLAUDE.md) guards against. Noted here as a sharper framing; not elevated to doctrine.

## Decision: record-only, no new surface

No code, no skill, no hook, no harness-audit check, no doctrine addition. The article validates the harness's core doctrine from an independent external source — useful as a citation when the maker/verifier separation needs defending — and every operational element it names is already implemented, mostly in a stronger (computational) form. The two sharper framings are recorded above as available-but-deferred, each with the reason it wasn't shipped.

This doc is the entire adaptation. `docs/research/` is not a runtime-loaded surface (CLAUDE.md: "other docs/ content is cached but only ever read from the repo"), so no version bump is required.

## Cross-refs

- `skills/orchestrate/SKILL.md` — the validation chain, fan-out cap, Fast Path Gate, and Ungated/Gated ladder this map references.
- CLAUDE.md § Architecture (operating model) — "the gate is a verifier, the model is the maker, and the maker can never grade its own work"; the L2–L5 autonomy retirement.
- `hooks/gates/task-complete-separation.sh` — the computational enforcement of maker ≠ checker.
- `docs/research/observations-pattern-2026-08-13.md` — the same convergence (Zep's "deterministic algorithm groups, LLM only writes prose" = maker/verifier from the memory side), handled the same way: one transferable idea extracted into the smallest surface, not the whole platform.
- `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md` — "cognitive locality" / fewest-agents rationale behind the fan-out cap.