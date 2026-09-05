---
name: tech-humanize
description: "Humanize dev/tech writing (English/Thai) to sound natural, not AI-generated. Use when editing chat, standup/PR/commit, UI copy, or prose/ticket/spec/ADR, or say แก้ให้เป็นธรรมชาติ. Don't use for translation."
model_limitation: "lexical-tell catalog currency (assumes current-gen LLM output still carries the enumerated tells — em dash, delve, rule-of-three, etc. — which research confirms shift/decay across model generations; re-validate at each quarterly cadence pass, docs/plans/mh-rebuild-v1-2026-09-05.md)"
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

Worked "soulless vs alive" example (same facts, neutral report → real voice): `examples.md`'s
Grit Gate: Soulless vs Alive section.

## Voice

Given a writing sample, match **their** voice (length, formality, paragraph openers, punctuation, recurring phrases) — don't just delete AI patterns, replace with the sample's own. Short sentences stay short; `ของ`/`อัน` stays, no upgrade to `องค์ประกอบ`/`ส่วนประกอบ`.

No sample → the Grit Gate default: opinionated where the genre allows, varied rhythm (short sentence; then a longer one that arrives somewhere; alternate), and let some mess in (asides, half-formed thoughts read human; perfect symmetry reads algorithmic).

## Pattern cue-sheet

Scan for these 30 universal tells (all languages). Thai-only tells (§31–§42) are in `patterns-thai.md`.

One line per cluster; the full 30-row table (pattern / EN+TH cue / fix) is in `patterns-universal.md`'s "Pattern cue-sheet" section — **Read it before scanning** (scans without it miss the cues), then the worked before/afters below it as needed.

- **Content (§1-6)** — significance puffery, notability name-drops, -ing pseudo-depth tails, promo language, weasel attribution, "challenges & future" formula.
- **Language & grammar (§7-13)** — AI-vocab words, copula avoidance, negative parallelism, rule of three, elegant variation, false ranges, passive/subjectless fragments.
- **Style (§14-19)** — em dashes (#14, zero tolerance), bold overuse, inline-header lists, title-case headings, emojis, curly quotes.
- **Communication (§20-22)** — chat artifacts, cutoff disclaimers / gap-fill, sycophancy.
- **Filler & hedging (§23-30)** — filler phrases, excessive hedging, generic positive conclusion, hyphenated-pair overuse, authority tropes, signposting, fragmented headers, diff-anchored writing.

## Don't over-edit

Look for **clusters**, not isolated tells — one em dash means nothing; em dashes + rule-of-three + *vibrant tapestry* + a "Conclusion" section is a confession. False-positive + "human writing" signs (incl. Thai notes): `patterns-universal.md`'s Detection Guidance section — read before gutting prose that might be human.

## Process and Output

1. **Identify every tell** — run the draft against the cue-sheet (§1–30) plus `patterns-thai.md` (§31–42) if Thai is present.
   Done when: every tell present is named, not just the first few obvious ones. (Failure modes in full: `examples.md`'s Process Step Rationale section.)
2. **Draft rewrite** — natural aloud, varied length, simple constructions (is/are/has · คือ/เป็น), correct register, grit gate applied.
   Done when: every tell named in step 1 is addressed, and everything step 1 cleared is left as written — a cleared term that now looks wrong mid-draft is new information, name it, don't quietly change it. (Failure modes in full: `examples.md`'s Process Step Rationale section.)
3. Ask **"what still makes this read AI?"** and answer in a few bullets — "nothing, looks good" grades your own work instead of scrutinizing it.
   Done when: at least one honest gap is named, even a minor one.
4. **Final rewrite** addressing them, zero em dashes (#14) — scan the text for `—`; a fixture once claimed dashes were cut while two remained. For each step-3 bullet, name the fix or write "kept as tradeoff: <reason>" (e.g., formal vocabulary the genre requires).
   Done when: every bullet from step 3 has a named resolution — fixed-where, or tradeoff-why. (Failure modes in full: `examples.md`'s Process Step Rationale section.)

Deliver: the draft, the brief "still-AI" bullets, the final rewrite, and (optionally) a short change summary.

## Bundled resources

Reference these on demand — each says when to load it (one level deep; read fully, don't preview).

- `patterns-universal.md` — full §1–§30 (problem + worked before/after) + complete detection guidance. **Load when:** you need the worked example/fix for a cue-sheet tell, or before deciding prose is AI vs human.
- `patterns-thai.md` — §31–§42 Thai-specific rules (terminology/calque, anti-fabrication tiers, connectives, register matrix, code-switching tells, AI-leaked closers). **Load when:** the draft has Thai or Thai↔EN. **Skip for monolingual English.**
- `examples.md` — worked examples A (TH chat), B (TH standup), C (TH UI), D (TH prose), E (EN UI), F (EN standup), G (EN prose). **Load when:** stuck, or to show the process.
- `references.md` — external sources (RTGS, Mozilla Thai Style Guide, W3C Thai Layout, PyThaiNLP, Conventional Commits Thai) + Thai+tech glossary + calque/typography cheat sheet. **Load when:** verifying transliteration or citations.

> Bilingual (EN + TH). Universal patterns (§1–§30) apply to both; Thai patterns (`patterns-thai.md`) apply only when Thai is present. No separate `patterns-en.md` — the universal catalog + EN examples cover the EN side.
