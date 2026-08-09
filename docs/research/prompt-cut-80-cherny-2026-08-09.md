# The 80% system-prompt cut (Cherny/Thariq) vs kbg's decay cadence — claim-by-claim

*2026-08-09. Line-by-line read of vibecodingthailand.com's write-up of Boris
Cherny's YC Startup School 2026 talk ("We Cut 80% of Claude Code's Prompt"),
cross-checked against the Anthropic-side primary source already in the vault:
Thariq (@trq212), "The new rules of context engineering for Claude 5 models,"
2026-07-24 (`llm-wiki/raw/The-new-rules-of-context-engineering-for-Claude-5-models.md`).
Method and verdict style follow the 2026-08-02 loop/graph trend audit
(`loop-graph-engineering-trend-audit-2026-08-02.md`).*

**Headline verdict:** the talk is external validation of `docs/harness-decay-cadence.md`
run at the vendor layer — most claims are already kbg doctrine, independently
arrived at. Three genuine deltas were adopted into the decay doc (product-consistency
carve-out, scored measure + eval-lifespan asymmetry, `/doctor` as a
candidate-surfacing lens). Nothing here re-opens ADR 0006 or the eval-gate
question — that territory was settled across an 11-source audit
(memory: `eval-gate-6step-article-vs-kbg-doctrine-2026-08-02`).

## Claims, verification, and mapping

Verdicts: **✓ already doctrine** · **Δ adopted** · **— noted, no change** · **? unverifiable**

| # | Claim (source) | Verified? | kbg posture | Verdict |
|---|---|---|---|---|
| 1 | >80% of Claude Code's system prompt deleted for the Claude 5 generation (both sources) | Yes — Thariq (Anthropic) states it directly: Opus 5 + Fable 5, "no measurable loss on our coding evaluations" | Same move `harness-decay-cadence.md` prescribes, at vendor scale | ✓ |
| 2 | Deletion is routine on every model generation — system prompt, tool set, tool prompts all rewritten | Corroborated by both sources | Decay doc's "on model upgrade" trigger | ✓ |
| 3 | A rule's lifespan = the model generation that necessitated it | Consistent across both | The decay doc's core lens, near-verbatim ("every component compensates for an assumed model limitation") | ✓ |
| 4 | Undocumented env var strips system + tool prompts for ablation | Env var unnamed in either source; the *practice* (ablation, measured) corroborated by Thariq | kbg analog: disable-and-measure (step 2) | ? / ✓ |
| 5 | Removing the excess made the model "slightly smarter" (Cherny) vs "no measurable loss" (Thariq) | The two sources differ slightly in strength; Thariq's is the primary written claim | No dependency on which is right — both justify delete-first | — |
| 6 | Not "fewer words always better": capability-scaffolding text (cut) ≠ product-consistency text (keep) | Cherny's own on-stage distinction | **Gap** — the decay lens had one carve-out (maker≠checker verifiers) but no product-consistency category; kbg has real instances (`output-styles/staff-eng.md`, templated PR/command bodies) | **Δ adopted** |
| 7 | What survives repeated cuts: safety, permission handling, static analysis, UI code | Cherny | kbg's operating model verbatim — gates deny the irrecoverable set computationally, advisory sensors journal; capability scaffolding is what ADR 0006 retired | ✓ |
| 8 | Users should strip CLAUDE.md/skills/hooks ~every 6 months and watch what the model does bare | Cherny's explicit recommendation | kbg's cadence is *more frequent* (quarterly) but gentler (per-candidate incremental). Full-class ablation on major upgrades is a legitimate aggressive variant | **Δ adopted** (documented as the upgrade-time variant, still human-gated) |
| 9 | 4-step rebuild loop: delete → run real (don't guess) → spot repeated failures → re-add only there | Cherny | Steps 2–3 = disable-and-measure; the re-add-only-on-repeated-failure discipline folds into the ablation-variant note | ✓ / Δ |
| 10 | Evals are the exception: keep and accumulate across model generations to score each cut | Cherny; Thariq's "no measurable loss on our coding evaluations" is this principle in action | **Gap** — decay step 2's "if quality holds" named no instrument; kbg's own "Score, not feel" crux demands one | **Δ adopted** |
| 11 | Each eval set saturates in ~1–3 model generations; retire on saturation (model aces it), not on upgrade cadence; write harder sets from where the current model fails | Cherny's estimate, uncorroborated but low-risk | Absent from the decay doc; now noted as the lifespan asymmetry (rules decay per generation, eval sets accumulate until saturated) | **Δ adopted** |
| 12 | Replace deleted rules with: a task slightly harder than you think it can do, goal overview, guardrails, done-condition — not step-by-step | Cherny | `task-prep` / `goal-craft` already encode goal + guardrail + done-when; METHODOLOGY's plan-mode checkpoint covers the rest | ✓ |
| 13 | Key skill shift: problem-setting + making Claude verify its own work mid-flight | Cherny | Scoped agreement: in-flight self-checks are fine (advisory), but *final* verification stays maker≠checker — the decay doc's hard guard. Cherny's advice doesn't claim otherwise; no change | — |
| 14 | "Coding is solved" — but only his kind of coding; deep systems, distributed systems, pixel-level UI verification still weak | Cherny, self-scoped on stage | Context for calibration; no kbg surface encodes a "coding is solved" assumption | — |
| 15 | Empirical stance: don't inherit old-model assumptions; run, observe, adjust | Both | kbg's evidence-over-feel doctrine + disable-and-measure | ✓ |

### Thariq-only claims (not in the talk write-up)

| Claim | kbg posture | Verdict |
|---|---|---|
| Conflicting instructions across assembled context ("leave documentation as appropriate" vs "DO NOT add comments") are the concrete over-constraint failure mode | Adjacent to `kbg:claude-md-health`'s three checks but not covered (it checks one doc's health, not cross-surface conflicts). No incident has proven the need — named here, not built (Rule 2) | — noted |
| `/doctor` (in-session) rightsizes skills and CLAUDE.md files | Verified locally 2026-08-09: CLI `claude doctor` is install-health only; its own help text points to in-session `/doctor` as "a full checkup that can also fix issues." The rightsizing purpose is Thariq's (Anthropic) claim | **Δ adopted** (decay step-1 lens) |
| Tool-usage examples constrain the exploration space; design expressive interfaces instead | Applies to tool descriptions, not skill prose; matt-pocock skill-authoring doctrine is a different surface with its own evidence | — noted |
| Progressive disclosure over central-repository CLAUDE.md | kbg already runs this shape (skills load on demand, `docs/reference/` trees, deferred tools) | ✓ |

## Adjustments shipped (same commit)

All three in `docs/harness-decay-cadence.md`, v0.68.238:

1. **Lens section** — second non-decay carve-out: product-consistency text
   (output styles, templated bodies) defines product behavior rather than
   compensating for a limitation; not decay-eligible on "the model got smarter"
   grounds (claim 6).
2. **Cadence step 2** — "quality holds" must be a score, not a recollection:
   prefer an existing deterministic check (behavioral test suite, harness-audit
   check, a skill's `evals/` set). Plus the lifespan asymmetry: eval sets
   accumulate across generations and retire on saturation (~1–3 generations),
   unlike the rules they measure (claims 10–11).
3. **Cadence step 1 + variant note** — `/doctor` added as a candidate-surfacing
   lens; Cherny's full-class ablation (~6-month strip of CLAUDE.md/skills/hooks)
   documented as the aggressive upgrade-time variant of disable-and-measure,
   human gate unchanged (claims 8–9).

## What was deliberately not done

- **No eval-gate rebuild, no autonomy re-litigation.** Claim 10 strengthens the
  *measurement* discipline inside the existing human-gated cadence; it does not
  argue for the retired merge-gate machinery (ADR 0006, reconfirmed on 4
  independent legs, 2026-08-02).
- **No cross-surface conflict detector.** Real failure mode per Thariq, zero
  observed incidents here. Named above so a future incident has a hook.
- **No memory entry.** This doc is the repo record; qmd indexes `docs/research/`
  (`kbg-research` collection), so it's findable without index weight.

**Sources:** vibecodingthailand.com/blog/claude-code-prompt-cut-80 (Thai
write-up of the YC talk, fetched 2026-08-09); Y Combinator channel clip "Boris
Cherny: We Cut 80% of Claude Code's Prompt"; Thariq (@trq212) X article
2026-07-24 (vault: `llm-wiki/raw/The-new-rules-of-context-engineering-for-Claude-5-models.md`).
