# References (extends SKILL.md)

> Sources + glossary for the Thai-specific patterns (§31-§42 in `patterns-thai.md`) and the universal patterns (§1-§30). No need to load this file to apply a pattern; load it when you must verify a transliteration or cite a source.

---

## Reference

This skill extends [Wikipedia:Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), maintained by WikiProject AI Cleanup, with 12 Thai-specific top-level patterns (§31-§42 in `patterns-thai.md`: terminology & calque, anti-fabrication, connectives, register matrix, code-switching tells, AI-leaked closers) and a Thai-register foundation (§0).

[github.com/blader/humanizer](https://github.com/blader/humanizer) (MIT) is a sibling project, not a source — independently confirmed to derive from the same Wikipedia essay, catalog 33 English-only patterns across the same 5 content/language/style/communication/filler buckets §1-§30 use here, and carry no non-English coverage. The convergence is both projects mirroring Wikipedia's own essay structure, not one copying the other.

### Thai-specific references
- Royal Society of Thailand (`ราชบัณฑิตยสภา`) transliteration: https://transliteration.orst.go.th/search
- Royal Society of Thailand (`ราชบัณฑิตยสภา`) terminology: https://royalsociety.go.th/thai-translation-terminology/
- Mozilla Thai Style Guide: https://mozilla-l10n.github.io/styleguides/th/  *(explicit "3 translation styles" framework: translate / transliterate / leave untranslated)*
- Microsoft Thai Style Guide (UI string + terminology, TBX)
- Google translation style: https://developers.google.com/style/translation
- W3C Thai Layout: https://www.w3.org/TR/thai-gap/ · https://www.w3.org/TR/thai-lreq/
- Microsoft Thai typography: https://learn.microsoft.com/en-us/typography/script-development/thai
- Thaweephol, P. & Saisuwan, P. (2021). Attitudes towards Thai-English code-switching among Thai speakers in Generation Y. *Journal of Language and Culture* 40(2), 53-78. https://so03.tci-thaijo.org/index.php/JLC/article/view/257581 (ChulaSEAL summary of the follow-on thesis, 2024: https://www.arts.chula.ac.th/chulaseal/2024/05/31/do-thai-people-really-consider-code-switching-inappropriate-and-unnatural-an-insight-into-thai-peoples-attitude-toward-code-switching/)
- Umpornpun, A. & Mongkolhutthi, P. (2022). Conversational code-switching among Thai teenage multilingual gamers: a sequential analysis. *Theory and Practice in Language Studies* 12(11). https://tpls.academypublication.com/index.php/tpls/article/view/5030 (closest published setting to "dev chat")
- Conventional Commits Thai v1.0.0: https://www.conventionalcommits.org/th/v1.0.0/  *(keeps `fix:`/`feat:` in English — tooling requirement)*

### Universal references
- Wikipedia "Signs of AI writing" (basis for §1-§30)

### Thai NLP / Code-switching References (v2.2 additions)

- **Lowphansirikul et al. (2021)** "WangchanBERTa" — Thai RoBERTa pretrained on ~78GB Thai monolingual corpus; basis for §38 code-switching tells *(arXiv:2101.09635 — 2021, arXiv preprint cs.CL, not EMNLP)*
- **Phatthiyaphaibun et al. (2023)** "PyThaiNLP: Thai Natural Language Processing in Python" — NLP-OSS 2023 workshop (co-located with EMNLP 2023, Singapore), pp. 25-36, ACL Anthology [2023.nlposs-1.4](https://aclanthology.org/2023.nlposs-1.4/), DOI 10.18653/v1/2023.nlposs-1.4, arXiv:2312.04649. Thai NLP toolkit with mixed-script tokenizers (newmm / attacut / nlpo3); used as §38 reference for tokenization-aware code-switching norms. *(Corrected 2026-07-02: the prior "PyThaiNLP 4.0 (2024)" attribution was fabricated — v4.0 was a software release, GitHub tag v4.0.0, April 2023, never a paper.)*

### Verification Tools (v2.2 additions)

- **WebFetch / WebSearch** — verify URL claim
- **context7 MCP** — verify library API
- **Glob / Grep** — verify file path
- **Google Scholar / arxiv** — verify paper claim
- **Calendar** — verify date precision

> **No empirical answer yet** (validate with your own audience): the right share of English in a Thai error message; each team's real code-switching pattern

---

## Default Thai+Tech Glossary

Canonical table lives in `patterns-thai.md` §31 — load it for the current, complete glossary. Sample rows only below, to show the shape; do not treat this file as authoritative for glossary lookups. Project-specific terms (ANPR, dwell, front-facing, PDPA, traffic-campaign) go in a project glossary, not here.

| Term | Internal | User-facing |
|----|----------|-------------|
| staging / develop / production | คงอังกฤษ | "ระบบทดสอบ" / (none) / "ระบบจริง" + อธิบาย |
| merge | merge | รวมโค้ด |
| declined (bank/payment) | declined (เก็บไว้ใน log เท่านั้น) | ถูกปฏิเสธ |

### Calques to avoid (selected; full list in §0 + §31)

| ❌ Calque | ✅ Better |
|-----------|-----------|
| ถือไว้ (HELD) | ยังไม่ปล่อย |
| ดัน (push) | merge |
| ระบบล้ม (down) | ระบบล่ม |
| เซสชั่น (non-RTGS) | เซสชัน |

### Typography rules (selected; full list in §0 + §14)
- Tone and silent marks: RTGS transliterations carry no tone mark (`เซสชัน`, not `เซสชั่น`); the silent mark `์` (การันต์) appears only where a silent source letter is kept, as in `ซอฟต์แวร์`, `ฟิล์ม`.
- Hyphen: use `-` (ASCII U+002D), not en-dash `–`, in compounds (low priority, font-dependent)
- Em dash `—`: never in Thai prose (see §14)
- En dash `–`: number ranges only (40-60%, §31-32, `2-5 นาที`)
