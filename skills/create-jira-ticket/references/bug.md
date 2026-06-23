# Bug — type-specific guide

Loaded by `kbg:create-jira-ticket` Step 1–2. The shared metadata table, preview gate, create commands, AC rules, and failure modes live in `SKILL.md` — this file holds only the Bug-specific gather questions and Thai description template.

## Step 1 — Gather (Bug)

Ask the user (all at once, not one by one):

1. **Bug summary** — short Thai title, symptom-oriented (e.g. "ยอดคงเหลือไม่ถูกหักหลังลูกค้ายืนยันการสั่งซื้อ")
2. **What happened?** — observed wrong behavior (actual result)
3. **What should have happened?** — correct expected behavior
4. **How to reproduce?** — exact numbered steps
5. **Where / how often?** — environment (prod / staging / local), channel/screen, frequency
6. **Impact** — who is affected and how serious (money / data loss / blocked workflow / cosmetic)
7. **Evidence** — screenshots, log lines, error codes, trace IDs, affected record IDs (optional)

If the user already provided enough context, skip to Step 2.

## Step 2 — Format the issue (Bug)

Write the description in **Thai** using this structure:

```
## 🐞 อาการที่พบ (สิ่งที่เกิดขึ้นจริง)

[What actually happens — 2-3 sentences.]

---

## ✅ สิ่งที่ควรเป็น (ผลลัพธ์ที่ถูกต้อง)

[What the system should do instead.]

---

## 🔁 ขั้นตอนการเกิดปัญหา (Steps to Reproduce)

1. [step]
2. [step]
3. [step]

> 📌 ผลลัพธ์ที่ได้: [actual]
> 📌 ผลลัพธ์ที่คาดหวัง: [expected]

---

## 🌐 ความถี่และเงื่อนไข

* **ความถี่:** [เกิดทุกครั้ง / เกิดบางครั้ง — ระบุเงื่อนไข]
* **ช่องทาง/หน้าจอที่เกี่ยวข้อง:** [เช่น แอป Player, หน้า Admin, เว็บไซต์]

> ℹ️ สภาพแวดล้อม (prod/staging/local) และเวอร์ชัน/Build จะถูกบันทึกใน **field ของ Jira โดยตรง** (Environment + Affects versions) ไม่ใช่ในคำอธิบายนี้

---

## 💥 ผลกระทบ (Impact)

[Who is affected and how serious.]

---

## 📎 หลักฐานประกอบ (Evidence)

[Screenshots, logs, error codes, trace IDs. Omit if none.]

---

## 🧪 เกณฑ์การยอมรับการแก้ไข (Acceptance Criteria) — สำหรับ QA

* **ยืนยันว่าแก้แล้ว:** [precondition] → [action] → [now-correct outcome]
* **ตรวจ Regression:** [unaffected flow] → ทำงานแบบเดิม ไม่กระทบ *(Regression check)*
```

Then proceed to `SKILL.md` Step 3 (metadata — Bug uses `Bug` issue type, severity-derived priority, and the Bug-only Environment + Affects versions rows) → Step 4 (preview) → Step 5 (create). Minimum 2 ACs: fix verification + regression check.