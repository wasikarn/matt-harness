---
name: tech-humanize
description: "Humanize dev/tech writing (English/Thai) to sound natural, not AI-generated. Use when editing chat, standup/PR/commit, UI copy, or prose/ticket/spec/ADR, or say แก้ให้เป็นธรรมชาติ. Don't use for translation."
model_limitation: "lexical-tell catalog currency (assumes current-gen LLM output still carries the enumerated tells — em dash, delve, rule-of-three, etc. — which research confirms shift/decay across model generations; re-validate at each quarterly cadence pass, docs/harness-decay-cadence.md)"
metadata:
  origin: kbg-native
  restored-from: "c452102 reset (last shipped v0.2.109, df012d8, 2026-06-20)"
model: inherit
effort: high
---

# Tech-Humanize: Remove AI Writing Patterns from Dev/Tech Writing (EN + TH)

You edit dev/tech writing — monolingual English, monolingual Thai, or Thai↔English code-switching (Thai particles next to English tech terms) — so it reads human, not AI-generated. Built on Wikipedia's "Signs of AI writing" (WikiProject AI Cleanup) plus Thai-specific register/terminology/anti-fabrication rules.

## The loop

Run these gates in order. Each links to its detail.

1. **Register gate** — pick genre + language before scanning (see [§0](#0-register-and-language-gate)). Skipping this is the #1 cause of AI-sounding output.
2. **Grit gate** — deletion alone still reads AI. Plan what concrete specifics and point of view the rewrite will carry (see [Grit Gate](#the-grit-gate)).
3. **Scan** — run the draft against the [pattern cue-sheet](#pattern-cue-sheet) (30 universal tells). **Thai drafts: load `patterns-thai.md` (§31–§42) first** — universal tells can't catch terminology drift/calque (§31), a Thai-only class (confirmed-incident detail there). Cheap to load; the miss isn't.
4. **Rewrite, don't delete** — replace AI-isms with natural alternatives; keep paragraph count and core meaning. Match the user's voice if they gave a sample (see [Voice](#voice)).
5. **Final pass** — re-read aloud; vary sentence length; **no em dashes** (cue #14); confirm the grit gate actually landed.

Anti-fabrication is a hard constraint throughout: for any fact you cannot verify right now, drop it (default T1 DROP; see `patterns-thai.md` §32.1). Don't invent specifics to fake grit.

## §0. Register and language gate

Pick genre **and** language (orthogonal — choose each independently; match what the reader actually reads, don't auto-mix).

| # | Genre | Example | English ~% | Particle default | Apply |
|---|-------|---------|-----------|------------------|-------|
| **A** | Chat / LINE | chat, comment | 10–25% (TH) / 100% (EN) | 555 / ค่ะ / ครับ ตาม gender / none (EN) | §34, §38 |
| **B** | Standup / PR / commit | daily standup, PR desc | 40–60% (TH) / 100% (EN) | ไม่มี particle บน terse items / none (EN) | §35, §38 |
| **C** | UI / error / notification | payment decline, 404 | 20–35% (TH) / 0% (EN) | ค่ะ/ครับ opener เดียว / none (EN) | §36, §36.1, §38 |
| **D** | Prose / blog / strategy / ADR | บทความ, brief | 30–50% (TH) / 100% (EN) | ไม่มี particle ทื่อๆ / none (EN) | §37, §38 |

**High cognitive load (hotfix, incident, alert)** → write monolingual, don't force mixing. EN-only audience → monolingual EN. (§34–§38 detail in `patterns-thai.md`.)

**Terminology:** default **keep English** in internal dev (commit, merge, PR, staging, develop, production); user-facing → translate/transliterate per RTGS; don't romanize Thai internally. Decision tree: §31 in `patterns-thai.md`.

**Typography:** Thai has no inter-word spaces (space = phrase/sentence break); 1 space around English when it helps; glued to identifiers/numbers is fine (`PR #82`, `v1.11.37`); Arabic numerals (`2026`, `77%`), not Thai numerals.

**Calques to kill:** `ถือไว้`→`ยังไม่ปล่อยขึ้น prod / พักไว้`; `ดัน`→`merge / นำขึ้น prod`; `ระบบล้ม`→`ระบบล่ม / down` (§31 has worked before/after). An unverified completion claim (`ทดสอบบน staging ผ่าน`) is a fabrication-boundary case, not a calque — see below, §32.

## The Grit Gate

**Removing the 30 patterns gets you to "clean," not "human."** Clean-but-neutral text sits in the safe middle — itself an AI tell (a skeptical reader scores it ~30/100 AI, not 0). To clear the middle, every rewrite must ALSO do both:

1. **Surface the grit.** Pull the concrete specifics a real author includes and an LLM rounds off: ticket/PR refs, file/module names, the actual cause (race condition, double-submit, null from an API), real numbers, the one weird detail. Grit is what reads human, not the absence of fluff.
2. **Commit to a point of view.** Say which part matters and what you'd actually do — neutral "balanced" reporting is the AI default. (POV only where the genre allows it — blog/standup/ADR yes; legal/spec/reference stays plain, and plain *is* the human voice there.)

**Fabrication boundary (don't fake grit).** Never invent a ticket, metric, cause, or source — pull specifics only from the source or context. **Pure puffery with nothing to pull → say so or ask for specifics; a polished, confidently-empty paragraph is still AI.**

**A single unverifiable claim inside an otherwise real draft differs from a hollow source** — don't drop it (deletes what the user told you) or invent a replacement (fabricates evidence). Use Tier-2 hedge (§32.1): keep the claim, strip unbacked certainty-intensifiers (`เรียบร้อยแล้ว`, "completely," "fully"), and ask what was checked where the genre allows. (§32.1's 3-tier logic — drop/hedge/cite — applies in any language; `patterns-thai.md` has the worked table with Thai examples, but the English equivalent is the same shape: unverifiable → drop, heard-but-unconfirmed → hedge once, sourced → cite.)

Worked "soulless vs alive" example (same facts, neutral report → real voice): `examples.md` §
Grit Gate: Soulless vs Alive.

## Voice

Given a writing sample, match **their** voice (length, formality, paragraph openers, punctuation, recurring phrases) — don't just delete AI patterns, replace with the sample's own. Short sentences stay short; `ของ`/`อัน` stays, no upgrade to `องค์ประกอบ`/`ส่วนประกอบ`.

No sample → the Grit Gate default: opinionated where the genre allows, varied rhythm (short sentence; then a longer one that arrives somewhere; alternate), and let some mess in (asides, half-formed thoughts read human; perfect symmetry reads algorithmic).

## Pattern cue-sheet

Scan for these 30 universal tells (all languages). **Load `patterns-universal.md`** when you need the worked before/after for a pattern or aren't sure how to fix a detected tell. Thai-only tells (§31–§42) are in `patterns-thai.md`.

| # | Pattern | Cue (EN / TH) | Fix |
|---|---------|---------------|-----|
| 1 | Significance/legacy puffery | testament, pivotal moment, evolving landscape / ถือเป็นก้าวสำคัญ, สะท้อนถึงความสำคัญ | Cut the importance claim; state the fact |
| 2 | Notability / media name-drops | independent coverage, active social media presence | Keep only sourced, specific claims |
| 3 | -ing pseudo-depth tails | highlighting, ensuring, reflecting, fostering / ซึ่งสะท้อนถึง, เพื่อส่งเสริม | Delete the trailing clause or make it a real fact |
| 4 | Promo / ad language | vibrant, nestled, in the heart of, breathtaking / งดงามตระการตา, ตั้งอยู่ใจกลาง | Neutral tone; concrete detail |
| 5 | Vague attribution / weasel | experts argue, observers cited, reports say / ผู้เชี่ยวชาญบางท่าน, รายงานระบุ | Name the source or cut |
| 6 | "Challenges & future" formula | Despite challenges, Future Outlook / ท่ามกลางความท้าทาย, อนาคตของ | Replace with specific facts/dates |
| 7 | AI-vocab words | delve, crucial, tapestry, underscore, intricate, landscape / อันที่จริง, ภูมิทัศน์, เน้นย้ำ | Plain synonyms |
| 8 | Copula avoidance | serves as, stands as, boasts, features / ทำหน้าที่เป็น, ถือเป็น | Use is/are · คือ/เป็น |
| 9 | Negative parallelism / tailing negation | not only…but, it's not just…it's / ไม่ใช่แค่…แต่ยัง, ไม่ต้องเดา | One real positive clause |
| 10 | Rule of three | forced triads "X, Y, and Z" / สองพอ สามเกิน | Two if there are two; cut the forced third |
| 11 | Elegant variation | protagonist→main character→central figure | Reuse the same noun |
| 12 | False ranges | "from X to Y" off-scale / ตั้งแต่…จนถึง, จาก…สู่ | List the items plainly |
| 13 | Passive / subjectless | "results are preserved automatically, no config needed" | Name the actor; active voice |
| 14 | Em dashes | `—` used for asides | Period / comma / colon / parens (en-dash ranges `40–60%` are fine) |
| 15 | Boldface overuse | mechanical `**bold**` | Drop decorative bold |
| 16 | Inline-header lists | `- **X:**` that restates X | Prose or plain bullets |
| 17 | Title case headings | `## Strategic Negotiations And` | Sentence case |
| 18 | Emojis | 🚀 💡 ✅ on headings/bullets | Remove |
| 19 | Curly quotes | `“ ”` | Straight quotes `" "` |
| 20 | Chat artifacts | I hope this helps, Certainly!, let me know | Cut the assistant talk |
| 21 | Cutoff disclaimers / gap-fill | as of my last update, likely grew up, maintains a low profile / ณ ขณะนี้, น่าจะ, เชื่อว่า | Say what's unknown or cut; don't guess |
| 22 | Sycophancy | Great question!, You're absolutely right / คำถามดีมากค่ะ | Drop |
| 23 | Filler phrases | in order to, due to the fact that, at this point in time / เนื่องจากข้อเท็จจริงที่ว่า, ณ จุดเวลานี้ | Shorten |
| 24 | Excessive hedging | could potentially possibly / อาจจะเป็นไปได้ว่าน่าจะ | One hedge max |
| 25 | Generic positive conclusion | future looks bright, journey toward excellence | Concrete next fact, or cut |
| 26 | Hyphenated-pair overuse | data-driven, high-quality, end-to-end | Keep hyphen when attributive; drop in predicate |
| 27 | Authority tropes | the real question is, at its core, fundamentally / คำถามที่แท้จริงคือ, ในแก่นสำคัญ | Make the actual point |
| 28 | Signposting | let's dive in, here's what you need to know | Just say it |
| 29 | Fragmented headers | heading + one-line restating it | Delete the warm-up line |
| 30 | Diff-anchored writing | "this was added to replace…" | Describe the thing as it is |

## Don't over-edit

Look for **clusters**, not isolated tells — one em dash means nothing; em dashes + rule-of-three + *vibrant tapestry* + a "Conclusion" section is a confession. False-positive + "human writing" signs (incl. Thai notes): `patterns-universal.md` § Detection Guidance — read before gutting prose that might be human.

## Process and Output

1. **Identify every tell** — run the draft against the cue-sheet (§1–30) plus `patterns-thai.md` (§31–42) if Thai is present.
   Done when: every tell present is named, not just the first few obvious ones. (Failure modes in full: `examples.md` § Process Step Rationale.)
2. **Draft rewrite** — natural aloud, varied length, simple constructions (is/are/has · คือ/เป็น), correct register, grit gate applied.
   Done when: every tell named in step 1 is addressed, and everything step 1 cleared is left as written — a cleared term that now looks wrong mid-draft is new information, name it, don't quietly change it. (Failure modes in full: `examples.md` § Process Step Rationale.)
3. Ask **"what still makes this read AI?"** and answer in a few bullets — "nothing, looks good" grades your own work instead of scrutinizing it.
   Done when: at least one honest gap is named, even a minor one.
4. **Final rewrite** addressing them, zero em dashes (#14) — scan the text for `—`; a fixture once claimed dashes were cut while two remained. For each step-3 bullet, name the fix or write "kept as tradeoff: <reason>" (e.g., formal vocabulary the genre requires).
   Done when: every bullet from step 3 has a named resolution — fixed-where, or tradeoff-why. (Failure modes in full: `examples.md` § Process Step Rationale.)

Deliver: the draft, the brief "still-AI" bullets, the final rewrite, and (optionally) a short change summary.

## Bundled resources

Reference these on demand — each says when to load it (one level deep; read fully, don't preview).

- `patterns-universal.md` — full §1–§30 (problem + worked before/after) + complete detection guidance. **Load when:** you need the worked example/fix for a cue-sheet tell, or before deciding prose is AI vs human.
- `patterns-thai.md` — §31–§42 Thai-specific rules (terminology/calque, anti-fabrication tiers, connectives, register matrix, code-switching tells, AI-leaked closers). **Load when:** the draft has Thai or Thai↔EN. **Skip for monolingual English.**
- `examples.md` — worked examples A (TH chat), B (TH standup), C (TH UI), D (TH prose), E (EN UI), F (EN standup), G (EN prose). **Load when:** stuck, or to show the process.
- `references.md` — external sources (RTGS, Mozilla Thai Style Guide, W3C Thai Layout, PyThaiNLP, Conventional Commits Thai) + Thai+tech glossary + calque/typography cheat sheet. **Load when:** verifying transliteration or citations.

> Bilingual (EN + TH). Universal patterns (§1–§30) apply to both; Thai patterns (`patterns-thai.md`) apply only when Thai is present. No separate `patterns-en.md` — the universal catalog + EN examples cover the EN side.
