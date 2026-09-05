---
name: ideate
description: "Parallel divergent ideation (5 isolated agents, rotating frames, novelty/viability/fit scoring). Use when the question is open-ended. Say 'brainstorm/ระดมความคิด/คิดไอเดีย'. Not for syntax, lookups, or closed-phrasing asks."
argument-hint: "[problem-statement]"
disable-model-invocation: false
disable-model-invocation-reason: Auto-fire on vague prompts is load-bearing (catches prompts the model would otherwise default on). Cost is bounded by the 5-agent-per-wave cap (METHODOLOGY Rule 13) and the 2-wave fan-out callout below — NOT by this flag.
model: inherit
effort: high
---

# Ideate

Single kbg ideation surface. Type `mh:ideate` explicitly (e.g.
`mh:ideate How should we design a feature flag service?`), or let the model auto-route here on
vague, open-ended, high-stakes prompts — either path runs the same algorithm.

## Pre-flight gate

This surface is expensive — about 8-10 Agent calls, 30-90s wall clock, 5-10x a single
answer — so don't pay that cost when a direct answer is better. Run this gate before Phase 1.

Steps 0-2 (warning-block check, explicit-invocation bypass, when the self-judge applies): read `references/preflight.md` first. An explicit `mh:ideate`/"brainstorm" skips straight to Phase 1; otherwise self-judge below.

Ask three questions. If any answer is NO, ABORT.

1. **Open-ended?** Multiple viable answers, or one canonical (syntax fix, known-root-cause
   bug, lookup, "what is the X for Y", "find the file that does X") → abort.
2. **High-stakes?** Is the obvious answer expensive to get wrong (architecture, public API,
   naming, schema, fuzzy-debug = yes; side project at 11pm = no)?
3. **Open phrasing?** Did the user avoid "quick"/"standard"/"canonical"/"textbook"/"just"/
   "one-line(r)"? Any of those → they want the direct answer, abort.

All three pass → proceed to Phase 1. Any fails → ABORT and answer directly, optionally
appending: *"If you want a wider exploration under parallel cognitive frames with explicit
trap detection, run `mh:ideate <your problem>`."*

## Session frame rotation, convergence, and memory search (advisory)

A SessionStart hook may inject `<ideate-rotation index="N">` with 5 frame names — prefer
those (already covers the 1-wild minimum, rotated vs. prior sessions). If absent, fall back
to [Picking frames](#picking-frames). Step 0's convergence capture side (SessionEnd embedding
hook + `convergence.sh`) is **not currently wired** (removed in the reset) — treat
convergence as advisory-only until rebuilt. Mechanics: `references/provenance.md`'s "Advisory
hooks — full mechanics" section.

## 2-wave fan-out (load-bearing)

> **WARNING — this skill is 2 fan-out waves, NOT 1.**
>
> - **Phase 1 (Diverge)**: 5 parallel Agent calls, peak 5.
> - **Phase 2 (Focus)**: sequential score + cluster on the host, no fan-out.
> - **Phase 3 (Deepen)**: 3 parallel Agent calls, peak 3.
>
> **Peak concurrent = 5** (the hard cap in METHODOLOGY Rule 13). Sequential: Phase 1 → Phase 2 →
> Phase 3. ≈8-10 Agent calls/run. **Do not collapse into 1 wave.**
>
> Audit history (the 44→105-agent failure mode) and enforcement mechanism:
> `references/provenance.md`'s "2-wave fan-out — audit history" section.

## Phase 1 — Diverge

For the problem P:

1. **Pick 5 cognitive frames** — see [Picking frames](#picking-frames).
2. **Spawn 5 parallel Agent calls**, one per frame — each Agent gets ONLY the payload and
   system prompt in `references/algorithm-detail.md`'s "Phase 1" section (read them there verbatim
   before dispatching), no peer branch data (see
   [Isolation invariant](#isolation-invariant)).
3. **Wait for all 5 to return** before reading outputs — don't start reading one branch
   before the others finish.

Algorithm-shape source + port decisions: `references/provenance.md`'s "Phase 1 algorithm-shape source" section.

## Phase 2 — Focus

After all 5 Diverge branches return:

1. **Score.** Rate each idea on three axes 0 to 10:
   - **Novelty** — distance from the obvious default
   - **Viability** — could it actually ship
   - **Fit** — does it address the stated problem

   Attach a one-line `trap` reason to any idea that looks attractive but is a trap (hidden
   cost, false economy, will-not-scale, premature abstraction) — `trap` is a free-text reason
   field, NOT a score threshold; full mechanics + score-chip format:
   `references/algorithm-detail.md`'s "3-axis scoring rubric" section.

   **Named bias guard (anchoring + confirmation):** score every idea on the same axes before
   ranking — don't let the first idea set the scale. `trap` is the confirmation guard: look
   for why an attractive idea is wrong, not just evidence it's right.

2. **Cluster.** Group ideas into 3-6 clusters by **underlying angle**, not surface keywords —
   label by angle ("remove-the-server plays", "cache-shaped plays"). The shape of the idea
   space is the point. **Note independent convergence:** when a cluster draws from ≥3
   distinct frames, say so next to the label ("3 frames converged here") — keep it visible.

3. **Deepen the top 3.** Rank by weighted score (`novelty × 0.35 + viability × 0.40 +
   fit × 0.25`), exclude traps, take top 3. Spawn one **parallel** Agent call per idea
   (Phase 3) with the FOCUS-mode system prompt from `references/algorithm-detail.md`'s
   "Phase 3" section — sibling ideas ride along as a recombination pool, never another deepen
   branch's output.

**Fresh-context critic — default on the auto-fire path.** Host-Claude scoring carries an
LLM-judge-circularity caveat; Step 2 already requires a YES on "high-stakes?" before
auto-fire, so:

- **Auto-fired (via Step 2):** default to the `ideate-critic` agent
  (`agents/ideate-critic.md`), not host-Claude.
- **Explicit invocation (via Step 1, self-judge skipped):** keep host-Claude as default —
  stakes aren't classified here; the user can request the critic explicitly.

Invocation + returned-field rendering: `references/algorithm-detail.md`'s "Critic invocation" section.
Full rationale: `references/provenance.md`'s "Phase 2 critic-routing source" section.

## Frames table

The 15 cognitive frames — each with its tags (`code`/`design`/`general`/`wild`) and vantage
prompt — live in [`references/frames.md`](references/frames.md), kept out of this file for
size.

### Picking frames

Code-shaped problems: pick 4 frames tagged `code` or `design`, plus 1 tagged `wild`. Open
product/strategy problems: a mix from all tags. Vary picks across sessions so re-runs produce
different candidates.

## 3-axis scoring rubric

```
total = novelty * 0.35 + viability * 0.40 + fit * 0.25
```

Viability is heaviest (unshippable-but-brilliant is the dominant failure mode). Full
mechanics — trap field, chip rendering, source: `references/algorithm-detail.md`'s
"3-axis scoring rubric" section.

## Isolation invariant

**Diverge branches MUST NOT see each other's output — each Agent call is independent.** The
Phase 1 payload does NOT list other branches or carry peer `Idea` objects, and its system
prompt forbids cross-talk. Sibling recombination is passed ONLY at Phase 3 (deepen), never
during Diverge. This is load-bearing: a branch seeing another's output anchors the two
together, collapsing the method to one wider thought (no shared mutable state across parallel
branches).

**Practical rules:** don't call one Diverge Agent from another; don't include a "here's what
the other branches generated" line in any Diverge userPrompt; don't carry `Idea` objects
forward into a Phase 1 sibling. DO pass siblings as a read-only recombination pool to the
Phase 3 deepen Agent — never the focus idea.
Source: `references/provenance.md`'s "Isolation invariant source" section.

## Phase 4 — Interactive deepen (optional)

If the user replies after the initial output asking to explore a shortlisted idea, rotate the
frames, or combine candidates, run a short Phase 4 pass instead of starting over. The 3
supported patterns and exact behavior: [`references/phase4.md`](references/phase4.md).
Phase 4 is **opt-in** — don't offer it unprompted. It costs the same as a partial run
(1-3 Agent calls); ask first if the budget/convergence warning is active.

## Output shape

Render in this order after Phase 2 — the structure is the point, never a wall of prose:
**1. Brief + cost estimate** → **2. Wide set** (clusters, score chips, convergence notes) →
**3. Converge** (2-4 shortlist with reasons, ★ non-obvious pick, traps listed separately) →
**4. Focus** (3 deepened branches) → **5. Provocation** (one wildcard).
Full per-item rendering contract — read before rendering:
`references/algorithm-detail.md`'s "Output shape — full rendering contract" section.

## When NOT to use

Concrete Step 2 abort triggers: syntax fixes, name/file lookups, known-root-cause bug fixes
("fix the bug, don't ideate around it"), anything phrased "quick"/"just"/"one-liner"/
"standard"/"canonical"/"textbook".

## Anti-patterns / Cost / Cross-references

How this skill goes wrong (convergence disguised as divergence, collapsing the 2-wave
structure, silent parse failures, same-model-judge-as-ground-truth):
`references/anti-patterns.md`. Per-run cost estimate + provenance: `references/cost.md`.
Why this exists, the F8.5 cap, maker≠checker methodology: `references/provenance.md`'s
"Cross-references" section.
