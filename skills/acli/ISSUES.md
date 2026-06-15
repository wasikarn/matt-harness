# Known Issues — acli skill

## Issue 1: md2adf.py ไม่ handle nested lists ถูกต้อง

**Severity:** Medium  
**Impact:** Description ใน Jira ที่มี nested list (bullet list ข้างใน ordered list) จะถูก flatten เป็น sibling lists แทนที่จะเป็น child lists  
**Affected files:**
- `skills/acli/scripts/md2adf.py`
- ทุก workflow ที่ใช้ `md2adf.py` → `acli jira workitem edit/create --from-json`

**Symptom:**
Markdown input:
```md
1. First item
   - Sub A
   - Sub B
2. Second item
```

Expected ADF: `orderedList > listItem > bulletList`  
Actual ADF: `orderedList` และ `bulletList` เป็น sibling (`listItem` ไม่มี `bulletList` เป็น child)

**Workaround:**
เขียน ADF JSON ด้วยมือโดยใส่ `bulletList` เป็น child ของ `listItem` โดยตรง ไม่ผ่าน `md2adf.py`

---

## Issue 2: `acli jira workitem edit --from-json` ไม่สามารถใช้คู่กับ `--key` ได้

**Severity:** Low  
**Impact:** CLI error เมื่อพยายามใช้ `--key` ร่วมกับ `--from-json`  
**Error message:**
```
if any flags in the group [key jql filter generate-json from-json] are set none of the others can be; [from-json key] were all set
```

**Workaround:**
ใช้ `issues` array ภายใน JSON แทน:
```json
{
  "issues": ["TP-643"],
  "description": { ... }
}
```

แล้วเรียก:
```bash
acli jira workitem edit --from-json file.json --yes
```

ไม่ต้องใช้ `--key`

---

## Reported
- **Date:** 2026-06-15
- **Reporter:** BIG-TATHEP / Claude Code session
- **Context:** ปัญหาพบขณะ update Jira ticket TP-643 description ด้วย acli skill
