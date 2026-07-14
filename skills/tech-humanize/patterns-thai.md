# Thai-Specific Patterns (extends SKILL.md §1-§30)

> ไฟล์นี้ extend catalog ใน `SKILL.md` เพิ่มอีก 12 top-level patterns (§31-§42) ที่จำเป็นสำหรับ Thai text เท่านั้น — terminology & calque, anti-fabrication, connectives, register matrix, code-switching tells, AI-leaked closers. อ่าน `SKILL.md` §0 Thai Foundations ก่อน แล้วค่อยกลับมาที่นี่.

---

## THAI-SPECIFIC PATTERNS (extend catalog with §31-§42)

### 31. Thai Terminology Drift & Calque (TBD-disciplined decisions)

**Problem:** Three terminology mistakes show up repeatedly in AI Thai text:

(a) **Drift in meaning**: คำที่ดริฟต์ความหมายในไทย (เช่น `API` มักหมายถึง web API เท่านั้น, แต่ในชีวิตจริง = interface ของ lib/function ก็มี) → **เก็บอังกฤษเพื่อความแม่น**
(b) **Calque (แปลตรงตัว)**: ใช้กริยาไทยที่แปลตามตัวอังกฤษ แต่ไม่ตรงกับ action จริง
(c) **Non-standard transliteration**: ทับศัพท์มั่ว ไม่ตรง RTGS

**3 วิธีตัดสิน terminology:**

| วิธี | ตัวอย่าง | ใช้เมื่อ |
|------|---------|---------|
| **เก็บอังกฤษ** (Latin) | `staging`, `merge`, `API`, `PR #82` | internal dev; คำที่แปลแล้วเพี้ยน/กำกวม |
| **ทับศัพท์** (อักษรไทย) | ซอฟต์แวร์, ดิจิทัล, เวอร์ชัน | คำที่ฝังในภาษาไทยทั่วไปแล้ว |
| **แปล** (ความหมายไทย) | ฐานข้อมูล, การควบคุมเวอร์ชัน | user-facing; non-dev อ่าน |

**Decision flow:**
```
ลูกค้า/non-dev อ่าน? ─ ใช่ ─> มีคำไทยที่ชัดไหม? ─ มี ─> แปล
   │                                 └ ไม่มี/แปลแล้วเพี้ยน ─> เก็บอังกฤษ + วงเล็บอธิบาย
   └ ไม่ (dev อ่าน) ─> เก็บอังกฤษ (default) หรือทับศัพท์ถ้าฝังแล้ว
```

**Verify transliteration** ที่ https://transliteration.orst.go.th/search (ราชบัณฑิตยสภา). อย่าทับศัพท์มั่ว.

**Section heading / หัวข้อ user-facing:** ห้ามผสม `(Declined)` แบบ `## การชำระเงินไม่สำเร็จ (Declined)` ให้ย้ายคำอังกฤษไปอยู่ใน body หรือแปลเป็น "ถูกปฏิเสธ" แทน.

**Default glossary (standard Thai+tech):**

| คำ | Internal | User-facing |
|----|----------|-------------|
| staging / develop / production | คงอังกฤษ | "ระบบทดสอบ" / (none) / "ระบบจริง" + อธิบาย |
| merge | merge | รวมโค้ด |
| deploy | deploy | นำขึ้นใช้งาน |
| session | session (เก็บอังกฤษ) | เซสชัน (RTGS, ไม่มีไม้หันอากาศ) |
| error code | error code | ข้อความแจ้งข้อผิดพลาด |
| declined (bank/payment) | declined (เก็บไว้ใน log เท่านั้น) | ถูกปฏิเสธ |
| ticket / issue (Jira, GitHub) | ticket (เก็บอังกฤษ) | "รายการแจ้งงาน" หรือคง ticket — ห้ามใช้ "ตั๋ว" (แปลว่าตั๋วเดินทาง/ตั๋วหนัง คนละความหมายกับ issue-tracker record เลย — drift-in-meaning (a), ไม่ใช่แค่ทับศัพท์ผิด) |

> Product-specific terms (ANPR, dwell, front-facing, PDPA, traffic-campaign) → เก็บใน project glossary แยก ไม่ใส่ใน global skill นี้.

**Before (terminology drift + calque):**
> ตัวกรองหันหน้าผมถือไว้ก่อน รอดันแก้เรื่องมอไซค์

**After (default เก็บอังกฤษ + ไทยเป็นกาว):**
> front-facing filter ยังไม่ปล่อยขึ้น prod รอแก้ moto-drop ก่อน

**Before (non-RTGS transliteration):**
> เซสชั่นหมดอายุ

**After (RTGS):**
> เซสชันหมดอายุ

**Before (drift-in-meaning — dev-tracker noun, not the deploy-vocab example above):**
> แผนผังความสัมพันธ์ตั๋ว (Dependency Map)

**After (เก็บอังกฤษ):**
> แผนผังความสัมพันธ์ Ticket (Dependency Map)

`ตั๋ว` reads as a plausible translation (it's a real Thai word, grammatically fine in the sentence) but its actual meaning — a physical travel/event ticket — doesn't overlap with a Jira/GitHub issue-tracker record at all. This is the same (a) drift-in-meaning failure as the `front-facing`/`API` cases above, in a different vocabulary domain (issue tracking, not deploy). Missed in a live scan 2026-07-14 despite this section already existing — the scan never reached §31 (see `SKILL.md` §"The loop" step 3). The lesson isn't "also check for ตั๋ว" — it's that ANY Thai noun standing in for an English technical term needs this same question asked, not just the ones already in the glossary table: does the Thai word's common meaning actually overlap with the technical one, or does it just sound like a reasonable translation?


### 32. Anti-Fabrication Discipline (TBD > invented specifics)

**Problem:** AI text is overconfident. Thai text in particular pads with invented file paths, branch names, ticket IDs, version numbers, dates, and metrics to look concrete. **Internal docs ที่สอน workflow ผิด = technical debt ที่คนละคนต้องมาแก้ทีหลัง** โดยเฉพาะ onboarding doc เพราะ new hire ไม่มี mental model ตรวจสอบ จะเชื่อและทำตาม.

**3 red flags:**

(a) **Candidate-path fabrication**: ไฟล์ที่ "น่าจะอยู่" ใต้ `src/...` แต่ไม่ได้ verify:
> ❌ `webhook middleware ใหม่: src/presentation/middleware/rate-limiter.ts`
> ✅ `webhook middleware ใหม่ (path จะ confirm ใน PR diff)`

(b) **Invented metrics / load numbers**: เลข load, latency, threshold ที่ยังไม่ได้ run:
> ❌ `burst test 500 req/min โควต้า 100/min → 400 queued ใน 1s`
> ✅ `burst test staging ผ่าน ตัวเลข load จะใส่หลัง run จริง`

(c) **Fake SLA / dates / versions**: เวอร์ชัน firmware, วัน rollout, เวลา rollback ที่ดูเหมือนจริง:
> ❌ `rely on camera firmware v2.1+ (2026-06-20 rollout)`
> ✅ `camera firmware dependency รอ confirm จาก camera team`
> ❌ `rollback ใช้เวลา 2-5 นาที`
> ✅ `rollback ใช้เวลาเท่าไหร่ขึ้นกับ image size/network/registry, verify หลัง deploy ครั้งแรก`

**TBD is a positive pattern, not an admission of failure:**
> ✅ `ไฟล์ที่แตะ รอ confirm จาก PR diff`
> ✅ `integration test 4 เคส drafted รอ run จริง`
> ✅ `Threshold/window size TBD จะใส่หลัง calibrate กับ traffic จริง`

**PR description structure (TBD-disciplined):**
- `## สรุป` (1 ย่อหน้า)
- `## ทำอะไร` (bullet)
- `## โค้ด` (file path จาก diff เท่านั้น, ถ้าไม่มี TBD)
- `## ทดสอบแล้ว` (ผลจริงเท่านั้น)
- `## Risk`
- `## Related` (ticket/branch จริง)

### 32.1 Anti-Fabrication 3-Tier Tree (v2.2)

**Default = TIER 1 (DROP).** ใช้ TIER 2 (HEDGE) เฉพาะเมื่อผู้อ่านต้องการสัญญาณ แต่คุณยัง verify ไม่ได้. ใช้ TIER 3 (CITE-VERIFIABLE) เมื่อผ่านการตรวจจริง.

| Tier | Action | ใช้เมื่อ | ตัวอย่าง |
|------|--------|---------|---------|
| **T1 DROP** | ตัดทิ้งทันที, ไม่แม้แต่ hedge | fact ที่ตรวจไม่ได้, ผลกระทบสูง | ❌ `"Google 2024 Codex 55% เร็วขึ้น"` → ✅ ไม่พูดถึงเลย |
| **T2 HEDGE** | เขียน claim + marker เตือนผู้อ่าน verify | claim ที่ "เคยได้ยินมา" แต่ยังไม่ verify | `"อ้างกันว่า Codex 55% (ยังไม่ได้ verify)"` |
| **T3 CITE-VERIFIABLE** | claim + แหล่งที่ตรวจได้ (URL / paper / log) | fact ที่ตรวจแล้วจริง | `"Codex eval (Wang et al. 2024, arxiv:2404.xxxxx)"` |

**Hedge budget (hard rule):** คนจริงเขียน ≤1 hedge per clause. ถ้าเขียน >1 hedge ใน clause เดียว → drop เป็น T1 แทน.

❌ `"ผมคิดว่าน่าจะประมาณว่า 55% ครับ ถ้าจะให้แน่ใจก็ต้อง verify"` — 3 hedges ใน 1 clause = T1
✅ `"Codex eval 55% (Wang et al. 2024, arxiv:2404.xxxxx)"` — T3 หรือ ไม่พูดถึง

**Honest-broker preamble (cut to claim):** ห้ามขึ้นประโยค `ผมไม่โทษเครื่องมือ แต่...` / `ต้องบอกว่า...` / `จริงๆ แล้ว...` ก่อน claim. ไปที่ claim เลย.

❌ `"ผมไม่โทษเครื่องมือนะ แต่ Codex เคย benchmark 55% ไว้"` — 50 tokens preamble
✅ `"Codex eval 55% (Wang et al. 2024, arxiv:2404.xxxxx)"` — 8 tokens

### 32.2 Red-Flag Patterns Catalog (v2.2)

Pattern ที่บ่งบอกว่า AI กำลัง fabricate โดยไม่รู้ตัว — drop ทันที:

1. **Path confidence without diff**: `"src/presentation/middleware/rate-limiter.ts"` แต่ไม่ได้ grep ไฟล์
2. **Round numbers without source**: `"55% faster"`, `"2-5 นาที"`, `"500 req/min"` ที่ดูสวยเกินไป
3. **Date precision without calendar check**: `"2026-06-20 rollout"` ที่ไม่ได้เช็ค calendar
4. **Version pinning without release note**: `"v2.1+ (2026-Q2 release)"` ที่ไม่มี changelog
5. **Authoritative source misattribution**: `"Google 2024 Codex eval"`, `"Stanford 2023 study"`, `"MIT 2024 report"` ที่จำ URL ไม่ได้
6. **Quote fabrication**: `"Steve Jobs เคยพูดว่า..."` ที่ไม่มี source
7. **Library API hallucination**: `pandas.DataFrame.diff()` ที่จำ signature ผิด
8. **Self-consistent but wrong narratives**: เล่าเรื่องที่ดู logical แต่ทุก detail ผิด
9. **Acronym expansion invented**: `CRUD = Create, Read, Update, Delete` (ถูก แต่ AI ชอบ over-explain), `YAML = Yet Another Markup Language` (ผิด — จริงๆ recursive)
10. **Generic company name + generic claim**: `"บริษัท Fortune 500 แห่งหนึ่งพบว่า..."` — ไม่มีชื่อจริง ไม่นับ

**Fast verification (ก่อนเขียน):**
- URL → `WebFetch` หรือ `WebSearch` ตรวจ
- Paper → arxiv/scholar search
- API → `context7` MCP หรือ official docs
- File path → `Glob`/`Grep` ตรวจ
- Date → calendar
- Quote → original source (interview, paper, book)

### 32.3 Cite-as-Published Convention (v2.2)

เมื่ออ้างอิงจริง (T3) — ใช้ format ที่ผู้อ่าน verify ต่อได้:

| ประเภท | Format | ตัวอย่าง |
|--------|--------|---------|
| Paper | `Author et al. (Year) [link/doi]` | `"Wang et al. (2024) arxiv:2404.12345"` |
| Blog | `Title — Author, Date` | `"Postgres hypertables — Timescale, 2024-11"` |
| RFC/Standard | `RFC NNNN / ISO NNNN` | `"RFC 7231 (HTTP semantics)"` |
| Internal doc | `path:section` | `"docs/anpr/sse-stream.md#auth"` |
| Log/metric | `dashboard URL + timestamp` | `"grafana/tat-anpr?from=2026-06-04T15:11Z"` |

❌ `"จาก research 2024 พบว่า..."` — ไม่มี source ที่ verify ได้
✅ `"Wang et al. (2024), arxiv:2404.12345 — CodeX eval benchmark 55% บน HumanEval"` (ถ้า verify แล้ว)

### 32.4 Thai Hedge Vocabulary (v2.2)

Hedge ภาษาไทยที่ใช้ได้ — เรียงจาก strong → weak:

| Strength | Thai | ใช้เมื่อ |
|----------|-----|---------|
| Strong | `"ผมไม่แน่ใจ"` | claim ที่ยังไม่ verify, แต่จำเป็นต้องพูดถึง |
| Strong | `"ยังไม่ได้ verify"` | claim ที่ "เคยได้ยิน" แต่ยังไม่ได้ตรวจ |
| Medium | `"น่าจะ"` | estimate ที่มี data รองรับบางส่วน |
| Medium | `"คาดว่า"` | projection ที่มี baseline |
| Medium | `"อ้างกันว่า"` | third-party claim ที่ยังไม่ verify |
| Weak | `"อาจจะ"` | possibility ทั่วไป |
| Weak | `"คงจะ"` | mild speculation |
| Avoid | `"ดูเหมือนว่า"` | ใช้บ่อยเกิน = AI tell |
| Avoid | `"น่าสนใจที่ว่า"` | ใช้บ่อยเกิน = AI tell |

**ปกติคนไทยเขียน ≤1 hedge per clause.** ≥2 = AI.

### 32.5 Citation Conventions — Thai Internal Doc (v2.2)

ใน internal Thai doc ใช้ pattern:

| ประเภท | Format | ตัวอย่าง |
|--------|--------|---------|
| Jira | `TP-XXX` (verify ใน Jira ก่อน) | `"ดู TP-549"` |
| PR | `repo#PR_NUMBER` (verify ใน GitHub) | `"acme-api#64"` |
| Commit | short SHA + message | `"a1b2c3d — fix rate-limiter"` |
| Doc path | `path:line` | `"docs/anpr/measurement.md#L42"` |
| Slack/Chat | channel + date (link) | `"#anpr-dev 2026-06-02"` |

❌ `"ตามที่คุยกันในทีม"` — ไม่มี link, verify ไม่ได้
✅ `"Slack #anpr-dev 2026-06-02 — คุยกับ P'X เรื่อง rate-limiter threshold"`

### 32.6 Epistemic Frame — Self-Aware Uncertainty (v2.2)

แยกให้ออกระหว่าง "ไม่รู้" กับ "รู้แต่ไม่ได้ verify":

| Frame | ใช้เมื่อ | Pattern |
|-------|---------|---------|
| **Unknown** | ไม่เคยเจอ case นี้ | `"ผมไม่เคยเจอเคสนี้"` |
| **Unverified** | เคยได้ยิน แต่ยังไม่ได้ verify | `"ผมเคยอ่านว่า... แต่ยังไม่ได้ verify"` |
| **Hedged estimate** | มี data บางส่วน | `"จาก data ที่เห็น น่าจะประมาณ X"` |
| **Verified** | ตรวจแล้ว | `"Wang et al. 2024 — 55%"` (พร้อม cite) |

❌ `"คิดว่าน่าจะประมาณ 55% ครับ ถ้า verify ก็คงจะใช่"` — 4 hedges, ไม่ระบุชัด
✅ `"ผมเคยอ่านว่า Codex 55% แต่ยังไม่ได้ verify"` — 1 frame, ชัด

### 32.7 Name-Dropping Discipline (v2.2)

ห้าม name-drop brand/company/paper เพื่อ authority ถ้า verify ไม่ได้:

❌ `"Google, Microsoft, และ MIT ต่างก็ศึกษา..."` — 3 names ไม่มี paper
❌ `"ตามที่ Stanford 2023 study พบ..."` — paper ที่จำไม่ได้
✅ `"Wang et al. 2024 (arxiv:2404.xxxxx) — Codex 55% บน HumanEval"`

**ถ้าจะ name-drop ต้อง:**
1. มี paper/URL/link
2. หรือเป็น "claim ที่เคยได้ยิน" + hedge ชัด

### 32.8 Royal Anti-Pattern (v2.2)

คำลงท้ายราชาศัพท์ (หม่อม, พระ, ฯลฯ) ใน informal register = AI tell:

❌ `"หวังว่าจะเป็นประโยชน์ต่อท่านผู้อ่าน"` — ไม่มีใครเขียนแบบนี้ใน Slack
✅ `"หวังว่าพอเป็นประโยชน์"` — natural register

**Rule:** match register → royal form. Chat/standup = ไม่มี royal. UI = ไม่มี royal. Essay = ไม่มี royal ยกเว้น address monarch/อ้างอิงพระราชดำรัช.

### 32.9 Hallucination Context Switch (v2.2)

เมื่อ AI "context switch" จาก claim ที่ verify ได้ → claim ที่ verify ไม่ได้ → drop ทั้ง clause:

❌ `"Postgres trigger ใช้ `pg_notify` แล้ว Redis เคย benchmark 55% บน HumanEval"`
   — `pg_notify` verify ได้, "55% HumanEval" verify ไม่ได้, **drop ทั้ง clause**

✅ `"Postgres trigger ใช้ `pg_notify` ตามที่คุยกับ P'X (Slack 2026-06-02)"`
   — verify ได้ทั้งหมด

### 32.10 Anti-Fabrication Cheat Sheet (v2.2)

**ก่อนเขียน fact ใดๆ → check 3 คำถาม:**
1. **Verify ได้ไหม?** → ถ้าไม่: T1 DROP
2. **มี source ไหม?** → ถ้าไม่: T2 HEDGE หรือ T1
3. **ผู้อ่าน verify ต่อได้ไหม?** → ถ้าไม่: T1

**Default = T1.** เมื่อใดที่ลังเล → T1.

### 33. Connective Density (Thai Connector Cluster)

**Problem:** AI Thai text ชอบใช้ formal connector ติดกันบ่อยเกินไป จนขาด rhythm ของ natural speech/writing.

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

**Problem:** AI text variety-hacks โดยใช้ synonym ของคำเดียวกัน 2-3 ครั้งในย่อหน้าเดียว คนจริงเขียนคำเดิม.

**Rule:** ใช้คำเดิมซ้ำได้ — อย่า "variety-hack" ด้วย synonym ที่ดูแปลก.

❌ `"ระบบมีปัญหา (system issue) เพราะ platform ล่ม (down) และ infrastructure ล้มเหลว (failed)"`
✅ `"ระบบล่ม สาเหตุน่าจะมาจาก infra"`

**Thai variant:** `"ระบบล่ม" / "ระบบ down" / "platform เข้าไม่ได้"` — ใช้ 1-2 ครั้ง, ไม่ทั้ง 3 ในย่อหน้าเดียว

### 35. Topic-First vs Background-First (Standup Register)

**Problem:** AI เริ่มย่อหน้าด้วย background/context ก่อนเข้า topic. คนจริงเริ่มที่ topic.

❌ `"เมื่อวานทำงานหลายอย่าง รวมถึง TP-549 ที่ต้องแก้ measurement design และ merge PR #36 เข้า develop วันนี้เลย refocus ที่ TP-549"`
   — background 3 clauses, topic ท้าย

✅ `"TP-549 measurement design เริ่มแล้ว PR #36 merge แล้ว"`
   — topic first, แล้ว detail

**Standup order (v2.2):**
1. **✅ Done** (เรียงตาม priority: critical → nice)
2. **🎯 Next** (สิ่งที่จะทำวันนี้/พรุ่งนี้)
3. **🚧 Blocker** (รอใคร/รออะไร)
4. **🙋 Ask** (ต้องการความเห็น/คำตอบ)

### 36. Marketing Calques (UI/Notification Register)

**Problem:** AI UI text ใช้ marketing calque ที่อ่านแล้วไม่รู้จะทำอะไร.

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

**UI block max 3 short sentences.** ไม่มี emoji marketing.

### 36.1 UI-Actual vs UI-Aspirational (v2.2)

แยกให้ออก:
- **UI-actual**: บอกสิ่งที่เกิดขึ้น + ให้ผู้ใช้ทำอะไรต่อ
- **UI-aspirational**: บอกว่าระบบ "ดี" แต่ไม่ช่วยให้ผู้ใช้ทำอะไร

❌ `"เรามุ่งมั่นมอบประสบการณ์ที่ดีที่สุด"` (UI-aspirational)
✅ `"ชำระเงินไม่สำเร็จ ลองใหม่อีกครั้ง หรือเช็คยอดเงิน"` (UI-actual)

### 37. Nominalization Avoidance

**Problem:** AI แปลง verb เป็น noun เพื่อ "ฟังดูเป็นทางการ" — แต่คนจริงใช้ verb.

❌ `"การดำเนินการปรับปรุงประสิทธิภาพ"` — nominalization overload
✅ `"ปรับให้เร็วขึ้น"` — verb-first

**Common Thai nominalizations ที่ต้องระวัง:**
- `"การดำเนินการ"` → `"ทำ"` / drop
- `"การปรับปรุง"` → `"ปรับ"`
- `"การพัฒนา"` → `"พัฒนา"` (already a verb)
- `"การใช้งาน"` → `"ใช้"`
- `"การทดสอบ"` → `"ทดสอบ"`

### 38. Code-Switching Tells (Mixed Thai/English)

**Problem:** AI ใช้ English term แบบ "เพราะฟังดูเก่ง" แต่คนจริงใช้เพราะจำเป็น.

**Rule:** ใช้ English เมื่อ:
1. **Term ที่ใช้ในงานจริง** (`merge`, `deploy`, `staging`, `commit`, `PR`, `API`)
2. **Library/framework name** (`React`, `Bun`, `Postgres`, `Tailwind`)
3. **Concept ที่ไทยไม่มี/แปลแล้วเพี้ยน** (`webhook`, `middleware`, `race condition`)

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
- `555` (laughter) ≥1 ครั้ง
- Reaction emoji (`👍`, `🙏`, `😂`) ปน
- Particle: `ค่ะ` (หญิง) / `ครับ` (ชาย) / `จ้า` (หญิง informal) / no particle (มั่น)
- 1-10 คำ/ข้อความ
- ตัวย่อ: `อ่อ`, `จ้า`, `จริงดิ`, `555+`, `เหรอ`, `คับ` (informal ของ `ครับ`)

❌ `"สวัสดีค่ะ ดิฉันหวังว่าข้อความนี้จะเป็นประโยชน์ค่ะ"` — formal, AI
✅ `"สวัสดีค่ะ พอดีมีเรื่องอยากถาม"` — natural chat

#### 39.2 Register B — Standup/PR/Commit

**Tells:**
- ไม่มี particle (`ครับ`/`ค่ะ`) ทุกบรรทัด
- ไม่มี emoji ใน PR description (commit = `type(scope): message`)
- คำสั้น: `ผ่าน`, `รอ`, `merged`, `shipped`, `rolled back`, `WIP`
- Verbatim repo/PR/branch names
- Filter scope: dev own work

❌ `"วันนี้ดิฉันได้ทำการปรับปรุงระบบ API ค่ะ"` — formal, AI
✅ `"ปรับ API แล้ว PR #64 merged"`

#### 39.3 Register C — UI/Error/Notification

**Tells:**
- 1-3 ประโยค ต่อ block
- ≤25 คำ
- One opener with `ค่ะ/ครับ` เท่านั้น
- Action verb + 1 alternative (`ลอง X หรือ Y`)
- Status word first: `"ชำระเงินไม่สำเร็จ"`, `"บันทึกแล้ว"`, `"ยกเลิกเรียบร้อย"`
- ไม่มี "หวังว่า", "ขออภัย", "แจ้งให้ทราบ", "ยินดีให้ความช่วยเหลือ"

❌ `"ขออภัยในความไม่สะดวกค่ะ เราจะพยายามปรับปรุงให้ดีขึ้น"` — AI
✅ `"ชำระเงินไม่สำเร็จ ลองใหม่อีกครั้ง หรือเช็คยอดเงินค่ะ"` — UI-actual

#### 39.4 Register D — Prose/Blog/Strategy/Essay

**Tells:**
- 3-30 คำ/ประโยค สลับ rhythm
- Personal aside (`ผมเคย`, `ผมรู้สึกว่า`, `ผมไม่แน่ใจว่า`)
- Concrete image แทน abstraction
- ไม่มี "หวังว่าจะเป็นประโยชน์" closer
- ไม่มี "อนาคตสดใส", "ก้าวต่อไปจะเป็นการเดินทางสู่ความเป็นเลิศ"

❌ `"ในยุคปัจจุบัน AI กำลังเปลี่ยนแปลงโลกอย่างมาก ซึ่งส่งผลกระทบต่ออุตสาหกรรมต่างๆ"`
   — formal connector spam, generic claim

✅ `"AI เขียนโค้ดเก่งขึ้นทุกปี ผมยังนึกถึง agent ที่เขียนผ่านมาทั้งคืน — แต่ครึ่ง dev community ก็ยังบอกว่ามันนับไม่ได้"`
   — opinion, image, mixed rhythm

### 40. AI-Leaked Thai Closers (v2.2 — Comprehensive)

**Closers to drop ทุก register:**

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
