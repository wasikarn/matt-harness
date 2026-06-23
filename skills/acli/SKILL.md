---
name: acli
description: "Use when handling bulk Jira work-item operations and Confluence space/page/blog management from the terminal. Covers transitions, labels, assignments, comments, clones, archives, bulk-edit fields, JQL exports. Thai: 'ย้ายสถานะหลายตัว', 'แก้ label/assignee หลายรายการ', 'อัปเดตหลาย ticket', 'export JQL'. For creating a single Thai-format Bug or Story with guided AC, use kbg:create-jira-ticket instead. Don't use for single-ticket reads, JQL syntax help, install/config/auth, cheat sheets, GitHub/GitLab, or non-Atlassian trackers."
---

# acli — Atlassian Cloud CLI

Drive Jira, Confluence, org admin, and Rovo Dev from the terminal. Auth-first, JQL-driven, confirmation-gated.

**When to use:** the **default** path for all Jira/Confluence work — search, view, edit, transition, comment, link, clone, bulk ops, page/space ops, admin.

> **Why this skill is model-invokable (no `disable-model-invocation`) despite doing bulk external Jira writes:** it is a *capability* the model uses to carry out tracker work the operator explicitly asked for — not an autonomous decision to mutate Jira. Every write is confirmation-gated in-flow (auth-first, JQL-driven, confirmation-gated) and runs through Bash with its own guards; gating the whole skill user-only would block the model from doing the bulk ops the operator requested. Single guided ticket *creation* routes to `create-jira-ticket`, which is likewise model-invokable and carries its own preview-and-confirm gate before any write.

**Prefer the dedicated skill for structured single-ticket creation:**
- `kbg:create-jira-ticket` — single Bug or Story with the Thai PO/QA-readable template (type-specific gather + template in on-demand references).

**Atlassian MCP is the fallback, not the default** — use it only for the few things acli genuinely can't do (see [When acli can't](#when-acli-cant-fall-back-to-the-atlassian-mcp)). Not for git/gh or non-Atlassian trackers.

---

## Always first: auth gate

Auth is two independent layers — global OAuth and per-product. A product can be authed even when the global profile is not.

```bash
acli jira auth status        # check BEFORE any jira command
acli confluence auth status
```

Not authed → pick one:
```bash
acli jira auth login --web                                              # OAuth, browser
echo "$TOKEN" | acli jira auth login --site SITE.atlassian.net --email me@x.com --token   # API token via stdin
```

Never pass a token as a flag value — `--token` reads stdin only. Token: https://id.atlassian.com/manage-profile/security/api-tokens

## Core loop (Jira work items)

```bash
# 1. FIND — JQL is the selector for everything downstream
acli jira workitem search --jql "project = TEAM AND statusCategory != Done" --fields key,summary,status
acli jira workitem search --jql "..." --json     # parse | --csv export | --web open | --count | --paginate

# 2. INSPECT
acli jira workitem view KEY-123 --fields summary,comment   # *all / *navigable / -field
acli jira workitem view KEY-123 --json | python3 ${CLAUDE_SKILL_DIR}/scripts/adf2md.py   # readable card, ~80% fewer tokens than raw JSON

# 3. CREATE
acli jira workitem create --summary "X" --project TEAM --type Task --assignee @me
acli jira workitem create-bulk --from-csv issues.csv       # or --from-json; --generate-json scaffolds input

# 4. MUTATE — target by --key | --jql | --filter (same selectors)
acli jira workitem transition --key KEY-1 --list   # discover valid statuses FIRST — names must match the workflow exactly
acli jira workitem transition --jql "project = TEAM AND status = 'To Do'" --status "In Progress" --yes
acli jira workitem edit --key "KEY-1,KEY-2" --summary "..." --labels a,b
# ⚠️ edit --description REPLACES the whole description. To add/change without
#    losing the original, append safely: bash ${CLAUDE_SKILL_DIR}/scripts/acli-edit.sh KEY notes.md
acli jira workitem comment create --key KEY-1 --body "..."
acli jira workitem assign --key KEY-1 --assignee @me       # @me | default | email
```

`@me` self-assign, `default` project default. `--generate-json` scaffolds any complex create/edit/link input. ⚠️ `assign --assignee` resolves `@me`/`default`/**email** only — a raw **accountId silently UNassigns** (acli prints "unassigned" and clears it). For accountId / privacy-hidden emails, see [When acli can't](#when-acli-cant-fall-back-to-the-atlassian-mcp).

**Description format:** Jira `description`/comment `body` is ADF. Flags (`--description`/`--body`) accept plain text (auto-wrapped); `--from-json` needs a full ADF object. Confluence body is storage-format XHTML instead. Don't hand-write ADF — write Markdown and run `python3 ${CLAUDE_SKILL_DIR}/scripts/md2adf.py desc.md`; read it back with `${CLAUDE_SKILL_DIR}/scripts/adf2md.py` (inverse). Rules + GOOD/BAD → `REFERENCE.md` "Description & body formats" + `examples/`. **Acceptance Criteria are the crown jewel** — keep them plain (no field/enum/API names) and cover error + boundary + regression, not just the happy path: rubric + worked GOOD/BAD → `examples/README.md`.

## Bulk-mutation safety

Mutating bulk ops (`edit`, `transition`, `assign`, `delete`, `clone`, `link create`) accept `--jql`/`--filter` and a `--yes` confirmation skip.

1. **Preview the set first** — run `search` with the *exact same* `--jql` and `--count` before any `--yes` mutation. The JQL selects what you'll change; verify it.
2. `--yes` skips the interactive confirm — only after the preview matches intent.
3. `--ignore-errors` continues past per-item failures. Default OFF — read the result summary; a partial failure must be loud, not swallowed. Sub-tasks can't be archived/deleted on their own (✗ "Issue is a subtask"), so a key-list `archive`/`delete` batch reports partial failures — archive/transition the parent or the sub-tasks separately.

## Create safety

`create`/`create-bulk` are outward-facing too — but unlike the mutations above they have no JQL set to preview, so preview the **payload itself** before firing.

1. **Render what you're about to send.** For a `--from-json` create, round-trip it first: `python3 ${CLAUDE_SKILL_DIR}/scripts/md2adf.py desc.md -s "..." -p TP -t Bug > /tmp/wi.json && python3 ${CLAUDE_SKILL_DIR}/scripts/adf2md.py /tmp/wi.json` prints a readable card — `(new) <type>`, project, labels, and the full description. Eyeball it, *then* `acli jira workitem create --from-json /tmp/wi.json`.
2. **For `create-bulk`**, `--generate-json` first (or render one row) and read it back before the batch — a bad template multiplies across every row. ⚠️ `create-bulk --from-json` **rejects rich-markdown descriptions** (headings/code fences/backticks/newlines) → ✗ "request body is missing or invalid". Pattern that works: bulk-create with **short placeholder** bodies, then set the real description per ticket with `bash ${CLAUDE_SKILL_DIR}/scripts/acli-set-desc.sh KEY desc.md` (verified TP-558..566).
3. **Resolve metadata, don't hardcode it.** Project/type/priority/labels/assignee must match the target project; `--generate-json` emits the schema the project actually accepts — scaffold from it when unsure of a type or field. The templates ship `projectKey:"TP"` as a personal default — swap it (or pass `-p`) for any other project. On an unknown project/type/field acli fails: fix it, never strip the field and retry (Rule 12).

## Confluence / admin / rovodev

```bash
acli confluence page view --id 123 --body-format storage   # page is view-only
acli confluence blog create --space-id 12345 --title "T" --body "<p>storage-format XHTML</p>"
acli confluence space create --key KEY --name "Name"       # space: full CRUD
acli admin user deactivate ...                             # org user lifecycle (admin auth)
acli rovodev auth login && acli rovodev run                # AI coding agent (beta, separate token)
```

Full command tree, every flag, and JSON schemas → `REFERENCE.md`.

## When acli can't (fall back to the Atlassian MCP)

acli is the default, but four operations genuinely need `mcp__plugin_atlassian_atlassian__editJiraIssue` / `*ConfluencePage` (or the Jira UI). Reach for the MCP **only** here:

- **Set/​change parent on an *existing* issue** — `edit --from-json` has no parent field and rejects a `parent` key; `--parent`/`parentIssueId` work only at *create* time (sub-tasks). → MCP `editJiraIssue cloudId:<id> issueIdOrKey:"TP-NNN" fields:{parent:{key:"TP-505"}}`.
- **Assign by accountId** when the email is privacy-hidden (`--assignee email` can't resolve, and a raw accountId silently UNassigns). → MCP `editJiraIssue cloudId:<id> issueIdOrKey:"TP-NNN" fields:{assignee:{accountId:"…"}}`; resolve the id with `lookupJiraAccountId cloudId:<id> searchString:"<name|email>"`.
- **fixVersion / release versions** — acli has no `version create`, `edit --from-json` rejects `fixVersions`, and `search --fields fixVersions` errors (read it via `view --json` + parse). → MCP or the Jira UI.
- **Create/update a Confluence *page*** — acli `confluence page` is view-only (blog + space have full CRUD). → MCP `createConfluencePage` / `updateConfluencePage`.

## METHODOLOGY

- **Rule 1 (think before coding):** auth-status + JQL-preview before any bulk mutation — `--yes` on a wrong JQL is silent orthogonal damage at scale.
- **Rule 5 (code for judgment):** let JQL deterministically select work items; don't hand-enumerate keys you could query.
- **Rule 12 (fail loud):** `--ignore-errors` off by default; "transitioned 40" must not hide "skipped 12". On a *single* create/edit rejected for an unknown field/label/type, report the exact error — never silently drop the offending field and retry. A dropped field is a silent spec change.

## Related

- Atlassian MCP (`mcp__plugin_atlassian_atlassian__*`) — fallback only, for the acli gaps in [When acli can't](#when-acli-cant-fall-back-to-the-atlassian-mcp); not the default for single ops
- `triage` skill — local issue-tracker state machine, not Jira-backed
