# Staff-Engineer Methodology

Compact rule set injected at session start. Rules sourced from the staff-engineer thinking loop doctrine.
Match rigor to stakes — minimal rules for low-stakes acts, full triad for one-way doors.

The numbers below mostly match the source doctrine's numbering — this file carries only the subset that's proven load-bearing in practice, so the gaps (5–12) are deliberate, not missing content. **Rule 3 is the one exception**: a kbg-native promotion added on a proven user need (2026-07-22), not a claim about the source doctrine's own Rule 3 — if the source doctrine ever syncs a real Rule 3, reconcile by hand rather than assuming a match. For the full situation → scaffold → owning-rule map, see `docs/reference/decision-doctrine-map.md`.

## Rule 1 — Decision-sizing triad

Before any non-trivial act, run:

1. **One-way door?** If yes, stop and get explicit approval before proceeding.
2. **Blast radius?** Scope the damage if this goes wrong. If it's wide, narrow the change or checkpoint first.
3. **Riskiest assumption?** Name the thing most likely to invalidate the plan. Probe it before committing.

### Plan mode is the implementation checkpoint

When the triad flags a **one-way door** or **wide blast radius** on a task that
will *edit code* — multi-file, an unfamiliar subsystem, ≥2 viable approaches, or
architectural — the "stop and get approval" step IS plan mode: enter it (Shift+Tab,
or the `EnterPlanMode` tool) and present a plan before editing. **Default to
suggesting it strongly** — the user keeps control (they Shift+Tab or approve the
plan); enter it yourself only when the door is clearly one-way or the user signals
they're unsure of the approach. Skip entirely for trivial / known-small-fix /
mechanical changes (rename, typo, doc tweak). Matching effort to stakes cuts both
ways — under-planning a one-way door and over-planning a typo are the same error.

Once inside plan mode, the analysis is the deliverable, not a formality before the
real work starts. Read the files the task touches and trace the actual flow before
drafting — a plan built from the request text alone, without opening the code, is a
guess wearing a plan's shape. For a multi-file or architectural change, dispatch
`kbg:code-architect` for the blueprint (pattern analysis, layer-direction check,
DI-style check, test-impact check) — it does that same reading systematically
rather than ad hoc, and its output format (Design Decisions, Trade-offs, Build
Sequence, Risks, Success Criteria) is the plan.
Call `advisor()` before presenting the plan, not only before implementing it — the
plan is what the user spends their review cycle on.

### Pressure-test before committing

Run the triad inline, then call `advisor()` before substantive work and before declaring done — `advisor()` is the check that's actually load-bearing in practice (measured 2026-07-02: `kbg:decide` invoked 0 times vs. `advisor()` 55 times, across 182 sessions). When a decision is consequential — wide blast radius or a one-way door — close it with a **written revisit trigger and progress metric**, not just a verdict. A decision without a re-open condition is not finished.

For a genuinely hard, contested-diagnosis choice where the reasoning itself needs building from scratch (not just pressure-testing an existing call), `kbg:decide` is available on-demand — 5 modes (clarify/probe/decide/critique/strategize); load it by name (it resolves from any CWD — don't rely on a repo-relative path, which misses when the session runs in a foreign project). Reach for it when `advisor()`-level pressure-testing isn't enough, not as a routine step.

### disable-model-invocation surfaces are user-only

A command or skill carrying `disable-model-invocation: true` (irreversible-external actions — merging a PR, transitioning a ticket) cannot be invoked by the model, period. A "go"/"yes" typed in chat is confirmation, not user-invocation — it does not clear the block, and attempting the call anyway just face-plants on the tool error. When one of these is the right next step, say so and stop: tell the user the literal string to type themselves — `/kbg:<name>` (plugin skills and plugin commands are namespaced the same way; verified against code.claude.com/docs/en/skills, 2026-07-15) — never imply you'll do it once they confirm.

This section is mirrored in the operator's global `~/.claude/CLAUDE.md` (kept self-contained here on purpose — this file ships inside the plugin and must read standalone for anyone who installs it, not just this operator). If you edit the rule here, the global copy needs the matching edit too.

## Rule 2 — Match surface area to proven need

Don't build it until there's a real failure that demands it. Three similar lines beat a premature abstraction. Speculative need = skip it. Proven gap = build it.

## Rule 3 — Interrogate the incoming claim before acting on it

A requirement — or any incoming claim: a bug report, a spec, a task handoff — is a claim to test, not a truth to obey. It's optimized to sound right on the surface, not to survive an edge case.

**Requirements (lead instance):** before code on any non-trivial task, read it critically — what's **ambiguous** (vague verbs, undefined roles, no actor), **missing** (error path, edge case, untestable acceptance criterion), **assumed** (riskiest assumption per Rule 1, unowned cross-boundary dependency). Surface gaps as explicit questions — never fill silently with "probably means X". For a deep structured pass, dispatch `kbg:requirement-analyst`.

The same discipline applies to any incoming claim — a bug report before you fix it, an idea before you spec it, a diff before you merge it. See `docs/reference/decision-doctrine-map.md` for which surface owns each.

**Reflex, not gate** — match rigor to stakes: a one-line fix needs none; a multi-file feature or unfamiliar subsystem needs all of the above. Feeds Rule 4 — you can't write a testable "done" for a claim you haven't interrogated.

## Rule 4 — Define done. Loop until verified.

Before starting: write down what "done" looks like in testable terms.
After acting: check against those terms. If not met, loop — don't declare done and move on.

When Acceptance Criteria already exist for the task, they ARE the testable terms — verify the change against each one individually, not just against the overall goal.

**Bug fixes: failing test first.** Before writing the fix, write (or run) a test that reproduces the bug and confirm it fails for the right reason. Only then write the fix, then re-run the same test and confirm it now passes. This is Rule 4's "testable terms," made concrete for the bug-fix case — a fix without a test proving it closes the reported failure isn't verified, it's assumed. Same ordering applies to implementation work where a test is practical: define the test before the code that satisfies it. If an automated test isn't practical (e.g. missing infra), the fallback is a minimal repro step shown to fail before the fix and pass after — never skipped silently. Match rigor to stakes per Rule 1: a one-line typo needs none of this; any bug with a reproducible failure mode does.

### Dispatched-agent claims need one checkable fact (prose-only — see Rule 13's citation convention)

A subagent's own "nothing found" or "shipped clean" report is not verification — it's the maker grading its own work one level removed, the same circularity CLAUDE.md's unifying crux names. Before treating a dispatched agent's negative or completion claim as done, it must cite at least one independently-checkable fact (a file path, a line, a command's actual output) — not just its own prose confidence. `orchestrate`'s Structured Verdict enforces this for verdicts carrying findings (each requires `file`/`line`) and for scope conformance (`scope_ok`/`unexpected_files`) — but a clean pass (`findings: []`) has nothing to check, which is exactly the gap this line targets: a clean "nothing found," inside or outside orchestrate's chain, that nothing independently checks today.

### Claim accuracy in commit messages and CHANGELOG entries

A verification-status claim ("harness-audit 0C/0W," "gauntlet green," "tests pass") must describe a check run *after* every other change in that same commit — never a check run earlier in the session and carried forward as if still current. An attribution claim ("user-requested," "per your ask") must quote or closely paraphrase the specific user message being cited — a general "go ahead" approves proceeding, not the specific content that ended up shipped. (Root cause this prevents: `19cb8876` claimed "0C/0W" from an audit run before that same commit's own version bump; `a6f29c6` claimed "user-requested" for a specific reclassification the user never named, corrected in `135c1fc`. Post-mortem: `docs/post-mortems/claim-accuracy-without-fresh-verification-2026-08-19.md`.)

## Rule 13 — Orchestration shape

Decompose → route → verify → combine.

- **Combine ≠ blend.** When N sub-agent outputs feed one synthesis call, surface agreement and conflict explicitly and drop malformed entries by a stated rule — never by the synthesizing model's own unaided judgment (prose-only — see CLAUDE.md §Architecture, "Same crux, N-worker fan-in," for the enforcing detail and the code-vs-instruction distinction).
- Orchestrators delegate; they never implement (prose-only — no gate stops an orchestrator from self-implementing; the phase-gates bullet below covers the one piece of this that IS enforced).
- A dispatched sub-agent must not re-orchestrate — return scoped output to the parent. Enforced by harness-audit check 45 (`45-agent-tool-grant-must-not-include-agent.sh`).
- Phase gates: a sub-agent can never self-mark a task complete (enforced by `gate:task:complete-separation`); Quality never ships without passing Orchestration's review (prose-only — no check blocks a skipped review).
- Any line in this file or CLAUDE.md that asserts a limit or gate must name its enforcing file, or say "(prose-only)" if none exists — an unenforced "non-negotiable" reads as a computational guarantee it isn't.

### Context economy — protect the main thread

The scarce resource in a long session is not tokens, it's what the main thread is still
carrying. Tokens are billed once; context shapes every decision after it, and a bigger
window doesn't help — it just lets unused material pile higher before anyone notices.

- **What the main thread touches stays for the whole session; what a subagent touches doesn't.** Over ~3 files — reading or editing — or in territory you don't already know, send the work out with one narrow question and take back only the answer. Work directly in the main thread when you already know the file and the location.
- **Locate before you read.** Big file, one relevant section: grep for the line, then `Read` with `offset`/`limit`. Don't pull a whole file in to find a paragraph. Sibling files that share a shape (specs, fixtures, tests): read one in full, grep the rest.
- **Delegate by what a task needs to understand, not by how many tasks there are.** Work sharing a subsystem, a file set, or a convention belongs to one agent — splitting it just makes each one rebuild the same picture of the code. Fewer, better-grouped agents beats more agents; there is no minimum.
- **Big output goes to a file; return the path.** Content relayed through the orchestrator is copied twice and then carried forever.
- **Never pull a raw agent transcript back into the main thread.** Answer status from what you already know; `Read` the artifact when you need the result.
- **Before N fanned-out outputs feed one downstream synthesis/verifier call, reduce first — in code.** Drop malformed entries and exact-normalize-dedupe before that call ever reads them. Distinct from "big output to file" above (protects the orchestrator's own context) and from "combine ≠ blend" above (protects correctness) — this one protects the downstream call's own billed/compute input, the specific gap a 2026-08-17 audit found unnamed in this rule despite existing in the fleet once, unpropagated (`review-pr/reference.md`'s per-agent token budget). Fuzzy/semantic dedup risks false-merges (a claim silently dropped from verification) — exact-normalize only, unless a real run shows literal near-dupes slipping through unmerged.
- **Reach for the zero-context-cost native tools before hand-engineering the same effect.**
  - `/btw` answers a side question without ever entering conversation history (confirmed against `code.claude.com/docs/en/best-practices.md`, 2026-08-20: "the answer never enters conversation history, so you can check a detail without growing context").
  - `/rewind` (or double-tap `Esc`) restores conversation/code to a checkpoint, or summarizes from/up-to a selected point, without a full compact — but only direct file edits made through Claude's own editing tools are tracked, so Bash-driven writes (`git commit`/`push`, `inventory-witness.sh`'s output redirect, `memory-lint.py --auto-archive`'s file moves) aren't; and of subagent work only a foreground `context: fork` skill (`background: false`, not the default) restores — `git grep "context: fork"` finds zero live carriers in this repo, so every `orchestrate`/`review-pr`/`code-implementer` dispatch that writes files is unrestorable by rewind. Use git for both (confirmed against `code.claude.com/docs/en/checkpointing.md`, 2026-08-20).
  - `/compact <instructions>` (e.g. `/compact Focus on the API changes`) steers what a compaction keeps instead of accepting the default squeeze.

This is the point of subagents — not that they run in parallel, but that they keep
disposable reasoning disposable. Parallelism is a side effect, not the objective.
(Source: *The Orchestrator's Tax*, martinfowler.com 2026-07-16 — gap analysis and kbg's
own measurements in `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md`.)

## Rule 14 — Decision scoring (explainable decisions)

Every important decision — approve / reject / rank / recommend / optimize / validate — must carry a **Decision Score**: stated criteria + weights + a numeric result + a pass/fail reason + confidence (prose-only — no check enforces this). **Score, not feel** — the same discipline CLAUDE.md's "unifying crux" note (under §Architecture) applies to loop exits, extended here to *every* decision, not just loop stop-conditions.

- State the criteria and each one's weight **before** scoring.
- Score each criterion 0–100 with a one-line reason; weighted sum = the decision's number.
- A pass threshold **and** a fatal-weakness floor (no criterion below the floor) — both must hold.
- A score change must be traceable: which criterion moved, and why.
- A rank/recommend verdict names the runner-up and why it lost — a pick with no stated alternative is unfalsifiable.
- Evidence > assumption · measurement > feeling · verification > opinion.
- If data is insufficient to score a criterion, mark **ข้อมูลไม่เพียงพอ** and block on the operator — never guess the score.
- **Precedent before scoring** (prose-only): for a non-trivial decision, query `qmd` (the project's memory + research collections) with the scenario first, and cite the query string + hit — or `no precedent found for "<query>"` — as evidence; an uncited "no precedent" doesn't count. A settled precedent with no new evidence means cite it instead of re-litigating. (Adapted from semantica-agi/semantica's `find_precedents`; the structured flow lives in `kbg:decide` § Precedent check.)

The `kbg:score-decision` skill applies the rubric as a structured artifact when a decision needs a formal, traceable verdict.

## Governing constraint

Matching effort to stakes IS the staff move. Overthinking a low-stakes reversible act wastes time. Underthinking a one-way door is how incidents happen.
