---
name: create-jira-bug
description: "Create a single Jira Bug using the team's Thai PO/QA-readable template. Tries acli first, falls back to Atlassian MCP when acli is unavailable or cannot set a required field. Use when the user says 'create bug', 'report a bug', 'file a Jira bug', or wants a structured Thai bug ticket with reproduction steps, impact, and Given/When/Then AC. Don't use for: bulk bug creation (use acli), editing an existing bug (use acli), security incidents (use kbg:incident/kbg:hotfix), or non-Jira trackers."
disable-model-invocation: true
---

# Create Jira Bug

Create a Jira **Bug** following the team's Thai format. Defaults to the **TP board** when the user doesn't name a project, but works on any project / Atlassian site. **Backend: acli-first with Atlassian MCP fallback** — aligns with `kbg:acli` doctrine. For everything else (bulk, edit, transition, Confluence) use `kbg:acli`.

## When to use this skill vs acli

- **Use this skill** for one structured Bug creation with Thai business-readable sections and AC coaching.
- **Use `kbg:acli`** for search, view, edit, transition, comment, clone, bulk create, JQL export, Confluence, or admin ops.

## Step 1 — Gather information

Ask the user (all at once, not one by one):

1. **Bug summary** — short Thai title, symptom-oriented (e.g. "ยอดคงเหลือไม่ถูกหักหลังลูกค้ายืนยันการสั่งซื้อ")
2. **What happened?** — observed wrong behavior (actual result)
3. **What should have happened?** — correct expected behavior
4. **How to reproduce?** — exact numbered steps
5. **Where / how often?** — environment (prod / staging / local), channel/screen, frequency
6. **Impact** — who is affected and how serious (money / data loss / blocked workflow / cosmetic)
7. **Evidence** — screenshots, log lines, error codes, trace IDs, affected record IDs (optional)

If the user already provided enough context, skip to Step 2.

## Step 2 — Format the issue

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

**AC1 — ยืนยันว่าแก้แล้ว (Fix verified)**

* กำหนดให้: [precondition]
* เมื่อ: [reproduction action]
* ผลลัพธ์: [now-correct outcome]

**AC2 — ตรวจ Regression**

* กำหนดให้: [unaffected flow]
* เมื่อ: [normal action]
* ผลลัพธ์: [unchanged behavior]
```

**AC rules (no engineering terms):**
- Use plain business nouns ("เครดิตจากคูปอง", "ยอดคงเหลือ", "วันหมดอายุ")
- Use baht amounts/day counts ("500 บาท", "หมดอายุ 30 วัน")
- ❌ column names, enum values, API paths, DB references
- Minimum 2 ACs: fix verification + regression check
- Full GOOD/BAD examples and register guidance: `skills/acli/examples/README.md` § Acceptance Criteria.

## Step 3 — Resolve issue metadata

Resolve at runtime; never hardcode IDs except the default project key `TP`.

| Field | Resolution |
|---|---|
| **Site** | Check `acli jira auth status` to find the authed site. For MCP fallback, use `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources`. Ask if several. |
| **Project key** | User request; default `TP`. Validate via `mcp__plugin_atlassian_atlassian__getVisibleJiraProjects` before create. |
| **Issue type** | `Bug`. Confirm via `mcp__plugin_atlassian_atlassian__getJiraProjectIssueTypesMetadata` if create rejects. |
| **Priority** | Money/data loss/blocked workflow → `High`; functional with workaround → `Medium`; cosmetic → `Low`. Confirm if unsure. |
| **Labels** | `bug` + 1-2 domain tags (billing, refund, credit, player). Do NOT auto-add PO/QA labels. |
| **Environment** | Native Jira field. Set to prod/staging/local. Wrap in ADF for MCP fallback (see Step 5). |
| **Affects versions** | Only if user gives a valid version; validate or omit. |
| **Assignee** | Leave unassigned by default. Only set if user explicitly names one; resolve via `mcp__plugin_atlassian_atlassian__lookupJiraAccountId`. |

## Step 4 — Preview and confirm

Show resolved metadata + Thai title + rendered description + chosen backend path. Ask for explicit confirmation before creating. Creating a Jira issue is outward-facing — never call create without a "yes".

## Step 5 — Create the issue

Default to `acli`. Fall back to the Atlassian MCP only when `acli` is unavailable, unauthenticated, or cannot set a required field.

### 5a — acli path (default)

Check auth first:
```bash
acli jira auth status
```

If authed, build the create payload from the Thai Markdown description:
```bash
python3 skills/acli/scripts/md2adf.py /tmp/bug.md \
  -s "<Thai summary>" -p <projectKey> -t Bug -l "bug,<domain>" > /tmp/wi.json
```

Then create:
```bash
acli jira workitem create --from-json /tmp/wi.json --json
```

Capture the returned key and reply: `✅ Created [PROJ-XXX](https://<site>.atlassian.net/browse/PROJ-XXX)`

> acli sets summary, description, project, type, and labels. If the user also needs `priority`, `environment`, `versions`, or `assignee` set at create time and acli cannot satisfy one of them, switch to the MCP fallback for that field.

### 5b — MCP fallback

Use when acli is not available, not authed, or cannot set a field. Call `mcp__plugin_atlassian_atlassian__createJiraIssue`:

```
cloudId:       <resolved>
projectKey:    <resolved>
issueTypeName: "Bug"
summary:       <Thai title>
description:   <formatted Thai description>
contentFormat: "markdown"
additional_fields: {
  "priority": { "name": <derived> },
  "labels": ["bug", <domain tags>],
  "environment": { "version": 1, "type": "doc", "content": [
    { "type": "paragraph", "content": [{ "type": "text", "text": "prod" }] }
  ]},
  "versions": [{ "name": <version> }]   // omit if unvalidated
}
# assignee_account_id: OMIT by default. Include ONLY if user named an assignee.
```

After creation reply: `✅ Created [PROJ-XXX](https://<site>.atlassian.net/browse/PROJ-XXX)`

## Input Contract

- **Required:** Thai bug summary, actual behavior, expected behavior, numbered reproduction steps, impact, environment.
- **Optional:** evidence, affected version, explicit project key (defaults to `TP`), explicit assignee.
- **Tooling:** prefers `acli` when installed and authed; falls back to Atlassian MCP. If neither is available, ask the user to run `acli jira auth login` or enable the Atlassian MCP.

## Output Format

- **Preview:** site, project, issue type, priority, labels, assignee (if any), Thai title, rendered description, chosen backend.
- **Result:** issue key + URL.

## Failure Modes

- `acli` not installed or not authed; prompt to auth or fall back to MCP.
- Project key or issue type does not exist on the resolved site.
- `environment` field rejected as plain string; retry with ADF wrapper.
- `versions` value not found; omit and retry.
- Assignee email cannot be resolved; leave unassigned.
- User does not confirm at preview gate — creation is skipped.

## Related

- `kbg:acli` — search, edit, transition, bulk ops, Confluence; also owns the canonical AC wording rules at `skills/acli/examples/README.md`.
- `kbg:create-jira-story` — structured Thai Story creation.
- `kbg:incident`, `kbg:hotfix` — production outages.
