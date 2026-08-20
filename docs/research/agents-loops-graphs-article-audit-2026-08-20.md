# "Agents, Loops, Graphs" article vs. kbg-harness — audit (2026-08-20)

**Source:** "Agents, Loops, Graphs. Everything You Need to Know in One Place," Mahax
(@Mahaximus_), published 2026-08-05 (X/Twitter thread, 464 lines, `~/llm-wiki/raw/`). Not yet
ingested to `wiki/`. Three sections: Agents (levels of agentic sophistication, agent system
prompts, checkpoint/memory prompts), Loops (PLAN/EXECUTE/CHECK/ITERATE/STOP cycle, a 4-condition
worth-it test, a self-scoring loop prompt, cost economics), Graphs (node/edge, the "fake edge"
test, "The Diamond" fan-out→reduce→verify→synthesize pattern, "The Checker" fresh-context
adversarial verification, the `workflow` keyword in Claude Code).

## Verdict

**Almost entirely already-settled ground, cross-referenced rather than re-derived — one small,
genuinely new candidate named, not built.** This article overlaps so heavily with 2 prior audits
this session found via `qmd` that most of it required confirmation, not fresh investigation:

- **Graphs section ≈ `docs/research/graph-engineering-convergence-2026-08-13.md`.** That doc
  already mapped an almost-identical "Diamond Pattern" (fan-out → skeptic → fan-in → human gate),
  the same maker≠checker "Checker" concept, and the same "smallest graph that improves quality"
  discipline against kbg's `orchestrate` skill and hard gates (`gate:task:complete-separation`),
  concluding "almost nothing to build." Nothing in this article's Graphs section adds beyond that.
  The specific fan-out/reduce/verify/synthesize pseudocode (article lines 306-338) is close enough
  to `deep-research.js`'s claim-dedup pattern that it's effectively the same ground this session's
  own `reducer-engineering-article-audit-2026-08-20.md` covered two cycles ago, from yet another
  source.
- **Loops section ≈ Article 11 (Hosni) coverage inside
  `docs/research/loop-graph-engineering-trend-audit-2026-08-02.md`, "Update 2026-08-06" (lines
  403-502).** That pass ran 5 independent verification sweeps against a *more* detailed loop
  design (typed task contracts, failure classification, retry budgets, worktree isolation) and
  found exactly 1 real gap, already shipped (v0.68.204). The current article's lighter framing
  (5-step cycle, 4-condition worth-it test, stop conditions) is a strict subset of what that pass
  already checked. `commands/iterate-skill.md`, `skills/harness-audit/`, `skills/eval-harness/`
  were all separately confirmed there as existing, sometimes-stronger matches for "a real test that
  can fail" / "a hard stop condition."

Two things weren't directly covered by either prior doc, and were checked fresh by a dispatched
verifier before writing this section:

## New finding 1: "Agent levels 1-4" — the top rung is ADR 0006's retired territory, not new

The article frames agentic sophistication as a natural ladder: Level 1 (chat) → Level 2 (Claude
decides to use a tool mid-response) → Level 3 (multi-step workflow, no human between steps) →
Level 4 (*"runs on a schedule or a trigger... without a human in the loop. You set the goal once
and check the output."*). Checked against kbg's own retired L2-L5 autonomy ladder and ADR 0009's
scoping clarification:

- **Levels 1-2 sit in territory kbg already has a considered, uncontested position on.** No tension
  — a session-initiated model deciding mid-response to use a tool is unremarkable under any of
  kbg's doctrine.
- **Level 3 is not cleanly "already permitted," on a closer read.** ADR 0009 allows bounded
  auto-continue *within an operator-started session* — but narrowly: "no self-launch... auto-
  continue within an operator-started session, not a launchd/cron/`claude -p` self-start"
  (`docs/research/adr-0009-bounded-review-fix-auto-loop.md:303-306`) — scoped to own-branch
  review→fix loops, capped at 5 rounds, not a general "no human between steps" license. In fact
  kbg's own general-purpose multi-step mechanisms shaped like Level 3 (`recursive-improve`,
  `iterate-skill`) deliberately do the opposite of the article's defining feature ("you are not
  involved between steps") — both require a human `AskUserQuestion` gate before every mutating
  step. Level 3 is a mixed picture, not a clean match either way.
- **Level 4 specifically is the exact case ADR 0006 retired, not a lookalike.** Both texts key on
  the same qualifying fact — schedule/trigger-launched execution with no human starting it. ADR
  0009 quotes ADR 0006 directly: *"The model cannot self-start the improvement loop. (The launchd
  self-start is gone with the L4 machinery; there is no OS-scheduler self-start either now.)"*
  (`adr-0009-bounded-review-fix-auto-loop.md:75-78`) — the same rule CLAUDE.md states as "The
  L2–L5 autonomy ladder is retired" (`CLAUDE.md:105`) and, in its literal scare-quoted phrasing,
  the "no model self-start" invariant (`CLAUDE.md:174`).

The article presents Level 4 as simply the natural top rung of a progression ("add one at a time
and you move up a level") with no acknowledgment that a real harness tried exactly this rung and
walked it back for a specific, documented reason (maker appointing its own verifier). Worth stating
precisely rather than either dismissing the framing wholesale or treating it as new information.

## New finding 2: "keep-rate" loop economics — genuinely new, small, not built

The article's cost argument (lines 240-242): *"The number worth tracking is not total tokens
spent. It is how many outputs you actually kept... Below a 50% keep rate, the loop costs more than
doing it yourself."* Checked against `hooks/stop/cost-tracker.sh` (accumulates additive spend only
— groups by `(model, agent_type)`, sums into `estimated_cost_usd`, no kept-vs-discarded concept
anywhere) and `commands/iterate-skill.md`/`skills/recursive-improve/SKILL.md` (both already record
a per-iteration `improved | flat | regressed` verdict — raw material for a keep-rate, but nothing
sums it into a ratio or reports one; each verdict feeds one human decision, not a cumulative
percentage).

This is a real, small, cheap-to-add idea kbg doesn't have today — **not built**, per the same Rule
2 standard this session's other audits have applied consistently: no session has yet surfaced "an
iterate-skill/recursive-improve run kept spending past the point it was worth it" as an observed
problem, and both mechanisms already cap at small iteration counts (3 and a 5-round ceiling
respectively), which limits how much a keep-rate metric would actually change behavior at this
scale. Recorded as an available-on-request candidate, same posture as
`graph-engineering-convergence-2026-08-13.md`'s "two framings sharper than kbg's current wording"
— named, not shipped.

## Bottom line

Two of the article's three sections are, on direct comparison, the same ground two prior deep
audits already covered — the Graph section almost verbatim, the Loop section a strict subset of a
more rigorous prior pass. The Agents section's one distinguishing idea (a natural 4-level ladder)
turns out to end exactly where kbg's own already-retired ladder ends, for the same reason. The one
genuinely new, unbuilt idea (keep-rate reporting on top of existing improved/flat/regressed
tallies) is real but thin — named as a candidate, not queued as work, consistent with how this
session's other article audits have handled small-but-unproven ideas.
