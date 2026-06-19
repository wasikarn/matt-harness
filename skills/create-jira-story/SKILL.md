---
name: create-jira-story
description: "Create a single Jira Story using the team's Thai PO/QA-readable template. Tries acli first, falls back to Atlassian MCP when acli is unavailable or cannot set a required field. Use when the user says 'create story', 'new Jira story', 'write a story', 'สร้าง story', 'เปิด story', 'เขียน story', 'ออก story', or wants a structured Thai Story with business reason, scope, and plain checklist AC (Given/When/Then only for complex cases). Don't use for: converting a whole spec / Confluence page into a backlog of epics + tickets (use atlassian:spec-to-backlog), bugs (use create-jira-bug), bulk story creation (use acli), editing an existing story (use acli), or technical tasks without PO-facing AC."
---

# Create Jira Story

Create a Jira **Story** following the team's Thai format. Defaults to the **TP board** when the user doesn't name a project, but works on any project / Atlassian site. **Backend: acli-first with Atlassian MCP fallback** — aligns with `kbg:acli` doctrine. For everything else (bulk, edit, transition, Confluence) use `kbg:acli`.

## When to use this skill vs acli

- **Use this skill** for one structured Story creation with Thai business-readable sections and AC coaching.
- **Use `kbg:acli`** for search, view, edit, transition, comment, clone, bulk create, JQL export, Confluence, or admin ops.

## Step 1 — Gather information

Ask the user (all at once, not one by one):

1. **Feature name** — short Thai title, action-oriented (e.g. "หักยอดคงเหลือตอนลูกค้ายืนยันการสั่งซื้อ")
2. **Why are we doing this?** — business reason / problem being solved
3. **What should the system do?** — desired behavior in plain language
4. **What is OUT of scope this round?** — important for QA
5. **Any PO decision points?** — trade-offs or edge cases PO must sign off on
6. **Acceptance criteria** — rough testable behaviors (you will format them)

If the user already provided enough context, skip to Step 2.

## Step 2 — Format the issue

Write the description in **Thai** using this structure:

```
## 🎯 เหตุผลทางธุรกิจ (ทำไมต้องทำ)

[Current problem — 2-3 sentences. End with what we want to achieve.]

---

## ✅ พฤติกรรมที่ต้องการ

1. [what the system does]
2. [what the system does]

> ⚠️ [caveat about what does NOT happen]

---

## 📋 ขอบเขต (Scope)

**อยู่ในขอบเขตรอบนี้**
* [bullet list]

**ไม่อยู่ในขอบเขตรอบนี้ (สำคัญ — แจ้ง QA ให้ทราบ)**
* [bullet list]

---

## ⚠️ จุดที่ PO ต้องรับทราบและตัดสินใจร่วม

[Only include if there is a genuine decision point.]

---

## 🧪 เกณฑ์การยอมรับ (Acceptance Criteria) — สำหรับ QA

* **[หัวข้อสั้น]:** [precondition] → [action] → [expected outcome]
* **[หัวข้อสั้น]:** [error / boundary / regression case] → [outcome] *(error / boundary / Regression check)*
...

---

📎 อ้างอิงการตัดสินใจเชิงเทคนิค: [spec or ADR if applicable]
```

**AC rules (no engineering terms):**
- Use plain business nouns ("เครดิตจากคูปอง", "ยอดคงเหลือ", "วันหมดอายุ")
- Use baht amounts/day counts ("500 บาท", "หมดอายุ 30 วัน")
- ❌ column names, enum values, API paths, DB references
- Default form: **checklist** — แต่ละ AC บรรทัดเดียว ตรวจ "ผ่าน/ไม่ผ่าน" ได้. ใช้ Given/When/Then (กำหนดให้/เมื่อ/ผลลัพธ์) เฉพาะพฤติกรรมซับซ้อนจริง ๆ — escape hatch ไม่ใช่ default
- Minimum 3 ACs: happy path, error/edge case, regression/permission
- Full GOOD/BAD examples and register guidance: `skills/acli/examples/README.md` § Acceptance Criteria.

**AC coverage rules:**
- **Regression AC** for every out-of-scope item that touches the same flow.
- **Per-surface AC** for each screen/channel the change is visible on.
- **Boundary AC** for values that look missing but are real (e.g. 0 baht = free).
- **Fallback AC** for existing data without the new information.

## Step 3 — Resolve issue metadata

Resolve at runtime; never hardcode IDs except the default project key `TP`.

| Field | Resolution |
|---|---|
| **Site** | Check `acli jira auth status` to find the authed site. For MCP fallback, use `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources`. Ask if several. |
| **Project key** | User request; default `TP`. Validate via `mcp__plugin_atlassian_atlassian__getVisibleJiraProjects` before create. |
| **Issue type** | `Story` (or Task if user asks). Confirm via `mcp__plugin_atlassian_atlassian__getJiraProjectIssueTypesMetadata` if create rejects. |
| **Priority** | `Medium` unless user specifies otherwise. |
| **Labels** | 1-2 domain tags (billing, refund, credit, player). Do NOT auto-add PO/QA labels. |
| **Assignee** | Leave unassigned by default. Only set if user explicitly names one; resolve via `mcp__plugin_atlassian_atlassian__lookupJiraAccountId` (pass `cloudId` + `searchString`), then set `assignee_account_id`. |

## Step 4 — Preview and confirm

Show resolved metadata + Thai title + rendered description + chosen backend path. Show this as a review surface, then create **only on the user's explicit go-ahead**. This preview-and-confirm step is the safeguard against an unwanted ticket — never write to Jira before it.

## Step 5 — Create the issue

Default to `acli`. Fall back to the Atlassian MCP only when `acli` is unavailable, unauthenticated, or cannot set a required field.

### 5a — acli path (default)

Check auth first:
```bash
acli jira auth status
```

If authed, build the create payload from the Thai Markdown description:
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/md2adf.sh" /tmp/story.md \
  -s "<Thai summary>" -p <projectKey> -t Story -l "<domain>" > /tmp/wi.json
```

Then create:
```bash
acli jira workitem create --from-json /tmp/wi.json --json
```

Capture the returned key and reply: `✅ Created [PROJ-XXX](https://<site>.atlassian.net/browse/PROJ-XXX)`

> acli sets summary, description, project, type, and labels. If the user also needs `priority` or `assignee` set at create time and acli cannot satisfy one of them, switch to the MCP fallback for that field.

### 5b — MCP fallback

Use when acli is not available, not authed, or cannot set a field. Call `mcp__plugin_atlassian_atlassian__createJiraIssue`:

```
cloudId:       <resolved>
projectKey:    <resolved>
issueTypeName: "Story"
summary:       <Thai title>
description:   <formatted Thai description>
contentFormat: "markdown"
additional_fields: {
  "priority": { "name": "Medium" },
  "labels": [<domain tags>]   // omit key entirely if none
}
# assignee_account_id: OMIT by default. Include ONLY if user named an assignee.
```

After creation reply: `✅ Created [PROJ-XXX](https://<site>.atlassian.net/browse/PROJ-XXX)`

## Input Contract

- **Required:** Thai feature summary, business reason, desired behavior, in/out scope, acceptance criteria.
- **Optional:** PO decision points, explicit project key (defaults to `TP`), explicit assignee.
- **Tooling:** prefers `acli` when installed and authed; falls back to Atlassian MCP. If neither is available, ask the user to run `acli jira auth login` or enable the Atlassian MCP.

## Output Format

- **Preview:** site, project, issue type, priority, labels, assignee (if any), Thai title, rendered description, chosen backend.
- **Result:** issue key + URL.

## Failure Modes

- `acli` not installed or not authed; prompt to auth or fall back to MCP.
- Project key or issue type does not exist on the resolved site.
- Assignee email cannot be resolved; leave unassigned.
- User does not confirm at preview gate — creation is skipped.

## Related

- `kbg:create-jira-bug` — structured Thai Bug creation.
- `kbg:acli` — search, edit, transition, bulk ops, Confluence; also owns the canonical AC wording rules at `skills/acli/examples/README.md`.
