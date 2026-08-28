# Audit: "Maximizing the value of your Claude Code sessions" vs matt-harness

**Source:** Lydia Hallie, Anthropic blog, 2026-08-14 —
https://claude.com/blog/maximizing-the-value-of-your-claude-code-sessions
(local copy: `~/Downloads/Maximizing_the_value_of_your_Claude_Code_sessions.md`)

**Method:** 4 parallel forks, each auditing one facet against actual repo files (grep/read,
not memory recall): (A) input/output pricing + prompt-cache mechanics, (B) context-input
economy (CLAUDE.md/skills/@-mention/noisy output), (C) turn/session hygiene (/clear,
/compact, /loop), (D) subagent economy. Each classified every article claim as COVERED /
PARTIAL / GAP / NOT-APPLICABLE against the current repo, and cross-checked qmd (mh-research,
llm-wiki) for prior art.

## Verdict

Most of the article is already reflected in doctrine, several points exceed the article's own
precision (see below), and 6 genuine, cheap gaps surfaced — no architectural surprises. This is
a maintenance-tier finding, not a rebuild.

## Facet A — Input/output pricing & prompt caching

| Claim | Verdict | Evidence |
|---|---|---|
| Output ~5x input (prefill/decode) | COVERED | `hooks/stop/cost-tracker.sh` rates `i:2.0, o:10.0` = 5x |
| Cache read 0.1x, write up to 2x | COVERED | Same file: `cr:0.20`/`i:2.0`=0.1x; `cw:2.50`/`i:2.0`=1.25x (real Sonnet-5 number, not the article's generic "up to 2x") |
| `MAX_THINKING_TOKENS=0` | COVERED, more precise | `docs/reference/env-vars.md:62` notes it's a no-op on Sonnet 5 (adaptive-reasoning models ignore it) — the article doesn't caveat this |
| Cache TTL 1hr/5min, `ENABLE_PROMPT_CACHING_1H` | COVERED, more precise | `env-vars.md:65` flags TTL is billing-mode-dependent (drops to 5min once a subscription draws on usage credits, not just "on an API key") — more precise than the article, and more precise than this session's own `ScheduleWakeup` tool description |
| `/compact` breaks cache, `/rewind` doesn't | COVERED, different framing | `METHODOLOGY.md:106-107` documents `/rewind` vs `/compact` for *restorability*, not cache-cost — the article's angle isn't stated anywhere |
| `/effort` sticky + cache-keyed | **GAP** | Zero doctrine |
| Fast mode breaks cache | **GAP** | Zero doctrine |
| `/model` mid-session switch re-prefills at full price | **PARTIAL** | `env-vars.md:68-73` covers *when* to switch models, silent on the re-prefill cost of doing it mid-conversation |

## Facet B — Context-input economy

| Claim | Verdict | Evidence |
|---|---|---|
| Skill description token budget | COVERED | `docs/skill-authoring-conventions.md`, enforced by harness-audit check 34 (≤25 words) |
| Noisy-command-output rewriting hook | COVERED (external) | User's global RTK proxy (`~/.claude/settings.json`, `rtk hook claude`) — confirmed wired, transparently rewrites `git status`→`rtk git status` etc. Closer real match to the article's "small hook" than anything matt-harness itself ships. |
| CLAUDE.md = specific instructions, workflow → skills | PARTIAL | Skills correctly use progressive disclosure; CLAUDE.md itself (489 lines) carries some accumulated workflow doctrine the article's own advice would push into a skill — self-referential tension, not a clean pass/fail |
| `/mcp` to disable unneeded servers | N/A | Native CC feature |
| @-mention discipline (attach without Read, don't re-mention) | **GAP** | Zero hits anywhere in repo docs |
| "Daily commands + quiet flags" in CLAUDE.md | **GAP** | No cheat-sheet block; closest is the Validation section, not a "type this daily" list |

## Facet C — Turn/session hygiene

| Claim | Verdict | Evidence |
|---|---|---|
| "Compact instructions" section in CLAUDE.md | COVERED | `CLAUDE.md:486`, exact heading the article recommends — traced to `docs/research/official-docs-best-practices-prompt-library-costs-audit-2026-08-20.md` |
| `/compact <instructions>` steers what's kept | COVERED | `METHODOLOGY.md:107`, `env-vars.md:104` |
| `/clear`-new-task vs `/compact`-same-task decision rule | **GAP** | Only `/compact` is discussed; no explicit "which one, when" |
| `/rename` before `/clear` | **GAP** | Zero mentions |
| `/autocompact 200k` on 1M models | **GAP** (adjacent partial) | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` exists but compacts *earlier* by %, not the 1M-model absolute-floor safety net the article names |
| `/loop` = full turn, carries whole conversation, >1hr = cache miss too | **GAP** — sharpest finding | No local doctrine. `hooks/advisory/loop-repeat-nudge.sh` catches spinning (unrelated mechanic); `skills/meta/loop-design-check` covers goal-decidability/Goodhart, zero mention of token/cache cost. `ScheduleWakeup`'s own tool description already states the 1hr TTL and non-polling guidance, but that only covers the newer dynamic-loop mechanism, not classic `/loop` |
| `mh:context-budget` scope | N/A to this facet | Confirmed by reading SKILL.md: static load only, explicitly excludes "one-off response trimming" |

## Facet D — Subagent economy

| Claim | Verdict | Evidence |
|---|---|---|
| Subagent = own context window, main thread untouched | COVERED | `METHODOLOGY.md:98` Rule 13 |
| Pays off for high-output-you-don't-need jobs | COVERED | `METHODOLOGY.md:101` "big output → file, return the path" — same principle, file-based |
| Small job = overhead, don't over-spawn | COVERED | `orchestrate/SKILL.md:60-61` fan-out cap 5, "prefer 2-4, 5+ ungrouped = consolidate signal" |
| "Main session only gets back what subagent chose to report" | COVERED, exceeds article | CLAUDE.md's "Same crux, N-worker fan-in" — treats the synthesis step as a code-vs-prompt reliability question, not just a fact |
| Give noisy repeated job `model: haiku` | **GAP, not worth building blind** | Grepped all 17 `agents/*.md`: zero `haiku` pins (10 sonnet, 7 opus). `CLAUDE_CODE_SUBAGENT_MODEL=inherit` confirmed live, so pins would actually take effect. But none of the 17 agents fit a haiku-tier noisy job (all are review/design/architecture); no repo pain point has surfaced yet. |

## Build candidates (ranked, all cheap doc-only edits)

1. **`/loop` cache-miss/full-turn-cost note** — sharpest gap. Add to
   `skills/meta/loop-design-check` or `docs/reference/env-vars.md`: classic `/loop` fires as a
   full turn carrying the whole conversation every time, and a >1hr gap is also a cache miss —
   run it from a fresh session/terminal instead of the one you're working in.
2. **`env-vars.md` token-cost table**: add `/effort` (sticky, cache-keyed) and Fast mode
   (cache-breaking) as rows; add a one-line caveat to the existing `/model` section that a
   mid-session switch re-prefills the whole conversation at full price — cheap at session start
   or right after `/clear`, expensive mid-conversation.
3. **`/clear` vs `/compact` decision rule + `/rename` tip** — one line each, likely in
   `docs/reference/env-vars.md` alongside the existing `/compact` coverage.
4. **@-mention doctrine** — one line: `@file` attaches without a Read call and only needs
   mentioning once per conversation.
5. Not recommended: haiku model-tier pin (no current agent is a natural fit — YAGNI until a
   noisy/repeated job actually shows up) and the CLAUDE.md-length tension in facet B (real, but
   restructuring CLAUDE.md is a separate, larger decision, not a copy-edit).

Candidates 1-4 touch `docs/reference/**` and/or `skills/meta/loop-design-check` — both inside
the version-bump gate (runtime-loaded surfaces), so shipping them requires the usual
`plugin.json`/`marketplace.json` bump, not just a content edit.
