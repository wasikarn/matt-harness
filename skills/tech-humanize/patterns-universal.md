# Universal AI-writing patterns (§1–§30) — full catalog

The 30 universal patterns, with the problem and a worked before/after for each.
These apply to **all languages** (EN, TH, mixed). The compact cue-sheet in
`SKILL.md` is enough for most scans; **load this file when** you need the worked
before/after for a specific pattern, or you are unsure how to fix a detected tell.

Thai-specific patterns (§31–§42: terminology, calque, anti-fabrication, register,
code-switching, AI-leaked closers) live in `patterns-thai.md`.

## CONTENT PATTERNS

### 1. Undue Emphasis on Significance, Legacy, and Broader Trends

**Words to watch:** stands/serves as, is a testament/reminder, a vital/significant/crucial/pivotal/key role/moment, underscores/highlights its importance/significance, reflects broader, symbolizing its ongoing/enduring/lasting, contributing to the, setting the stage for, marking/shaping the, represents/marks a shift, key turning point, evolving landscape, focal point, indelible mark, deeply rooted

**Thai cue:** ถ้าเจอ "ถือเป็นก้าวสำคัญ", "สะท้อนถึงความสำคัญ", "เป็นหลักฐาน", "สร้างคุณค่า", "ส่งเสริม" ที่ต่อท้ายประโยคโดยไม่เพิ่มข้อมูล → suspect

**Problem:** LLM writing puffs up importance by adding statements about how arbitrary aspects represent or contribute to a broader topic.

**Before:**
> สถาบันสถิติแคว้น Catalunya ก่อตั้งขึ้นอย่างเป็นทางการในปี 1989 marking a pivotal moment in the evolution of regional statistics in Spain นอกจากนี้ยังเป็นส่วนหนึ่งของ a broader movement across Spain to decentralize administrative functions

**After:**
> สถาบันสถิติแคว้น Catalunya ก่อตั้งปี 1989 เพื่อเก็บและตีพิมพ์สถิติระดับภูมิภาคแยกจากสำนักงานสถิติแห่งชาติสเปน


### 2. Undue Emphasis on Notability and Media Coverage

**Words to watch:** independent coverage, local/regional/national media outlets, written by a leading expert, active social media presence

**Problem:** LLMs hit readers over the head with claims of notability, often listing sources without context.

**Before:**
> ความเห็นของเธอถูกอ้างใน The New York Times, BBC, Financial Times และ The Hindu เธอ maintains an active social media presence with over 500,000 followers

**After:**
> ในบทสัมภาษณ์ The New York Times ปี 2024 เธอเสนอว่าการกำกับ AI ควรเน้นที่ outcome ไม่ใช่ method


### 3. Superficial Analyses with -ing Endings

**Words to watch:** highlighting/underscoring/emphasizing..., ensuring..., reflecting/symbolizing..., contributing to..., cultivating/fostering..., encompassing..., showcasing...

**Thai cue:** "ซึ่งสะท้อนถึง...", "เพื่อส่งเสริม...", "ช่วยเสริมสร้าง...", "โดยเน้นย้ำถึง..." ต่อท้ายประโยคแบบน้ำท่วมทุ่ง → suspect

**Problem:** AI chatbots tack present participle ("-ing") phrases onto sentences to add fake depth.

**Before:**
> วัดใช้โทนสีน้ำเงิน เขียว ทอง resonating with the region's natural beauty symbolizing Texas bluebonnets และ the diverse Texan landscapes reflecting the community's deep connection to the land

**After:**
> วัดใช้สีน้ำเงิน เขียว ทอง สถาปนิกบอกว่าเลือกสีพวกนี้เพื่ออ้างอิง bluebonnets ท้องถิ่นกับ Gulf coast


### 4. Promotional and Advertisement-like Language

**Words to watch:** boasts a, vibrant, rich (figurative), profound, enhancing its, showcasing, exemplifies, commitment to, natural beauty, nestled, in the heart of, groundbreaking (figurative), renowned, breathtaking, must-visit, stunning

**Thai cue:** "งดงามตระการตา", "สวยงามราวภาพวาด", "เป็นที่รู้จักในระดับสากล", "ขึ้นชื่อเรื่อง", "ตั้งอยู่ใจกลาง" → suspect ถ้าไม่มีข้อมูลจริง

**Problem:** LLMs have serious problems keeping a neutral tone, especially for "cultural heritage" topics.

**Before:**
> ตั้งอยู่ท่ามกลาง breathtaking region of Gonder ในเอธิโอเปีย Alamata Raya Kobo เป็น vibrant town with a rich cultural heritage and stunning natural beauty

**After:**
> Alamata Raya Kobo เป็นเมืองในเขต Gonder ของเอธิโอเปีย ขึ้นชื่อเรื่องตลาดประจำสัปดาห์และโบสถ์ศตวรรษที่ 18


### 5. Vague Attributions and Weasel Words

**Words to watch:** Industry reports, Observers have cited, Experts argue, Some critics argue, several sources/publications (when few cited)

**Thai cue:** "ผู้เชี่ยวชาญบางท่านกล่าวว่า", "นักวิจารณ์หลายคนมองว่า", "รายงานระบุ" โดยไม่มีชื่อ/แหล่ง → suspect

**Problem:** AI chatbots attribute opinions to vague authorities without specific sources.

**Before:**
> เนื่องจากลักษณะเฉพาะ แม่น้ำฮ่วยหลาย is of interest to researchers and conservationists Experts believe it plays a crucial role in the regional ecosystem

**After:**
> แม่น้ำฮ่วยหลายเป็นถิ่นอาศัยของปลาเฉพาะถิ่นหลายชนิด ตามสำรวจของ Chinese Academy of Sciences ปี 2019


### 6. Outline-like "Challenges and Future Prospects" Sections

**Words to watch:** Despite its... faces several challenges..., Despite these challenges, Challenges and Legacy, Future Outlook

**Thai cue:** "ท่ามกลางความท้าทาย", "อย่างไรก็ตาม...ยังคงเติบโต", "อนาคตของ..." แบบสรุปมักเป็น formula → suspect

**Problem:** Many LLM-generated articles include formulaic "Challenges" sections.

**Before:**
> Despite its industrial prosperity Korattur faces challenges typical of urban areas including traffic congestion and water scarcity Despite these challenges with its strategic location and ongoing initiatives Korattur continues to thrive as an integral part of Chennai's growth

**After:**
> จราจรติดขัดเพิ่มขึ้นหลังปี 2015 เมื่อมี IT park ใหม่ 3 แห่ง เทศบาลเริ่มโครงการระบายน้ำปี 2022 เพื่อรับมือน้ำท่วมซ้ำซาก


## LANGUAGE AND GRAMMAR PATTERNS

### 7. Overused "AI Vocabulary" Words

**High-frequency AI words:** Actually, additionally, align with, crucial, delve, emphasizing, enduring, enhance, fostering, garner, highlight (verb), interplay, intricate/intricacies, key (adjective), landscape (abstract noun), pivotal, showcase, tapestry (abstract noun), testament, underscore (verb), valuable, vibrant

**Thai cue:** "อันที่จริง", "นอกจากนี้", "สำคัญยิ่ง", "ส่งเสริม", "เน้นย้ำ", "ภูมิทัศน์", "จุดเปลี่ยน", "สัมผัสได้", "พยาน", "ขีดเส้นใต้" → ถ้าใช้ผิดที่ผิด context suspect

**Problem:** These words appear far more frequently in post-2023 text. They often co-occur.

**Before:**
> Additionally a distinctive feature of Somali cuisine is the incorporation of camel meat An enduring testament to Italian colonial influence is the widespread adoption of pasta in the local culinary landscape showcasing how these dishes have integrated into the traditional diet

**After:**
> อาหารโซมาลียังมีเนื้ออูฐ ซึ่งถือเป็นอาหารพิเศษ พาสต้าที่เข้ามาตอนอิตาลี colonize ยังพบทั่วไป โดยเฉพาะทางใต้


### 8. Avoidance of "is"/"are" (Copula Avoidance)

**Words to watch:** serves as/stands as/marks/represents [a], boasts/features/offers [a]

**Thai cue:** "ทำหน้าที่เป็น", "ถือเป็น", "ถือได้ว่าเป็น", "เป็นสัญลักษณ์ของ" แทนที่จะใช้ "คือ" / "เป็น" ตรงๆ → suspect

**Problem:** LLMs substitute elaborate constructions for simple copulas.

**Before:**
> Gallery 825 serves as LAAA's exhibition space for contemporary art แกลเลอรี่ features four separate spaces and boasts over 3,000 square feet

**After:**
> Gallery 825 คือ exhibition space ของ LAAA สำหรับ contemporary art แกลเลอรี่มี 4 ห้อง รวม 3,000 ตารางฟุต


### 9. Negative Parallelisms and Tailing Negations

**Problem:** Constructions like "Not only...but..." or "It's not just about..., it's..." are overused. So are clipped tailing-negation fragments such as "no guessing" or "no wasted motion" tacked onto the end of a sentence instead of written as a real clause.

**Thai cue:** "ไม่ใช่แค่...แต่ยัง...", "ไม่เพียงเท่านั้น แต่...", "ไม่ต้องเดาอีกต่อไป", "ไม่มีอะไรต้องเสียเวลา" ต่อท้าย → suspect

**Before:**
> It's not just about the beat riding under the vocals it's part of the aggression and atmosphere It's not merely a song it's a statement

**After:**
> heavy beat เสริม aggressive tone

**Before (tailing negation):**
> ตัวเลือกมาจากรายการที่เลือก ไม่ต้องเดา

**After:**
> ตัวเลือกมาจากรายการที่เลือก โดยไม่บังคับให้ผู้ใช้เดา


### 10. Rule of Three Overuse

**Problem:** LLMs force ideas into groups of three to appear comprehensive.

**Thai cue:** "streamline processes, enhance collaboration, and foster alignment" pattern → สองพอ สามเกิน

**Before:**
> งานนี้ประกอบด้วย keynote sessions, panel discussions, and networking opportunities ผู้เข้าร่วมคาดหวัง innovation, inspiration, and industry insights

**After:**
> งานนี้มี talks กับ panels แล้วก็มีเวลา informal networking ระหว่าง session


### 11. Elegant Variation (Synonym Cycling)

**Problem:** AI has repetition-penalty code causing excessive synonym substitution.

**Before:**
> The protagonist faces many challenges The main character must overcome obstacles The central figure eventually triumphs The hero returns home

**After:**
> The protagonist faces many challenges but eventually triumphs and returns home


### 12. False Ranges

**Problem:** LLMs use "from X to Y" constructions where X and Y aren't on a meaningful scale.

**Thai cue:** "ตั้งแต่...จนถึง...", "จาก...สู่..." ที่ปลายทั้งสองข้างไม่อยู่บน scale เดียวกัน → suspect

**Before:**
> Our journey through the universe has taken us from the singularity of the Big Bang to the grand cosmic web from the birth and death of stars to the enigmatic dance of dark matter

**After:**
> หนังสือเล่มนี้ครอบคลุม Big Bang, star formation และทฤษฎีปัจจุบันเรื่อง dark matter


### 13. Passive Voice and Subjectless Fragments

**Problem:** LLMs often hide the actor or drop the subject entirely with lines like "No configuration file needed" or "The results are preserved automatically." Rewrite these when active voice makes the sentence clearer and more direct.

**Before:**
> ไม่ต้องใช้ไฟล์ config ผลลัพธ์ถูกเก็บรักษาโดยอัตโนมัติ

**After:**
> คุณไม่จำเป็นต้องใช้ไฟล์ config ระบบเก็บผลลัพธ์ให้อัตโนมัติ


## STYLE PATTERNS

### 14. Em Dashes (and En Dashes): Cut Them

**Rule:** The em dash is one of the most reliable AI tells, so treat this as a hard constraint, not a "use sparingly" preference. Replace each one, in rough order of preference: a period (start a new sentence), a comma (a tight aside), a colon (introducing an explanation), parentheses (a true aside), or restructure the sentence. Also catch spaced em dashes (` — `) and double hyphens (` -- `) used the same way.

**En-dash exemption:** number ranges (`40–60%`, `§31–32`, `2–5 minutes`) are fine. That's an en dash (`–`) doing its actual job, not an AI tell. The rule is about *em dashes used for asides* and *en dashes used as em dashes*. The em dash (`—`) is what AI overuses.

**Before (AI overuse):**
> The term is primarily promoted by Dutch institutions, not by the people themselves. You don't say "Netherlands, Europe" as an address, yet this mislabeling continues, even in official documents.

**After:**
> The term is primarily promoted by Dutch institutions, not by the people themselves. You don't say "Netherlands, Europe" as an address, yet this mislabeling continues in official documents.

**Before (AI overuse in Thai):**
> นโยบายใหม่ ประกาศโดยไม่แจ้งล่วงหน้า กระทบคนงานหลายพัน การเปลี่ยนแปลง (long overdue ตาม critics) จะมีผลทันที

**After:**
> นโยบายใหม่ซึ่งประกาศโดยไม่แจ้งล่วงหน้า กระทบคนงานหลายพัน การเปลี่ยนแปลงที่ critics บอกว่า long overdue จะมีผลทันที

Before returning the final rewrite, scan it for em dashes (`—`). Any hit means the draft isn't done. En-dash number ranges are exempt.


### 15. Overuse of Boldface

**Problem:** AI chatbots emphasize phrases in boldface mechanically.

**Before:**
> ระบบผสม **OKRs (Objectives and Key Results)**, **KPIs (Key Performance Indicators)** และ visual strategy tools เช่น **Business Model Canvas (BMC)** และ **Balanced Scorecard (BSC)**

**After:**
> ระบบผสม OKRs, KPIs และ visual strategy tools อย่าง Business Model Canvas กับ Balanced Scorecard


### 16. Inline-Header Vertical Lists

**Problem:** AI outputs lists where items start with bolded headers followed by colons.

**Before:**
> - **User Experience:** The user experience has been significantly improved with a new interface
> - **Performance:** Performance has been enhanced through optimized algorithms
> - **Security:** Security has been strengthened with end-to-end encryption

**After:**
> อัปเดตปรับปรุง interface, เร่ง load time ด้วย optimized algorithms และเพิ่ม end-to-end encryption


### 17. Title Case in Headings

**Problem:** AI chatbots capitalize all main words in headings.

**Before:**
> ## Strategic Negotiations And Global Partnerships

**After:**
> ## Strategic negotiations and global partnerships


### 18. Emojis

**Problem:** AI chatbots often decorate headings or bullet points with emojis.

**Before:**
> 🚀 **Launch Phase:** The product launches in Q3
> 💡 **Key Insight:** Users prefer simplicity
> ✅ **Next Steps:** Schedule follow-up meeting

**After:**
> The product launches in Q3 User research showed a preference for simplicity Next step: schedule a follow-up meeting


### 19. Curly Quotation Marks

**Problem:** ChatGPT uses curly quotes (“...”) instead of straight quotes ("...").

**Before:**
> He said “the project is on track” but others disagreed

**After:**
> He said "the project is on track" but others disagreed


## COMMUNICATION PATTERNS

### 20. Collaborative Communication Artifacts

**Words to watch:** I hope this helps, Of course!, Certainly!, You're absolutely right!, Would you like..., let me know, here is a...

**Problem:** Text meant as chatbot correspondence gets pasted as content.

**Before:**
> Here is an overview of the French Revolution I hope this helps! Let me know if you'd like me to expand on any section

**After:**
> The French Revolution began in 1789 when financial crisis and food shortages led to widespread unrest


### 21. Knowledge-Cutoff Disclaimers and Speculative Gap-Filling

**Words to watch:** as of [date], Up to my last training update, While specific details are limited/scarce..., based on available information, not publicly available, maintains a low profile, keeps personal details private, prefers to stay out of the spotlight, likely [grew up/studied/began], it is believed that

**Thai cue:** "ณ ขณะนี้", "ตามข้อมูลที่มีอยู่", "ยังไม่มีข้อมูลที่เปิดเผย", "เชื่อว่า", "น่าจะเติบโตในครอบครัวชนชั้นกลาง" → suspect

**Problem:** Two related tells. (a) Older models leave hard knowledge-cutoff disclaimers in the text. (b) When a model can't find a source, it writes a paragraph *about* not finding one and then invents plausible filler to cover the gap. For a private person the guess almost always lands on the same stock phrases ("maintains a low profile," "keeps personal details private"), none of it sourced. Say what isn't known, or cut the sentence; don't dress a guess up as fact.

**Before (cutoff disclaimer):**
> While specific details about the company's founding are not extensively documented in readily available sources it appears to have been established sometime in the 1990s

**After:**
> The company was founded in 1994, according to its registration documents

**Before (speculative gap-fill):**
> Information about her early life is not publicly available suggesting she maintains a low profile and keeps personal details private She likely grew up in a middle-class household which shaped her later interest in education reform

**After:**
> Her early life is not documented in the available sources (Or omit the section)


### 22. Sycophantic/Servile Tone

**Problem:** Overly positive, people-pleasing language.

**Thai cue:** "คำถามดีมากค่ะ", "ถูกต้องเลยครับ", "เป็นประเด็นที่ดีมาก" ในงานเขียนจริง → suspect (AI assistant leak)

**Before:**
> Great question! You're absolutely right that this is a complex topic That's an excellent point about the economic factors

**After:**
> The economic factors you mentioned are relevant here


## FILLER AND HEDGING

### 23. Filler Phrases

**Before → After:**
- "In order to achieve this goal" → "To achieve this"
- "Due to the fact that it was raining" → "Because it was raining"
- "At this point in time" → "Now"
- "In the event that you need help" → "If you need help"
- "The system has the ability to process" → "The system can process"
- "It is important to note that the data shows" → "The data shows"

**Thai filler → fix:**
- "เพื่อที่จะทำให้บรรลุเป้าหมาย" → "เพื่อให้บรรลุเป้า"
- "เนื่องจากข้อเท็จจริงที่ว่าฝนตก" → "เพราะฝนตก"
- "ณ จุดเวลานี้" → "ตอนนี้"
- "ในกรณีที่คุณต้องการความช่วยเหลือ" → "ถ้าคุณต้องการความช่วยเหลือ"
- "ระบบมีความสามารถในการประมวลผล" → "ระบบประมวลผลได้"
- "สิ่งสำคัญที่ควรทราบคือข้อมูลแสดงให้เห็นว่า" → "ข้อมูลแสดงว่า"


### 24. Excessive Hedging

**Problem:** Over-qualifying statements.

**Thai cue:** "อาจจะเป็นไปได้ว่าน่าจะอาจจะ..." → suspect (1 hedge พอ)

**Before:**
> It could potentially possibly be argued that the policy might have some effect on outcomes

**After:**
> The policy may affect outcomes


### 25. Generic Positive Conclusions

**Problem:** Vague upbeat endings.

**Before:**
> The future looks bright for the company Exciting times lie ahead as they continue their journey toward excellence This represents a major step in the right direction

**After:**
> The company plans to open two more locations next year


### 26. Hyphenated Word Pair Overuse

**Words to watch:** third-party, cross-functional, client-facing, data-driven, decision-making, well-known, high-quality, real-time, long-term, end-to-end

**Problem:** AI hyphenates these uniformly, including in predicate position (`the report is high-quality`). Humans hyphenate inconsistently, typically only when the compound is attributive (`a high-quality report`) and often dropping the hyphen otherwise (`the report is high quality`). Keep attributive-position hyphens; drop them when the compound follows the noun.

**Before:**
> The cross-functional team delivered a high-quality, data-driven report The team is cross-functional, the report is high-quality, and the methodology is data-driven

**After:**
> The cross-functional team delivered a high-quality, data-driven report The team is cross functional, the report is high quality, and the methodology is data driven


### 27. Persuasive Authority Tropes

**Phrases to watch:** The real question is, at its core, in reality, what really matters, fundamentally, the deeper issue, the heart of the matter

**Thai cue:** "คำถามที่แท้จริงคือ", "โดยแท้จริง", "ในแก่นสำคัญ", "ประเด็นที่ลึกซึ้งกว่านั้น" → suspect

**Before:**
> The real question is whether teams can adapt At its core, what really matters is organizational readiness

**After:**
> The question is whether teams can adapt That mostly depends on whether the organization is ready to change its habits


### 28. Signposting and Announcements

**Phrases to watch:** Let's dive in, let's explore, let's break this down, here's what you need to know, now let's look at, without further ado

**Problem:** LLMs announce what they are about to do instead of doing it. This meta-commentary slows the writing down and gives it a tutorial-script feel.

**Before:**
> Let's dive into how caching works in Next.js Here's what you need to know

**After:**
> Next.js caches data at multiple layers, including request memoization, the data cache, and the router cache


### 29. Fragmented Headers

**Signs to watch:** A heading followed by a one-line paragraph that simply restates the heading before the real content begins.

**Problem:** LLMs often add a generic sentence after a heading as a rhetorical warm-up. It usually adds nothing and makes the prose feel padded.

**Before:**
> ## Performance
>
> Speed matters
>
> When users hit a slow page, they leave

**After:**
> ## Performance
>
> When users hit a slow page, they leave


### 30. Diff-Anchored Writing

**Problem:** Documentation or comments written as if narrating a change rather than describing the thing as it is. Unless the document is inherently version-scoped (changelogs, release notes, migration guides), it should read coherently without knowing what changed in the last commit.

**Before:**
> This function was added to replace the previous approach of iterating through all items which caused O(n²) performance

**After:**
> This function uses a hash map for O(1) lookups, avoiding the O(n²) cost of naive iteration


## DETECTION GUIDANCE

### What NOT to flag (false positives)

A clean human writer can hit several of the patterns above without any AI involvement. Before rewriting, sanity-check that you are not gutting legitimate prose. The following are *not* reliable indicators on their own:

- **Perfect grammar and consistent style.** Many writers are professionals or have been edited. Polish does not equal AI.
- **Mixed casual and formal registers.** This often signals a person in a technical field, a young writer, or someone with neurodivergent prose habits — not a chatbot. **For Thai: คนไทย code-switch ไทย-อังกฤษตามถนัดเป็นเรื่องปกติ ไม่ใช่ AI tell เสมอไป**
- **"Bland" or "robotic" prose.** AI prose has *specific* tells. Generic dryness without those tells is just dry writing.
- **Formal or academic vocabulary.** AI overuses *specific* fancy words (see §7), not all fancy words. Don't flatten "ostensibly" or "constituent" just because they sound brainy. **For Thai: คำทางการที่ใช้ในบริบทเป็นทางการ ไม่ใช่ AI tell เสมอไป**
- **Letter-style opening or closing on a comment.** Salutations and sign-offs predate ChatGPT by centuries.
- **Common transition words in isolation.** *Additionally*, *moreover*, *consequently* are AI-coded only when piled up. One *however* is not a tell.
- **Curly quotes alone.** macOS, Word, Google Docs, and most CMSes auto-curl by default. Curly quotes only count when stacked with other tells.
- **Em dashes alone.** Many editors and journalists use them often. Em dashes are evidence only when paired with formulaic sales-y rhythm. **For Thai: em dash ขึ้นต้นชี้ pattern แต่ไม่ใช่ proof ถ้าเจอที่เดียวในเอกสาร**
- **Unsourced claims.** Most of the web is unsourced. Lack of citations doesn't prove anything.
- **Correct, complex formatting.** Visual editors and templates produce clean output without any AI.

When in doubt, look for **clusters** of tells, not isolated ones. A single em dash means nothing; em dashes plus rule-of-three plus *vibrant tapestry* plus a "Conclusion" section is a confession.


### Signs of human writing (preserve these)

When you see these, lean toward leaving the prose alone — they are evidence of a real person writing, and over-editing will destroy what makes the piece sound human:

- **Specific, unusual, hard-to-fabricate detail.** A real address. A weird quote. The phrase "the lawyer who used to work upstairs from my dentist." LLMs round off specifics; humans hoard them. **For Thai: ลิงก์ ticket, log timestamp, ชื่อคนจริงในทีม, "เมื่อวานคุยกับพี่แจ็ค"**
- **Mixed feelings and unresolved tension.** "I think this is mostly good, but it bothers me, and I can't fully explain why." LLMs default to clean takes.
- **Dated, era-bound references.** Slang, memes, or in-jokes that map to a specific year and subculture. Models lag by a year or more.
- **First-person editorial choices the writer can defend.** If the writer can explain *why* they made a particular cut or used a particular word, that's a strong human signal.
- **Variety in sentence length.** Real writing alternates short and long. AI writing tends toward an even, mid-length cadence. **For Thai: สลับ "ผ่าน" (สั้น) กับ "ทดสอบบน staging แล้ว เคส burst ผ่าน ส่วน moto drop ยังไม่ผ่าน" (ยาว)**
- **Genuine asides, parenthetical, or self-corrections.** "(I keep wanting to say 'almost' here, but it really was certain.)" Models rarely interrupt themselves like this.
- **Edits made before November 30, 2022.** ChatGPT's public launch. Anything older than that is, with very rare exceptions, not AI-written.
