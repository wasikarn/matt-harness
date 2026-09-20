# Kyrox / Hanako "Loops and Graphs" Thai post — source audit (2026-09-20)

**Trigger:** the operator ran `/mattpocock-skills:research` on a Thai-language post presenting a
7-step framework for organizing AI coding agents around four terms — Agent (does the work), Loop
(verify-and-fix cycle with a stop condition), Harness (tools/scope/permissions), Graph (task
dependency ordering). The post states it was "เรียบเรียงแนวทางจากโพสต์ของ Kyrox และบทความ Loops
and Graphs ของ Hanako มาเป็นวิธีเริ่มต้น พร้อมตรวจเทียบกับบทความวิศวกรรมของ Anthropic" —
synthesized from a post by "Kyrox" and an article "Loops and Graphs" by "Hanako," cross-checked
against an Anthropic engineering article.

**Scope note:** this repo already has `loop-graph-engineering-trend-audit-2026-08-02.md`, which
read 10 X.com articles in the same Agent/Loop/Harness/Graph genre in full, including one by Hanako
(@hanakoxbt) — but that one was titled "Eval Engineering: build the gate that lets your agents
merge without you," not "Loops and Graphs." That prior doc audits kbg/mh's own architecture
against the trend; this doc instead checks the Thai post's specific source attributions and its
cross-check claim against Anthropic.

## 1. "Kyrox" — exhausted search, no source found

Search rounds actually run, each with a different angle, before closing this out:

1. **Plain / topical:** `"Kyrox" AI agent`, `Kyrox agent harness loop graph Claude Code post`,
   `"kyrox" "harness" OR "loop" OR "graph" Claude Code steps roadmap`.
2. **Handle-guess variants**, matching this genre's actual naming convention (other sources in the
   2026-08-02 audit use `@0xCodez`, `@0xCarnagee`, `@0xMorlex`, `@0xwhrrari`): `"0xKyrox" OR
   "@Kyrox"`, plus spelling variants `Cyrox`, `Kairox`.
3. **Crypto/NFT-adjacent angle** (the operator's specific hypothesis — a trading/dashboard hype
   account mistaken for a dev account): `Kyrox crypto NFT twitter handle`,
   `kyroxxxq agent loop harness graph coding bug fix`.
4. **Direct handle enumeration:** `"Kyrox" site:x.com OR site:twitter.com` — this is the only
   round that returned real accounts using the name.
5. **Newsletter/long-form:** `"Kyrox" substack OR medium OR newsletter agent engineering September
   2026`.
6. **archive.org**: attempted a Wayback Machine listing for `x.com/kyrox` — blocked, this
   environment's `WebFetch` cannot reach `web.archive.org` at all (tool error, not a content
   result). Not independently retried through another path.

Round 4 surfaced nine distinct real X accounts using some form of "Kyrox": `@vfx_kyrox` (VFX
editor), `@Kyroxbtw` (Twitch affiliate), `@KyroxYT` (YouTube creator, joined 2015), `@OhhKyrox`,
`@Kyrox7TV` (Fortnite creator), `@YoKyrox`, `@kyroxity` (fan-art account), a personal account at
`x.com/kyrox` ("Max 'Kyrox' D."), and `@kyroxxxq` — the one account with any AI/autonomous-systems
content, but on the topic of a "$239,000 business running entirely on a custom, autonomous
terminal" (a trading/dashboard-hype framing), not coding-agent verification loops. A follow-up
search for that account's content against this specific framework (round 3, second query) returned
nothing connecting it to Agent/Loop/Harness/Graph vocabulary. None of the nine accounts, and no
article or newsletter found in rounds 1, 3, or 5, discuss the coding-agent framework this Thai post
attributes to "Kyrox."

**Verdict: exhausted search, no source found.** Six independent search angles across two rounds of
this audit (spelling variants, handle conventions, a specific crypto/NFT hypothesis, direct handle
enumeration, newsletter search, and an attempted archive lookup) turned up no AI-agent-engineering
commentator, account, or article by this name. This is not "unconfirmed pending more digging" — it
is the practical ceiling of what web search can surface for this name. Treat any claim in the Thai
post sourced only to "Kyrox" as the composer's own synthesis or a mistranscribed name, not a
checkable citation.

## 2. Hanako's "Loops and Graphs" — real tweet, found

Found: [Hanako (@hanakoxbt) on X, status 2091864379314565333](https://x.com/hanakoxbt/status/2091864379314565333)
(same account as the 2026-08-02 audit's source 1, different post). Direct fetch returned HTTP 402
(X blocks unauthenticated fetch of full tweet text); the quote below is from a search engine's
indexed snippet of the tweet, not a live re-fetch:

> "Anthropic engineer: 'At Anthropic we don't write prompts anymore. We build loops and graphs.'
> in 32 minutes she shows how the Claude team builds systems that prompt themselves
> Prompts → Agents → Loops → Graphs — a loop finishes one unit of work without you, a graph decides
> [which units exist and turns every accepted one into a rule the next run inherits]"

This tweet is real and matches the Thai post's summary framing closely (Agent does the work, Loop
verifies/retries, Graph decides ordering). **But its central claim — that an Anthropic engineer
said this, on video, in 32 minutes — does not hold up against Anthropic's own primary sources**
(§3, §4 below).

## 3. The "Anthropic engineer" claim traces to a real talk — checked against its own transcript, not just a fact-check-of-a-fact-check

Pinned down the actual primary source, not a secondhand tweet description or a third party's
summary of it:

- **Talk:** "Build Agents That Run for Hours (Without Losing the Plot)," AI Engineer conference,
  uploaded May 2026.
- **Speakers, confirmed from the transcript itself:** Ash Prabaker (Engineer, Applied AI team,
  Anthropic) and Andrew Wilson (Solution Architect, Applied AI team, Anthropic, based in London).
- **YouTube upload:** [youtube.com/watch?v=mR-WAvEPRwE](https://www.youtube.com/watch?v=mR-WAvEPRwE)
  — also listed on Anthropic's own speaker page, [ai.engineer/speakers/andrew-wilson](https://ai.engineer/speakers/andrew-wilson).
- **Runtime, confirmed from the transcript timestamps:** 00:00–75:23, i.e. ~75 minutes.
- **Transcript source used:** [sozai.app/transcript/anthropic-workshop-build-long-running-agents](https://sozai.app/transcript/anthropic-workshop-build-long-running-agents/)
  — a third-party transcript host, not Anthropic's own posting, so this is as close to primary as
  this pass could get without watching all 75 minutes directly. Two separate targeted queries were
  run against it specifically to check the "graph" claim, not inferred from a summary:

  > "The word 'graph' does not appear anywhere in this transcript."
  >
  > Closest conceptual matches offered, both about harness/model co-evolution, not about a graph
  > layer: **[05:43]** "So really these things are like co-evolving together" (models and harnesses
  > evolving as unified systems); **[16:51]** "it's really evolving as the models change over time."

  A separate query for "graph", "prompt", "loop", "harness" independently returned zero "graph"
  hits and confirmed the talk's own harness-focused framing directly, e.g. **"the harness doesn't
  just disappear as the models get better. It's really evolving"** and **"the scaffolding um around
  the model. And we have the agent SDK which ships with all of the primitives."** No sentence
  resembling "we don't write prompts anymore" appears anywhere in the transcript either.

- **What the talk is actually about, confirmed independently of the "graph" question:** a
  GAN-inspired planner-generator-evaluator architecture for long-running single-agent harnesses —
  separate agents negotiate contracts before building, use Playwright to test live apps, and apply
  adversarial pressure so the evaluator doesn't rubber-stamp its own generator's work. This is a
  harness-and-adversarial-evaluation talk, not a "loops vs. graphs" comparison — a second, independent
  mismatch from the Thai post's framing, on top of the missing word itself.

This corroborates, from the primary transcript directly, the same conclusion a third-party
fact-check article ([aibuilderclub.com: "Anthropic Agents That Run for Days: What's Real"](https://www.aibuilderclub.com/blog/anthropic-agents-that-run-for-days))
had already reached secondhand: **"the word 'graph' appears zero times in the 75-minute
transcript."** Re-upload/summary channels grafted graph-engineering vocabulary onto the talk after
the fact; an unsourced "30% of code written by agentic graphs" claim circulating in the same wave
doesn't appear in the transcript either.

**Cross-check on internal consistency, not just against the real talk:** at least four different
X accounts describe what is nominally the same "Anthropic engineer video," with mutually
incompatible details:

| Account | Claimed length | Claimed speaker |
|---|---|---|
| Hanako (@hanakoxbt) | 32 minutes | "she" |
| darkzodchi (@zodchiii) | 34 minutes | "he" |
| Codez (@0xCodez) | "1-hour course" | "senior engineer" |
| Anatoli Kopadze | 40 minutes | "Head of Claude Code" |

None of these match the real talk's actual length (75 minutes) or match each other. This is the
same pattern the 2026-08-02 audit already flagged for this genre: "argued, not verified" framing
presented as if it were reported fact. **Verdict: the "Anthropic engineer says we build loops and
graphs" claim is a viral mischaracterization, not a citable Anthropic statement.**

## 4. Anthropic's actual first-party "loop" content: loops only, no graph, no harness

Two genuine Anthropic/Claude sources on this exact topic exist and were fetched directly:

- [claude.com/blog/getting-started-with-loops](https://claude.com/blog/getting-started-with-loops)
  — "Loop Engineering: Getting Started with Loops," by Delba de Oliveira and Michael Segner,
  published 2026-06-30. Defines a loop as **"agents repeating cycles of work until a stop condition
  is met,"** and covers four loop types (turn-based, goal-based, time-based, proactive). **No
  mention of "graphs" or "harness" anywhere in the article.**
- [anthropic.com/webinars/startup-builds-getting-started-with-loops](https://www.anthropic.com/webinars/startup-builds-getting-started-with-loops)
  — companion webinar, presented by Mark Nowicki (Anthropic Applied AI), 45 minutes, 2026-07-24.
  Same four-loop-type scope. **No mention of graphs.**

**Verdict: the "Graph" and "Harness" layers in the Thai post's framework are not Anthropic
vocabulary.** They come from the community-coined taxonomy already documented across the 10
sources in `loop-graph-engineering-trend-audit-2026-08-02.md` (e.g. source 6, "HARNESS = ENVIRONMENT
/ LOOP = FEEDBACK / GRAPH = FLOW"), not from anything Anthropic has published under its own name.

## 5. Where the Thai post's actual content does hold up: Anthropic's "Building Effective Agents"

The post's substance — independent of the disputed Kyrox/Hanako attribution — maps well onto a
different, unambiguously real Anthropic engineering article:
[anthropic.com/engineering/building-effective-agents](https://www.anthropic.com/engineering/building-effective-agents).
Each row below quotes the Thai post's own words verbatim next to the Anthropic article's exact
wording, so the match can be checked directly rather than taken on trust:

**Step 1** — start with one small, checkable task.
> Thai post: *"เริ่มจากงานเดียว เช่น แก้บั๊กหนึ่งจุด ระบุข้อมูลตั้งต้น ผลลัพธ์ที่ต้องการ และไฟล์ที่แก้ได้ให้ชัด"*
> ("Start with a single task, e.g. one bug fix. State the starting input, the wanted output, and
> exactly which files may change.")
>
> Anthropic: *"finding the simplest solution possible, and only increasing complexity when
> needed."*

**Step 2** — set pass/fail criteria before starting.
> Thai post: *"...ต้องมีวิธีตรวจที่สามารถตัดสินว่า 'ไม่ผ่าน' ได้จริง คำตอบว่า 'เรียบร้อยแล้ว' ยังไม่ใช่หลักฐานครับ"*
> ("...there must be a check that can actually rule 'fail' — an answer of 'it's done' is not yet
> evidence.")
>
> Anthropic: *"the key to success, as with any LLM feature, is measuring performance and iterating
> on implementations"*; for agents specifically, *"extensive testing in sandboxed environments,
> along with the appropriate guardrails."*

**Step 3** — loop needs a stop condition (rounds/time/cost cap).
> Thai post: *"...พร้อมกำหนดเพดานจำนวนรอบ เวลา หรือค่าใช้จ่าย เพื่อไม่ให้วนแก้ไม่จบ"*
> ("...also set a ceiling on round count, time, or cost, so the fix loop doesn't run forever.")
>
> Anthropic: agents *"often terminate upon completion, but it's also common to include stopping
> conditions (such as a maximum number of iterations) to maintain control."*

**Step 5** — deterministic script for fixed-rule sub-tasks.
> Thai post: *"งานที่มีกติกาตายตัว เช่น เรียงรายการหรือลบข้อมูลซ้ำ ใช้สคริปต์ธรรมดาได้"*
> ("Tasks with fixed rules, like sorting a list or deduplicating, a plain script can do.")
>
> Anthropic: prompt-chaining workflows let you *"add programmatic checks... on any intermediate
> steps to ensure that the process is still on track."*

**Step 7** — human approval before irreversible actions.
> Thai post: *"ให้คนตรวจและอนุมัติก่อนงานที่ย้อนกลับยาก เช่น ลบข้อมูล เปลี่ยนข้อมูล Production หรือทำธุรกรรม ไม่ใช้คะแนนความมั่นใจของ AI แทนหลักฐาน"*
> ("Have a person review and approve before hard-to-reverse work — deleting data, changing
> production data, or transactions. Don't use the AI's own confidence score as a substitute for
> evidence.")
>
> Anthropic: *"human review remains crucial for ensuring solutions align with broader system
> requirements"*; agents *"pause for human feedback at checkpoints or when encountering
> blockers."*

**Verdict: these five steps are accurate, well-grounded restatements of a real Anthropic source** —
just not the source the post names. The post's citation ("บทความวิศวกรรมของ Anthropic," singular,
no title given) is ambiguous enough that it could mean either this article or the loops blog in
§4; the content matches this one, not that one.

Steps 4 and 6 (drawing a dependency graph from data hand-offs; returning only the broken piece with
expected/actual/evidence/scope) have no equivalent in either real Anthropic source — they belong to
the community graph-engineering vocabulary from §4/§3, argued but not Anthropic-attributed.

## Bottom line

- **"Kyrox"**: unconfirmed attribution — no matching source found after a real search effort.
- **Hanako's "Loops and Graphs" tweet**: real post, real account, but its own central claim (an
  Anthropic engineer describing "loops and graphs" on video) is a viral mischaracterization of a
  real talk that never uses the word "graph" — independently confirmed by a third-party fact-check
  and by internal inconsistency across four retellings of the same supposed video.
  Same account, different article, as `loop-graph-engineering-trend-audit-2026-08-02.md` source 1.
- **"Cross-checked against Anthropic's engineering article"**: partially true. Anthropic's real
  first-party loop content (§4) says nothing about graphs or harnesses. But five of the post's
  seven steps do genuinely, accurately restate Anthropic's separate "Building Effective Agents"
  article (§5) — the strongest, cleanest verified claim in the whole chain, just attached to the
  wrong named source.
- **Net assessment**: the post's practical advice (small scoped tasks, pass criteria before
  starting, bounded loops, human gates on irreversible actions) is sound and traceable to a real
  Anthropic source. The specific attribution to "Kyrox" and to an Anthropic engineer's video is not
  supportable as written.

## What this repo could learn — flagged, not fixed

`loop-graph-engineering-trend-audit-2026-08-02.md` §1 scored kbg/mh's Graph layer "thin" against a
community taxonomy (source 6: "HARNESS = ENVIRONMENT / LOOP = FEEDBACK / GRAPH = FLOW") and named
`orchestrate`'s Builder→Validator→Fixer→Re-validator chain as a real multi-node flow enforced by
prompt discipline, not a tool-validated schema. This pass's verification against actual Anthropic
primary sources sharpens that finding in two specific ways — neither is a proposal to build
anything, both are evidence-status corrections:

1. **The taxonomy behind "Graph — thin" was never an Anthropic-endorsed vocabulary, even in the
   one real Anthropic talk that comes closest to the topic.** §3's primary-transcript check found
   the actual long-running-agents talk (Prabaker & Wilson) doesn't use "graph" once in 75 minutes —
   it uses "harness," "loop," and "scaffolding," and its multi-agent pattern is a
   planner-generator-evaluator/GAN-inspired contract negotiation, not node/edge graph language.
   This doesn't shrink or dissolve the 08-02 finding (orchestrate's chain still lacks mechanical,
   schema-validated flow control) — it means citing "Anthropic does graph engineering" as
   motivation for closing that gap would itself repeat this post's exact attribution error. The
   gap is real; its best available justification is the community taxonomy on its own terms, not
   borrowed Anthropic authority.
2. **A concretely real, Anthropic-sourced pattern newly available as evidence: adversarial,
   independent evaluation via negotiated contracts, not self-grading.** §3's transcript confirms
   the real talk's core technique — "apply adversarial pressure to avoid rubber-stamping" via a
   separate evaluator that negotiates a contract with the generator before work starts — as an
   actual Anthropic Applied-AI-team practice, not a tweet paraphrase. This is closer to validating
   kbg/mh's own existing "validator must stay independent, never collapse into the builder" rule
   (already named in 08-02 §3.1 from the `superpowers` cross-repo check) than to validating a graph
   layer specifically. It's a second, independent, and more solidly-sourced confirmation of a
   principle mh already holds, not new information pointing at a new gap.
3. **§5's "Building Effective Agents" matches are a cleaner, unambiguous-source instance of the
   same discipline `orchestrate`'s already-shipped fix (v0.68.135/v0.68.204, per 08-02 §3's
   summary table) targets.** The prompt-chaining quote — "add programmatic checks... on any
   intermediate steps to ensure that the process is still on track" — is exactly the
   schema-validated, tool-call-layer verification `orchestrate`'s Structured Verdict shape already
   implements. Worth keeping as the citation of record for that design choice going forward: it's
   real, first-party, and unambiguous, unlike the Hanako/Kyrox chain this post leans on.
