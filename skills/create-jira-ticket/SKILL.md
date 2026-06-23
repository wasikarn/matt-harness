---
name: create-jira-ticket
description: "Create a single Jira Bug or Story using the team's Thai PO/QA-readable template. Use when the user says 'create bug'/'create story', 'report a bug', 'file a Jira bug', 'new Jira story', 'write a story', 'สร้างบั๊ก', 'แจ้งบั๊ก', 'เปิดบั๊ก', 'เปิดตั๋วบั๊ก', 'สร้าง story', 'เปิด story', 'เขียน story', 'ออก ticket bug', 'ออก story', or wants a structured Thai ticket. Don't use for: de-duping/triaging before filing (use atlassian:triage-issue), converting a spec/Confluence page to a backlog (use atlassian:spec-to-backlog), bulk creation (use acli), editing an existing ticket (use acli), technical tasks without PO-facing AC (use acli), security incidents (use kbg:incident/kbg:hotfix), or non-Jira trackers."
---

# Create Jira Ticket

Create a single Jira **Bug** or **Story** following the team's Thai format. Defaults to the **TP board** when the user doesn't name a project, but works on any project / Atlassian site. **Backend: acli-first with Atlassian MCP fallback** — aligns with `kbg:acli` doctrine. For everything else (bulk, edit, transition, Confluence) use `kbg:acli`.

The type-specific gather questions and Thai description template live in on-demand references — load the one matching the ticket type:

- **Bug** → `cat "${CLAUDE_SKILL_DIR}/references/bug.md"`
- **Story** → `cat "${CLAUDE_SKILL_DIR}/references/story.md"`

## When to use this skill vs acli

- **Use this skill** for one structured Bug or Story creation with Thai business-readable sections and AC coaching.
- **Use `kbg:acli`** for search, view, edit, transition, comment, clone, bulk create, JQL export, Confluence, or admin ops.

## Step 1 — Pick the type and gather

Determine the type: **Bug** (something is wrong) or **Story** (something new is wanted). If the request is ambiguous, ask once.

Then load the type guide (`references/bug.md` or `references/story.md`) and ask its gather questions **all at once, not one by one**. If the user already provided enough context, skip to Step 2.

## Step 2 — Format the issue

Write the description in **Thai** using the template from the type guide (`references/bug.md` or `references/story.md`).

## Acceptance Criteria rules (single source — apply to both Bug and Story)

- Use plain business nouns ("เครดิตจากคูปอง", "ยอดคงเหลือ", "วันหมดอายุ")
- Use baht amounts/day counts ("500 บาท", "หมดอายุ 30 วัน")
- ❌ column names, enum values, API paths, DB references
- Default form: **checklist** — แต่ละ AC บรรทัดเดียว ตรวจ "ผ่าน/ไม่ผ่าน" ได้. ใช้ Given/When/Then (กำหนดให้/เมื่อ/ผลลัพธ์) เฉพาะพฤติกรรมซับซ้อนจริง ๆ — escape hatch ไม่ใช่ default
- **Minimum ACs:** Bug = 2 (fix verification + regression check); Story = 3 (happy path + error/edge case + regression/permission). Story also follows the coverage rules in `references/story.md`.
- Full GOOD/BAD examples and register guidance: `skills/acli/examples/README.md` § Acceptance Criteria.

## Step 3 — Resolve issue metadata

Resolve at runtime; never hardcode IDs except the default project key `TP`.

| Field | Resolution |
|---|---|
| **Site** | Check `acli jira auth status` to find the authed site. For MCP fallback, use `mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources`. Ask if several. |
| **Project key** | User request; default `TP`. Validate via `mcp__plugin_atlassian_atlassian__getVisibleJiraProjects` before create. |
| **Issue type** | Bug → `Bug`; Story → `Story` (or `Task` if user asks). Confirm via `mcp__plugin_atlassian_atlassian__getJiraProjectIssueTypesMetadata` if create rejects. |
| **Priority** | **Bug:** money/data loss/blocked workflow → `High`; functional with workaround → `Medium`; cosmetic → `Low`. **Story:** `Medium` unless user specifies otherwise. Confirm if unsure. |
| **Labels** | `bug` + 1-2 domain tags (Bug); 1-2 domain tags (Story) (billing, refund, credit, player). Do NOT auto-add PO/QA labels. |
| **Environment** *(Bug only)* | Native Jira field. Set to prod/staging/local. Wrap in ADF for MCP fallback (see Step 5). |
| **Affects versions** *(Bug only)* | Only if user gives a valid version; validate or omit. |
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
bash "${CLAUDE_SKILL_DIR}/scripts/md2adf.sh" /tmp/ticket.md \
  -s "<Thai summary>" -p <projectKey> -t <Bug|Story> -l "<labels>" > /tmp/wi.json
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
issueTypeName: "Bug" | "Story"
summary:       <Thai title>
description:   <formatted Thai description>
contentFormat: "markdown"
additional_fields: {
  "priority": { "name": <derived> },
  "labels": [<domain tags>],
  // Bug only:
  "environment": { "version": 1, "type": "doc", "content": [
    { "type": "paragraph", "content": [{ "type": "text", "text": "prod" }] }
  ]},
  "versions": [{ "name": <version> }]   // Affects Version/s, NOT fixVersions (Fix Version/s) — different Jira fields; omit if unvalidated
}
# assignee_account_id: OMIT by default. Include ONLY if user named an assignee.
# Story: omit environment/versions; labels may be omitted entirely if none.
```

After creation reply: `✅ Created [PROJ-XXX](https://<site>.atlassian.net/browse/PROJ-XXX)`

## Input Contract

- **Required (Bug):** Thai bug summary, actual behavior, expected behavior, numbered reproduction steps, impact, environment.
- **Required (Story):** Thai feature summary, business reason, desired behavior, in/out scope, acceptance criteria.
- **Optional:** evidence (Bug), affected version (Bug), PO decision points (Story), explicit project key (defaults to `TP`), explicit assignee.
- **Tooling:** prefers `acli` when installed and authed; falls back to Atlassian MCP. If neither is available, ask the user to run `acli jira auth login` or enable the Atlassian MCP.

## Output Format

- **Preview:** site, project, issue type, priority, labels, assignee (if any), Thai title, rendered description, chosen backend.
- **Result:** issue key + URL.

## Failure Modes

- `acli` not installed or not authed; prompt to auth or fall back to MCP.
- Project key or issue type does not exist on the resolved site.
- `environment` field rejected as plain string (Bug); retry with ADF wrapper.
- `versions` value not found (Bug); omit and retry.
- Assignee email cannot be resolved; leave unassigned.
- User does not confirm at preview gate — creation is skipped.

## Related

- `kbg:acli` — search, edit, transition, bulk ops, Confluence; also owns the canonical AC wording rules at `skills/acli/examples/README.md`.
- `kbg:incident`, `kbg:hotfix` — production outages.
- `atlassian:triage-issue` — de-duping/triaging before filing.
- `atlassian:spec-to-backlog` — converting a spec/Confluence page into a backlog of epics + tickets.