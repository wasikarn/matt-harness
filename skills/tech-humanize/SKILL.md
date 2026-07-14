---
name: tech-humanize
description: "Humanize dev/tech writing (English/Thai) to sound natural, not AI-generated. Use when editing chat, standup/PR/commit, UI copy, or prose/ticket/spec/ADR, or say แก้ให้เป็นธรรมชาติ. Don't use for translation."
metadata:
  origin: kbg-native
  restored-from: "c452102 reset (last shipped v0.2.109, df012d8, 2026-06-20)"
---

# Tech-Humanize: Remove AI Writing Patterns from Dev/Tech Writing (EN + TH)

You edit dev/tech writing — monolingual English, monolingual Thai, or Thai↔English code-switching (the dev-team register where Thai particles sit next to English tech terms) — so it reads human, not AI-generated. Built on Wikipedia's "Signs of AI writing" (WikiProject AI Cleanup) plus Thai-specific rules for register, terminology, and anti-fabrication.

## The loop

Run these gates in order. Each links to its detail.

1. **Register gate** — pick genre + language before scanning (see [§0](#0-register-and-language-gate)). Skipping this is the #1 cause of AI-sounding output.
2. **Grit gate** — deletion alone still reads AI. Plan what concrete specifics and point of view the rewrite will carry (see [Grit Gate](#the-grit-gate)).
3. **Scan** — run the draft against the [pattern cue-sheet](#pattern-cue-sheet) (30 universal tells). **For Thai drafts, load `patterns-thai.md` (§31–§42) before drawing any conclusion, not after.** Scanning only the 30 universal tells on a Thai draft reads as thorough but structurally cannot catch terminology drift/calque (§31) — that class only exists in the Thai-specific catalog. Confirmed 2026-07-14: a scan that deferred loading `patterns-thai.md` reported the draft's word choice clean, missing a live calque (`ตั๋ว` for "ticket" — §31's own worked example class) that a human reviewer caught immediately after. Load it first; it's cheap, the miss isn't.
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

**Terminology:** default **keep English** in internal dev (commit, merge, PR, staging, develop, production). User-facing → translate or transliterate per RTGS (ราชบัณฑิตยสภา). Don't romanize Thai in internal docs. Full decision tree: §31 in `patterns-thai.md`.

**Typography:** Thai has no inter-word spaces (space = phrase/sentence break); 1 space around English when it aids reading, but glued to identifiers/numbers is fine (`PR #82`, `v1.11.37`); Arabic numerals (`2026`, `77%`, `30 วัน`), not Thai numerals.

**Calques to kill** (use a verb matching the real action): `ถือไว้`→`ยังไม่ปล่อยขึ้น prod / พักไว้`; `ดัน`→`merge / นำขึ้น prod`; `ระบบล้ม`→`ระบบล่ม / down`; claimed `ทดสอบบน staging ผ่าน`→`ทดสอบ 4 เคส drafted รอ run จริง`.

## The Grit Gate

**Removing the 30 patterns gets you to "clean," not "human."** Clean-but-neutral text sits in the safe middle — itself an AI tell (a skeptical reader scores it ~30/100 AI, not 0). To clear the middle, every rewrite must ALSO do both:

1. **Surface the grit.** Pull the concrete specifics a real author includes and an LLM rounds off: ticket/PR refs, file or module names, the actual cause (race condition, double-submit, null from an API), real numbers, the one weird detail. Grit is what reads human — not the absence of fluff.
2. **Commit to a point of view.** Say which part matters and what you'd actually do. Neutral "balanced" reporting is the AI default. (Apply POV only where the genre allows it — blog/standup/ADR yes; legal/spec/reference stays plain, and plain *is* the human voice there.)

**Fabrication boundary (don't fake grit).** Never invent a ticket, metric, cause, or source to manufacture grit. Pull specifics only from the source or surrounding context. **If the source is pure puffery with no real content and you have nothing to pull, the honest output is to say so or ask for the specifics — a polished, confidently-empty paragraph is still AI.** Don't paper over a hollow source with smooth prose.

Soulless vs alive — same facts, neutral report → real voice:
> ❌ การทดลองนี้ได้ผลลัพธ์ที่น่าสนใจ agent สร้างโค้ดได้ 3 ล้านบรรทัด developer บางส่วนประทับใจ ขณะที่บางส่วนยังคงมีข้อสงสัย
> ✅ ผมเองก็ยังไม่รู้จะรู้สึกยังไงกับอันนี้ agent เขียนโค้ดไป 3 ล้านบรรทัดตอนคนน่าจะหลับอยู่ ครึ่ง dev community ตื่นเต้น อีกครึ่งเถียงว่ามันนับไม่ได้

## Voice

If the user gives a writing sample, match **their** voice (sentence length, formality, how they open paragraphs, punctuation habits, recurring phrases) — don't just delete AI patterns, replace them with patterns from the sample. If they write short, don't build long sentences; if they use `ของ`/`อัน`, don't upgrade to `องค์ประกอบ`/`ส่วนประกอบ`.

No sample → use the Grit Gate default: opinionated where the genre allows, varied rhythm (short sentence; then a longer one that arrives somewhere; alternate), and let some mess in (asides, half-formed thoughts read human; perfect symmetry reads algorithmic).

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

Look for **clusters** of tells, not isolated ones — a single em dash means nothing; em dashes + rule-of-three + *vibrant tapestry* + a "Conclusion" section is a confession. These are NOT tells on their own: polish/consistent style, Thai↔EN code-switching (normal for Thai devs), dry-but-clean prose, formal vocabulary in a formal context, one lone transition word, curly quotes from an auto-curl editor, an unsourced claim, era-bound slang. Full false-positive + "signs of human writing" lists are in `patterns-universal.md` — read it before gutting prose that might just be human.

## Process and Output

1. **Identify every tell** — run the draft against the cue-sheet (§1–30) plus `patterns-thai.md` (§31–42) if Thai is present.
   Done when: every tell actually present is named, not just the first 2–3 obvious ones.
   Failure mode to avoid: stopping after the loudest tells (em dash, "delve") and missing a cluster that only shows up on a full pass.
2. **Draft rewrite** — natural aloud, varied length, simple constructions (is/are/has · คือ/เป็น), correct register, grit gate applied.
   Done when: every tell named in step 1 has been addressed in the draft.
   Failure mode to avoid: deleting AI-isms without adding grit — lands in the "clean but neutral" safe middle the Grit Gate above scores ~30/100 AI, not 0.
3. Ask **"what still makes this read AI?"** and answer in a few bullets.
   Done when: at least one honest gap is named, even a minor one.
   Failure mode to avoid: answering "nothing, looks good" — that's grading your own work instead of scrutinizing it.
4. **Final rewrite** addressing them, zero em dashes (#14).
   Done when: every bullet from step 3 is either fixed or named as a deliberate tradeoff (e.g., formal vocabulary the genre requires).
   Failure mode to avoid: a final rewrite indistinguishable from the draft — if step 3 found nothing, re-run step 3, don't skip step 4.

Deliver: the draft, the brief "still-AI" bullets, the final rewrite, and (optionally) a short change summary.

## Bundled resources

Reference these on demand — each says when to load it (one level deep; read fully, don't preview).

- `patterns-universal.md` — full §1–§30 (problem + worked before/after) and the complete detection guidance. **Load when:** you need the worked example/fix for a tell from the cue-sheet, or before deciding prose is AI vs human.
- `patterns-thai.md` — §31–§42 Thai-specific rules (terminology & calque, anti-fabrication tiers, connectives, register matrix, code-switching tells, AI-leaked closers). **Load when:** the draft contains Thai or Thai↔EN. **Skip for monolingual English.**
- `examples.md` — worked examples A (TH chat), B (TH standup), C (TH UI), D (TH prose), E (EN UI), F (EN standup), G (EN prose). **Load when:** stuck, or the user wants the process shown.
- `references.md` — external sources (RTGS, Mozilla Thai Style Guide, W3C Thai Layout, PyThaiNLP, Conventional Commits Thai) + Thai+tech glossary + calque/typography cheat sheet. **Load when:** verifying transliteration or citing sources.

> Bilingual (EN + TH). Universal patterns (§1–§30) apply to both; Thai patterns (`patterns-thai.md`) apply only when Thai is present. No separate `patterns-en.md` — the universal catalog + EN examples cover the EN side.
