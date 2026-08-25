# Worked Examples (extends SKILL.md)

> ตัวอย่างการ apply 30 universal + 12 Thai-specific top-level patterns ใน `SKILL.md` + `patterns-thai.md` แบบเต็มรอบ: draft → "still-AI" bullets → final rewrite. ใช้เป็น reference ตอน stuck.
>
> ❌/✅ below = bad/good notation, not the decorative emoji §18 tells you to cut from real writing.
>
> **Language coverage:** Examples A–D below are Thai (or Thai↔EN mixed). The section after the side-by-side table covers **monolingual English** so the same rules apply when no Thai is in the draft.

---

## Full Example

**Before (AI-sounding — Thai mixed):**
> คำถามดีมากครับ! นี่คือภาพรวมของหัวข้อนี้ หวังว่าจะเป็นประโยชน์ครับ!
>
> AI-assisted coding serves as an enduring testament to the transformative potential of large language models marking a pivotal moment in the evolution of software development ใน today's rapidly evolving technological landscape these groundbreaking tools—nestled at the intersection of research and practice—are reshaping how engineers ideate, iterate, and deliver underscoring their vital role in modern workflows
>
> At its core the value proposition is clear streamlining processes enhancing collaboration and fostering alignment It's not just about autocomplete; it's about unlocking creativity at scale ensuring that organizations can remain agile while delivering seamless, intuitive, and powerful experiences to users The tool serves as a catalyst The assistant functions as a partner The system stands as a foundation for innovation
>
> Industry observers have noted that adoption has accelerated from hobbyist experiments to enterprise-wide rollouts from solo developers to cross-functional teams The technology has been featured in The New York Times, Wired, and The Verge Additionally the ability to generate documentation tests and refactors showcases how AI can contribute to better outcomes highlighting the intricate interplay between automation and human judgment
>
> - 💡 **Speed:** Code generation is significantly faster, reducing friction and empowering developers
> - 🚀 **Quality:** Output quality has been enhanced through improved training, contributing to higher standards
> - ✅ **Adoption:** Usage continues to grow, reflecting broader industry trends
>
> While specific details are limited based on available information it could potentially be argued that these tools might have some positive effect Despite challenges typical of emerging technologies—including hallucinations, bias, and accountability—the ecosystem continues to thrive In order to fully realize this potential teams must align with best practices
>
> ในที่สุด อนาคตของทีมสดใส ก้าวต่อไปจะเป็นการเดินทางสู่ความเป็นเลิศ แจ้งให้ทราบหากต้องการขยายความในส่วนใดส่วนหนึ่ง!

**Draft rewrite:**
> AI coding tools ทำงานบางอย่างเร็วขึ้น ในการศึกษาของ Google ปี 2024 นักพัฒนาที่ใช้ Codex ทำ simple functions เสร็จเร็วขึ้น 55% เทียบกับ control group แต่ debugging กับ architectural decisions ไม่ดีขึ้น
>
> เครื่องมือพวกนี้เก่งเรื่อง boilerplate: ไฟล์ config, test scaffolding, refactor ซ้ำๆ แต่ไม่รู้ว่าตัวเองผิดตอนไหน ผมเคย mass-accept suggestion ที่ compile ผ่าน, ผ่าน lint, แต่ทำผิดอยู่ดี เพราะผมหยุด pay attention
>
> มิร่า engineer ที่ fintech startup ที่ผมสัมภาษณ์ บอกว่าใช้ Copilot "เหมือน autocomplete สำหรับโค้ดน่าเบื่อๆ" แต่ review ทุกบรรทัดก่อน commit เจค senior dev ที่บริษัทใหญ่กว่า disable มัน หลังจากมันชอบ suggest pattern จาก deprecated internal library
>
> Productivity claims ยากจะ verify GitHub บอกว่า Copilot users "accept 30% of suggestions" แต่ acceptance ไม่ใช่ correctness และ correctness ไม่ใช่ value การศึกษาของ Uplevel ปี 2024 ไม่เจอ statistically significant difference ใน pull-request throughput ระหว่างทีมที่มีกับไม่มี AI assistant
>
> ไม่ได้แปลว่าเครื่องมือพวกนี้ไร้ประโยชน์ แปลว่ามันคือเครื่องมือ มันแทน judgment ไม่ได้ และตัดความจำเป็นของ test ไม่ได้ ถ้าคุณไม่มี test คุณบอกไม่ได้ว่า suggestion ถูกหรือเปล่า

**What makes the below so obviously AI generated?**
- The rhythm is still a bit too tidy (clean contrasts, evenly paced paragraphs).
- The named people and study citations can read like plausible-but-made-up placeholders unless they're real and sourced. — **For Thai: ยิ่งเป็นชื่อไทย/สถิติไทยที่ไม่เคยได้ยิน ต้อง suspect**
- The closer leans a touch slogan-y ("ถ้าคุณไม่มี test...") rather than sounding like a person talking.

**Now make it not obviously AI generated.**
> AI coding tools เร่งความเร็วตรงส่วนน่าเบื่อได้ ไม่ใช่ทุกส่วน ไม่ใช่ architecture
>
> เก่งเรื่อง boilerplate: ไฟล์ config, test scaffolding, refactor แบบเดิมๆ แต่ก็เก่งเรื่องฟังดูถูกทั้งที่ผิด ผมเคย accept suggestion ที่ compile ผ่าน ผ่าน lint แต่พลาดประเด็นเพราะหยุด pay attention
>
> คนที่ผมคุยด้วยแบ่งเป็นสองฝั่ง บางคนใช้เหมือน autocomplete สำหรับงานน่าเบื่อ แล้ว review ทุกบรรทัด อีกฝั่ง disable ไปเลยหลังมันชอบ suggest pattern ที่ไม่อยากได้ ทั้งสองฝั่งมีเหตุผลของตัวเอง
>
> Productivity metrics ลื่นไหล GitHub บอก Copilot users "accept 30% of suggestions" แต่ acceptance ไม่ใช่ correctness และ correctness ไม่ใช่ value ถ้าคุณไม่มี test คุณเดาอยู่ดี

**Changes made:** Stripped the chatbot framing (I hope this helps, Let me know), significance inflation (pivotal moment, broader trends), promotional and -ing padding (underscoring, fostering), rule-of-three and synonym cycling (catalyst/partner/foundation), false ranges (from X to Y), copula avoidance (serves as, stands as), em dashes/emojis/boldface/curly quotes, the formulaic "challenges" section, cutoff and hedging disclaimers, filler and persuasive framing, the generic upbeat conclusion (อนาคตสดใส), and the sycophantic opening (คำถามดีมากครับ). Then rebuilt the voice with varied rhythm and concrete detail, and applied §0 register choice (dev register mixed Thai-English, internal team voice) plus §31 terminology (kept "AI coding tools" ไม่แปล, kept "Copilot", kept technical terms in English).

---

## Grit Gate: Soulless vs Alive

Same facts, neutral report → real voice. Illustrates `SKILL.md`'s Grit Gate (surface the grit,
commit to a point of view):

> ❌ การทดลองนี้ได้ผลลัพธ์ที่น่าสนใจ agent สร้างโค้ดได้ 3 ล้านบรรทัด developer บางส่วนประทับใจ ขณะที่บางส่วนยังคงมีข้อสงสัย
> ✅ ผมเองก็ยังไม่รู้จะรู้สึกยังไงกับอันนี้ agent เขียนโค้ดไป 3 ล้านบรรทัดตอนคนน่าจะหลับอยู่ ครึ่ง dev community ตื่นเต้น อีกครึ่งเถียงว่ามันนับไม่ได้

---

## Process Step Rationale

Failure modes for `SKILL.md`'s Process and Output steps, in full — the numbered steps there link here rather than carry this inline.

- **Step 1 (Identify every tell):** stopping after the loudest tells (em dash, "delve") and missing a cluster that only shows up on a full pass.
- **Step 2 (Draft rewrite):** deleting AI-isms without adding grit — lands in the "clean but neutral" safe middle the Grit Gate scores ~30/100 AI, not 0. Also: overriding your own step-1 "not a tell" call mid-rewrite without saying so — an untracked change like that can't get caught by step 3/4, since it was never named as a problem in the first place.
- **Step 4 (Final rewrite):** treating the em-dash check as a stylistic reminder instead of a literal character scan — stating an intention to remove em dashes in a change summary is not the same as checking the delivered text for `—`. A fixture run once claimed em dashes were cut while two remained in the shipped rewrite. Also: a final rewrite indistinguishable from the draft — if step 3 found nothing, re-run step 3, don't skip step 4. Also: naming a real weakness in step 3 and then shipping it unchanged in step 4 without ever revisiting it — step 3 and step 4 have to actually connect, not run as two independent exercises.

---

## Per-Register Worked Examples (v2.2)

ตัวอย่างการ apply register selection gate (SKILL.md §0) + patterns ต่อ register.

### Example A — Chat / LINE (Register A)

**Before (AI-sounding — too formal for chat):**
> สวัสดีค่ะ ดิฉันขอเรียนให้ทราบว่าวันนี้ระบบอาจจะมีความไม่เสถียรเล็กน้อย อันเนื่องมาจากการปรับปรุงระบบ backend หวังว่าจะไม่เป็นการรบกวนค่ะ ยินดีให้ความช่วยเหลือหากมีข้อสงสัยค่ะ

**Red flags:**
- `"ดิฉัน"` (formal 3rd person, AI in chat)
- `"ขอเรียนให้ทราบ"` (formal opener)
- `"อันเนื่องมาจาก"` (translation of "due to the fact that")
- `"ความไม่เสถียรเล็กน้อย"` (vague understatement)
- `"หวังว่าจะไม่เป็นการรบกวน"` (sycophantic hedge)
- `"ยินดีให้ความช่วยเหลือหากมีข้อสงสัย"` (AI-leaked closer)

**After (chat register):**
> สวัสดีค่ะ วันนี้ backend ปรับนิดหน่อย อาจจะเข้าไม่ได้บ้าง 5-10 นาที ถ้าเจอปัญหาทักมาค่ะ 🙏

**Changes applied:**
- Drop formal 3rd person → `ค่ะ` opener (chat register female)
- `backend` เก็บอังกฤษ (dev term)
- `5-10 นาที` = concrete estimate (real window ที่ maintenance จริง)
- `ทักมา` action verb (UI-actual)
- 🙏 emoji แทน formal closer

### Example B — Standup (Register B)

**Before (AI-sounding — too narrative):**
> สวัสดีครับ วันนี้ดิฉันได้ทำการปรับปรุง API endpoint ในส่วนของ measurement redesign รวมถึง merge PR #64 เข้าสู่ develop branch นอกจากนี้ยังได้ review code ของเพื่อนร่วมทีมอีก 2 ท่าน พร้อมทั้งอัปเดต documentation ให้ทันสมัย

**Red flags:**
- `"ดิฉัน"` (3rd person, AI)
- `"ได้ทำการปรับปรุง"` (nominalization)
- `"นอกจากนี้ยัง"` (formal connector spam)
- `"เพื่อนร่วมทีมอีก 2 ท่าน"` (vague — ไม่ระบุ PR, ไม่ระบุชื่อ)
- `"อัปเดต documentation ให้ทันสมัย"` (vague — ไฟล์อะไร, PR อะไร)

**After (standup register — Standup Reporting Style from [[feedback_standup_reporting]]):**
```
✅ ทำเสร็จ
- TP-549: PR #64 measurement redesign merged เข้า develop
- review: PR #62 (P'Meow), PR #65 (P'Noi)

🎯 ต่อไป
- TP-549: เขียน strategy brief ส่ง P'Big ก่อน deploy prod

🚧 รอ
- camera firmware dependency — P'X ยังไม่ส่ง release note

🙋 ถาม
- TP-549 deploy timing — จะ roll forward ตอน traffic ต่ำ หรือ soak 7 วันก่อน?
```

**Changes applied:**
- 1st person implied (drop `ดิฉัน`/`ผม`)
- Verbatim ticket ID (`TP-549`), PR number (`#64`), branch (`develop`)
- 4-section structure (✅🎯🚧🙋) ตาม team format
- Topic-first opener (`TP-549:`)
- Particle ไม่ลงท้ายทุกบรรทัด (terse)
- Filter scope: own work (P'Meow/P'Noi = review by others, ไม่ใช่ own PR)

### Example C — UI Error Message (Register C)

**Before (AI-sounding — marketing fluff):**
> ขออภัยในความไม่สะดวกค่ะ! การชำระเงินของท่านไม่สำเร็จ อันเนื่องมาจากระบบของธนาคารปฏิเสธการทำรายการ เรามุ่งมั่นมอบประสบการณ์ที่ดีที่สุด และพร้อมให้บริการท่านตลอด 24 ชั่วโมงค่ะ

**Red flags:**
- `"ขออภัยในความไม่สะดวกค่ะ!"` (sycophantic opener)
- `"อันเนื่องมาจาก"` (formal connector)
- `"ท่าน"` (royal register ใน UI — overkill)
- `"มุ่งมั่นมอบประสบการณ์ที่ดีที่สุด"` (UI-aspirational, marketing calque)
- `"พร้อมให้บริการท่านตลอด 24 ชั่วโมง"` (UI-leaked closer)

**After (UI-actual):**
> ชำระเงินไม่สำเร็จ
> ธนาคารปฏิเสธรายการ ลองใหม่อีกครั้ง หรือเช็คยอดเงินค่ะ
> ติดปัญหา: ทักแชทหรือโทร 02-123-4567

**Changes applied:**
- Status word first (`ชำระเงินไม่สำเร็จ`)
- `ถูกปฏิเสธ` (ไม่ใช่ "ปฏิเสธการทำรายการ" — drop nominalization)
- Actionable next step: `ลองใหม่อีกครั้ง` / `เช็คยอดเงิน` / `ทักแชท`
- One `ค่ะ` opener เท่านั้น (UI formal register)
- ไม่มี title parenthetical English (`## การชำระเงิน (Declined)` ❌)
- ≤25 คำ
- ไม่มี "ขออภัย", "มุ่งมั่น", "พร้อมให้บริการ"

### Example D — Prose / Blog (Register D)

(See full example above. v2.2 adds: §32.1 anti-fabrication tier tree, §32.3 cite-as-published, §40 closers drop.)

**v2.2 specific fix in the prose example:**
- ❌ `"Google ปี 2024 Codex 55% เร็วขึ้น"` → ✅ `"Wang et al. 2024 (arxiv:2404.xxxxx) — Codex 55% บน HumanEval"` (T3 cite)
- ❌ `"มิร่า engineer ที่ fintech startup ที่ผมสัมภาษณ์ บอกว่า..."` → ระบุชื่อ + วันที่สัมภาษณ์ หรือ drop
- ❌ `Uplevel ปี 2024 ไม่เจอ statistically significant difference` → ตรวจ paper จริง หรือ drop
- ❌ `"หวังว่าจะเป็นประโยชน์"` closer → drop
- ❌ `"ถ้าคุณไม่มี test คุณบอกไม่ได้ว่า suggestion ถูกหรือเปล่า"` slogan-y closer → soften or drop

### Side-by-Side: Same Content, 4 Registers

ผมเขียน `ผมได้ merge PR #64 เข้า develop แล้ว measurement redesign เสร็จเรียบร้อย`:

| Register | Rewrite | Why |
|----------|---------|-----|
| **A** (chat) | `"merge แล้วค่ะ PR #64 🎉"` | terse, emoji, 1st-line topic |
| **B** (standup) | `"✅ TP-549 PR #64 merged เข้า develop"` | emoji + ticket + scope |
| **C** (UI) | `"บันทึกการเปลี่ยนแปลงเรียบร้อย"` | status-word-first, action-complete |
| **D** (blog) | `"PR #64 merge เข้า develop เมื่อเช้า เป็นก้าวแรกของ measurement redesign — ก้าวต่อไปคือ..."` | narrative, personal, longer |

**Rule:** same fact, different register → different sentence shape, different particle, different length. ใช้ register ที่ผู้อ่านอยู่, ไม่ใช่ register ที่ "ฟังดูดี".


---

## Monolingual English Examples (v3.0)

Same catalog (30 universal + 12 Thai-specific top-level in `patterns-thai.md`), but applied to drafts that contain **no Thai**. Useful when the user writes internal EN-only docs, EN UI copy, or EN strategy/blog prose. Universal patterns (§1-§30 in `SKILL.md`) all apply; Thai-specific patterns (§31-§42 in `patterns-thai.md`) are skipped.

### Example E — EN UI Error (Stripe-style)

**Register:** C (UI / error / notification). Language axis: EN. Particle: none.

**Before (AI-sounding — chatbot-flavored):**
> Oops! It looks like your payment couldn't be processed at this time. Don't worry, our team is working diligently to ensure a seamless experience for you. This serves as a testament to our commitment to security. Please try again, and feel free to reach out if you have any questions — we're here to help!

**Red flags:**
- `"Oops!"` + `"It looks like"` — chatbot-flavored, not Stripe-actual
- `"Don't worry"` — sycophantic reassurance
- `"working diligently to ensure a seamless experience"` — promotional padding + AI vocab (`diligently`, `seamless`)
- `"serves as a testament to our commitment"` — significance puffing
- `"feel free to reach out"` — servile closer
- `"— we're here to help!"` — em dash + sycophantic closer

**After (EN UI — register C):**
> Card was declined.
> Try a different card, or contact your bank.
> Need help? support@example.com

**Changes applied:**
- Status word first (`Card was declined.`)
- Plain verb (`Try a different card`) instead of nominalization
- Actionable next step + concrete channel
- No opener, no closer, no "we"
- ≤25 words, 3 short lines (UI-actual density)

### Example F — EN Standup / Slack message

**Register:** B (Standup / PR / commit). Language axis: EN. Particle: none.

**Before (AI-sounding — narrative + puffing):**
> I hope everyone is doing well! I wanted to provide a quick update on the work I completed this week. Notably, I successfully merged PR #847 which represents a pivotal milestone in our migration journey. Additionally, I undertook a comprehensive refactor of the authentication module, showcasing my commitment to code quality. Furthermore, I collaborated with cross-functional stakeholders to align on best practices. Looking ahead, I will be leveraging my expertise to drive innovation.

**Red flags:**
- `"I hope everyone is doing well!"` — chatbot opener
- `"successfully merged"` — significance puffing (`successfully` adds nothing)
- `"represents a pivotal milestone"` — §1 emphasis on legacy
- `"undertook a comprehensive refactor"` — nominalization + AI-vocab
- `"showcasing my commitment"` — promotional + -ing ending
- `"collaborated with cross-functional stakeholders"` — vague weasel attribution
- `"align on best practices"` — vague-upbeat contentless verb
- `"leverage expertise to drive innovation"` — AI-vocab pileup
- Em dash + 1st-person throughout (standup author speaks from their own experience, not a narrated CV)

**After (EN standup — register B):**
> PR #847 merged to develop. Auth refactor landed in the same PR — break it into chunks for review next time.
>
> Reviewed: PR #842 (Sam), PR #851 (Priya). Both have my notes inline.
>
> Next: pick up the migration ticket for the analytics module, will flag blockers in #eng-help.

**Changes applied:**
- 1st-person implied (drop "I" at sentence start, keep it where ownership is real)
- Verbatim PR numbers, branch names, person names — no vague stakeholders
- `-` for tight asides, not em dashes
- Topic-first (PR #847 / Reviewed: / Next:)
- No closer, no "I'm excited", no "leverage"
- ≤80 words across 3 short paragraphs

### Example G — EN Prose / Blog (register D)

**Before (AI-sounding — significance + rule of three + vague attribution):**
> The rise of remote work stands as a testament to the evolving nature of the modern workforce. It's not just about flexibility; it's about unlocking human potential at scale. Industry observers have noted that companies embracing this shift are fostering a culture of innovation, collaboration, and accountability. The future of work is bright, and those who adapt will thrive in this new landscape.

**Red flags:**
- `"stands as a testament to"` — §1 significance + §8 copula avoidance
- `"the evolving nature of"` — vague-upbeat filler
- `"It's not just about... it's about"` — §9 negative parallelism
- `"unlocking human potential at scale"` — promotional + rule-of-three bait
- `"Industry observers have noted"` — §5 vague attribution
- `"fostering a culture of innovation, collaboration, and accountability"` — §10 rule of three + §3 -ing ending
- `"The future of work is bright"` — §25 generic positive conclusion
- `"those who adapt will thrive in this new landscape"` — landscape = §7 AI vocab

**After (EN prose — register D):**
> Three years after we switched to async-first, the things that surprised me weren't the ones I expected. The big one: written decisions make weaker ideas die faster. A bad proposal that would have survived an hour-long meeting in 2019 gets three Slack replies saying "wait, why" and quietly gets revised by Friday.
>
> The smaller surprise: people who never spoke up in meetings started writing long, careful docs. Not because we asked them to. Because the medium fit.
>
> I'm not claiming async is better. I'm claiming the medium does more work than I gave it credit for.

**Changes applied:**
- Specific anchor ("three years after we switched") — not a vague "evolution"
- Personal voice ("surprised me", "I'm not claiming")
- Mixed sentence length (short + long, varied rhythm)
- No rule of three, no "industry observers", no "landscape"
- Skeptical ending that lands somewhere real ("the medium does more work than I gave it credit for") — not a slogan
- No em dashes, no "I'd love to hear your thoughts" closer

### Side-by-Side: Same content, monolingual EN

`"merged PR #847 to develop; auth refactor landed in the same PR — break it into chunks for review next time"`:

| Register | Rewrite | Why |
|----------|---------|-----|
| **A** (chat, EN) | `"PR #847's in 🎉"` | terse, emoji, no detail |
| **B** (standup, EN) | `"PR #847 merged. auth refactor in same PR — chunk next time"` | ticket + scope + improvement |
| **C** (UI, EN) | `"PR #847 merged to develop."` | status-only, no narrator |
| **D** (blog, EN) | `"We merged PR #847 to develop this morning. The auth refactor rode along in the same commit — splitting review by feature would have been cleaner, in retrospect."` | narrative, first-person, hindsight |
