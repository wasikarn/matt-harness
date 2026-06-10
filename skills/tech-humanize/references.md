# References (extends SKILL.md)

> แหล่งอ้างอิง + glossary สำหรับ Thai-specific patterns (§31-§42 ใน `patterns-thai.md`) และ universal patterns (§1-§30). ไม่ต้อง load ไฟล์นี้เพื่อ apply pattern, load เมื่อต้อง verify transliteration หรือ cite แหล่ง.

---

## Reference

This skill extends [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), maintained by WikiProject AI Cleanup, with 12 Thai-specific top-level patterns (§31-§42 in `patterns-thai.md`: terminology & calque, anti-fabrication, connectives, register matrix, code-switching tells, AI-leaked closers) and a Thai-register foundation (§0).

### Thai-specific references
- ราชบัณฑิตยสภา transliteration: https://transliteration.orst.go.th/search
- ราชบัณฑิตยสภา terminology: https://royalsociety.go.th/thai-translation-terminology/
- Mozilla Thai Style Guide: https://mozilla-l10n.github.io/styleguides/th/  *(explicit "3 translation styles" framework: translate / transliterate / leave untranslated)*
- Microsoft Thai Style Guide (UI string + terminology, TBX)
- Google translation style: https://developers.google.com/style/translation
- W3C Thai Layout: https://www.w3.org/TR/thai-gap/ · https://www.w3.org/TR/thai-lreq/
- Microsoft Thai typography: https://learn.microsoft.com/en-us/typography/script-development/thai
- Piyangkool Thaweephol (2024) — Chulalongkorn thesis, Thai Gen-Y attitudes toward English-Thai code-switching
- Umpornpun & Mongkolhutthi (2022) — Thai multilingual gamers on Discord (closest published setting to "dev chat")
- Conventional Commits Thai v1.0.0: https://www.conventionalcommits.org/th/v1.0.0/  *(keeps `fix:`/`feat:` in English — tooling requirement)*

### Universal references
- Wikipedia "Signs of AI writing" (basis for §1-§30)

### Thai NLP / Code-switching References (v2.2 additions)

- **Lowphansirikul et al. (2021)** "WangchanBERTa" — Thai RoBERTa pretrained on ~78GB Thai monolingual corpus; basis for §38 code-switching tells *(arXiv:2101.09635 — 2021, arXiv preprint cs.CL, not EMNLP)*
- **Phatthiyaphaibun et al. (2024)** "PyThaiNLP 4.0" — Thai NLP toolkit with mixed-script tokenizers (newmm / attacut / nlpo3); used as §38 reference for tokenization-aware code-switching norms

### Verification Tools (v2.2 additions)

- **WebFetch / WebSearch** — verify URL claim
- **context7 MCP** — verify library API
- **Glob / Grep** — verify file path
- **Google Scholar / arxiv** — verify paper claim
- **Calendar** — verify date precision

> **ยังไม่มีคำตอบ empirical** (validate กับ audience เอง): สัดส่วน English ที่เหมาะใน error message ไทย; pattern code-switching จริงของแต่ละทีม

---

## Default Thai+Tech Glossary (from §31)

ใช้เป็น baseline เมื่อตัดสินใจ terminology. Project-specific terms (ANPR, dwell, front-facing, PDPA, traffic-campaign) เก็บใน project glossary แยก ไม่ใส่ที่นี่.

| คำ | Internal | User-facing |
|----|----------|-------------|
| staging / develop / production | คงอังกฤษ | "ระบบทดสอบ" / (none) / "ระบบจริง" + อธิบาย |
| merge | merge | รวมโค้ด |
| deploy | deploy | นำขึ้นใช้งาน |
| session | session (เก็บอังกฤษ) | เซสชัน (RTGS, ไม่มีไม้หันอากาศ) |
| error code | error code | ข้อความแจ้งข้อผิดพลาด |
| declined (bank/payment) | declined (เก็บไว้ใน log เท่านั้น) | ถูกปฏิเสธ |

### Calques to avoid (selected; full list in §0 + §31)

| ❌ Calque | ✅ Better |
|-----------|-----------|
| ถือไว้ (HELD) | ยังไม่ปล่อย |
| ดัน (push) | merge |
| ระบบล้ม (down) | ระบบล่ม |
| เซสชั่น (non-RTGS) | เซสชัน |

### Typography rules (selected; full list in §0 + §14)
- ไม้หันอากาศ (์): เซสชัน**ไม่**มี ใช้แค่ นิยาย, วัฒนธรรม, etc.
- Hyphen: ใช้ `-` (ASCII U+002D) ไม่ใช่ en-dash `–` ใน compound (low-priority, ขึ้นกับ font)
- Em dash `—`: ห้ามใช้ใน Thai prose (ดู §14)
- En dash `–`: ใช้กับ number ranges เท่านั้น (40-60%, §31-32, 2-5 นาที)
