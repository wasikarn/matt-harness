# Thai-Specific Patterns (extends `patterns-universal.md` §1-§30)

> This file extends the catalog in `patterns-universal.md` with 12 more top-level patterns (§31-§42) that only Thai text needs: terminology & calque, anti-fabrication, connectives, register matrix, code-switching tells, AI-leaked closers. Read `SKILL.md` §0 (register and language gate) first, then come back here.
>
> ❌/✅ below is the notation for bad/good examples (like code // BAD / // GOOD), not the decorative emoji that §18 in `cue-sheet.md` says to cut from real writing.

---

## THAI-SPECIFIC PATTERNS (extend catalog with §31-§42)

### 31. Thai Terminology Drift & Calque (TBD-disciplined decisions)

**Problem:** Three terminology mistakes show up repeatedly in AI Thai text:

(a) **Drift in meaning**: words whose meaning has drifted in Thai (e.g. `API` usually means only a web API, but in practice a lib/function interface is an API too) → **keep English for precision**
(b) **Calque (`แปลตรงตัว`)**: a Thai verb that translates the English word literally but does not match the real action
(c) **Non-standard transliteration**: ad-hoc transliteration that does not follow RTGS

**Meaning-overlap test (run BEFORE the decision flow below, on every candidate term — not just terms already in the glossary table):** for any Thai noun/verb standing in for an English technical term, ask *does this word's actual, common meaning overlap with the technical meaning, or does it just sound like a plausible translation?* A grammatically-fine sentence is not evidence the term is correct — `ตั๋ว` (travel/event ticket) reads as a fine translation of "ticket" and is still (a) drift-in-meaning, because its real meaning has nothing to do with an issue-tracker record. Fail this test on any term, glossary or not → treat as (a). This is the check that catches new drift the glossary table hasn't enumerated yet; the table only covers terms already caught once.

**3 ways to decide terminology:**

| Method | Example | Use when |
|--------|---------|----------|
| **เก็บอังกฤษ** (Latin) | `staging`, `merge`, `API`, `PR #82` | internal dev; คำที่แปลแล้วเพี้ยน/กำกวม |
| **ทับศัพท์** (อักษรไทย) | ซอฟต์แวร์, ดิจิทัล, เวอร์ชัน | คำที่ฝังในภาษาไทยทั่วไปแล้ว |
| **แปล** (ความหมายไทย) | ฐานข้อมูล, การควบคุมเวอร์ชัน | user-facing; non-dev อ่าน |

**Decision flow:**
```
Customer/non-dev reads it? ─ yes ─> is there a clear Thai word? ─ yes ─> แปล (translate)
   │                                        └ none / translation drifts ─> เก็บอังกฤษ (keep English) + parenthetical gloss
   └ no (dev reads it) ─> เก็บอังกฤษ (default), or ทับศัพท์ (transliterate) if already embedded in Thai
```

**Verify transliteration** at https://transliteration.orst.go.th/search (Royal Society of Thailand). Never transliterate ad hoc.

**Section heading / user-facing headings:** never mix in `(Declined)` as in `## การชำระเงินไม่สำเร็จ (Declined)`; move the English word into the body or translate it as "ถูกปฏิเสธ" instead.

**Default glossary (standard Thai+tech):**

| Term | Internal | User-facing |
|----|----------|-------------|
| staging / develop / production | คงอังกฤษ | "ระบบทดสอบ" / (none) / "ระบบจริง" + อธิบาย |
| merge | merge | รวมโค้ด |
| deploy | deploy | นำขึ้นใช้งาน |
| session | session (เก็บอังกฤษ) | เซสชัน (RTGS, ไม่มีไม้หันอากาศ) |
| error code | error code | ข้อความแจ้งข้อผิดพลาด |
| declined (bank/payment) | declined (เก็บไว้ใน log เท่านั้น) | ถูกปฏิเสธ |
| ticket / issue (Jira, GitHub) | ticket (เก็บอังกฤษ) | "รายการแจ้งงาน" หรือคง ticket — ห้ามใช้ "ตั๋ว" (แปลว่าตั๋วเดินทาง/ตั๋วหนัง คนละความหมายกับ issue-tracker record เลย — drift-in-meaning (a), ไม่ใช่แค่ทับศัพท์ผิด) |

> Product-specific terms (ANPR, dwell, front-facing, PDPA, traffic-campaign) → keep them in a separate project glossary, not in this global skill.

When replacing a calque, pick a verb matching the real action — not a vague placeholder — as the before/after pairs below do.

**Before (terminology drift + calque):**
> ตัวกรองหันหน้าผมถือไว้ก่อน รอดันแก้เรื่องมอไซค์

**After (default `เก็บอังกฤษ`, Thai as glue):**
> front-facing filter ยังไม่ปล่อยขึ้น prod รอแก้ moto-drop ก่อน

**Before (non-RTGS transliteration):**
> เซสชั่นหมดอายุ

**After (RTGS):**
> เซสชันหมดอายุ

**Before (drift-in-meaning — dev-tracker noun, not the deploy-vocab example above):**
> แผนผังความสัมพันธ์ตั๋ว (Dependency Map)

**After (`เก็บอังกฤษ`, keep English):**
> แผนผังความสัมพันธ์ Ticket (Dependency Map)

Same (a) drift-in-meaning failure as the `front-facing`/`API` cases above, in the issue-tracking vocabulary domain instead of deploy. The glossary row covers `ตั๋ว`; the meaning-overlap test above catches the next term the glossary doesn't list.


### 32. Anti-Fabrication Discipline (TBD > invented specifics)

**Problem:** AI text is overconfident. Thai text in particular pads with invented file paths, branch names, ticket IDs, version numbers, dates, and metrics to look concrete. **Internal docs that teach the wrong workflow = technical debt someone else fixes later**, especially onboarding docs, because a new hire has no mental model to check against and will trust and follow them.

**3 red flags:**

(a) **Candidate-path fabrication**: a file that "probably lives" under `src/...` but was never verified:
> ❌ `webhook middleware ใหม่: src/presentation/middleware/rate-limiter.ts`
> ✅ `webhook middleware ใหม่ (path จะ confirm ใน PR diff)`

(b) **Invented metrics / load numbers**: load, latency, threshold figures that were never run:
> ❌ `burst test 500 req/min โควต้า 100/min → 400 queued ใน 1s`
> ✅ `burst test staging ผ่าน ตัวเลข load จะใส่หลัง run จริง`

(c) **Fake SLA / dates / versions**: firmware versions, rollout dates, rollback times that look real:
> ❌ `rely on camera firmware v2.1+ (2026-06-20 rollout)`
> ✅ `camera firmware dependency รอ confirm จาก camera team`
> ❌ `rollback ใช้เวลา 2-5 นาที`
> ✅ `rollback ใช้เวลาเท่าไหร่ขึ้นกับ image size/network/registry, verify หลัง deploy ครั้งแรก`

**TBD is a positive pattern, not an admission of failure:**
> ✅ `ไฟล์ที่แตะ รอ confirm จาก PR diff`
> ✅ `integration test [N] เคส drafted รอ run จริง`
> ✅ `Threshold/window size TBD จะใส่หลัง calibrate กับ traffic จริง`

`[N]` above is a placeholder for the real count from the source — never copy a number out of this example verbatim, and never let a future edit read this line as literal data instead of shape.

**PR description structure (TBD-disciplined):**
- `## สรุป` (1 paragraph)
- `## ทำอะไร` (bullet)
- `## โค้ด` (file paths from the diff only; otherwise TBD)
- `## ทดสอบแล้ว` (real results only)
- `## Risk`
- `## Related` (real ticket/branch)

### 32.1 Anti-Fabrication 3-Tier Tree (v2.2)

**Default = TIER 1 (DROP).** Use TIER 2 (HEDGE) only when the reader needs the signal but you still cannot verify. Use TIER 3 (CITE-VERIFIABLE) once it has actually been checked.

| Tier | Action | Use when | Example |
|------|--------|----------|---------|
| **T1 DROP** | ตัดทิ้งทันที, ไม่แม้แต่ hedge | fact ที่ตรวจไม่ได้, ผลกระทบสูง | ❌ `"Google 2024 Codex 55% เร็วขึ้น"` → ✅ ไม่พูดถึงเลย |
| **T2 HEDGE** | เขียน claim + marker เตือนผู้อ่าน verify | claim ที่ "เคยได้ยินมา" แต่ยังไม่ verify | `"อ้างกันว่า Codex 55% (ยังไม่ได้ verify)"` |
| **T3 CITE-VERIFIABLE** | claim + แหล่งที่ตรวจได้ (URL / paper / log) | fact ที่ตรวจแล้วจริง | `"Codex eval (Wang et al. 2024, arxiv:2404.xxxxx)"` |

**Hedge budget (hard rule):** real people write ≤1 hedge per clause. More than 1 hedge in one clause → drop to T1 instead.

❌ `"ผมคิดว่าน่าจะประมาณว่า 55% ครับ ถ้าจะให้แน่ใจก็ต้อง verify"` — 3 hedges ใน 1 clause = T1
✅ `"Codex eval 55% (Wang et al. 2024, arxiv:2404.xxxxx)"` — T3 หรือ ไม่พูดถึง

**Honest-broker preamble (cut to claim):** never open with `ผมไม่โทษเครื่องมือ แต่...` / `ต้องบอกว่า...` / `จริงๆ แล้ว...` before the claim. Go straight to the claim.

❌ `"ผมไม่โทษเครื่องมือนะ แต่ Codex เคย benchmark 55% ไว้"` — 50 tokens preamble
✅ `"Codex eval 55% (Wang et al. 2024, arxiv:2404.xxxxx)"` — 8 tokens

### 32.2 Red-Flag Patterns Catalog (v2.2)

Patterns that show AI is fabricating without knowing it; drop on sight:

1. **Path confidence without diff**: `"src/presentation/middleware/rate-limiter.ts"` with no grep of the file
2. **Round numbers without source**: `"55% faster"`, `"2-5 นาที"`, `"500 req/min"` that look too neat
3. **Date precision without calendar check**: `"2026-06-20 rollout"` with no calendar check
4. **Version pinning without release note**: `"v2.1+ (2026-Q2 release)"` with no changelog
5. **Authoritative source misattribution**: `"Google 2024 Codex eval"`, `"Stanford 2023 study"`, `"MIT 2024 report"` with no recallable URL
6. **Quote fabrication**: `"Steve Jobs เคยพูดว่า..."` with no source
7. **Library API hallucination**: `pandas.DataFrame.diff()` with a misremembered signature
8. **Self-consistent but wrong narratives**: a story that looks logical but every detail is wrong
9. **Acronym expansion invented**: `CRUD = Create, Read, Update, Delete` (correct, but AI loves to over-explain), `YAML = Yet Another Markup Language` (wrong; it is actually recursive)
10. **Generic company name + generic claim**: `"บริษัท Fortune 500 แห่งหนึ่งพบว่า..."`; no real name, does not count

**Fast verification (before writing):**
- URL → check with `WebFetch` or `WebSearch`
- Paper → arxiv/scholar search
- API → `context7` MCP or official docs
- File path → check with `Glob`/`Grep`
- Date → calendar
- Quote → original source (interview, paper, book)

### 32.3 Cite-as-Published Convention (v2.2)

When citing for real (T3), use a format the reader can verify onward:

| Type | Format | Example |
|------|--------|---------|
| Paper | `Author et al. (Year) [link/doi]` | `"Wang et al. (2024) arxiv:2404.12345"` |
| Blog | `Title — Author, Date` | `"Postgres hypertables — Timescale, 2024-11"` |
| RFC/Standard | `RFC NNNN / ISO NNNN` | `"RFC 7231 (HTTP semantics)"` |
| Internal doc | `path:section` | `"docs/anpr/sse-stream.md#auth"` |
| Log/metric | `dashboard URL + timestamp` | `"grafana/tat-anpr?from=2026-06-04T15:11Z"` |

❌ `"จาก research 2024 พบว่า..."` — ไม่มี source ที่ verify ได้
✅ `"Wang et al. (2024), arxiv:2404.12345 — CodeX eval benchmark 55% บน HumanEval"` (ถ้า verify แล้ว)

### 32.4 Thai Hedge Vocabulary (v2.2)

Thai hedges that work, ordered strong → weak:

| Strength | Thai | Use when |
|----------|------|----------|
| Strong | `"ผมไม่แน่ใจ"` | claim ที่ยังไม่ verify, แต่จำเป็นต้องพูดถึง |
| Strong | `"ยังไม่ได้ verify"` | claim ที่ "เคยได้ยิน" แต่ยังไม่ได้ตรวจ |
| Medium | `"น่าจะ"` | estimate ที่มี data รองรับบางส่วน |
| Medium | `"คาดว่า"` | projection ที่มี baseline |
| Medium | `"อ้างกันว่า"` | third-party claim ที่ยังไม่ verify |
| Weak | `"อาจจะ"` | possibility ทั่วไป |
| Weak | `"คงจะ"` | mild speculation |
| Avoid | `"ดูเหมือนว่า"` | ใช้บ่อยเกิน = AI tell |
| Avoid | `"น่าสนใจที่ว่า"` | ใช้บ่อยเกิน = AI tell |

**Thai writers normally use ≤1 hedge per clause.** ≥2 = AI.

### 32.5 Citation Conventions — Thai Internal Doc (v2.2)

In an internal Thai doc use this pattern:

| Type | Format | Example |
|------|--------|---------|
| Jira | `TP-XXX` (verify ใน Jira ก่อน) | `"ดู TP-549"` |
| PR | `repo#PR_NUMBER` (verify ใน GitHub) | `"acme-api#64"` |
| Commit | short SHA + message | `"a1b2c3d — fix rate-limiter"` |
| Doc path | `path:line` | `"docs/anpr/measurement.md#L42"` |
| Slack/Chat | channel + date (link) | `"#anpr-dev 2026-06-02"` |

❌ `"ตามที่คุยกันในทีม"` — ไม่มี link, verify ไม่ได้
✅ `"Slack #anpr-dev 2026-06-02 — คุยกับ P'X เรื่อง rate-limiter threshold"`

### 32.6 Epistemic Frame — Self-Aware Uncertainty (v2.2)

Tell "ไม่รู้" (do not know) apart from "รู้แต่ไม่ได้ verify" (know, but unverified):

| Frame | Use when | Pattern |
|-------|----------|---------|
| **Unknown** | ไม่เคยเจอ case นี้ | `"ผมไม่เคยเจอเคสนี้"` |
| **Unverified** | เคยได้ยิน แต่ยังไม่ได้ verify | `"ผมเคยอ่านว่า... แต่ยังไม่ได้ verify"` |
| **Hedged estimate** | มี data บางส่วน | `"จาก data ที่เห็น น่าจะประมาณ X"` |
| **Verified** | ตรวจแล้ว | `"Wang et al. 2024 — 55%"` (พร้อม cite) |

❌ `"คิดว่าน่าจะประมาณ 55% ครับ ถ้า verify ก็คงจะใช่"` — 4 hedges, ไม่ระบุชัด
✅ `"ผมเคยอ่านว่า Codex 55% แต่ยังไม่ได้ verify"` — 1 frame, ชัด

### 32.7 Name-Dropping Discipline (v2.2)

Never name-drop a brand/company/paper for authority when it cannot be verified:

❌ `"Google, Microsoft, และ MIT ต่างก็ศึกษา..."` — 3 names ไม่มี paper
❌ `"ตามที่ Stanford 2023 study พบ..."` — paper ที่จำไม่ได้
✅ `"Wang et al. 2024 (arxiv:2404.xxxxx) — Codex 55% บน HumanEval"`

**If you name-drop, you need:**
1. A paper/URL/link
2. Or a "claim I once heard" framing + a clear hedge

### 32.8 Royal Anti-Pattern (v2.2)

Royal-register endings (`หม่อม`, `พระ`, etc.) in an informal register = AI tell:

❌ `"หวังว่าจะเป็นประโยชน์ต่อท่านผู้อ่าน"` — ไม่มีใครเขียนแบบนี้ใน Slack
✅ `"หวังว่าพอเป็นประโยชน์"` — natural register

**Rule:** match register → royal form. Chat/standup = no royal. UI = no royal. Essay = no royal except when addressing the monarch or quoting a royal speech.

### 32.9 Hallucination Context Switch (v2.2)

When AI "context switches" from a verifiable claim → an unverifiable one → drop the whole clause:

❌ `"Postgres trigger ใช้ `pg_notify` แล้ว Redis เคย benchmark 55% บน HumanEval"`
   — `pg_notify` is verifiable, "55% HumanEval" is not, **drop the whole clause**

✅ `"Postgres trigger ใช้ `pg_notify` ตามที่คุยกับ P'X (Slack 2026-06-02)"`
   — all verifiable

### 32.10 Anti-Fabrication Cheat Sheet (v2.2)

**Before writing any fact → check 3 questions:**
1. **Can it be verified?** → if not: T1 DROP
2. **Is there a source?** → if not: T2 HEDGE or T1
3. **Can the reader verify it onward?** → if not: T1

**Default = T1.** Whenever in doubt → T1.

### 33. Connective Density (Thai Connector Cluster)

**Problem:** AI Thai text stacks formal connectors back to back until the rhythm of natural speech/writing is gone.

**Red-flag connectors (v2.2):**

| Tier | Connector | Replace with |
|------|-----------|--------------|
| **Over-formal** | `"อย่างไรก็ตาม"` | `"แต่"` / `"ก็"` / sentence break |
| **Over-formal** | `"นอกจากนี้"` | `"แล้วก็"` / `"อีกอย่าง"` / new paragraph |
| **Over-formal** | `"ในขณะเดียวกัน"` | `"ตอนเดียวกัน"` / restructure |
| **Over-formal** | `"ในยุคปัจจุบัน"` | `"ตอนนี้"` / drop |
| **Over-formal** | `"ทั้งนี้"` | drop or rephrase |
| **Over-formal** | `"โดยเฉพาะอย่างยิ่ง"` | `"โดยเฉพาะ"` / `"ยิ่งกว่านั้น"` |
| **Over-formal** | `"โดยทั่วไป"` | `"ส่วนใหญ่"` / `"ปกติ"` |
| **Over-formal** | `"ดังนั้น"` (ติดๆ) | `"เลย"` / `"ก็"` / sentence break |

**Density rule:** ≤1 over-formal connector per paragraph. ≥2 = AI tell.

❌ `"อย่างไรก็ตาม ในขณะเดียวกัน ทั้งนี้ ระบบก็ทำงานปกติ"`
✅ `"แต่ระบบก็ยังทำงานปกติ"`

### 34. Lexical Budget — Same Word, Not Synonym Spam

**Problem:** AI text variety-hacks by using 2-3 synonyms of the same word in one paragraph. Real people repeat the word.

**Rule:** repeating the same word is fine; do not "variety-hack" with odd synonyms.

❌ `"ระบบมีปัญหา (system issue) เพราะ platform ล่ม (down) และ infrastructure ล้มเหลว (failed)"`
✅ `"ระบบล่ม สาเหตุน่าจะมาจาก infra"`

**Thai variant:** `"ระบบล่ม" / "ระบบ down" / "platform เข้าไม่ได้"`: use 1-2 of them, not all 3 in one paragraph

### 35. Topic-First vs Background-First (Standup Register)

**Problem:** AI opens a paragraph with background/context before the topic. Real people start at the topic.

❌ `"เมื่อวานทำงานหลายอย่าง รวมถึง TP-549 ที่ต้องแก้ measurement design และ merge PR #36 เข้า develop วันนี้เลย refocus ที่ TP-549"`
   — 3 clauses of background, topic last

✅ `"TP-549 measurement design เริ่มแล้ว PR #36 merge แล้ว"`
   — topic first, then detail

**Standup order (v2.2):**
1. **✅ Done** (ordered by priority: critical → nice)
2. **🎯 Next** (what you will do today/tomorrow)
3. **🚧 Blocker** (waiting on whom/what)
4. **🙋 Ask** (need an opinion/answer)

### 36. Marketing Calques (UI/Notification Register)

**Problem:** AI UI text uses marketing calques that leave the user unsure what to do.

**Top marketing calques (v2.2):**

| ❌ Calque | ✅ UI-actual |
|-----------|-------------|
| `"ครอบคลุมทุกความต้องการ"` | drop หรือ `"ครบทุก feature ที่ใช้บ่อย"` |
| `"มอบประสบการณ์ที่ดีที่สุด"` | drop |
| `"ส่งมอบคุณค่า"` | drop |
| `"เจาะลึก"` | `"ดู detail"` |
| `"ขับเคลื่อน"` | drop หรือ verb จริง |
| `"ยกระดับ"` | drop หรือ verb จริง |
| `"ก้าวสู่"` | drop |
| `"เปิดรับ (ข้อเสนอแนะ)"` | `"รับ feedback"` |

**UI block max 3 short sentences.** No marketing emoji.

### 36.1 UI-Actual vs UI-Aspirational (v2.2)

Tell them apart:
- **UI-actual**: says what happened + what the user does next
- **UI-aspirational**: says the system is "good" but does not help the user do anything

❌ `"เรามุ่งมั่นมอบประสบการณ์ที่ดีที่สุด"` (UI-aspirational)
✅ `"ชำระเงินไม่สำเร็จ ลองใหม่อีกครั้ง หรือเช็คยอดเงิน"` (UI-actual)

### 37. Nominalization Avoidance

**Problem:** AI turns verbs into nouns to "sound formal"; real people use the verb.

❌ `"การดำเนินการปรับปรุงประสิทธิภาพ"` — nominalization overload
✅ `"ปรับให้เร็วขึ้น"` — verb-first

**Common Thai nominalizations to watch:**
- `"การดำเนินการ"` → `"ทำ"` / drop
- `"การปรับปรุง"` → `"ปรับ"`
- `"การพัฒนา"` → `"พัฒนา"` (already a verb)
- `"การใช้งาน"` → `"ใช้"`
- `"การทดสอบ"` → `"ทดสอบ"`

### 38. Code-Switching Tells (Mixed Thai/English)

**Problem:** AI uses an English term "because it sounds smart"; real people use it because they need it.

**Rule:** use English when:
1. **The term is used in real work** (`merge`, `deploy`, `staging`, `commit`, `PR`, `API`)
2. **Library/framework name** (`React`, `Bun`, `Postgres`, `Tailwind`)
3. **The concept has no Thai word, or the translation drifts** (`webhook`, `middleware`, `race condition`)

❌ `"ระบบมี redundant ของข้อมูล"` — "redundant" ที่ไม่จำเป็น
✅ `"ข้อมูลซ้ำซ้อน"`

❌ `"Initialize ระบบใหม่"` — Thai "init/เริ่มต้น" ก็ได้
✅ `"init ระบบ"`

**Discourse-marker calques (English → Thai, not English-leak):**

| ❌ Calque | ✅ Better |
|-----------|-----------|
| `"อย่างไรก็ตาม"` (translation of "however") | `"แต่"` / sentence break |
| `"นอกจากนี้"` (translation of "furthermore") | `"อีกอย่าง"` / new para |
| `"เพื่อที่จะ"` (translation of "in order to") | `"เพื่อ"` / drop |
| `"เนื่องจากว่า"` (translation of "due to the fact that") | `"เพราะ"` / `"เนื่องจาก"` |
| `"ในกรณีที่"` (translation of "in the case that") | `"ถ้า"` / `"หาก"` |

### 39. Register-Specific Tells (Per-Register Deep-Dive)

#### 39.1 Register A — Chat/LINE

**Tells:**
- `555` (laughter) at least once
- Reaction emoji (`👍`, `🙏`, `😂`) mixed in
- Particle: `ค่ะ` (female) / `ครับ` (male) / `จ้า` (female, informal) / no particle (assertive)
- 1-10 words per message
- Abbreviations: `อ่อ`, `จ้า`, `จริงดิ`, `555+`, `เหรอ`, `คับ` (informal `ครับ`)

❌ `"สวัสดีค่ะ ดิฉันหวังว่าข้อความนี้จะเป็นประโยชน์ค่ะ"` — formal, AI
✅ `"สวัสดีค่ะ พอดีมีเรื่องอยากถาม"` — natural chat

#### 39.2 Register B — Standup/PR/Commit

**Tells:**
- No particle (`ครับ`/`ค่ะ`) on every line
- No emoji in the PR description (commit = `type(scope): message`)
- Short words: `ผ่าน`, `รอ`, `merged`, `shipped`, `rolled back`, `WIP`
- Verbatim repo/PR/branch names
- Filter scope: dev own work

❌ `"วันนี้ดิฉันได้ทำการปรับปรุงระบบ API ค่ะ"` — formal, AI
✅ `"ปรับ API แล้ว PR #64 merged"`

#### 39.3 Register C — UI/Error/Notification

**Tells:**
- 1-3 sentences per block
- ≤25 words
- One opener with `ค่ะ/ครับ` only
- Action verb + 1 alternative (`ลอง X หรือ Y`)
- Status word first: `"ชำระเงินไม่สำเร็จ"`, `"บันทึกแล้ว"`, `"ยกเลิกเรียบร้อย"`
- No "หวังว่า", "ขออภัย", "แจ้งให้ทราบ", "ยินดีให้ความช่วยเหลือ"

❌ `"ขออภัยในความไม่สะดวกค่ะ เราจะพยายามปรับปรุงให้ดีขึ้น"` — AI
✅ `"ชำระเงินไม่สำเร็จ ลองใหม่อีกครั้ง หรือเช็คยอดเงินค่ะ"` — UI-actual

#### 39.4 Register D — Prose/Blog/Strategy/Essay

**Tells:**
- 3-30 words per sentence, alternating rhythm
- Personal aside (`ผมเคย`, `ผมรู้สึกว่า`, `ผมไม่แน่ใจว่า`)
- Concrete image instead of abstraction
- No "หวังว่าจะเป็นประโยชน์" closer
- No "อนาคตสดใส", "ก้าวต่อไปจะเป็นการเดินทางสู่ความเป็นเลิศ"

❌ `"ในยุคปัจจุบัน AI กำลังเปลี่ยนแปลงโลกอย่างมาก ซึ่งส่งผลกระทบต่ออุตสาหกรรมต่างๆ"`
   — formal connector spam, generic claim

✅ `"AI เขียนโค้ดเก่งขึ้นทุกปี ผมยังนึกถึง agent ที่เขียนผ่านมาทั้งคืน แต่ครึ่ง dev community ก็ยังบอกว่ามันนับไม่ได้"`
   — opinion, image, mixed rhythm

### 40. AI-Leaked Thai Closers (v2.2 — Comprehensive)

**Closers to drop in every register:**

| Closer | Register | Replace with |
|--------|----------|--------------|
| `"หวังว่าจะเป็นประโยชน์"` | A, D | drop |
| `"หวังว่าพอเป็นประโยชน์"` | A, D | drop |
| `"ดีใจที่ได้ช่วย"` | A, D | drop |
| `"ยินดีให้ความช่วยเหลือค่ะ"` | A, C, D | drop |
| `"แจ้งให้ทราบ"` | A, B, C, D | drop |
| `"หากต้องการขยายความ"` | A, D | drop |
| `"ขอบคุณคำถามดีๆ ค่ะ"` | A, D | `"ขอบคุณค่ะ"` / drop |
| `"Let me know if you need more"` | D | drop |
| `"If you need further assistance"` | A, C, D | drop |
| `"Feel free to reach out"` | A, D | drop |
| `"สามารถติดต่อเราได้ตลอด 24 ชั่วโมง"` | C | drop |
| `"หากมีข้อสงสัยประการใด กรุณาติดต่อ..."` | C | drop |
| `"เราพร้อมให้บริการ"` | C | drop |

**Particle decision table (v2.2):**

| Register | Opener particle | Closer | Note |
|----------|-----------------|--------|------|
| A (chat, female) | `ค่ะ` / `จ้า` / no | `ค่ะ` / `นะคะ` | ไม่ลงท้ายทุกประโยค |
| A (chat, male) | `ครับ` / no | `ครับ` / `นะครับ` | ไม่ลงท้ายทุกประโยค |
| B (standup) | no | no | terse = AI detection < human |
| B (PR/commit) | no | no | conventional commit format |
| C (UI, formal) | `ค่ะ`/`ครับ` (1 opener) | no | ไม่ลงท้ายทุกประโยค |
| C (UI, casual app) | no | no | match brand voice |
| D (essay) | no | no | particle ทื่อๆ = AI tell |
| D (personal blog) | `ผม` 1st-person แทน | no | personal = no particle |

### 41. Royal Register Anti-Pattern

See §32.8 — the rule and matrix already live there. §41 retained as a number-pointed entry to keep the catalog at 12 top-level sections; consult §32.8 for the canonical rule.

### 42. Quick Reference — All 12 Thai-Specific Top-Level Patterns (sub-patterns listed beneath)

| # | Name | When |
|---|------|------|
| §32.1 | Anti-fabrication 3-tier tree | ทุก register (default T1) |
| §32.2 | Red-flag patterns catalog | เจอ path/date/metric ที่ดูดีเกิน |
| §32.3 | Cite-as-published | T3 cite |
| §32.4 | Thai hedge vocabulary | เขียน T2 |
| §32.5 | Citation conventions | internal doc cite |
| §32.6 | Epistemic frame | เขียน uncertainty |
| §32.7 | Name-dropping discipline | อ้าง brand/paper |
| §32.8 | Royal anti-pattern | match register |
| §32.9 | Hallucination context switch | เขียน claim ผสม |
| §32.10 | Anti-fabrication cheat sheet | quick lookup |
| §33 | Connective density | formal connector cluster |
| §34 | Lexical budget | synonym spam |
| §35 | Topic-first | standup/chat opener |
| §36 | Marketing calques | UI/notification |
| §36.1 | UI-actual vs aspirational | UI text |
| §37 | Nominalization | formal writing |
| §38 | Code-switching tells | mixed register |
| §39 | Register-specific tells | 4 register deep-dive |
| §40 | AI-leaked closers | closers + particle |
