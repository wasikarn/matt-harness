# Delegation criteria — field survey and outside lenses (2026-09-04)

**Date:** 2026-09-04
**Sources:** in-repo prior art (Step 1), 12 vendor/practitioner primary sources (Step 2), 9 outside-field lenses (Step 2b). Every external claim carries a URL and the section it came from; a source that could not be fetched is marked **not fetched** and its claim is downgraded to secondary or dropped. Full list at the end.
**Scope:** analysis + recommendations only. No surface was edited. Written while `skills/workflow/orchestrate/**` and `hooks/stop/cost-tracker.sh` were under concurrent edit by another agent — citations into those files are as of the working tree read on 2026-09-04.

---

## TL;DR

1. Every vendor (Anthropic ×3, OpenAI, LangChain, Google) says the same first thing: **single agent first; split only on evidence.** mh already inverted the default for the *main thread* (ADR 0012) — defensible only because mh's "single agent" is the *worker*, not main. Keep it, but name the boundary.
2. The field's split criteria reduce to three inputs, in order of weight: **(a) does the subtask's context pollute later work, (b) is there real independent bulk to hand off, (c) does the task need a tool/persona set a single agent can't hold.** Task *count* is never a criterion. mh has (a) and (c); (b) is only implicit.
3. Anthropic's 2026 cost measurements (`optimizing-for-cost-and-intelligence`) are the sharpest new evidence: delegation pays on **routine, normally-solvable work (tail insurance: ~half the cost, a third at p90)** and on **work larger than one context window**, and *loses* on one dependent chain that fits in a context (solo at lower effort 22–30% cheaper at equal accuracy). Rule 14's routine-vs-important boundary is the right axis, pointed the right way.
4. The handoff itself is a transaction with three costs — brief authoring, verification, and re-integration (Coase/Williamson; Jensen-Meckling's monitoring + residual loss). mh prices the first two (F9, validation chain) and not the third: nothing measures what main re-reads after a return.
5. The structured-handoff literature (I-PASS, NEJM 2014: −23% errors, −30% preventable adverse events with a fixed handoff template) is the strongest external evidence for F9's slot discipline; F9 lacks I-PASS's last field — **receiver synthesis (read-back)** — and mission command's **"intent two levels down"**.
6. The 5-cap is a **WIP limit**, not a parallelism target; Little's law says the right number derives from main's verification throughput, which is unmeasured. Keep 5, add the measurement, don't relitigate the number.
7. Cognition's objection (decisions carry implicit context; parallel writers conflict) is already mh doctrine for *writers* (FILES YOU OWN, Step 0 grouping); it does not apply to read-only/verifier fan-out, which is where mh should keep fanning out.
8. Top 3 changes: (i) measure the third handoff cost (main's post-return re-reads) in `cost-tracker.sh`; (ii) add a **read-back slot** to F9 (`## Brief-back`); (iii) write the **route rubric below into `routing.md`** as Step 0.5 with Solver and Advisor as named routes. All three are doctrine-neutral with ADR 0012, Rule 14, and the 5-cap.

---

## Step 1 — What this harness already says (≤15 lines)

1. **Main never executes** — ADR 0012 (`docs/research/adr-0012-main-plans-dispatches-never-executes.md:87-91`): plans, dispatches, verifies, decides; gate `hooks/gates/main-exec-guard.sh` (opt-in `MH_MAIN_EXEC_GUARD=1`, on in the operator's shell). Steelman-against retained (`:61-85`): CC sub-agents doc's 4 inline conditions, Anthropic's 15×/80% figures, superpowers #1120's 10–15× on a 5-line file, Cognition.
2. **Rule 13 "Main retains"** (`docs/METHODOLOGY.md:94`): plan/design, dispatch, read-to-decide, verify a returned score, adjudicate/merge, task list, ask user, own plan/memory/scratch files.
3. **Context economy** (`METHODOLOGY.md:100-121`): >~3 files or unknown territory → out; locate-before-read; group by mental model not by count; big output to file; never pull a transcript; reduce-in-code before fan-in. "Parallelism is a side effect, not the objective."
4. **Rule 14** (`METHODOLOGY.md:123-138`, commit 79604975): important = Rule-1-flagged or user-asked rank/recommend; everything else routine and terse. Precedent-before-scoring via qmd.
5. **Orchestrate routing** (`skills/workflow/orchestrate/SKILL.md:19-38`): Gather → Prioritize → Route (single/parallel/sequential/drop) → AskUserQuestion on any write-capable dispatch → verify against done-when → combine.
6. **Step 0 grouping** (`SKILL.md:99-107`): merge items sharing subsystem/file-set/conventions before scoring; overlapping FILES YOU OWN = consolidation signal.
7. **Fan-out** (`SKILL.md:52-64`): hard cap 5/wave, no floor, "prefer 2-4"; lead is the clamp; floor of 3 removed 2026-08-07.
8. **Single-agent fast path** (`SKILL.md:86-95`): 1 file, 1 behavior, <30 lines, deterministic check, not auth → one haiku fixer.
9. **F9 template** (`orchestrate/f9-template.md:16-81`): Task + `[role:]`, What/Why/Where/Focus/Deliverable/Skills, FILES YOU OWN, UPSTREAM CONTRACTS + basis hash (`STALE-BASIS`), Files+Criteria+Constraints, Constraints-always (`NEEDS-DECISION`), Done-when + Deadline. No fork for F9 dispatches; Explore for read-only (`:85-87`).
10. **Validation chain** (`orchestrate/validation-chain.md:13-46`): Builder → Validator → Fixer → Re-validator; chain when ≥2 files or ≥1 test; Re-validator skipped when no Fixer and same lens; fix-retry cap 3; JSON verdict fail-closed; `gate:task:complete-separation` makes completion main's call.
11. **Advisory accelerator** (`hooks/advisory/flow-nudge.sh`): fires on >~3 files; reports orchestrator:subagent token ratio; ~22.6% follow-through (ADR 0012 `:57-59`).
12. **Cost profile** (`docs/research/orchestrate-cost-optimization-2026-09-03.md:45-60`): main rent 234K cache-read tok/turn, $9,002 vs $4,633 subagent; fork 205K vs general-purpose 100K vs Explore 67K tok/turn; role tag shipped since as candidate #10.
13. **2026-09-01 5-agent verdict** (memory `user-delegation-preference-main-never-executes-2026-09-01.md`): no framework enforces a zero-execution orchestrator; user chose enforcement over policy flip; ADR 0012 then superseded the 9-clause checklist.
14. **Orchestrator's Tax** (`orchestrator-tax-gap-analysis-2026-08-07.md`): scarce resource is main's working memory; F1 removed the floor; F2 built the measurement; "group before you count."
15. Net: mh has a *who* rule (gate), a *shape* rule (F9 + chain), a *ceiling* (cap 5), and a *nudge* — but the **route decision itself** is prose spread over four files with no single input list.

---

## Step 2 — External primary sources

### Anthropic — "Building effective agents" (fetched)
`anthropic.com/engineering/building-effective-agents`. "We recommend finding the simplest solution possible, and only increasing complexity when needed." Routing: "distinct categories that are better handled separately, and where classification can be handled accurately." Parallelization: "sectioning … voting … effective when the divided subtasks can be parallelized for speed, or when multiple perspectives or attempts are needed." Orchestrator-workers: "complex tasks where you can't predict the subtasks needed." **Criterion:** fan-out is for *unpredictable decomposition* or *diverse-lens confidence*; routing is for *classifiable categories*.

### Anthropic — "How we built our multi-agent research system" (fetched)
`anthropic.com/engineering/multi-agent-research-system`. Agents ≈4× chat tokens, multi-agent ≈15×; "token usage by itself explains 80% of the variance." Scale rule: "Simple fact-finding requires just 1 agent with 3-10 tool calls, direct comparisons might need 2-4 subagents with 10-15 calls each, and complex research might use more than 10 subagents." Brief: "an objective, an output format, guidance on the tools and sources to use, and clear task boundaries." Failure modes: "spawning 50 subagents for simple queries", "performed the exact same searches", vague instructions. Not a fit: "domains that require all agents to share the same context or involve many dependencies"; "most coding tasks involve fewer truly parallelizable tasks than research." **Criterion:** effort scales with a *complexity tier*, stated as numbers; the brief has four required parts (F9 has all four).

### Anthropic — "When to use multi-agent systems (and when not to)" (fetched)
`claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them`. Three justifications: context protection ("subtasks generate >1000 tokens … mostly irrelevant to downstream work"), parallelization, specialization ("20+ tools, spanning unrelated domains, or requiring conflicting behavioral modes"). Cost "3-10x more tokens". "Work should only be split when context can be truly isolated … Sequential phases of the same work belong together." "Start with the simplest approach that works." **Criterion:** the split test is *context isolation*, with a stated token threshold.

### Anthropic — "Optimizing for cost and intelligence" (fetched, 2026)
`platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence`, §Orchestrator strategy. "An orchestrator buys something only when there is bulk to hand off: many independent pieces, ideally too many for one context window." "On work a single model could handle alone, the same model at lower effort was cheaper every time." Case 1 (tail insurance): coordinator + one Sonnet 5 worker "cost about half as much … and about a third as much at the 90th percentile ($12 compared with $33)"; "Delegation paid on the routine, normally solvable share of the work, the opposite of the intuition that workers are for hard problems." Case 2: 21.6M-token corpus, "coordinator … cost about 47% to 55% less … and scored 10 to 12 points below." Boundary: "Claude Fable 5 alone reached the coordinator configuration's accuracy at 22% to 30% lower cost" on hard BrowseComp. **Criterion:** delegate *routine* and *oversized*; keep *one hard dependent chain* in one context. External evidence base for Rule 14's boundary.

### Anthropic — Managed Agents multiagent orchestration (fetched)
`platform.claude.com/docs/en/managed-agents/multiagent-orchestration`, §What to delegate. "Best suited for complex tasks that either require work across a variety of surfaces, or where multiple well-scoped tasks contribute to an overall goal." Patterns: parallelization, specialization, escalation ("consult a more capable agent … for a subset"). Threads persistent; "Tools, MCP servers, and context are not shared." **Criterion:** escalation is a third route (advisor) — mh has it only as `advisor()` in Rule 1, not in orchestrate's routing table.

### Claude Code sub-agents docs (fetched)
`code.claude.com/docs/en/sub-agents`. Main-conversation conditions: "frequent back-and-forth or iterative refinement", "multiple phases share significant context", "a quick, targeted change", "latency matters". Subagent conditions: "verbose output you don't need", "enforce specific tool restrictions", "self-contained and can return a summary". Fork "inherits the entire conversation"; fresh context = agent prompt + task message + CLAUDE.md hierarchy + git status + preloaded skills + sibling roster (Explore/Plan skip CLAUDE.md and git status). 15,000-token description warning. Nesting up to 3 layers (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`). Resumable via `SendMessage`. **Criterion:** the four inline conditions are the field's canonical "worse-than-main" list; ADR 0012 knowingly overrides them for main and routes them to a single worker.

### Claude Code costs docs (fetched)
`code.claude.com/docs/en/costs`. "Use Sonnet for teammates"; "Keep teams small … token usage is roughly proportional to team size"; "Keep spawn prompts focused … everything in the spawn prompt adds to their context from the start"; "For simple subagent tasks, specify `model: haiku`"; agent teams "approximately 7x more tokens" in plan mode; long sessions re-read history at cache-read rate every turn. **Criterion:** spawn-prompt size is itself a cost lever.

### Claude prompting best practices (fetched; saved locally, not grepped — Bash gate mid-edit)
`platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices`. Not cited further.

### OpenAI — Agents SDK: handoffs vs agents-as-tools (fetched)
`openai.github.io/openai-agents-python/handoffs/` and `/multi_agent/`. Agents-as-tools: "a specialist should help with a bounded subtask but should not take over the user-facing conversation." Handoffs: "routing itself is part of the workflow and you want the chosen specialist to own the remainder of the current turn"; the new agent "gets to see the entire previous conversation history" (input filters trim it). Orchestrating via code is "more deterministic and predictable, in terms of speed, cost and performance." **Criterion:** two mechanisms — *call-and-return* (fresh context, summary back) vs *transfer-of-control* (shared history). mh's Agent tool is the first; the second isn't needed (main is the only user-facing party).

### OpenAI — "A practical guide to building agents" (HTML 403; PDF binary; quotes via Firecrawl snippets of the HTML page)
§Orchestration. "Our general recommendation is to maximize a single agent's capabilities first." "A single agent can handle many tasks by incrementally adding tools." Manager pattern: "a central LLM … orchestrate[s] a network of specialized agents seamlessly through tool calls … ideal for workflows where you only want one agent to control workflow execution and have access to the user." Decentralized: "edges represent handoffs that transfer execution between agents." The widely quoted "10-15 well-defined tools" threshold was **not verified in fetched text** — unconfirmed. **Criterion:** manager pattern is the mh shape; the split trigger is tool/logic overload, not task count.

### LangChain multi-agent (`docs.langchain.com/oss/python/langchain/multi-agent` fetched; LangGraph concepts page redirect loop)
Reasons: "specialized knowledge without overwhelming the model's context window", independent development, concurrent specialized workers. Subagents cost "four model calls for simple tasks" vs handoffs "two calls" but sequential. "Not every complex task requires this approach—a single agent with the right (sometimes dynamic) tools and prompt can often achieve similar results." **Criterion:** a supervisor round-trip has a fixed 2-call overhead on top of the worker's calls — the floor of the handoff tax.

### Google ADK (`adk.dev/workflows/` fetched, thin; multi-agents page redirected twice)
Sequential / Loop / Parallel workflow agents "provide fixed execution logic structures"; benefits: predictability, reliability, "separating responsibilities and limiting data contexts." `transfer_to_agent` and AgentTool-vs-sub_agents were **not in the fetched page** — not cited.

### Cognition — "Don't build multi-agents" (fetched)
`cognition.com/blog/dont-build-multi-agents`. Principle 1: "Share context, and share full agent traces, not just individual messages." Principle 2: "Actions carry implicit decisions, and conflicting decisions carry bad results." Flappy Bird example. "The simplest way to follow the principles is to just use a single-threaded linear agent." Long tasks → a model that "compress[es] a history of actions & conversation into key details, events, and decisions." Claude Code subagents answer questions only because "the subtask agent lacks context from the main agent." "Running multiple agents in collaboration only results in fragile systems." **Criterion:** parallel *writers* need shared decisions; parallel *readers/verifiers* don't. No formal rebuttal fetched; Anthropic's research post is the de-facto counterpoint and concedes the coding case.

### Staff-engineer literature
- Larson, *Work on what matters* (`staffeng.com/guides/work-on-what-matters/`, `lethain.com/work-on-what-matters/`, fetched): avoid "snacking", "preening", "chasing ghosts"; swarm "existential issues"; the last category is what "simply won't happen if you don't do them." **Criterion:** main's own hands go only to existential/unique work; snacking is the failure ADR 0012 measured.
- Larson, *Staff archetypes* (fetched): Tech Lead "default[s] to delegating such projects across the team"; Solver "go[es] deep into knotty problems … until they're resolved"; Right Hand "edit[s] the approach, delegate[s] execution … pop[s] over to the next fire." **Criterion:** the *Solver* is the field's named exception — one hard, contained, dependent problem. Matches Anthropic's "one hard dependent chain."
- Marquet, ladder of leadership (**primary sites 404; secondary** `blog.mikebowler.ca/2024/04/25/ladder-of-leadership/`): "Tell me what to do" → "I think" → "I recommend" → "I would like to" → "I intend to" → "I've done" → "I've been doing"; at "I intend to" the leader "retain[s] veto power." **Criterion:** F9's `NEEDS-DECISION` is rung 1; a worker acting inside FILES YOU OWN is rung 5; the AskUserQuestion gate is the veto.
- Eisenhower (1954 address, `presidency.ucsb.edu`, fetched): "I have two kinds of problems, the urgent and the important. The urgent are not important, and the important are never urgent." **Criterion:** already the first matrix in `routing.md`; the source says nothing about *delegating* the routine — Rule 14 stands on the Anthropic cost data instead.
- Fournier, *The Manager's Path*: **not fetched** (book only) — not cited.

---

## Step 2b — Outside lenses

### 1. Transaction-cost economics — Coase 1937, Williamson
Coase (`onlinelibrary.wiley.com/doi/full/10.1111/j.1468-0335.1937.tb00002.x`, §II–III, via search highlights): "there is a cost of using the price mechanism … discovering what the relevant prices are"; "a firm will tend to expand until the costs of organising an extra transaction within the firm become equal to the costs of carrying out the same transaction by means of an exchange on the open market"; "as a firm gets larger, there may be decreasing returns to the entrepreneur function." Williamson (Nobel lecture PDF 403; via Aguinis AMP 2013 review and Cambridge JIE commemoration): costs rise with **asset specificity, uncertainty (esp. *behavioral* — "unable to evaluate the quality of activities"), frequency**; bounded rationality + opportunism. Mapping: main is the firm, a dispatch is a market transaction, the F9 brief is the contract, verification is monitoring. "Decreasing returns to the entrepreneur" is the Orchestrator's Tax. Behavioral uncertainty is the biggest driver toward hierarchy (~2× asset specificity in the meta-analysis): the less verifiable an output, the stronger the case for keeping it close.
**Criterion:** route by *verifiability*: deterministic-checkable → worker; judgment-only → validator with a scored rubric or advisor. **mh coverage:** doctrine (fast-path condition 3; chain's JSON verdict) — no route input named "verifiability" in `routing.md`.

### 2. Principal-agent theory — Jensen & Meckling 1976
Primary 403; **definition via secondary** `open.ncl.ac.uk/theories/21/agency-theory/`: agency costs are "the sum of (i) monitoring expenditures by the principal, (ii) bonding expenditures by the agent, and (iii) the residual loss." Self-grading has zero monitoring cost and maximal residual loss. Bonding = the worker's `STALE-BASIS`/`NEEDS-DECISION` stops and the verdict contract.
**Criterion:** delegation cost = brief + monitoring + residual; where monitoring ≈ redoing the work (a 5-line diff), a dispatch buys only the gate — the fast path is the minimum-monitoring form. **mh coverage:** gate (`task-complete-separation`) + doctrine (chain); *monitoring cost is never priced*.

### 3. Mission command / Auftragstaktik — ADP 6-0 (2019)
Primary PDFs unreachable; **ADP 6-0 text quoted via** War Room (`warroom.armywarcollege.edu/articles/new-doctrine-mission-command/`) and Townsend et al., Military Review May–June 2019: "Mission command is the Army's approach to command and control that empowers subordinate decision making and decentralized execution appropriate to the situation." Principles: competence, mutual trust, shared understanding, commander's intent, mission orders, disciplined initiative, risk acceptance. Townsend: "applying the appropriate level of control so that … leaders make the best possible decision at the right level"; observed failure: "Communicating a clear commander's intent to subordinate units two levels down … is often not happening." F9's `## Why` = intent; `## Focus` = the trade-off dimension; `Constraints (always)` = control measures. Gaps: `Why` is *optional*; nothing carries the *user's* intent to a Wave-2 worker.
**Criterion:** a worker gets intent + constraints + end state, never steps; detailed control only where the act is irreversible. **mh coverage:** doctrine (F9 Why/Focus/Done-when); make `Why` required when Done-when is not fully deterministic.

### 4. Clinical handoff protocols — I-PASS (Starmer et al., NEJM 2014)
`nejm.org/doi/full/10.1056/NEJMsa1405556` (abstract via Firecrawl highlight; PubMed 25372088): "the medical-error rate decreased by 23% … (24.5 vs. 18.8 per 100 admissions, P<0.001), and the rate of preventable adverse events decreased by 30% (4.7 vs. 3.3 events per 100 admissions, P<0.001)" across nine hospitals, 10,740 admissions. I-PASS fields: Illness severity, Patient summary, Action list, Situation awareness/contingency, **Synthesis by receiver**. Against F9: severity ≈ Focus/blast radius; summary ≈ What/Where/UPSTREAM CONTRACTS; action list ≈ Files+Criteria + Done-when; contingency ≈ `NEEDS-DECISION`/`STALE-BASIS`/Deadline; **receiver synthesis has no F9 equivalent**.
**Criterion:** a structured template with a *read-back* step is the best-measured handoff intervention; the read-back is one line and is the part F9 lacks. **mh coverage:** doctrine (4 of 5 fields); read-back: **none**.

### 5. Queueing theory / Little's law / Kanban WIP limits
Little 1961 (INFORMS 403; **via** `en.wikipedia.org/wiki/Little%27s_law`): L = λW, "not influenced by the arrival process distribution, the service distribution, the service order, or practically anything else." Kanban WIP (llm-wiki `wiki/sources/agile/src-wip-limits.md`): set limits below observed WIP, keep In-Progress below team size; "raising limits to avoid hitting them" is the anti-pattern. Main is a single server whose service is *verifying returns*; with λ bounded by main's verification rate, more agents in flight only raise wait time and carried context. Amdahl: the serial fraction (brief + verify + merge) caps speedup regardless of N. The 5-cap is a **WIP limit on main's verification queue**; neither 5 nor 2-4 has been derived from a measured λ.
**Criterion:** wave size ≤ returns main can verify before the first goes stale; measure returns-per-turn and verification tokens per return before touching the cap. **mh coverage:** doctrine (cap 5, prefer 2-4); measurement: **none**.

### 6. Distributed systems — MapReduce stragglers, sagas
Dean & Ghemawat 2004 (`static.googleusercontent.com/…/mapreduce-osdi04.pdf`, fetched): §3.6 stragglers — "a job with 200 tasks … runs 44% longer without backup executions"; backup copies near completion, first finisher wins. §3.3 — failed workers' tasks re-executed; temp file + atomic rename makes re-execution "deterministic, idempotent". Sagas (Garcia-Molina & Salem 1987; ACM 403, PDFs unreadable — **via secondary**): a long-lived transaction as sub-transactions each with a compensating transaction. mh's Deadline is straggler *detection*; no backup-execution rule; a Builder dying mid-task leaves partial writes with no compensating step — FILES YOU OWN gives the scope, but main can't run the revert under the guard.
**Criterion:** every write-capable dispatch needs idempotent output, a named compensating action, and a straggler rule; speculative duplicates only for read-only work. **mh coverage:** doctrine (Deadline; FILES YOU OWN; basis hash); compensation: **none** named.

### 7. Brooks and Conway
Brooks (**via** `en.wikipedia.org/wiki/The_Mythical_Man-Month`): "Adding manpower to a late software project makes it later"; intercommunication n(n−1)/2; man-months interchangeable only when a task "can be partitioned among many workers with no communication among them"; the surgical team. Conway 1968 (`melconway.com/Home/Committees_Paper.html`, fetched): "organizations which design systems … are constrained to produce designs which are copies of the communication structures of these organizations"; "Every time a delegation is made and somebody's scope of inquiry is narrowed, the class of design alternatives which can be effectively pursued is also narrowed." mh's fan-out is a star (N channels, not N²) — the structural reason star + FILES YOU OWN survives Brooks. Conway's warning: the *shape of the split* decides the design; Step 0's group-by-mental-model is the mitigation. The surgical team is Larson's Solver.
**Criterion:** partition only where the seam is a real interface; a split that forces an unmade design decision is a `NEEDS-DECISION`, not a wave. **mh coverage:** doctrine (Step 0); star topology structural (check 41).

### 8. Aviation CRM — sterile cockpit (14 CFR 121.542)
`law.cornell.edu/cfr/text/14/121.542` (fetched): no duties "during a critical phase of flight except those duties required for the safe operation of the aircraft"; no "nonessential conversations within the cockpit"; critical phases = "taxi, takeoff and landing, and all other flight operations conducted below 10,000 feet, except cruise flight." Main's critical phases are *verify-and-merge* and the AskUserQuestion decision; status chatter and transcript reads are nonessential conversation.
**Criterion:** during verify/merge, no new dispatch and no transcript reads; batch returns. **mh coverage:** doctrine (`SKILL.md:37`, Rule 13); no hook — low stakes, keep as prose.

### 9. Cognitive load — Miller 1956 (Sweller 1988 not fetched)
Miller (`musanim.com/miller1956/`, fetched): "Absolute judgment is limited by the amount of information. Immediate memory is limited by the number of items"; recoding lets us "break (or at least stretch) this informational bottleneck … by building larger and larger chunks." Sweller 1988 — all hosts blocked — **not cited**. Main's context is the immediate-memory analogue; the item count that matters is *open threads*, not tokens; "big output to file, return the path" is recoding. The 5-cap sits inside 7±2 by coincidence, not derivation.
**Criterion:** count main's *open items* (in-flight agents + unresolved NEEDS-DECISIONs + unverified returns); keep it small; chunk returns into paths. **mh coverage:** doctrine (Rule 13); an open-item counter: **none**.

---

## Step 3 — Synthesis

### Comparison table

| Source | Self / one context | Delegate to one agent | Fan out | Handoff mechanism | Context strategy | Named failure modes |
|---|---|---|---|---|---|---|
| Anthropic, Building effective agents | default ("simplest solution possible") | routing: classifiable categories | sectioning / voting; orchestrator-workers when subtasks unpredictable | tool call, result returned | fresh per worker | complexity without need |
| Anthropic, multi-agent research | 1 agent, 3–10 calls for fact-finding | — | 2–4 for comparisons; >10 complex research | brief: objective, output format, tools, boundaries | fresh; lead saves plan to memory | 50 subagents for simple queries; duplicate searches; vague briefs |
| Anthropic, when-to-use-multi-agent | default; sequential phases stay together | context pollution >~1K tokens | parallel independent facets; 20+ tools | brief with explicit success criteria | split only when context isolatable | 3–10× tokens; shortcuts without concrete criteria |
| Anthropic, cost & intelligence (2026) | one dependent chain that fits; same model at lower effort | routine work → cheaper worker (½ mean, ⅓ p90) | bulk > one context (−47–55% cost, −10–12 pts) | coordinator threads, `submit_result` | isolated, persistent threads | orchestrator pays plan+handoff+merge a solo gets free |
| Claude Code sub-agents / costs | iterative; shared phases; quick change; latency | verbose output; tool restriction; self-contained summary | "keep teams small", Sonnet teammates | Agent tool; summary returns | fresh (+CLAUDE.md, git status) vs fork | 15K description budget; 7× in team plan mode |
| OpenAI guide + SDK | "maximize a single agent's capabilities first" | agent-as-tool: bounded subtask | manager (tool calls) vs decentralized (handoffs) | call-and-return vs transfer-of-control | fresh vs shared history | tool/logic overload |
| LangChain | single agent with right tools often enough | subagent = 4 calls; handoff = 2 | parallel specialized workers | supervisor tool-call / `Command` | shared messages or final-result-only | fixed round-trip overhead |
| Cognition | single-threaded linear agent | subagents answer questions only | avoid parallel writers | full trace sharing | shared; dedicated compressor | conflicting implicit decisions |
| Larson | existential, unique-to-you, Solver's problem | Tech Lead delegates by default | Right Hand delegates execution | scoping + unblocking | — | snacking, preening, chasing ghosts |
| Marquet | rung 1 (worker stops) | rung 5 "I intend to" with veto | — | intent + veto | — | leaders answering instead of asking |
| Coase / Williamson | organise internally until marginal cost = transaction | when brief+verify < carrying it | frequency spreads fixed cost | contract + monitoring | — | decreasing returns; behavioral uncertainty |
| Jensen-Meckling | — | cost = monitoring + bonding + residual | — | bonding devices | — | self-grading |
| Mission command | detailed control when untrusted/irreversible | intent + end state + constraints | decentralized "appropriate to the situation" | intent two levels down | shared understanding | intent not reaching two levels down |
| I-PASS | — | 5-field structured handoff | — | template + receiver synthesis | — | −23% errors with template |
| Little / Kanban | — | — | WIP ≤ verification capacity | — | — | raising the limit |
| MapReduce / sagas | — | idempotent output; compensating action | speculative duplicates (read-only) | atomic rename; backup tasks | — | stragglers +44%; partial writes |
| Brooks / Conway | surgical team: one core owner | — | partition only without inter-worker communication | star (N channels) | — | delegation narrows design space |
| Sterile cockpit | — | — | — | batch returns during verify/merge | — | interruptions in critical phases |
| Miller | — | — | — | chunk returns into paths | open-item count | too many open items |

### Merged decision rubric

Inputs (score before routing; `ข้อมูลไม่เพียงพอ` on any input blocks the route, per Rule 14):

| # | Input | How to read it | Source |
|---|---|---|---|
| I1 | **Context pollution** — will intermediate material be irrelevant to main's later decisions? | yes if >~1K tokens main won't reuse, or >~3 files, or unknown territory | Anthropic when-to-use; Rule 13 |
| I2 | **Bulk / independence** — independent pieces after Step 0; do they exceed one context? | count after grouping; flag shared files | Anthropic cost&intel; Brooks; Conway |
| I3 | **Verifiability** — deterministic command / scored rubric / judgment only | — | Williamson; Rule 4; fast-path cond. 3 |
| I4 | **Reversibility / blast radius** — Rule 1 triad | one-way door or wide radius → important | Rule 1/14; mission command |
| I5 | **Dependency shape** — one chain / DAG / independent | — | Anthropic research; cost&intel |
| I6 | **Wrong-answer cost vs handoff cost** — brief (~1–2K) + worker overhead (~10K) + verify + re-read | if verify ≈ redo, delegation buys only the gate | Coase; Jensen-Meckling; LangChain 2-call floor |
| I7 | **Open-item load** — in-flight agents + unverified returns + pending NEEDS-DECISIONs | ≤ what main verifies in one turn | Little; Miller; Kanban |

Routes (first matching row wins):

| Route | Condition | mh status |
|---|---|---|
| **Drop / defer** | I4 one-way door undecided → `NEEDS-DECISION` to user; or Value×Risk "avoid" with re-open condition | doctrine (`SKILL.md:138`) |
| **Do (in main)** | only the "Main retains" list — never execution | **gate** (`main-exec-guard.sh`, opt-in) |
| **Single worker, fast path** | 1 file, 1 behavior, I3 deterministic, not auth; haiku fixer + shape check | doctrine (`SKILL.md:86-95`) |
| **Single worker, Solver** | I5 = one dependent chain that fits one context; I3 ≠ deterministic; the CC "inline" conditions — routed to *one* foreground worker with `Why` required | doctrine (ADR 0012 accepted cost) — **not named as a route** |
| **Sequential chain** | ≥2 files or ≥1 test; or I5 = DAG with upstream contract | doctrine (`validation-chain.md`), gate on completion |
| **Parallel wave (read-only / verifier)** | I2 ≥2 independent read-only pieces, or diverse-lens voting; no I7 breach; speculative duplicate allowed | doctrine (cap 5, prefer 2-4); **no per-wave measurement** |
| **Parallel wave (writers)** | I2 ≥2 with disjoint FILES YOU OWN after Step 0, I5 independent, idempotent output + compensating action; AskUserQuestion gate | doctrine + hook + gates; compensation: **none** |
| **Escalate (advisor)** | I3 = judgment and I4 = important: one stronger-model read-only consult before committing | doctrine (Rule 1 `advisor()`) — **absent from orchestrate's routing table** |

Thresholds mh shares with the field: >~3 files ≈ Anthropic's >1K downstream-irrelevant tokens; cap 5 ≈ "keep teams small"; 2–4 for comparisons = "prefer 2-4". Thresholds mh states that the field doesn't: "<30 lines and <2000 tokens" (fast path); "≥2 files or ≥1 test" (chain). Neither contradicts a source.

### Handoff cost, "fresh is worse than main," and the Cognition objection

**What a handoff costs.** A fresh non-Explore worker starts with ≈10–11K tokens of CLAUDE.md + roster + git status (`orchestrate-cost-optimization-2026-09-03.md:53`), plus the F9 brief (≈1–2K authored at output price, then copied), plus its own reads, plus a return that main re-reads and — the unpriced part — whatever main opens to verify it. LangChain's floor is 2 extra calls per delegation; superpowers #1120 measured 10–15× on a 5-line file. Fixed cost ≈12–15K tokens before any work. Against that, Anthropic's 2026 data says the *variable* side is where delegation wins: capping the spiral tail and reading bulk at worker rates. ADR 0012's accepted cost ("every tiny fix pays a dispatch") is that fixed ~12–15K; the fast path is the right mitigation *and* exactly the "routine work → cheaper worker" case the tail-insurance data supports. The missing piece is the third cost: nothing records what main re-reads after a return — hence G1 is a measurement, not a policy.

**When a fresh-context agent is worse than main.** The CC doc's four conditions, Anthropic's "one dependent chain that fits," and Larson's Solver describe the same shape: iterative, shared-phase, latency-bound, judgment-verified work. mh's answer — route it to *one* foreground worker — is consistent with every source except the CC doc's literal advice, and ADR 0012 records that as a knowing override. No new evidence to reopen it; this shape deserves a **named route** ("Solver") so the lead stops treating it as a 4-step chain. Where the override genuinely bites: a worker needing the *user's* intent two levels up gets only main's paraphrase — make `Why` mandatory on that route.

**Cognition.** Both principles concern *writers making implicit decisions in parallel*. mh already forbids that shape (disjoint FILES YOU OWN, Step 0 consolidation), and its ADR concedes coding is less parallelizable. What Cognition doesn't argue against — and Anthropic's data supports — is parallel *read-only* work returning summaries: lookups, reviews, voting panels. The rubric therefore splits "parallel wave" into a read-only row (fan out freely under the cap) and a writer row (disjoint ownership + compensation, gated). Cognition's compressor idea is `/compact <instructions>` plus big-output-to-file; already doctrine.

### Gap list vs matt-harness

| # | Gap | Recommendation | Effort | Doctrine conflict |
|---|---|---|---|---|
| G1 | Third handoff cost (main's post-return re-reads) unmeasured; Little's λ unknown | **measure-first**: in `cost-tracker.sh` (after the concurrent edit lands) attribute main tokens between an agent's return and the next dispatch to `verify` for that agent id; add returns-per-turn and verify-tokens-per-return to `cost-report`; collect ≥10 sessions | small | none — extends F2/#10 |
| G2 | F9 has no receiver read-back (I-PASS field 5) | **add**: `## Brief-back` — worker restates What+Deliverable in ≤1 line as its first output; mismatch → main stops it | trivial | none |
| G3 | Route decision spread across 4 files; Solver and Advisor routes unnamed | **add**: I1–I7 + route table into `routing.md` as Step 0.5; `single-agent: solver` / `single-agent: advisor` descriptors (Output Format keeps the four leading words) | small | none; ADR 0012 unchanged |
| G4 | `Why` optional; intent doesn't reach Wave 2+ | **change**: `Why` required when Done-when is not fully deterministic or on the Solver route; UPSTREAM CONTRACTS carries the user's one-line goal (sanitized) in every wave | trivial | none |
| G5 | No compensating action on mid-task writer failure | **add** one F9 Constraints line: on Deadline/STOP with partial writes, report owned files touched; main dispatches a revert-fixer scoped to FILES YOU OWN | trivial | none; respects main-exec-guard |
| G6 | "Prefer 2-4" has no basis beyond the 44→105 incident and Anthropic's numbers | **keep**; **measure-first** via G1; do not derive from Miller | none | none |
| G7 | Speculative duplicate for stragglers absent | **add (read-only only)**: past Deadline on a read-only dispatch, send a narrower duplicate rather than wait; never for writers | trivial | none |
| G8 | Verifiability not an explicit route input | **change**: name it (I3) in `routing.md`; judgment-only outputs route to advisor/validator-with-rubric, never accepted from a single worker's self-report | small | reinforces Rule 14 |
| G9 | Sterile-cockpit batching of returns | **keep** as prose (`SKILL.md:37`); no hook | none | none |
| G10 | Managed Agents' worker→advisor escalation | **defer**: subagents can't spawn under check 41; only main escalates | none | check 41 |

### Top 3, in order

1. **G1 — price the third handoff cost.** Every open question (cap, 2-4, model downgrades, 7c) waits on the same missing number.
2. **G2 + G4 — F9 read-back and required intent.** Two lines in `f9-template.md`; the best-measured handoff intervention (I-PASS) and the mission-command failure mode both land here.
3. **G3 — one routing rubric in one file.** Turns the survey into the Step 0.5 test the lead actually runs, with Solver and Advisor as named routes.

---

## Sources

**In-repo:** `docs/METHODOLOGY.md:88-142`; `docs/research/adr-0012-main-plans-dispatches-never-executes.md`; `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md`; `docs/research/orchestrate-cost-optimization-2026-09-03.md`; `skills/workflow/orchestrate/{SKILL,f9-template,validation-chain,reference}.md`; `hooks/gates/main-exec-guard.sh:1-70`; `hooks/advisory/flow-nudge.sh:1-60`; memory `user-delegation-preference-main-never-executes-2026-09-01.md`, `mh-sweep3-delegation-redesign-shipped-2026-09-01.md`; llm-wiki `wiki/ai-agents/multi-agent/orchestrators-tax.md`, `wiki/sources/agile/src-wip-limits.md`.

**Fetched (primary):**
- https://www.anthropic.com/engineering/building-effective-agents
- https://www.anthropic.com/engineering/multi-agent-research-system
- https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them
- https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence (§Orchestrator strategy)
- https://platform.claude.com/docs/en/managed-agents/multiagent-orchestration (§What to delegate)
- https://code.claude.com/docs/en/sub-agents ; https://code.claude.com/docs/en/costs
- https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices (fetched, not grepped)
- https://openai.github.io/openai-agents-python/handoffs/ ; https://openai.github.io/openai-agents-python/multi_agent/
- https://docs.langchain.com/oss/python/langchain/multi-agent
- https://adk.dev/workflows/ (thin)
- https://cognition.com/blog/dont-build-multi-agents
- https://staffeng.com/guides/work-on-what-matters/ ; https://lethain.com/work-on-what-matters/ ; https://staffeng.com/guides/staff-archetypes/
- https://www.presidency.ucsb.edu/documents/address-the-second-assembly-the-world-council-churches-evanston-illinois
- https://onlinelibrary.wiley.com/doi/full/10.1111/j.1468-0335.1937.tb00002.x (Coase, via search highlights)
- https://www.nejm.org/doi/full/10.1056/NEJMsa1405556 (Starmer 2014, abstract via highlight; PubMed 25372088)
- https://static.googleusercontent.com/media/research.google.com/en//archive/mapreduce-osdi04.pdf
- https://www.law.cornell.edu/cfr/text/14/121.542
- https://www.melconway.com/Home/Committees_Paper.html
- http://www.musanim.com/miller1956/

**Secondary (primary unreachable — claims downgraded):**
- OpenAI "A practical guide to building agents": HTML 403, PDF binary; quotes from Firecrawl snippets. "10-15 tools" unverified.
- Jensen & Meckling 1976: via https://open.ncl.ac.uk/theories/21/agency-theory/
- ADP 6-0 (2019): via https://warroom.armywarcollege.edu/articles/new-doctrine-mission-command/ and Townsend et al., Military Review May–June 2019
- Williamson: via Aguinis AMP 2013 review (hermanaguinis.com/pdf/AMP2013.pdf) and Cambridge JIE commemoration
- Garcia-Molina & Salem 1987 Sagas: via secondary blog posts
- Little 1961: via https://en.wikipedia.org/wiki/Little%27s_law
- Brooks 1975: via https://en.wikipedia.org/wiki/The_Mythical_Man-Month
- Marquet ladder: via https://blog.mikebowler.ca/2024/04/25/ladder-of-leadership/

**Not fetched, not cited:** Sweller 1988; Fournier *The Manager's Path*; LangGraph concepts page (redirect loop); Google ADK multi-agents page (redirect to thin workflows page).
