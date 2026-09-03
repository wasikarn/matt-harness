# Staff-Engineer Methodology

Compact rule set injected at session start. Rules sourced from the staff-engineer thinking loop doctrine.
Match rigor to stakes — minimal rules for low-stakes acts, full triad for one-way doors.

Rule numbers follow the source doctrine; only the load-bearing subset ships here, so the gaps are intentional. Rule 3 is kbg-native. Situation → scaffold → owning-rule map: `docs/reference/decision-doctrine-map.md`.

Only the every-turn core above the `core-end` HTML-comment marker is injected each session. The situational blocks below it stay in this file at full length; each core pointer names the section heading and the event that should trigger a `Read` of `$CLAUDE_PLUGIN_ROOT/docs/METHODOLOGY.md`.

## Rule 1 — Decision-sizing triad

Before any non-trivial act, run:

1. **One-way door?** If yes, stop and get explicit approval before proceeding.
2. **Blast radius?** Scope the damage if this goes wrong. If it's wide, narrow the change or checkpoint first.
3. **Riskiest assumption?** Name the thing most likely to invalidate the plan. Probe it before committing.

**Plan mode is the implementation checkpoint.** When the triad flags a one-way door or wide blast radius on a task that will edit code (multi-file, unfamiliar subsystem, ≥2 viable approaches, architectural), the "stop and get approval" step IS plan mode — suggest it strongly; enter it yourself only when the door is clearly one-way. Skip for trivial / mechanical changes. Full text: `Read` `$CLAUDE_PLUGIN_ROOT/docs/METHODOLOGY.md` section "Plan mode is the implementation checkpoint" before entering plan mode.

**Pressure-test before committing.** Run the triad inline, then call `advisor()` before substantive work and before declaring done. A consequential decision closes with a **written revisit trigger and progress metric**, not just a verdict. Full text (grilling escalation): section "Pressure-test before committing" — `Read` before committing to an approach.

**disable-model-invocation surfaces are user-only.** A typed "go"/"yes" never lifts `disable-model-invocation: true`; hand the user the literal `/mh:<name>` (or `/mattpocock-skills:<name>`) to type themselves and stop. Full text (wizard candidates): section "disable-model-invocation surfaces are user-only" before naming a disable-model-invocation skill.

## Rule 2 — Match surface area to proven need

Don't build it until there's a real failure that demands it. Three similar lines beat a premature abstraction. Speculative need = skip it. Proven gap = build it.

## Rule 3 — Interrogate the incoming claim before acting on it

A requirement — or any incoming claim: a bug report, a spec, a task handoff — is a claim to test, not a truth to obey. Before code on any non-trivial task, read it critically — what's **ambiguous**, **missing** (error path, edge case, untestable acceptance criterion), **assumed** (riskiest assumption per Rule 1). Surface gaps as explicit questions — never fill silently with "probably means X"; for a deep structured pass, dispatch `mh:requirement-analyst`. **Reflex, not gate** — a one-line fix needs none; a multi-file feature or unfamiliar subsystem needs all of it. Feeds Rule 4 — you can't write a testable "done" for a claim you haven't interrogated. Which surface owns each claim type: `docs/reference/decision-doctrine-map.md`. Full text (ambiguity sub-cues, cross-boundary dependency, idea/diff instances): section "Rule 3 — Requirements (lead instance)" in `$CLAUDE_PLUGIN_ROOT/docs/METHODOLOGY.md`, `Read` before scoping a requirement or reviewing a spec.

## Rule 4 — Define done. Loop until verified.

Before starting: write down what "done" looks like in testable terms; existing Acceptance Criteria ARE those terms — verify each individually. After acting: check against them. If not met, loop — don't declare done and move on. **Bug fixes: failing test first.** Same red/green discipline as `mattpocock-skills:tdd`; for a live bug (not a known one-line fix), dispatch `mattpocock-skills:diagnosing-bugs` rather than iterating inline. If an automated test isn't practical, show a minimal repro failing before the fix and passing after — never skipped silently. Match rigor to stakes per Rule 1.

Full text: sections "Dispatched-agent claims need one checkable fact" and "Claim accuracy in commit messages and CHANGELOG entries" — `Read` before writing a commit message or claiming a dispatched result.

## Rule 13 — Orchestration shape

Decompose → route → verify → combine.

- Orchestrators delegate; they never implement — enforced by `hooks/gates/main-exec-guard.sh` when `MH_MAIN_EXEC_GUARD=1` (off by default; ADR 0012).
  - **Main retains:** plan and design; dispatch (Agent tool, F9 spawn-prompt template); read code and files to decide what's next; verify a subagent's returned score/verdict, never redo the work; adjudicate conflicting results and merge; manage the task list (`TaskCreate`/`TaskUpdate`); ask the user a clarifying question before dispatching; write its own plan files, the memory store, and the session scratchpad.
- A dispatched sub-agent must not re-orchestrate — return scoped output to the parent. Enforced by harness-audit check 41.

### Context economy — protect the main thread

The scarce resource in a long session is not tokens, it's what the main thread is still carrying. Tokens are billed once; context shapes every decision after it.

- **What the main thread touches stays for the whole session; what a subagent touches doesn't.** Over ~3 files — reading or editing — or in territory you don't already know, send the work out with one narrow question and take back only the answer. A known-location one-line change still goes to a fixer agent. Main reads to decide, not to execute.
- **Locate before you read.** Big file, one relevant section: grep for the line, then `Read` with `offset`/`limit`. Sibling files that share a shape: read one in full, grep the rest.
- **Delegate by what a task needs to understand, not by how many tasks there are.** Work sharing a subsystem, file set, or convention belongs to one agent. Fewer, better-grouped agents beats more agents; there is no minimum.
- **Big output goes to a file; return the path.** Content relayed through the orchestrator is copied twice and then carried forever.
- **Never pull a raw agent transcript back into the main thread.** `Read` the artifact when you need the result.
- **Before N fanned-out outputs feed one downstream synthesis/verifier call, reduce first — in code.** Drop malformed entries and exact-normalize-dedupe; fuzzy dedup can silently drop a claim from verification.

Full text (combine ≠ blend, under-delegation accelerator, phase gates, enforcing-file rule, the zero-context-cost native tools `/btw` `/rewind` `/compact` `/mattpocock-skills:handoff`): section "Rule 13 — Orchestration shape (remaining bullets)" — `Read` before choosing a native tool over a subagent, combining N fanned-out results, or asserting a limit/gate in doctrine text.

## Rule 14 — Decision scoring (explainable decisions)

Every important decision — approve / reject / rank / recommend / optimize / validate — must carry a **Decision Score**: stated criteria + weights + a numeric result + a pass/fail reason + confidence (prose-only — no check enforces this). **Score, not feel.**

**What counts as important:** a decision Rule 1 flags (one-way door or wide blast radius), or one the user explicitly asked to be ranked, recommended, or compared. Everything else is routine and follows the terse default in `output-styles/crisp.md` — a one-line answer with the reason, no score.

If data is insufficient to score a criterion, mark **ข้อมูลไม่เพียงพอ** and block on the operator — never guess the score. Full text (scoring bullets, precedent-before-scoring, `mh:score-decision`): section "Rule 14 — Decision scoring (scoring procedure)" — `Read` before scoring an important decision (per the bar above; approve/reject/validate/rank).

## Governing constraint

Matching effort to stakes IS the staff move. Overthinking a low-stakes reversible act wastes time. Underthinking a one-way door is how incidents happen.

<!-- core-end -->

# Situational rules — full text

Not injected at session start. Each block keeps its original heading so citations by section name still resolve.

### Plan mode is the implementation checkpoint

When the triad flags a **one-way door** or **wide blast radius** on a task that
will *edit code* — multi-file, an unfamiliar subsystem, ≥2 viable approaches, or
architectural — the "stop and get approval" step IS plan mode: enter it (Shift+Tab,
or the `EnterPlanMode` tool) and present a plan before editing. **Default to
suggesting it strongly** — the user keeps control (they Shift+Tab or approve the
plan); enter it yourself only when the door is clearly one-way or the user signals
they're unsure of the approach. Skip entirely for trivial / known-small-fix /
mechanical changes (rename, typo, doc tweak).

Once inside plan mode, the analysis is the deliverable: read the files the task
touches and trace the actual flow before drafting, and call `advisor()` before
presenting the plan, not only before implementing it. Which surface owns the
blueprint (`mh:code-architect` and its narrower matt-skill neighbours):
`docs/reference/decision-doctrine-map.md`, "Task/requirement → plan authoring".

### Pressure-test before committing

Run the triad inline, then call `advisor()` before substantive work and before declaring done. When a decision is consequential — wide blast radius or a one-way door — close it with a **written revisit trigger and progress metric**, not just a verdict. A decision without a re-open condition is not finished.

For a genuinely hard or contested call where `advisor()`-level pressure-testing isn't enough, escalate to `mattpocock-skills:grilling` — relentless adversarial stress-testing of the plan, decision, or diagnosis. On-demand, not a routine step.

### disable-model-invocation surfaces are user-only

A command or skill carrying `disable-model-invocation: true` cannot be invoked by the model — irreversible-external actions and timing-gated read-only ones alike. A "go"/"yes" typed in chat is confirmation, not user-invocation. When one is the right next step, tell the user the literal string to type themselves (`/mh:<name>`, or `/mattpocock-skills:<name>` for a DMI-gated matt skill) and stop.

A human-only multi-step procedure that would otherwise require the user to type out each step by hand is a candidate for `mattpocock-skills:wizard`, which generates the walkthrough instead.

Full rule with sourcing: the operator's global `~/.claude/CLAUDE.md`, "Disable-Model-Invocation Surfaces" — that copy loads in every project; this one ships with the plugin. Edit both together.

### Rule 3 — Requirements (lead instance)

Before code on any non-trivial task, read the requirement critically — what's **ambiguous** (vague verbs, undefined roles, no actor), **missing** (error path, edge case, untestable acceptance criterion), **assumed** (riskiest assumption per Rule 1, unowned cross-boundary dependency). The same discipline applies to any incoming claim — a bug report before you fix it, an idea before you spec it, a diff before you merge it.

### Dispatched-agent claims need one checkable fact (prose-only — see Rule 13's citation convention)

A subagent's own "nothing found" or "shipped clean" report is not verification — it's the maker grading its own work one level removed, the same circularity `docs/reference/operating-model.md`'s "unifying crux" note names. Before treating a dispatched agent's negative or completion claim as done, it must cite at least one independently-checkable fact (a file path, a line, a command's actual output) — not just its own prose confidence. `orchestrate`'s Structured Verdict enforces this for verdicts carrying findings and for scope conformance (`scope_ok` / `unexpected_files`); a clean `findings: []` is the gap this line targets.

### Claim accuracy in commit messages and CHANGELOG entries

A verification-status claim ("harness-audit 0C/0W," "gauntlet green," "tests pass") must describe a check run *after* every other change in that same commit — never a check run earlier in the session and carried forward as if still current. An attribution claim ("user-requested," "per your ask") must quote or closely paraphrase the specific user message being cited — a general "go ahead" approves proceeding, not the specific content that ended up shipped.

### Rule 13 — Orchestration shape (remaining bullets)

- **Combine ≠ blend.** When N sub-agent outputs feed one synthesis call, surface agreement and conflict explicitly and drop malformed entries by a stated rule — never by the synthesizing model's own unaided judgment (prose-only — see `docs/reference/operating-model.md`, "Same crux, N-worker fan-in," for the enforcing detail and the code-vs-instruction distinction).
- Orchestrators delegate; they never implement — enforced by `hooks/gates/main-exec-guard.sh` when `MH_MAIN_EXEC_GUARD=1` (denies the top-level session's Write/Edit/MultiEdit/NotebookEdit and mutating Bash; plan, memory, and scratchpad paths are exempt; off by default, `log` counts without denying). Decision record: ADR 0012 (`docs/research/adr-0012-main-plans-dispatches-never-executes.md`).
- **Under-delegation has one accelerator:** `hooks/advisory/flow-nudge.sh` fires on prompts naming >~3 files and points at the F9 spawn-prompt template; the fan-out cap and `agent-recursion-guard.sh` are the brakes. Whether the model acts on the nudge is prose-only.
- A dispatched sub-agent must not re-orchestrate — return scoped output to the parent. Enforced by harness-audit check 41 (`41-agent-tool-grant-must-not-include-agent.sh`).
- Phase gates: a sub-agent can never self-mark a task complete (enforced by `gate:task:complete-separation`); Quality never ships without passing Orchestration's review (prose-only — no check blocks a skipped review).
- Any line in this file or CLAUDE.md that asserts a limit or gate must name its enforcing file, or say "(prose-only)" if none exists — an unenforced "non-negotiable" reads as a computational guarantee it isn't.
- **Reach for the zero-context-cost native tools before hand-engineering the same effect.**
  - `/btw` answers a side question without ever entering conversation history.
  - `/rewind` (or double-tap `Esc`) restores conversation/code to a checkpoint, or summarizes from/up-to a selected point, without a full compact — but only edits made through Claude's own editing tools are tracked: Bash-driven writes and subagent work aren't (only a foreground `context: fork` skill restores). Use git for those.
  - `/compact <instructions>` (e.g. `/compact Focus on the API changes`) steers what a compaction keeps instead of accepting the default squeeze.
  - Ending a session mid-thread on unfinished work → `/mattpocock-skills:handoff` writes resumable state, so the next session (or `mh:learn`) doesn't start from zero.

This is the point of subagents — not that they run in parallel, but that they keep
disposable reasoning disposable. Parallelism is a side effect, not the objective.
(Source: *The Orchestrator's Tax*, martinfowler.com 2026-07-16; `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md`.)

### Rule 14 — Decision scoring (scoring procedure)

**Score, not feel** — the same discipline `docs/reference/operating-model.md`'s "unifying crux" note applies to loop exits, extended here to *every* decision, not just loop stop-conditions.

- State the criteria and each one's weight **before** scoring.
- Score each criterion 0–100 with a one-line reason; weighted sum = the decision's number.
- A pass threshold **and** a fatal-weakness floor (no criterion below the floor) — both must hold.
- A score change must be traceable: which criterion moved, and why.
- A rank/recommend verdict names the runner-up and why it lost — a pick with no stated alternative is unfalsifiable.
- Evidence > assumption · measurement > feeling · verification > opinion.
- If data is insufficient to score a criterion, mark **ข้อมูลไม่เพียงพอ** and block on the operator — never guess the score.
- **Precedent before scoring** (prose-only): for a non-trivial decision, query `qmd` (the project's memory + research collections) with the scenario first, and cite the query string + hit — or `no precedent found for "<query>"` — as evidence; an uncited "no precedent" doesn't count. A settled precedent with no new evidence means cite it instead of re-litigating.

The `mh:score-decision` skill applies the rubric as a structured artifact when a decision needs a formal, traceable verdict.
