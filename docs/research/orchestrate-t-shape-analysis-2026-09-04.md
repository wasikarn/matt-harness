# Orchestrate T-shape analysis — token cost and work-distribution surfaces (2026-09-04)

**Date:** 2026-09-04
**Sources:** `hooks/hooks.json`, `hooks/pretooluse-table.json`, `hooks/{dispatch-single,dispatch-pretooluse}.sh`, `hooks/session/*.sh`, `hooks/advisory/flow-nudge.sh`, `hooks/gates/{main-exec-guard,agent-recursion-guard}.sh`, `hooks/stop/cost-tracker.sh`, `scripts/workflows/cost-report-dedup.js`, `skills/workflow/orchestrate/{SKILL,reference,f9-template,validation-chain,routing}.md`, `docs/METHODOLOGY.md`, `output-styles/crisp.md`, `agents/*.md`, `BOUNDARY.md`, `docs/research/{orchestrate-cost-optimization-2026-09-03,adr-0012-main-plans-dispatches-never-executes}.md`, `~/.claude/CLAUDE.md`, `~/.claude/rules/*.md`, `~/.claude/plugins/{installed_plugins.json,cache/ponytail/ponytail/4.9.0/hooks/*,cache/mattpocock/mattpocock-skills/1.2.3/.claude-plugin/plugin.json}`, the bundled `claude-api` skill's `shared/model-migration.md` (Opus 4.7/4.8/5, Sonnet 5, Fable 5.1 sections), all read 2026-09-04.
**Scope:** read-only analysis; no surface edited. Byte counts are measured where the 2026-09-03 research doc cites them, else Read line counts × ~60 B/line. Written by a research subagent for the coordinator.

## TL;DR

1. Main's per-turn rent (234K cache-read tok/turn, $9,002 vs $4,633 subagent, `orchestrate-cost-optimization-2026-09-03.md:49`) is mostly accumulated conversation; the *fixed* prefix this harness controls is ~110 KB (~27K tok) and only ~40 KB of it is doctrine main actually needs every turn.
2. Every non-Explore subagent inherits ~75-80 KB before the F9 brief lands: CLAUDE.md ×3 (22 KB), MEMORY.md (~20 KB, observed in this agent's own context), skill roster (~25 KB), ponytail SubagentStart (~4.5 KB), agent list + MCP instructions (~5 KB). The research doc's "10-11K tok fixed per agent" (`:53`) undercounts by ~2×.
3. Three surfaces sit on both bars (broad cost × deep in the loop): the CLAUDE.md+MEMORY.md+roster spawn bundle, the on-demand `f9-template.md`/`validation-chain.md` pair (rent for the rest of the session once read), and Opus-pinned reviewer frontmatter (`effort: xhigh` on 3 of 6 Opus agents).
4. Cross-check: 4 confirmed (free wins shipped, xhigh violates the Opus 5 guide, Sonnet-5-as-literal-reader, one lever per diff), 2 confirmed with a dispute on mechanism (cache-prefix claim; "low for lookups").
5. New tension not in the mapping pass: the Opus 5 guide says *delete* verification scaffolding and *never* use subagents to verify (`model-migration.md:1072,1091`); the Fable 5.1 guide says fresh-context verifier subagents outperform self-critique (`:1503`). The chain is right for a Fable main and wrong for an Opus main.

## Horizontal

Bytes: measured where the research doc cites them, else lines × ~60 B. "Freq" = when it is billed.

| Surface | file:line | ~Bytes | Who loads | When / freq | Kind |
|---|---|---|---|---|---|
| Project CLAUDE.md | `CLAUDE.md` | 9,781 | main + every non-Explore subagent | session start / spawn; cache-read every turn | doctrine |
| Global CLAUDE.md + RTK.md include | `~/.claude/CLAUDE.md`, `dotfiles/claude/RTK.md` | 11,284 + 964 | same | same | doctrine |
| `~/.claude/rules/code-review-graph.md` | no `paths:` → always | ~1,200 | main + subagents | session start | doctrine |
| `~/.claude/rules/test-honesty.md` | `paths:` incl. `**/*.py` | ~2,400 | whoever Reads a .py | per matching read | doctrine |
| MEMORY.md (auto-memory index) | `~/.claude/projects/.../memory/MEMORY.md` | ~20,000 (cap 25,600) | main + subagents (present in this agent's context) | session start / spawn | doctrine |
| Output style crisp | `output-styles/crisp.md:1-261`, `force-for-plugin: true` | ~15,500 | main (subagent unverified) | session start | doctrine |
| METHODOLOGY.md via doctrine-bootstrap | `hooks/session/doctrine-bootstrap.sh:8-12`, `hooks.json:6-14` | 17,518 | main only (SessionStart never reaches subagents; ponytail-subagent.js:4 states the same) | session start, tier minimal | doctrine |
| memory-health-nudge / injection-budget-check | `hooks.json:28-48`; cap 24,576 B at `injection-budget-check.sh:28` | 0 clean, ≤2,600 dirty | main | session start | advisory |
| command-root-anchor | `hooks.json:17-26` | 0 (env file) | main | session start | telemetry |
| flow-nudge | `hooks.json:52-62`; `flow-nudge.sh:188-200,408-419` | ~600-1,100 when firing (+ jq pass over 37K-row costs.jsonl) | main | per prompt | advisory |
| jira-route-nudge | `hooks.json:64-74` | ~400 when firing | main | per prompt | advisory |
| PreToolUse dispatcher → 17 gates | `hooks.json:78-88`, `pretooluse-table.json:1-104` | 0 on allow; ~300-500 stderr per deny/ask | main + subagents | per tool call | gate |
| main-exec-guard (2 legs) | `pretooluse-table.json:9-25`, `main-exec-guard.sh:63-64` (opt-in `MH_MAIN_EXEC_GUARD=1`) | 0 / ~450 per deny (`:680-686`) | main only (exits 0 on `agent_id`, `:81-83`) | per Write/Edit/Bash | gate |
| agent-recursion-guard, task-complete-separation | `pretooluse-table.json:45-61` | 0 / ~300 per deny | subagents only | per Agent/TaskUpdate/Bash | gate |
| PostToolUse ×5 (skill telemetry, loop-repeat, compliance-audit, plan-review, gate-syntax) | `hooks.json:91-150` | 0 / ~300-600 when firing | main + subagents | per tool result | telemetry / advisory |
| PostToolUseFailure mcp-failure-nudge | `hooks.json:153-164` | 0 / ~300 | main + subagents | per MCP failure | advisory |
| Stop: cost-tracker (async), nudge-compliance-tracker, memory-audit-commit | `hooks.json:167-205` | 0 tokens (jq, writes JSONL) | main only | per stop | telemetry |
| Stop: stale-task-nudge (sync, tier strict) | `hooks.json:206-216` | 0 / ~300 | main | per stop | advisory |
| PreCompact state-flush, InstructionsLoaded journal, SessionEnd learn-nudge | `hooks.json:218-256` | 0 (stderr / file) | main | event | telemetry |
| Skill descriptions, mh | 45 skills; cap `DESC_MAX=1536`, ≤25 words | 7,121 (research doc `:42`) | main + every spawn | prefix, every turn | roster |
| Skill descriptions, all plugins (matt 25, ponytail 6, superset 10, diagram, bundled…) | observed in this agent's context | ~25,000 total | main + every spawn | prefix, every turn | roster |
| Agent descriptions (spawn list) | 12 mh + 6 native | ~3,000 (mh 2,509) | main + every spawn | prefix | roster |
| Agent frontmatter: model/effort/tools | `agents/*.md:1-14` | n/a | the spawned agent | per spawn | config |
| — opus + xhigh | plan-reviewer `:6,12`, blind-spot-hunter `:5,12`, security-reviewer `:6,12` | — | — | Opus rows $574 total, ≈$9-10/dispatch (research `:55`) | config |
| — opus + high/medium | code-architect, backend-architect (high); requirement-analyst (medium) | — | — | — | config |
| — sonnet | typescript-reviewer, nextjs-reviewer, summarizer (medium); silent-failure-hunter, performance-optimizer, ideate-critic (high) | — | — | — | config |
| `skills:` preload on 9 agents | e.g. `security-reviewer.md:10-11` | +3-10 KB skill body each | that agent | per spawn | doctrine |
| orchestrate SKILL.md | `skills/workflow/orchestrate/SKILL.md:1-144` | ~11,000 | main | on invocation, then rent | doctrine |
| orchestrate reference.md (post-split index + history) | `reference.md:1-309`; `:3` "load one file per phase" | ~28,000 | main | on Read, then rent | doctrine |
| f9-template.md | `:1-111` | ~10,000 | main | before each non-trivial dispatch, then rent | doctrine |
| validation-chain.md | `:1-121` | ~12,000 | main | before a chain, then rent | doctrine |
| routing.md | `:1-92` | ~13,900 | main | when triaging, then rent | doctrine |
| cost-tracker.sh + cost-report-dedup.js + cost-report SKILL | `cost-tracker.sh:59-81` (role tag), `cost-report-dedup.js:67-84` | 0 in-session; report ~1 KB when run | main | per stop / on demand | telemetry |
| ADR 0012 | `docs/research/adr-0012-...md` | ~9,500 | nobody by default (pointer from Rule 13) | on Read | doctrine |
| ponytail SessionStart | `ponytail/4.9.0/hooks/claude-codex-hooks.json:3-15` | ~4,500 | main | session start | doctrine (3rd-party) |
| ponytail SubagentStart | `claude-codex-hooks.json:16-27`, `ponytail-subagent.js:45-48` (no matcher → every subagent) | ~4,500 | every subagent | per spawn | doctrine (3rd-party) |
| ponytail UserPromptSubmit tracker | `claude-codex-hooks.json:28-39` | 0 | main | per prompt | telemetry |
| mattpocock-skills hooks | `mattpocock-skills/1.2.3/.claude-plugin/plugin.json` has no `hooks` key; `hooks/hooks.json` absent | 0 | — | — | none |
| qmd hooks | no `hooks/hooks.json` in `qmd/2.8.3` | 0; MCP instructions block ~1,000 | main + spawns | prefix | roster |
| MCP server instructions (Firecrawl, Notion, code-review-graph, mongodb, context7, qmd) | system prompt block | ~2,500 | main + spawns | prefix | roster |
| MCP tool schemas | ~200 names listed as deferred; schemas load only via ToolSearch | ~6,000 names; +1-3 KB per loaded schema | main + spawns | prefix / on ToolSearch | roster |

**Top 10 by bytes × frequency** (frequency weight: every-turn-in-every-context = 3, every-turn-main-only = 2, per-spawn-once = 1.5, conditional = 0.5):

| # | Surface | Bytes | Weight | Score | Note |
|---|---|---|---|---|---|
| 1 | Skill roster, all plugins | ~25,000 | 3 | 75,000 | 2/3 of it is non-mh plugins main can't trim |
| 2 | CLAUDE.md trio | 22,029 | 3 | 66,000 | global 11 KB is operator prefs a subagent rarely needs |
| 3 | MEMORY.md | ~20,000 | 3 | 60,000 | injected into subagents that never read memory |
| 4 | METHODOLOGY.md | 17,518 | 2 | 35,000 | main only; the one doctrine load that pays for itself |
| 5 | crisp.md | ~15,500 | 2 | 31,000 | voice doc; 261 lines for a "concise" register |
| 6 | reference.md (if read whole) | ~28,000 | 1 (main, once loaded) | 28,000 | `:3` now warns; SKILL.md:42 says don't read it for F9 |
| 7 | routing.md | ~13,900 | 1 | 13,900 | per triage |
| 8 | ponytail SubagentStart | ~4,500 | 3 (per spawn + rent) | 13,500 | only 3rd-party injection reaching subagents |
| 9 | validation-chain.md + f9-template.md | ~22,000 | 0.5-1 | ~13,000 | rent for the rest of the session after first read |
| 10 | Opus reviewer effort (xhigh) | n/a | per dispatch | $9-10 each | thinking is output-priced; 3 agents |

## Vertical

One task: "add `GET /health` + review it" (the worked example, `validation-chain.md:58-121`).

| Hop | +tokens main | +tokens subagent | Enforced | Advised only | If skipped | Cheapest correct alternative |
|---|---|---|---|---|---|---|
| 0 Session start | ~27K prefix (CLAUDE ×3, MEMORY, crisp, METHODOLOGY, roster, ponytail, MCP) | — | dispatch-single tiers (`dispatch-single.sh:40-43`) | — | — | `MH_HOOK_PROFILE=minimal` drops nudges, not doctrine |
| 1 Prompt → flow-nudge | ~250 tok nudge + delegation ratio (`flow-nudge.sh:193-198`) | — | fires deterministically | acting on it (22.6% compliance, ADR `:57-59`) | hoarding; but main-exec-guard now denies main writes anyway | with guard=1 the nudge is mostly redundant; keep the ratio line, drop the F9 pointer |
| 2 Rule 1/13/14 sizing | 0 (already in prefix, `METHODOLOGY.md:8-45,100-121,123-138`) | — | none (prose-only, `:98`) | all | over/under-planning | none cheaper; already paid |
| 3 `Skill(orchestrate)` + Step 0 grouping | +~2.7K (SKILL.md) +~3.5K routing.md if triaging (`SKILL.md:99-107,117`) | — | fan-out cap on Workflow tool only; Agent tool "lead is the clamp" (`SKILL.md:54,61`) | grouping | over-fragmentation (44→105 incident) | ≤3-file known fix → short-form F9 (`reference.md:198-205`), skip orchestrate |
| 4 F9 assembly | +~2.5K Read f9-template.md (rent thereafter) + 1-2K output for the brief | receives: system prompt + CLAUDE ×3 + MEMORY.md + roster + agent list + MCP + ponytail (~19-20K tok) + agent body + `skills:` preload + brief (~1K). Not: METHODOLOGY, crisp, conversation. Rent: fork 205K / gp 100K / Explore 67K per turn (`orchestrate-cost-optimization…:54`) | `[role:]` tag read by cost-tracker (`cost-tracker.sh:73-77`), fail-open | every slot; no-fork rule (`f9-template.md:85`); Explore for lookups (`:87`) | under-specified brief → guesses; fork = 2× rent | Explore for read-only; `general-purpose` only when Bash/Write needed |
| 5 Builder (gated) | AskUserQuestion turn ~300 | brief + ~20K fixed; sonnet/opus per frontmatter or inherit | irrecoverable, verifier-protect, agent-recursion-guard, task-complete-separation, worktree-guard | FILES YOU OWN, NEEDS-DECISION, Deadline | scope drift; nested spawns (blocked) | short-form F9 with `model: haiku` (`reference.md:199`; haiku spend $7.51 total → unused) |
| 6 Validator (ungated) | +~3K Read validation-chain.md; verdict Read ~300 | Opus xhigh reviewer ≈ $9-10; sonnet reviewer ≈ $2-4 | task-complete-separation (`pretooluse-table.json:45-49`) | verdict JSON contract, fail-closed shape check (`validation-chain.md:43-46`), scope check via `git diff --name-only` (`:44`) | unverified pass; maker grades itself | Opus 5 guide `:1014`: "stays accurate at lower effort… cheap fast pass" → `effort: high` first, measure |
| 7 Fixer (conditional, gated) | ~300 | same as Builder | gates as hop 5 | retry cap 3 (`validation-chain.md:22`, prose) | infinite fix loop | same-agent resume via SendMessage (`reference.md:204-205`) |
| 8 Re-validator (D-skip) | 0 when skipped | 0 when skipped; else one more reviewer | none — prose at `validation-chain.md:20` | skip rule | one extra $4-10 dispatch on a clean pass | rule already shipped; only run D on lens change |
| 9 Return → main re-read | ≤1-3K summary; `Read` verdict.md not transcript (`SKILL.md:37`) | — | none | Rule 13 "never pull a raw transcript" (`METHODOLOGY.md:110`) | 10s of K tokens of transcript in every later turn | Deliverable = path (`f9-template.md:33`) |
| 10 Stop → cost-tracker | 0 (async jq) | — | rows keyed (model, agent_type, role) `cost-tracker.sh:114-124` | — | no per-role data → 7c stays deferred | already in place; needs ≥10 orchestrate sessions (`cost-report-dedup.js:83`) |
| 11 cost-report | ~1K on demand | — | dedup latest-row rule `cost-report-dedup.js:26-37` | — | double-counted spend | — |

**Where the T intersects.** Three surfaces are both broad-cost and deep-in-the-loop, so they are the highest-leverage edits:

1. **The spawn bundle (CLAUDE.md trio + MEMORY.md + roster, ~67 KB).** Main pays it every turn and every subagent pays it at spawn and then every turn of its own. Hops 4-8 each re-bill it. The platform injects CLAUDE.md (sub-agents doc §4) and, by observation, MEMORY.md; the only lead-controlled lever is Explore for read-only work and shorter files. Global CLAUDE.md (11 KB of operator preferences, Thai recap rule, browser-automation notes) is the least useful 11 KB in every subagent.
2. **`f9-template.md` + `validation-chain.md` (~22 KB).** Loaded once in main and then rent for the rest of the session, while also shaping every brief. The split already cut ~11K tok/turn (research candidate #1); the next cut is a "short-form only" 1-page file for the fix-round path, since `reference.md:198` says most dispatches should be that shape.
3. **Opus reviewer frontmatter (`effort: xhigh` ×3).** One-line edits that change the price of hops 6 and 8 by ~2-3× per dispatch, with no eval on this repo (`f9-template.md:13`). Cheapest experiment: `effort: high`, then measure via the new `role` rows.

## Disputes

| Claim from the mapping pass | Verdict | Evidence |
|---|---|---|
| Free wins shipped in v0.68.625 | **Confirmed** on content; version label unverified in git | `.claude-plugin/plugin.json:4` = v0.68.625; cache `installed_plugins.json:157` = v0.68.625 at `92472600`; f9-template.md `:17,85,87` (role tag, no-fork, Explore), validation-chain.md `:20` (D-skip), cost-tracker.sh `:73-77`, cost-report-dedup.js `:70-84`. Snapshot HEAD `92472600` is labelled v0.68.624 in its message — the .625 bump commit was not in the snapshot; confirm with `git log -1` before citing the version. |
| No round-2 edit can break cache-prefix stability, since all targets are session-start content | **Confirmed for running sessions, disputed as the risk model** | A running session's context is frozen at spawn (`reference.md:275`); prompt-cache is per-session and any new session builds a fresh prefix, so edits never "break" a cache. The real hazard is the opposite: a same-version edit is a silent no-op in the cache (`CLAUDE.md` Cache-invalidation) — every round-2 edit needs a manifest bump. Also `f9-template.md`/`validation-chain.md` are not session-start content; they enter `messages` via Read, mid-session. |
| `xhigh` on the 3 Opus-pinned reviewers violates the Opus 5 guide | **Confirmed** | `model-migration.md:1018-1019`: "Start at `high` (the API default), then sweep down… `xhigh` and `max` are for measured wins, not a starting point"; `:1133` checklist; `:1014` reviewers "stay accurate at lower effort". Opus 4.8 guide `:854` says the same. No eval exists here (`f9-template.md:13`), so xhigh is exactly the unmeasured default the guide forbids. Caveat: `model: opus` resolves to whatever alias CC maps; if it is still 4.8, `:854` applies instead — same verdict. |
| `f9-template.md:13` "low for lookups" violates the Fable 5.1 guide (search skipped at low) | **Confirmed as doctrine risk, disputed as mechanism** | Guide `:1819-1821`: at `low`, Fable 5.1 "calls a search or retrieval tool less often… answers from memory more"; `:1823` same for the crop tool. A "pure lookup" that must grep is the case that breaks. But `f9-template.md:13` also says the Agent tool has no `effort` param — "`Effort: low`" is prose, not `output_config.effort`, so the API-level behaviour the guide describes is not triggered; only a pinned agent's frontmatter sets effort, and none of the 12 is `low`. Fix: drop "low is acceptable" or pair it with the guide's "familiarity is not a reason to skip the search" line. Also note `:1461,1751`: low still "often exceeds prior models' xhigh", so `medium` for research dispatches (`:13`) is sound. |
| Shared prompts should be written for Sonnet 5 as the most literal reader | **Confirmed, with a tension to name** | Sonnet 5 `:1259`: "interprets prompts literally… state the scope explicitly"; Opus 4.7 `:724` likewise. 6 of 12 agents are Sonnet-pinned. Tension: Fable 5.1 `:1504,1538` says over-prescriptive prompts *reduce* quality — "de-prescribe". Resolution: explicit scope and goal (literal-safe), no step enumeration (Fable-safe). The F9 slots already fit that shape. |
| One lever per diff | **Confirmed** | claude-api cost-optimize contract ("any lever that earns a place becomes its own diff"), Rule 14 traceability (`METHODOLOGY.md:132`), memory "re-review after every fix round" (9 confirmations). Cost: each diff needs its own version bump. |
| (new) Verification chain vs Opus 5 guide | **Flag** | Opus 5 `:1072,1091,1140`: delete verification scaffolding, "do NOT use subagents for review/verification". Fable 5.1 `:1503`: "separate fresh-context verifier sub-agents tend to outperform self-critique"; `:1794` keep test-before-report. This session's main is Fable 5.1, so the Builder→Validator chain is aligned today; it inverts if main is ever run on Opus 5. Same split for delegation: Opus 5 `:1080,1144` says remove "delegate more" and add a cap; Fable `:1477` says let it delegate. `flow-nudge.sh`'s accelerator is Fable-correct and Opus-wrong. |

## Sources

- `hooks/hooks.json:4-256` (all events; no SubagentStart/SubagentStop); `hooks/pretooluse-table.json:1-104`; `hooks/dispatch-single.sh:18-45`; `hooks/dispatch-pretooluse.sh:20-27`
- `hooks/session/doctrine-bootstrap.sh:6-12`; `hooks/session/injection-budget-check.sh:24-28,45-50`; `hooks/session/memory-health-nudge.sh:105-121`
- `hooks/advisory/flow-nudge.sh:145-200,244-260,387-419`; `hooks/advisory/plan-review-nudge.sh:1-8`
- `hooks/gates/main-exec-guard.sh:61-83,236-241,680-687`; `hooks/gates/agent-recursion-guard.sh:106-139`
- `hooks/stop/cost-tracker.sh:31-37,59-81,98-156,158-186`; `hooks/stop/nudge-compliance-tracker.sh:44-60`
- `scripts/workflows/cost-report-dedup.js:23-37,62-84`; `skills/meta/cost-report/SKILL.md:15-41,63-77`
- `skills/workflow/orchestrate/SKILL.md:15-17,24-38,42,48,52-64,68-80,86-95,99-107,117`; `reference.md:3-8,14-41,53-94,156-166,168-191,198-238,275,283-286`; `f9-template.md:3,13,16-81,85-87,97`; `validation-chain.md:9,15-26,30-46,58-121`; `routing.md:9-47`
- `docs/METHODOLOGY.md:8-45,88-121,123-138`; `docs/research/adr-0012-main-plans-dispatches-never-executes.md:9-24,28-34,57-59,87-100,102-113`
- `docs/research/orchestrate-cost-optimization-2026-09-03.md:18-22,34-60,79-92`
- `output-styles/crisp.md:1-19,229-254`; `CLAUDE.md` (Cache-invalidation, Architecture); `~/.claude/CLAUDE.md:1-5`; `~/.claude/rules/test-honesty.md:1-10`; `~/.claude/rules/code-review-graph.md`
- `agents/{plan-reviewer,blind-spot-hunter,security-reviewer}.md:1-13` (opus/xhigh); `agents/{code-architect,backend-architect}.md:1-8` (opus/high); `agents/requirement-analyst.md:1-10` (opus/medium); `agents/{typescript-reviewer,silent-failure-hunter,nextjs-reviewer,performance-optimizer,summarizer,ideate-critic}.md:1-14` (sonnet)
- `.claude-plugin/plugin.json:4`; `~/.claude/plugins/installed_plugins.json:85-93,144-162`; `BOUNDARY.md:5-100,173`
- `~/.claude/plugins/cache/ponytail/ponytail/4.9.0/.claude-plugin/plugin.json:9`, `hooks/claude-codex-hooks.json:3-39`, `hooks/ponytail-subagent.js:3-11,45-48`
- `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/.claude-plugin/plugin.json` (no hooks); `~/.claude/plugins/cache/qmd/qmd/2.8.3/` (no hooks/hooks.json)
- claude-api skill, `shared/model-migration.md:724,736-753,854,864-876,1012-1021,1035-1104,1125-1150,1207-1235,1259,1461-1467,1477-1479,1503-1505,1538,1751,1794-1821,1823,1835`
