---
name: acli
description: "ALWAYS trigger this skill when the user wants ANY bulk / set-based Jira work-item operation: move all tickets to Done, transition every issue in a sprint, label every bug, clone to another project, delete old tickets, bulk-edit priority/assignee/labels/status, assign a batch, comment on multiple, archive resolved, or export JQL to CSV/Excel. Also trigger for ANY Confluence space / page / blog create / manage, or whenever \"acli\" appears in the prompt. Use for ops selected by JQL, sprint name, or issue-key list. Do NOT use for JQL syntax help, installing / configuring acli, GitHub/GitLab ops, or non-Atlassian trackers."
---

# acli — Atlassian Cloud CLI

Drive Jira, Confluence, org admin, and Rovo Dev from the terminal. Auth-first, JQL-driven, confirmation-gated.

**When to use:** terminal-native Jira/Confluence work — search, create, bulk-edit, transition, comment, page/space ops.

**When NOT to use:** the `mcp__claude_ai_Atlassian_Rovo__*` MCP tools (richer for one-off reads inside a chat; this skill is for scriptable bulk/terminal ops), git/gh, or non-Atlassian trackers.

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
acli jira workitem view KEY-123 --json | python3 scripts/adf2md.py   # readable card, ~80% fewer tokens than raw JSON

# 3. CREATE
acli jira workitem create --summary "X" --project TEAM --type Task --assignee @me
acli jira workitem create-bulk --from-csv issues.csv       # or --from-json; --generate-json scaffolds input

# 4. MUTATE — target by --key | --jql | --filter (same selectors)
acli jira workitem transition --jql "project = TEAM AND status = 'To Do'" --status "In Progress" --yes
acli jira workitem edit --key "KEY-1,KEY-2" --summary "..." --labels a,b
# ⚠️ edit --description REPLACES the whole description. To add/change without
#    losing the original, append safely: bash scripts/acli-edit.sh KEY notes.md
acli jira workitem comment create --key KEY-1 --body "..."
acli jira workitem assign --key KEY-1 --assignee @me       # @me | default | email
```

`@me` self-assign, `default` project default. `--generate-json` scaffolds any complex create/edit/link input.

**Description format:** Jira `description`/comment `body` is ADF. Flags (`--description`/`--body`) accept plain text (auto-wrapped); `--from-json` needs a full ADF object. Confluence body is storage-format XHTML instead. Don't hand-write ADF — write Markdown and run `python3 scripts/md2adf.py desc.md`; read it back with `scripts/adf2md.py` (inverse). Rules + GOOD/BAD → [REFERENCE.md](REFERENCE.md) "Description & body formats" + [examples/](examples/). **Acceptance Criteria are the crown jewel** — keep them plain (no field/enum/API names) and cover error + boundary + regression, not just the happy path: rubric + worked GOOD/BAD → [examples/README.md](examples/README.md).

## Bulk-mutation safety

Mutating bulk ops (`edit`, `transition`, `assign`, `delete`, `clone`, `link create`) accept `--jql`/`--filter` and a `--yes` confirmation skip.

1. **Preview the set first** — run `search` with the *exact same* `--jql` and `--count` before any `--yes` mutation. The JQL selects what you'll change; verify it.
2. `--yes` skips the interactive confirm — only after the preview matches intent.
3. `--ignore-errors` continues past per-item failures. Default OFF — read the result summary; a partial failure must be loud, not swallowed.

## Create safety

`create`/`create-bulk` are outward-facing too — but unlike the mutations above they have no JQL set to preview, so preview the **payload itself** before firing.

1. **Render what you're about to send.** For a `--from-json` create, round-trip it first: `python3 scripts/md2adf.py desc.md -s "..." -p TP -t Bug > /tmp/wi.json && python3 scripts/adf2md.py /tmp/wi.json` prints a readable card — `(new) <type>`, project, labels, and the full description. Eyeball it, *then* `acli jira workitem create --from-json /tmp/wi.json`.
2. **For `create-bulk`**, `--generate-json` first (or render one row) and read it back before the batch — a bad template multiplies across every row.
3. **Resolve metadata, don't hardcode it.** Project/type/priority/labels/assignee must match the target project; `--generate-json` emits the schema the project actually accepts — scaffold from it when unsure of a type or field. The templates ship `projectKey:"TP"` as a personal default — swap it (or pass `-p`) for any other project. On an unknown project/type/field acli fails: fix it, never strip the field and retry (Rule 12).

## Confluence / admin / rovodev

```bash
acli confluence page view --id 123 --body-format storage   # page is view-only
acli confluence blog create --space-id 12345 --title "T" --body "<p>storage-format XHTML</p>"
acli confluence space create --key KEY --name "Name"       # space: full CRUD
acli admin user deactivate ...                             # org user lifecycle (admin auth)
acli rovodev auth login && acli rovodev run                # AI coding agent (beta, separate token)
```

Full command tree, every flag, and JSON schemas → [REFERENCE.md](REFERENCE.md).

## METHODOLOGY

- **Rule 1 (think before coding):** auth-status + JQL-preview before any bulk mutation — `--yes` on a wrong JQL is silent orthogonal damage at scale.
- **Rule 5 (code for judgment):** let JQL deterministically select work items; don't hand-enumerate keys you could query.
- **Rule 12 (fail loud):** `--ignore-errors` off by default; "transitioned 40" must not hide "skipped 12". On a *single* create/edit rejected for an unknown field/label/type, report the exact error — never silently drop the offending field and retry. A dropped field is a silent spec change.

## Related

- `mcp__claude_ai_Atlassian_Rovo__*` — MCP path for conversational reads/writes of a single work item
- `triage` skill — local issue-tracker state machine, not Jira-backed
