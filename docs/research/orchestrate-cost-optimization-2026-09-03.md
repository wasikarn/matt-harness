# `orchestrate` cost optimization — fresh analysis and plan (2026-09-03)

**Date:** 2026-09-03
**Sources:**
- `skills/workflow/orchestrate/SKILL.md` (15,376 B) and `reference.md` (64,470 B), read in full
- `hooks/stop/cost-tracker.sh`, `hooks/stop/nudge-compliance-tracker.sh`, `hooks/advisory/flow-nudge.sh`, `skills/meta/cost-report/`
- Live data: `~/.local/share/kbg/metrics/costs.jsonl` (36,962 rows, 2026-06-29 → 2026-09-03), `skill-usage.jsonl`, `nudge-compliance.jsonl`
- `docs/METHODOLOGY.md` Rules 13/14, `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md`, `docs/research/adr-0012-main-plans-dispatches-never-executes.md`, memory `mh-sweep3-delegation-redesign-shipped-2026-09-01.md`
- `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/skills/` (research, code-review, implement-spec)
- `code.claude.com/docs/en/sub-agents` and `/docs/en/costs`, fetched 2026-09-03

**Scope:** analysis + plan only. No surface was edited. Token estimates use bytes÷4 unless a measured number is cited.

---

## TL;DR

1. The dominant measured cost is not the skill — it is the **main thread's carried context**: 234K cache-read tokens re-billed every turn across 181 sessions since 2026-08-07 ($9,002 orchestrator vs $4,633 subagent). `reference.md` at ~16K tokens is the single largest thing `orchestrate` itself adds to that rent.
2. **No per-orchestrate-run data exists.** `skill-usage.jsonl` shows exactly 1 `mh:orchestrate` invocation since 2026-08-25; `cost-tracker.sh` tags rows by `agent_type`, never by chain role, so Builder/Validator/Fixer/Re-validator cost is unmeasurable today. 7c's deferral stands.
3. Three changes are safe now, doctrine-neutral, and version-bump-sized: split `reference.md` (progressive disclosure, ~11K tokens/turn of rent removed), skip the Re-validator when no Fixer ran and the lens is the same, and add one line banning `fork` for F9-shaped dispatches (fork measured at 2× the per-turn rent of `general-purpose`).
4. The "haiku fixer" protocol (`reference.md:494-496`) is effectively unused: total haiku subagent spend is $7.51, one `general-purpose` row.
5. Model downgrades for validators and any 7c threshold are **measure first**: add a `role:` tag to the F9 header, extract it in `cost-tracker.sh`, and collect ≥10 orchestrate sessions before deciding.

## Current architecture, as-is

**Triage flow** (`SKILL.md:19-38`): Gather → Prioritize (matrix) → Route → Propose-then-dispatch (AskUserQuestion gate on any agent holding Edit/Write/Bash, `SKILL.md:26`) → Verify then combine (`SKILL.md:31-38`). Step 0 grouping-before-scoring is in the "Pick the matrix" section (`SKILL.md:99-107`). Single-agent fast path with `model: haiku` fixer at `SKILL.md:86-95`.

**F9 spawn template** (`reference.md:217-296`): 11 slots (Task, What, Why, Where, Focus, Deliverable, Skills, FILES YOU OWN, UPSTREAM CONTRACTS with basis hash, Files+Criteria+Constraints table, Constraints-always, Done-when with Deadline). `SKILL.md:42` orders the lead to read the full text "before dispatching a non-trivial subagent, and use it verbatim, not from memory". Short form for ≤3-file fixes: `reference.md:494-501`.

**Validation chain** (`reference.md:318-367`, worked example `:369-430`): Builder (gated) → Validator (ungated, read-only by allowlist) → conditional Fixer (gated) → Re-validator (ungated). Threshold for using a chain: ≥2 files or ≥1 test file (`SKILL.md:48`). Fix-retry cap 3 (`reference.md:333`). Structured JSON verdict contract (`reference.md:350-357`). Note: on a clean Validator pass the lead "skips straight to Task 4" (`reference.md:430`) — the Re-validator still runs even when nothing was fixed.

**Fan-out cap** (`SKILL.md:52-64`, history `reference.md:124-184`): hard cap 5 per wave, prefer 2-4, no floor; no mechanical enforcement on the Agent tool ("the lead is the clamp", `SKILL.md:54`). Platform 200/session cap was removed in CC 2.1.224 (`reference.md:164-167`).

**What loads when:**

| Item | When it enters context | Size |
|---|---|---|
| `SKILL.md` body | on skill invocation (main thread) | 15,376 B ≈ 3.8K tok |
| `reference.md` | when the lead `Read`s it — `SKILL.md:42,48` demand two sections "full text"; no `offset`/`limit` guidance, so in practice the whole file | 64,470 B ≈ 16.1K tok |
| Project + user `CLAUDE.md` (+ `RTK.md`) | every non-Explore/Plan subagent automatically (sub-agents doc §4) | 9,781 + 11,284 + 964 B ≈ 5.5K tok |
| `METHODOLOGY.md` | main session only, via `hooks/session/doctrine-bootstrap.sh:6-10` (SessionStart; `hooks.json` has no SubagentStart entry) | 17,518 B ≈ 4.4K tok |
| Skill + agent description roster | every session and every spawn (observed in this subagent's own context) | mh skills 7,121 B + mh agents 2,509 B; whole roster across plugins ≈ 15-20K B |
| F9 brief | per dispatch, authored by the lead | template skeleton ≈ 3.5K B before fill-in |

## Where the tokens go — per orchestrate run

| Cost source | Measured / estimated | Source of number |
|---|---|---|
| Main-thread rent (all sessions since 08-07) | **233,928 cache-read tok/turn**; $9,002 over 181 sessions, 108,641 turns | `cost-report-dedup.js` run 2026-09-03; `costs.jsonl` |
| `reference.md` once loaded | ≈16.1K tok added to every subsequent main turn; at 300 turns ≈ 4.8M cache-read tok ≈ $1 (Sonnet) / $2.4 (Opus) per session | bytes÷4; rates `cost-tracker.sh:37,125-127` |
| `SKILL.md` | ≈3.8K tok, same rent mechanics | bytes÷4 |
| F9 brief per dispatch | ≈1-2K tok authored (output-priced on main) + copied into agent's first message | template `reference.md:227-292` |
| Fixed per-agent overhead (CLAUDE.md files + roster) | ≈10-11K tok in every fresh non-Explore agent, cache-read on every agent turn | sub-agents doc §4; file sizes above |
| Subagent rent by type | `general-purpose` 99.5K tok/turn (129 rows, $2,366, median $6.82/session); `Explore` 67K/turn ($423); **`fork` 205K/turn** ($160, 27 rows); `kbg:code-implementer` 165K/turn | `costs.jsonl` aggregated by `agent_type`, latest row per (session, stream, model, type) |
| Opus-pinned reviewers | Opus subagent rows: 59, $574 total. `mh:plan-reviewer` $61/6 rows (≈$10 each), `mh:blind-spot-hunter` $27/3 (≈$9 each) vs earlier `kbg:plan-reviewer` $71/18 (≈$4 each) | `agents/plan-reviewer.md`, `blind-spot-hunter.md`, `security-reviewer.md`, `code-architect.md`, `backend-architect.md`, `requirement-analyst.md` carry `model: opus`; costs above |
| Validator → Re-validator chain | **no data** — `cost-tracker.sh:100` keys only on `agent_type`; chain role is not recorded anywhere | `cost-tracker.sh` |
| Fan-out | **no data per wave**; `main_dispatches` per session exists since 2026-09-01 (13 sessions) | `nudge-compliance-tracker.sh:152-163` |
| Haiku usage | $7.51 total subagent haiku spend, 13 rows, 12 of them `claude-code-guide`; 1 `general-purpose` row ($1.52) | `costs.jsonl` |

Reference point from the one isolated session measured before the tracker split (`orchestrator-tax-gap-analysis-2026-08-07.md:93-113`): main $21.23 vs 15 subagents $16.14, 202K tok/turn carried; cache_read = 59% of the main bill.

## What real data exists vs doesn't

**Exists:**
- Orchestrator vs subagent split, per model, per `agent_type`, per turn rent — 2026-08-07 onward (`cost-tracker.sh:144-162`).
- `main_writes` / `main_dispatches` per session — 2026-09-01 onward, 13 sessions (`nudge-compliance.jsonl`).
- Skill invocation log — 2026-08-25 onward, 78 rows; `mh:orchestrate` appears once.
- flow-nudge delegation-ratio line, computed live from `costs.jsonl` (`flow-nudge.sh:145-182`).

**Does not exist:**
- Any per-orchestrate-run cost (the skill is invoked too rarely to isolate; sessions aren't tagged as "orchestrate sessions").
- Chain-role attribution (Builder/Validator/Fixer/Re-validator).
- Wave size distribution (agents per wave) — only cumulative dispatch counts.
- Any LLM-output quality eval to weigh a model downgrade against (`reference.md:225`: "Unmeasured on this repo — no LLM-output eval exists as of 2026-09-03").
- The 7c threshold baseline: deferred 2026-09-01 for exactly this reason (memory `mh-sweep3-delegation-redesign-shipped-2026-09-01.md`, "7c ... deliberately NOT built"). Since then ADR 0012 (`adr-0012…md:3-7`) replaced the opt-in `main-write-budget.sh` with `main-exec-guard.sh` (commit `aa279aca`), which shifts 7c's question from "how many writes" to "why did main write at all" — the baseline need is unchanged.

## Ranked optimization candidates

| # | Candidate | Saving | Mechanism | Risk | Doctrine conflict | Effort | Status |
|---|---|---|---|---|---|---|---|
| 1 | **Split `reference.md` (progressive disclosure)** | ≈11-13K tok off every main turn after the lead loads it; ~$1-2.4/session, more in context terms | Move the two "read before dispatching" sections into `f9-template.md` (≈10K B: template + why-each-slot + sanitize note) and `validation-chain.md` (≈12K B: chain + verdict contract + worked example). Routing tables (13.9K B) into `routing.md`. History/rationale (fan-out history, L4/L5, pattern vocabulary, anti-patterns, protocols ≈ 28K B) stays as `reference.md`. `SKILL.md:42,48,117,123,143` pointers change to file names. | Broken section pointers; harness-audit checks that grep `reference.md` (`checks/34-*`, check 68 fence lint); `docs/reference/adding-a-surface.md` ritual applies | None — CLAUDE.md's own progressive-disclosure rule. `orchestrator-tax…md:367` declined "trim SKILL.md" on standing-cost grounds; this targets the on-demand load's rent, a different argument | Small (file moves + pointer edits + version bump) | **Safe now** |
| 2 | **Skip Re-validator when no Fixer ran and lens is unchanged** | One dispatch per clean chain; on Opus reviewers ≈ $4-10 each | Doctrine edit at `reference.md:331,430`: D runs iff C ran, OR D's lens differs from B's (e.g. B = language reviewer, D = `security-reviewer`). B's structured verdict is already the machine-checkable score. | A second look sometimes catches what the first missed — but D is defined as "the same or a different validator" verifying *the fix* (`reference.md:331`); with no fix, same-lens D re-grades B's work | None: verifier separation intact (B still separate from A); "score, not feel" intact (B's JSON verdict). Matches `reference.md:357` "adding one would add a check this chain doesn't need (Rule 2)" | Small | **Safe now** |
| 3 | **Ban `fork` for F9-shaped dispatches** | fork rent 205K tok/turn vs 100K `general-purpose` / 67K `Explore`; 27 rows, $160 | One line in the F9 section: the brief *is* the context; fork only when the task genuinely needs the conversation (sub-agents doc: fork "inherits the entire parent conversation"). `reference.md` never mentions fork today | Occasional task really needs history — the rule names the exception | None | Trivial | **Safe now** |
| 4 | **Prefer `Explore` for read-only lookups** | ≈6K tok/turn less rent per agent (Explore skips CLAUDE.md + git status, sub-agents doc §4); measured 67K vs 99.5K/turn | Add to the Delegation-guardrail section (`reference.md:452-462`): pure search/lookup → `Explore`; `general-purpose` only when Bash/Write is needed | Explore can't run Bash-based validation | None | Trivial | **Safe now** |
| 5 | **Cheaper model for Validator / Re-validator** | Opus→Sonnet ≈ 2.5× on input/output; per dispatch ≈ $4-6 on the observed reviewer rows | Per-dispatch `model` param on the Agent tool, or `model: sonnet` in the 6 Opus-pinned agent files. Costs doc: "Use Sonnet for teammates"; "Reserve Opus for complex architectural decisions" | Judge quality — no eval to detect regression; `security-reviewer` on auth code is the case Opus exists for | Rule 14 "measure > feel" — a blind downgrade is a guess; G1 in `orchestrator-tax…md:419` was declined for the same reason | Small edit, but needs an eval first | **Measure first** |
| 6 | **Effort down-tune on xhigh reviewers** | thinking tokens are output-priced (costs doc); `kbg:plan-reviewer` 1.1M output tok / 1,618 turns | `effort: high` instead of `xhigh` on `plan-reviewer`, `blind-spot-hunter`, `security-reviewer`; `reference.md:225` already defaults `medium` for research-shaped work | Same eval gap as #5 | Same as #5 | Trivial | **Measure first** |
| 7 | **Description-cap enforcement** | none available | Already enforced: harness-audit #20 `DESC_MAX=1536`, CLAUDE.md ≤25-word rule; mh total 9,630 B vs the docs' 15,000-token warning threshold | — | — | — | **Nothing to do** |
| 8 | **Tool-restricted agents** | marginal | All 12 agents already use `tools:` allowlists (`reference.md:23-25`, `agents/*.md`); background agents get the reduced set automatically; `disallowedTools: mcp__*` on reviewers would drop only deferred MCP stubs | — | — | — | **Nothing to do** beyond #4 |
| 9 | **Drop duplicate doctrine in spawn prompts** | small | CLAUDE.md injection is platform-side (can't be turned off except via Explore/Plan); METHODOLOGY is main-only; F9 already forbids pasting skill bodies (`reference.md:247-252`). The only lead-controlled duplicate is the ≈1.2K B "Constraints (always)" block repeated per brief — keep it; agents can't be trusted to `Read` a pointer | — | — | — | **Nothing to do**; `reference.md:582` ("sub-agents receive only the slice they need") overstates what the lead controls — fix the wording in #1 |
| 10 | **Baseline plan for 7c and chain-role cost** | enables #5/#6 and 7c | (a) Add `[role: builder\|validator\|fixer\|revalidator\|lookup]` to the F9 `# Task:` line; (b) `cost-tracker.sh` `build_type_map` reads the first user message of each `agent-*.jsonl` and extracts the tag into a `role` field (a few lines of jq, same pattern as `agentType`); (c) `cost-report` adds a "By role" block; (d) tag orchestrate sessions by joining `skill-usage.jsonl` `session_id` to `costs.jsonl`; (e) collect ≥10 orchestrate sessions before any threshold or downgrade decision | Tag drift if the lead forgets; fail-open to `role: null` like `agent_type: "unknown"` | None — extends the existing measurement patch the same way the 08-07 split did | Small (hook + report + test in `tests/skills/test-cost-report.sh`) | **Do now, decide later** |

Not a candidate: the AskUserQuestion gate and the fan-out cap. Both bound authorization/runaway, not tokens (`reference.md:454`), and the 44→105 incident is the reason the cap exists.

**Upstream comparison.** Matt's dispatching skills stay cheap by being thin: `research/SKILL.md` (≈2K B) dispatches one background agent with a 3-item job; `code-review/SKILL.md` (6,589 B) spawns exactly two parallel sub-agents with prompts assembled from pointers; `implement-spec/SKILL.md:13` states the principle outright — "Communicate primarily through context pointers ... Don't duplicate information already available via pointers." None carries a 64K reference. mh's F9 slot discipline is the more rigorous contract (and the reason to keep it); the cost gap is the always-loaded rationale around it, which #1 fixes without dropping the contract.

## Recommended next 3 steps

1. **Ship #1 + #2 + #3 + #4 in one version bump.** Split `reference.md` into `f9-template.md`, `validation-chain.md`, `routing.md`, and a slimmer `reference.md`; update the five `SKILL.md` pointers; add the D-skip rule, the no-fork line, and the Explore-for-lookups line; rewrite `reference.md:582`. Run `bash scripts/run-gauntlet.sh` and harness-audit; `claude plugin update mh@wasikarn` before committing per `docs/reference/adding-a-surface.md`.
2. **Ship #10's instrumentation.** `role:` tag in the F9 header, `role` field in `cost-tracker.sh` rows (fail-open), "By role" section in `cost-report`, regression case in `tests/skills/test-cost-report.sh`.
3. **Collect, then decide.** After ≥10 orchestrate-tagged sessions: compare Validator vs Re-validator spend and pass rates; decide #5/#6 per agent with the numbers, and set 7c's threshold from the `main_dispatches` / `main_writes` distribution — not before.

## Sources

- `skills/workflow/orchestrate/SKILL.md:19-38, 42, 48, 52-64, 86-95, 99-107, 117, 123, 143`
- `skills/workflow/orchestrate/reference.md:3-34, 23-25, 124-184, 217-296, 225, 247-252, 318-367, 331, 333, 350-357, 369-430, 452-462, 494-501, 582`
- `hooks/stop/cost-tracker.sh:37, 52-69, 86-142, 100, 125-127, 144-162`
- `hooks/stop/nudge-compliance-tracker.sh:44-60, 152-163`
- `hooks/advisory/flow-nudge.sh:132-193`
- `hooks/session/doctrine-bootstrap.sh:6-10`; `hooks/hooks.json` (event list, no SubagentStart)
- `skills/meta/cost-report/SKILL.md`, `references/schema-history.md`; `scripts/workflows/cost-report-dedup.js` output 2026-09-03
- `agents/{backend-architect,blind-spot-hunter,code-architect,plan-reviewer,requirement-analyst,security-reviewer}.md` frontmatter (`model: opus`)
- `docs/METHODOLOGY.md:88-121` (Rule 13), `:123-138` (Rule 14)
- `docs/research/orchestrator-tax-gap-analysis-2026-08-07.md:70-127, 367, 419`
- `docs/research/adr-0012-main-plans-dispatches-never-executes.md:1-21`; commits `7184108a`, `e5812a76`, `aa279aca`
- Memory: `mh-sweep3-delegation-redesign-shipped-2026-09-01.md`, `skill-listing-budget-mechanics.md`
- `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/skills/engineering/{research,code-review}/SKILL.md`, `in-progress/implement-spec/SKILL.md:13-15`
- `code.claude.com/docs/en/sub-agents` (model resolution order; `tools`/`disallowedTools`; 15,000-token description warning; fresh-context contents incl. CLAUDE.md except Explore/Plan; fork inherits full conversation; `experimental.cacheTtl`; `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`), fetched 2026-09-03
- `code.claude.com/docs/en/costs` ("Use Sonnet for teammates"; `model: haiku` for simple subagent tasks; thinking tokens billed as output; cache-read rent in long sessions), fetched 2026-09-03

## Applying the cost-optimize lever order (2026-09-04)

**Sources:** the bundled `/claude-api cost-optimize` guide (`claude-api/shared/cost-optimization.md`, cited by section heading) and `shared/prompt-caching.md`; four official prompting pages fetched 2026-09-04 from `platform.claude.com/docs/en/build-with-claude/prompt-engineering/`: `claude-prompting-best-practices` (baseline, model-invariant by definition), `prompting-claude-fable-5-1` (main + inherited subagents), `prompting-claude-opus-5` (6 agents pinned `model: opus`), `prompting-claude-sonnet-5` (candidate for data-gated validator/lookup roles). Harness state v0.68.625 (`.claude-plugin/plugin.json:4`). Bash was gated off during this pass (another session mid-edit on `verifier-protect.sh`), so sizes not already measured above are marked *est.* — the Builder re-measures with `wc -c`.

### 1. The guide's lever order and its measurement rules

1. **Step 0 — scope, quality bar, baseline.** Per traffic class ("cost per task means nothing blended across classes"). No eval → say so; free wins still proposable; every tradeoff "needs an eval before applying"; the user's manual review "gates free wins — it never clears a tradeoff" (§ Step 0, item 2). Baseline = cost per *task* at four token rates (item 3).
2. **Step 1 — token profile.** Measure or read the code; rank by savings ceiling in the unit the data supports; deflate overlapping ceilings so the list "can never sum past the bill" (§ Rank the levers).
3. **Free wins, in order** (§ Step 2): **2.1 caching** — largest lever measured, 2.5–3.7× off at 81–90% hit rate; "verify from usage, not from code review — and re-verify after every prompt-assembly change". **2.2 input hygiene** — progressive disclosure, prompt-audit ~14% at same accuracy; caveat "a smaller prefix is not automatically a cheaper task". **2.3 loop hygiene** — deep loops only; context editing "cost more than it saved". **2.4 output hygiene** — specify the output shape; reasoning length is effort, not `max_tokens`. **2.5 batch** — 50% off unattended work.
4. **Tradeoffs, last** (§ 2.6–2.7): "sweep effort before touching the model", separate sessions per level; model "last, deliberately", one tier at a time; multi-model only in the two measured shapes.
5. **Step 3 — one lever per diff**, keep or revert against the eval; "never keep or revert on a one-case swing"; caching diffs measured from the second request on.

### 2. Lever → Claude Code term → harness item → status

| Guide lever | In Claude Code terms | Harness item | Status / why |
|---|---|---|---|
| 2.1 Prompt cache | Prefix = CC system prompt + output style (`crisp.md:5` `force-for-plugin`) + tool schemas → `messages[0]` carrying CLAUDE.md / MEMORY.md / SessionStart stdout as `<system-reminder>` text | `hooks/session/doctrine-bootstrap.sh:8-11` (METHODOLOGY 17,518 B); `hooks.json:4-49` (4 SessionStart hooks) | **Already on** — CC caches automatically, per session only (system prompt embeds `gitStatus`, so no cross-session share). Only "don't break it" (§3) |
| 2.2 — reference doc in every prompt | Session-start files re-billed at cache-read rate every turn | `reference.md` → `f9-template.md`, `validation-chain.md` | **Done v0.68.625** (#1) |
| 2.2 — the prompt text itself | System prompt + doctrine prose | `crisp.md` (261 lines, ~14.5 KB *est.*), `docs/METHODOLOGY.md` (17,518 B), MEMORY.md (25,600 B cap) | **Round 2** — but the guide's skip-when applies: prompt-audit on mh settled v0.68.617 with 0 findings, so round 2 is a *byte* cut of duplicates and baseline-contradicting rules (§4 matrix), not a second pattern audit. Known duplicates: METHODOLOGY `:49-55` mirrored verbatim in `~/.claude/CLAUDE.md` (`:55` says so); `crisp.md:100-103`, `:135-141` restate global Communication Style |
| 2.2 — hook outputs | UserPromptSubmit stdout appended to the user turn, carried all session | `flow-nudge.sh:188-200` (delegation block ~600 B/fire, live numbers `:182`), `:408-414` | **Round 2** (quiet rule). History rent, not a cache breaker |
| 2.2 — tool schemas | Deferred tools + `ToolSearch`; `tools:` allowlists | native; `agents/*.md` | **n/a** (#8) |
| 2.3 Loop hygiene | Explore for lookups, no `fork`, D-skip, output to file | `f9-template.md:85-87`, `validation-chain.md:20`, METHODOLOGY `:109` | **Done v0.68.625** (#2–#4) |
| 2.3 — compaction | `/compact`, PreCompact flush | `hooks.json:218-229`; CLAUDE.md Compact instructions | **Nothing to do** — a window tool, not a savings lever; Fable page: with cheaper cache reads "compacting early to save cost may no longer be the right tradeoff" (§ Keep the conversation history append-only) |
| 2.4 Output hygiene | Agent return size; reply length | `f9-template.md:32-33`; `crisp.md:21-49` | **Compliant** — no `max_tokens` knob exists in CC |
| 2.5 Batch | — | — | **n/a** (interactive) |
| 2.6 Effort | Frontmatter `effort:`; no per-dispatch param (`f9-template.md:13`) | `plan-reviewer.md:12`, `blind-spot-hunter.md`, `security-reviewer.md` = `xhigh` | **Data-gated** — `role` ships (`cost-tracker.sh:113,118,145`), effort is not recorded; one exception in §4 |
| 2.7 Model | Frontmatter `model:` | 6 agents `model: opus` | **Data-gated**, after the effort sweep |
| Orchestrator shape | main plans, subagents execute | ADR 0012, `main-exec-guard.sh`, `validation-chain.md:9` threshold | **Already the architecture**; the ≥2-files threshold is the guide's "no bulk → no handoff" guard |

### 3. Guide rules the current plan violates or skips → round-2 fix

- **Quality bar first (Step 0.2).** No eval (`f9-template.md:13` admits it). Free wins may ship, but only behind the manual spot-check the guide names — the plan has none. *Fix:* freeze 5 real prompts from this session; replay after each diff; user judges side by side (§ Step 3, no-outcome-check mode). No tradeoff ships in round 2.
- **Cost per completed task, not per token.** The plan's metric is rent (`cache_read_per_turn`); rent can fall while turns rise (§ 2.2 caveat). *Fix:* read `turns` and `estimated_cost_usd` per session with it; a trim that raises turns >10% reverts.
- **Traffic classes (Step 0.1).** crisp.md and METHODOLOGY load on main only (no SubagentStart in `hooks.json`; output styles are main-only); CLAUDE.md loads on every non-Explore agent. Round 2 touches the main class — claim only that. The third-party Ponytail `SubagentStart` injection (~4 KB/spawn) is the largest per-spawn input item and lives outside this repo.
- **One lever per diff (Step 3).** Round 2 bundles three edits. *Fix:* three bumps — flow-nudge quiet → crisp/METHODOLOGY dedupe → MEMORY archive — with a `costs.jsonl` read between.
- **Re-verify caching after every prompt-assembly change (§ 2.1).** Absent. *Fix:* criterion 6; `costs.jsonl` already carries `cache_write_tokens`/`cache_read_tokens` per row, so the healthy-loop signature (`prompt-caching.md` § Verifying cache hits) is observable with no new tooling.
- **Cache-invalidation ordering.** Render order is system → tools → messages. Per-turn hook stdout (flow-nudge) and CC's own turn-scoped notes land *inside the current user turn*, after every breakpoint: they grow history, never invalidate. SessionStart stdout and CLAUDE.md/MEMORY.md land once in `messages[0]`. All three round-2 targets are session-start content: editing them changes the prefix *between* sessions only. **No round-2 edit can break prefix stability.** Real in-session breakers are elsewhere: `/model` or an effort change mid-session (caches are model-scoped; effort invalidates the messages cache — § Invalidation hierarchy), a late-connecting MCP server changing the tool list, compaction. Keep `doctrine-bootstrap.sh` free of per-session values (dates, counters) above the METHODOLOGY block; its conditional preflights (`:32-43,53-62`) are per-machine stable and harmless.
- **Effort before model (§ 2.6 → 2.7).** #5/#6 are unordered in the plan. *Fix:* #6 first, per level in separate sessions; #5 only if `low`/`medium` holds.

### 4. Prompting guides → harness prompt surfaces (baseline / Fable 5.1 / Opus 5 / Sonnet 5)

Who reads what: `crisp.md` and doctrine-bootstrap output → main only (Fable 5.1). `f9-template.md` is authored by main but *executed* by the dispatched agent's model (Fable via inherit, or Opus for the 6 pinned agents, Sonnet if step 3 lands). `validation-chain.md` → main, but its Task-2 brief text runs on the validator's model.

| Topic | Baseline (best-practices) | Fable 5.1 | Opus 5 | Sonnet 5 | Harness surface → mark |
|---|---|---|---|---|---|
| Effort default | thinking depth via `effort`; adaptive beats extended (§ Leverage thinking) | start `high`; `low` "often competitive with Opus and Sonnet on cost per task" (§ Consider all effort levels) | start `high`; use `low`/`medium` "liberally"; code review "accuracy holds at lower effort" (§ Capability improvements) | default `high`; `low` "reserve for short, scoped tasks … not intelligence-sensitive"; under-thinking risk at `low`/`medium` (§ Calibrating effort) | `f9-template.md:13` medium-for-research: fine for Fable/Opus, **wrong for a Sonnet validator** → model-specific, move to frontmatter |
| `xhigh` | — | `high` for long deliverables; `xhigh` "only where you've measured a quality gain" (§ Leave room for long outputs) | "step up to `xhigh` for demanding coding and agentic work" — but review accuracy holds lower | `xhigh` "recommended for the hardest coding and agentic use cases" | `plan-reviewer.md:12` et al. `xhigh` on Opus reviewers: **violates** Opus's own review note; `high` is every guide's start point → own diff after round 2 |
| Verbosity | "Less verbose" default; prompt for summaries if wanted (§ Communication style) | prose dense → "remove all mannered prose" (§ Writing density) | runs long; effort "does not reliably" shorten it → prompt explicitly (§ Response length) | self-calibrates; positive examples beat "don't" (§ Response length) | `crisp.md:51-159` Voice: Fable-only surface → **trim candidate** (replace overlapping bullets with the one-line density rule). Opus agents need their own conciseness + "written deliverable length" line (§ Written deliverable length) in `agents/*.md`, not in shared doctrine |
| Progress updates | may skip summaries after tool use; ask if wanted | writes *fewer* — "remove lines like that" that suppress narration (§ Ask for user-facing progress updates) | narrates *more* — describe cadence to tune down (§ User-facing progress updates) | already good — "try removing" scaffolding | **Opposite directions → model-specific by definition.** `crisp.md:33-36` (permits one-line notes, Fable-safe) compliant; nothing about cadence belongs in f9/METHODOLOGY |
| Verification / self-check | "Ask Claude to self-check … Claude Opus 5 is the exception" (§ Leverage thinking) | — | "remove them … over-verification"; "do not use subagents to verify or double-check your own work" (§ Task scope and over-verification, § Controlling subagent spawning) | reaches for self-verification loops readily (§ Tool use triggering) | METHODOLOGY Rule 4 `:71-82` + `:45` (`advisor()` before done) is main/Fable-only → compliant; **never add a SubagentStart injection of METHODOLOGY** (would hit Opus agents). Builder greps `agents/*.md` for "double-check/re-verify" on the 6 Opus agents → delete. The chain's *structural* verifier (separate agent, `validation-chain.md:26`) is not a prompt instruction and stays |
| Review recall | — | — | "only report high-severity" is followed literally → "report everything and filter in a separate pass" | same, with the coverage block + confidence/severity per finding (§ Code review harnesses) | `validation-chain.md:43` verdict already carries `severity` + `confidence` → compliant shape; **add the coverage sentence to the Task-2 brief (`:102`)**; Builder greps reviewer prompts for "conservative/only high/don't nitpick" → delete |
| Prescriptiveness | "Prefer general instructions over prescriptive steps"; "tell Claude what to do instead of what not to do"; dial back "CRITICAL/MUST" (§ Tool usage) | existing prompts "should perform well … without changes" | — | "interprets prompts literally … state the scope explicitly" (§ More literal instruction following) | Resolution: explicit *scope + success criteria* is invariant (F9 What/Where/Done-when); prescriptive *method* steps are not. METHODOLOGY `:28-41` (plan-mode step recipe) and crisp.md's "Don't/Never" bullets → **trim candidates**; `f9-template.md:9,11` "MUST … verbatim" → soften to plain imperative |
| Scope / autonomy | conservative-action block; reversibility confirm (§ Balancing autonomy and safety); overeagerness block | "Keep changes and tests to what the task asks for"; autonomy block "suits … long-horizon", exception "problem description → assessment, don't fix" (§ Finish the whole task) | same scoping block (§ Task scope) | at `low`/`medium` "scopes its work to what was asked" | `f9-template.md:73` (near-verbatim Fable/Opus block), `:74` NEEDS-DECISION, METHODOLOGY Rule 1 triad `:10-14` → **compliant, keep list** |
| Role | "Even a single sentence makes a difference" (§ Give Claude a role) | — | — | — | `crisp.md:11-13` → keep; agent bodies already open with a role |
| Sectioning / XML | XML tags for mixed content (§ Structure prompts with XML tags) | — | — | — | doctrine-bootstrap wraps in HTML comments `:9,11` → cheap **trim candidate**: `<doctrine>` tags; F9 uses `##` headings — fine |
| Long-context placement | "longform data at the top … query at the end" (§ Long context prompting) — the same rule as the cache prefix | — | — | — | CC puts CLAUDE.md/doctrine in `messages[0]`, prompt last → compliant |
| Examples vs rules | 3–5 `<example>`s beat rules | one full example for quoting | positive examples > instructions | positive examples > negative | `crisp.md` is rules-only (one caught example `:250-253`); `validation-chain.md:63-96` has a worked example → keep; add none in round 2 (bytes) |
| Parallel tool calls | steerable, ~100% with the block | turn-scoped nudge each round | — | — | CC injects natively → **n/a**, don't add to F9 |
| Search at low effort | — | skips search at `low`; raise effort or add the verify line (§ Search triggering) | — | with thinking off, fewer tools; `high`/`xhigh` = more tool use | `f9-template.md:13` "`low` acceptable for pure lookup" → **violates**; floor lookups at `medium` (Fable) and `high` (Sonnet) |
| Thinking control | `budget_tokens` gone; effort is the lever | always on | on by default; off only ≤`high` | adaptive on by default; +~30% tokens vs 4.6 tokenizer | not harness-controllable in CC → n/a; but bytes÷4 undercounts Sonnet by ~30%, so the 2.5× Opus→Sonnet estimate above is ≈2× net |
| Subagent caps | watch for overuse; explicit "when to delegate" rule | lead keeps working while subagents run | delegates readily; cap deterministically (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`) | — | `SKILL.md:52-64` cap 5, check 41 no-nested-spawn → compliant; the env-var cap is a free deterministic backstop worth setting |

**Which model each shared surface is written for.** `f9-template.md` and the Task-2 brief in `validation-chain.md`: write for **Sonnet 5**, the most literal reader — explicit scope, explicit "check every file in FILES YOU OWN", the coverage sentence, no negative-only rules. The Fable and Opus guides prescribe the same scoping block, so nothing there hurts them; the only text that differs by model is effort and narration cadence, and those leave the template for `agents/*.md` frontmatter. `crisp.md` and doctrine-bootstrap output: **Fable 5.1 only** (main), so Rule 4's self-check language is safe there and must stay main-only.

**For a Sonnet-run validator to hold quality** (guide § Calibrating effort, § More literal instruction following, § Code review harnesses): (a) frontmatter `effort: high`, never `medium` — the F9 `medium` default is a Fable/Opus number; (b) Task-2 brief gains "Report every issue you find, including low-severity or uncertain ones; do not filter — the lead ranks by your `severity` and `confidence`"; (c) scope stated per file ("apply to every file in FILES YOU OWN, not just the first"); (d) Builder deletes any "be conservative / only high-severity" line in reviewer prompts; (e) budget +30% tokens for the same brief (new tokenizer) when reading `costs.jsonl` Sonnet rows.

**Keep list (invariant across all four pages) for the crisp.md / METHODOLOGY trim:** role sentence; lead with the outcome; scope = the request, extras become follow-ups (`f9:73`); explicit done-when / success criteria; reversibility confirm before destructive or shared-visible actions (Rule 1 triad); "problem description → assessment, not a fix"; report-everything + severity/confidence in reviews; stable content first, query last; tell what to do, not what not to. **Model-specific (move to frontmatter or per-agent body, out of shared doctrine):** effort level; narration cadence (up for Fable, down for Opus, none for Sonnet); the Opus conciseness + deliverable-length lines; self-check/verify instructions (never for Opus); the mannered-prose line (Fable); anti-formatting rules (remove for Fable); the search-verify line (Fable at `low`); "think carefully" (Sonnet at `low`).

### 5. Round 2 acceptance criteria (Builder must meet all)

1. Three diffs, three version bumps, in order: flow-nudge quiet rule → crisp/METHODOLOGY dedupe → MEMORY archive; each commit names the byte delta (`wc -c` before/after) and tokens ≈ bytes÷4.
2. `crisp.md` ≤ 10,000 B (from ~14.5 KB *est.*; measure first), by deletion only: lines duplicated in `~/.claude/CLAUDE.md`, Voice bullets the one-line density rule replaces, and negative-only ("Don't/Never") bullets the baseline contradicts. Lines `11-13`, `29-45`, `150-153`, `161-198`, `200-227` survive verbatim. Zero new rules; zero narration-suppressing lines (Fable § Progress updates).
3. `METHODOLOGY.md` ≤ 14,000 B; one copy of the disable-model-invocation block (`:49-55`) remains, here or global; the plan-mode recipe `:28-41` shrinks to the general rule plus one pointer; `injection-budget-check.sh` stays silent; the `<!-- -->` wrappers in `doctrine-bootstrap.sh:9,11` become `<doctrine>` tags.
4. MEMORY.md: `memory-lint.py --auto-archive` dry-run is the verdict (its clean verdict governs over the ~17 KB soft target); index stays < 25,600 B.
5. flow-nudge: `tests/hooks/test-flow-nudge.sh` green plus one new case; the delegation block (`:188-200`) ≤ 400 B and prints only when `DELEGATION_TRIGGER=1`; the live ratio line is dropped or gated behind the trigger so no per-turn number enters history otherwise.
6. Cache signature after each diff, on a ≥30-turn session: orchestrator rows in `costs.jsonl` show `cache_write_tokens / turns` ≤ 1.5× the pre-diff median and `cache_read_per_turn` down by ≥ (bytes removed ÷ 4) − 500.
7. Cost per task: `turns` per session not up by more than 10% vs the last 10 sessions of the same class; otherwise revert that diff.
8. Quality gate: 5 frozen prompts replayed before/after each diff, replies side by side, user signs off — the only gate the guide allows without an eval.
9. `f9-template.md:13` lookup floor becomes `medium` (Fable) with a note that Sonnet-run roles use `high` from frontmatter; `validation-chain.md:102` gains the coverage sentence; `f9-template.md:9,11` lose "MUST/verbatim"; no other effort/model change in round 2. xhigh→high on the 3 Opus reviewers and the "double-check" grep on `agents/*.md` are one separate later diff.
10. `bash scripts/run-gauntlet.sh` green, harness-audit 0 CRIT, `claude plugin update mh@wasikarn` before each commit.
