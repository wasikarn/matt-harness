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
precision (see below), and **9** genuine GAP rows surfaced across the 4 facet tables — no
architectural surprises. This is a maintenance-tier finding, not a rebuild.

**Correction (deep-audit pass, same day):** this section originally said "6 genuine, cheap gaps
surfaced," matching only the count of GAP rows that made it into the first "Build candidates"
list below — it undercounted the facet tables' own 9 GAP rows by 3, and 2 of those 3
(`/autocompact 200k`, the daily-commands cheat sheet) had silently disappeared between the facet
tables and that list with no decline rationale, unlike the third (haiku pin), which was
explicitly declined. A `/mh:deep-audit` pass caught this along with one shipped factual error
(see below) — both are now fixed; see "Build candidates" for the corrected, complete disposition
of all 9.

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

## Build candidates — disposition of all 9 GAP rows

Built into `docs/reference/env-vars.md`'s "Session-switch & turn-cost tips" section, with a
one-line cross-ref from `skills/meta/loop-design-check`:

1. **`/loop` cache-miss/full-turn-cost note** — sharpest gap, blog-sourced (see caveat below).
2. **`/effort` sticky + cache-keyed, Fast mode cache-breaking, `/model` mid-session caveat** —
   one bullet, cross-checked against `code.claude.com/docs/en/{commands,prompt-caching,model-config}.md`.
3. **`/clear` vs `/compact` decision rule** — cross-referenced to the pre-existing "Strategic
   Compaction" table instead of duplicating it.
4. **@-mention doctrine** — one line, blog-sourced (see caveat below).
5. **`/autocompact 200k`** — added on the deep-audit pass below; confirmed real syntax
   (`/autocompact [auto|<tokens>]`), originally flagged GAP in Facet C but dropped from the first
   build list without explanation.

Explicitly declined, with reasoning:

6. **`model: haiku` agent pin** — no current agent (all 17 are review/design/architecture) is a
   natural fit; YAGNI until a noisy/repeated job actually shows up.
7. **"Daily commands + quiet flags" cheat-sheet block in CLAUDE.md** (Facet B) — declined on the
   deep-audit pass: this is editorial polish, not an accuracy or functional gap. CLAUDE.md already
   documents its actual daily commands where they're relevant (Validation section, git-hooks
   section); consolidating them into one cheat-sheet block is a nice-to-have, not a defect, and
   risks becoming a second, driftable copy of commands documented elsewhere. Not built.
8. **CLAUDE.md-length tension** (Facet B) — real, but restructuring CLAUDE.md is a separate,
   larger decision, not a copy-edit.

**Not a GAP after re-verification, corrected:**

9. **`/rename` before `/clear`** — the original build shipped this as a real command; a
   `/mh:deep-audit` fact-check against `code.claude.com/docs/en/commands.md` found no `/rename`
   command exists. The actual mechanism is `/clear <name>` — the name is an argument to `/clear`
   itself, not a separate prior step. **This was a factual error shipped into the public repo's
   docs for one commit (`c7c1d81c`)** before this same-day correction. Fixed in place, same
   section.

**Sourcing caveat:** items 1 and 4 (`/loop`, @-mention) come from Anthropic's own blog post only.
A `claude-code-guide` fact-check against the public reference docs (`commands.md`,
`prompt-caching.md`) could not independently corroborate either mechanic (not contradicted,
just not documented at that level of detail) — item 9's `/rename` was the one blog claim that
*was* contradicted. The env-vars.md section now carries this caveat inline rather than presenting
1 and 4 with the same confidence as the cross-checked items.

## Fourth pass (2026-08-29, same day) — direct primary-source check on the remaining hedge

The deep-audit pass above relied partly on a subagent's report for the `/loop` and @-mention
"could not verify" verdict. Since that subagent's own read of `/rename` turned out to miss the
correct doc, its other verdicts got a second, direct check — `WebFetch` against 3 pages myself,
not delegated: `code.claude.com/docs/en/scheduled-tasks.md` (the actual `/loop` reference page,
confirmed real: "A scheduled prompt fires between your turns, not while Claude is mid-response,"
consistent with the hedge's claim but not spelling out the whole-conversation-resend or
cache-miss mechanics in those terms), `interactive-mode.md`, and `context-window.md` (both
describe `@` as triggering file-path autocomplete and document `Read`-tool costs generically, but
neither states the attach-without-Read or re-mention-duplicates mechanic). All three confirm the
hedge is still accurate — **no edit needed**, the existing "not independently spelled out" framing
in `env-vars.md` holds under direct primary-source check, not just the earlier subagent's read.

**Warp article, re-checked same session, no new build needed.** `ทบทวนอย่างละเอียดอีกครั้ง` covered
both this article and `warp-self-improving-agents-article-audit-2026-08-28.md` in one request.
That audit already went through 3 independent rounds (build → compliance-audit → third-pass
live-execution re-audit, 2026-08-28/29) and is settled. Per `advisor()`, a 4th full re-audit with
fresh forks would just re-derive the same evidence; instead, both built scripts were live-executed
again this session: `skills/meta/recursive-improve/scripts/gate-journal-summary.sh` (66 real
journal rows, exit 0) and `feedback-surface-scan.py` (real clustering output, exit 0), plus
`.github/workflows/harness-audit-drift.yml` confirmed still scheduled (`0 9 * * 1`). No drift.
No cross-interaction found with this article's cache/turn-cost lessons: `harness-audit-drift.yml`
is a GitHub Actions cron, not a Claude Code `/loop` session, so prompt-cache economics don't apply
to it.
