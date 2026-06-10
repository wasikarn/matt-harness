# acli Reference

Full command tree for acli `1.3.18-stable`. Verified against the installed binary's `--help`. When in doubt, `acli <path> --help` is authoritative for the installed version.

## Install / upgrade (macOS)

```bash
brew tap atlassian/homebrew-acli
brew install acli
brew upgrade acli
acli --version          # acli version 1.3.18-stable
```

Config lives in `~/.config/acli/*.yaml` — one file per product (`jira_config.yaml`, `confluence_config.yaml`, `global_auth_config.yaml`, `rovodev_config.yaml`, …). Treat auth config files as secrets; don't cat them.

## Top-level surfaces

| Command | Scope |
|---|---|
| `acli auth` | Global OAuth account (login/logout/status/switch) |
| `acli jira` | Jira Cloud |
| `acli confluence` | Confluence Cloud |
| `acli admin` | Org admin (user lifecycle) — needs admin auth |
| `acli rovodev` | Rovo Dev AI coding agent (beta), separate scoped API token |
| `acli config` | `gov-cloud` toggle (Atlassian Government Cloud) |
| `acli completion` | Shell autocompletion script |
| `acli feedback` | Submit feedback/report |

Global flags: only `-h/--help` and `-v/--version`. There is **no** global `--site`/`--profile` flag — site is bound at auth time, per product. `--json` (and `--csv`/`--web` where applicable) are per-command.

## Auth model (the gotcha)

Two independent layers:

- **Global** — `acli auth login|logout|status|switch`. OAuth only (`--web`). Used by admin + cross-product.
- **Per-product** — `acli jira auth ...`, `acli confluence auth ...`. Each can be OAuth *or* API token, and reports its own status/type. `acli auth status` (global) can say "Jira, Confluence not authenticated with your global profile" while `acli jira auth status` shows `api_token` and works fine.

```bash
acli jira auth login --web                                    # OAuth via browser
echo "$TOKEN" | acli jira auth login --site S.atlassian.net --email me@x.com --token   # API token (stdin only)
acli jira auth status        # ✓ Authenticated / Site / Email / Authentication Type
acli jira auth switch        # switch between accounts
acli jira auth logout
```

`--token` reads stdin exclusively (no flag value) — keeps the token out of argv/history. Same shape for `acli confluence auth login`.

## jira workitem (the workhorse)

| Subcommand | Purpose |
|---|---|
| `create` | Single create |
| `create-bulk` | Bulk create from CSV/JSON |
| `search` | JQL / filter search |
| `view` | Read one or more by key |
| `edit` | Update fields |
| `transition` | Change status |
| `assign` | Set/remove assignee |
| `comment` | `create`/`list`/`update`/`delete`/`visibility` |
| `link` | `create`/`delete`/`list`/`type` |
| `attachment` | `list`/`delete` |
| `watcher` | watcher commands |
| `clone` | Duplicate (optionally `--to-project`/`--to-site`) |
| `delete`, `archive`, `unarchive` | Lifecycle |

**Selectors** (shared by search/edit/transition/assign/comment/clone): `--key "K-1,K-2"` · `--jql "<JQL>"` · `--filter <ID>` · `--from-file <path>` (keys separated by comma/space/newline).

### create
```bash
acli jira workitem create --summary "New Task" --project TEAM --type Task
acli jira workitem create --from-file desc.txt --project PROJ --type Bug --assignee user@x.com --label bug,cli
acli jira workitem create --generate-json          # scaffold, then --from-json workitem.json
```
Flags: `-s/--summary`, `-p/--project`, `-t/--type` (Epic/Story/Task/Bug…), `-a/--assignee` (`@me`|`default`|email), `-d/--description` (plain or ADF), `--description-file`, `-l/--label`, `--parent`, `-e/--editor`, `-f/--from-file`, `--from-json`, `--generate-json`, `--json`.

### create-bulk
```bash
acli jira workitem create-bulk --from-csv issues.csv     # cols: summary,projectKey,issueType,description,label,parentIssueId,assignee
acli jira workitem create-bulk --from-json issues.json   # { "issues": [ {summary,projectKey,issueType,label[],assignee}, ... ] }
acli jira workitem create-bulk --generate-json
```
Flags: `--from-csv`, `--from-json`, `--generate-json`, `--ignore-errors`, `--yes`.

### search
```bash
acli jira workitem search --jql "project = TEAM" --paginate
acli jira workitem search --jql "..." --count
acli jira workitem search --jql "..." --fields key,summary,assignee --csv
acli jira workitem search --filter 10001 --web
```
Flags: `-j/--jql`, `--filter`, `-f/--fields` (default `issuetype,key,assignee,priority,status,summary`), `-l/--limit`, `--paginate`, `--count`, `--json`, `--csv`, `-w/--web`.

### view
```bash
acli jira workitem view KEY-123 --fields summary,comment --json
```
`-f/--fields` accepts `*all`, `*navigable`, `field,field`, or `-field` to exclude (default `key,issuetype,summary,status,assignee,description`). `--json`, `-w/--web`.

### edit
```bash
acli jira workitem edit --key "K-1,K-2" --summary "New"
acli jira workitem edit --jql "project = TEAM" --assignee user@x.com
acli jira workitem edit --filter 10001 --description "..." --yes
acli jira workitem edit --generate-json   # then --from-json
```
Flags: `-k/--key`, `--jql`, `--filter`, `-s/--summary`, `-d/--description`, `--description-file`, `-t/--type`, `-a/--assignee`, `--remove-assignee`, `-l/--labels`, `--remove-labels`, `--from-json`, `--generate-json`, `--ignore-errors`, `-y/--yes`, `--json`.

> ⚠️ **`--description` REPLACES the whole description — it does not append.** Verified by create+delete: a naive `edit --description "X"` wipes all existing content (0 original sections survive). To **add**, **change**, or **remove one section** while keeping the rest, you must read-modify-write the ADF (all three verified e2e — append/edit/remove a section, original untouched):
> ```bash
> # one-step helpers (preserve original; written for read-modify-write):
> bash scripts/acli-edit.sh KEY notes.md                  # append Markdown (or: KEY - < notes.md)
> bash scripts/acli-edit.sh KEY --remove-section "HEADING" # drop a section by exact heading (incl. nested)
> bash scripts/acli-edit.sh KEY --replace-section "HEADING" new.md # replace a section in place
>
> # manual read-modify-write (for surgical in-place edits):
> acli jira workitem view KEY --fields description --json   # grab .fields.description (ADF)
> #   …edit the content[] array (append/replace/remove nodes)…
> acli jira workitem edit --from-json payload.json          # { "issues": ["KEY"], "description": <merged ADF> }
> ```

### transition
```bash
acli jira workitem transition --key "K-1,K-2" --status Done
acli jira workitem transition --jql "project = TEAM" --status "In Progress"
```
Flags: `-k/--key`, `--jql`, `--filter`, `-s/--status`, `--ignore-errors`, `-y/--yes`, `--json`. Status names must match the workflow exactly.

### assign
```bash
acli jira workitem assign --key K-1 --assignee @me
acli jira workitem assign --jql "project = TEAM" --assignee user@x.com
acli jira workitem assign --from-file issues.txt --remove-assignee --json
```
Flags: `-k/--key`, `--jql`, `--filter`, `-f/--from-file`, `-a/--assignee`, `--remove-assignee`, `--ignore-errors`, `-y/--yes`, `--json`.

### comment
```bash
acli jira workitem comment create --key K-1 --body "This is a comment"
acli jira workitem comment create --jql "project = TEAM" --body-file comment.txt --edit-last
acli jira workitem comment create --jql "..." --editor
```
`create` flags: `-b/--body` (plain/ADF), `-F/--body-file`, `-e/--edit-last`, `--editor`, selectors, `--ignore-errors`, `--json`. Also `comment list|update|delete|visibility`.

### link
```bash
acli jira workitem link create --out KEY-123 --in KEY-456 --type Blocks
acli jira workitem link create --from-json links.json   # --generate-json to scaffold
acli jira workitem link type                            # list available link types
```
`create` flags: `--out`, `--in`, `--type` (outward description, e.g. Blocks), `--from-json`, `--from-csv` (out,in,type; header row ignored), `--generate-json`, `--ignore-errors`, `--yes`.

### clone
```bash
acli jira workitem clone --key "K-1,K-2" --to-project TEAM
```
Flags: `-k/--key`, `--jql`, `--filter`, `-f/--from-file`, `--to-project`, `--to-site` (default = current authed site), `--ignore-errors`, `-y/--yes`, `--json`.

## jira project / sprint / board / filter / dashboard / field

```bash
# project: archive | create | delete | list | restore | update | view
acli jira project create --from-project TEAM --key NEWTEAM --name "New Project" --lead-email me@x.com
acli jira project create --generate-json        # or --from-json project.json
acli jira project list --limit 30               # one of --limit | --recent | --paginate is REQUIRED (no bare list)
acli jira project view KEY

# sprint: create | delete | list-workitems | update | view
acli jira sprint create --name "Sprint 1" --board 5 --start 2025-01-01 --end 2025-01-14 --goal "..."
acli jira sprint list-workitems ...

# board: create | delete | get | list-projects | list-sprints | search
acli jira board search
acli jira board list-sprints ...

# filter: add-favourite | change-owner | get | get-columns | list | reset-columns | search | update
acli jira filter list --my            # one of --my | --favourite is REQUIRED
acli jira filter search

# dashboard: search
acli jira dashboard search

# field: cancel-delete | create | delete | update   (custom fields)
acli jira field create ...
```
`project create` is clone-only (`--from-project`, company-managed only) or `--from-json`; flags `-k/--key`, `-n/--name`, `-d/--description`, `-u/--url`, `-l/--lead-email`. `sprint create` requires `--name` + `--board`; dates ISO 8601.

## confluence

```bash
# page — VIEW ONLY (no create/update via CLI in this version)
acli confluence page view --id 123456789 --body-format storage   # storage|atlas_doc_format|view
#   include flags: --include-labels --include-version --include-direct-children --include-properties …
#   --status current,draft,archived | --version N | --get-draft

# blog — create | list | view
acli confluence blog create --space-id 12345 --title "Release Notes" --body "<p>XHTML storage format</p>"
acli confluence blog create --space-id 12345 --title "WIP" --status draft --body "..."
acli confluence blog create --private --space-id 12345 --title "..." --body "..."
acli confluence blog create --from-file ./content.html      # or --from-json / --generate-json

# space — archive | create | list | restore | update | view  (full CRUD)
acli confluence space create --key SPACEKEY --name "Space Name" --description "..." [--private --alias X --template-key K]
acli confluence space list
acli confluence space view --key SPACEKEY
```
Confluence body is **storage format (XHTML)**, not Jira's ADF. `blog create` flags: `--space-id`, `--title`, `--body`, `--status` (current|draft, default current), `--private`, `--created-at` (ISO 8601), `--from-file`, `--from-json`, `--generate-json`, `-j/--json`.

## admin / rovodev / config

```bash
# admin user lifecycle (managed accounts) — needs `acli admin auth`
acli admin user activate|deactivate|delete|cancel-delete ...

# Rovo Dev AI coding agent (beta) — separate scoped API token
#   token: https://go.atlassian.com/rovo-dev-api-token
acli rovodev auth login
acli rovodev run

# Atlassian Government Cloud toggle
acli config gov-cloud --status
acli config gov-cloud --enable          # --enable=false to disable
```

## Description & body formats (the #1 gotcha)

Jira and Confluence use **different** rich-text formats. Mixing them is the most common failure.

| Target | Format | Commands |
|---|---|---|
| Jira `description` / comment `body` | **ADF** — Atlassian Document Format (structured JSON) | `workitem create/edit/comment` |
| Confluence page / blog `body` | **storage format** — XHTML (`<p>…</p>`) | `confluence blog create` |

### Jira: plain string vs ADF object — two input paths, two rules

- **Flags** (`--description`, `--body`, `--description-file`, `--body-file`) accept **plain text** — acli wraps it into ADF for you. Pass a raw sentence; no JSON.
  ```bash
  acli jira workitem create -p TEAM -t Task -s "X" --description "Plain text works here."
  ```
- **`--from-json`** requires `description` to be a full **ADF document object** — a bare string does not match the schema.
  ```json
  "description": { "type": "doc", "version": 1,
    "content": [ { "type": "paragraph",
      "content": [ { "type": "text", "text": "Your text." } ] } ] }
  ```

ADF skeleton (verified via `--generate-json`): `{ type:"doc", version:1, content:[ {type:"paragraph", content:[ {type:"text", text:"…"} ]} ] }`. Bold/links/lists are extra marks/node types nested inside `content` — ADF `text` is literal, so `**bold**` renders as the literal asterisks, not bold.

Don't hand-write ADF. Write Markdown and convert:
```bash
python3 scripts/md2adf.py desc.md                       # → ADF doc object (stdout)
python3 scripts/md2adf.py desc.md -s "Summary" -p TP -t Bug > /tmp/wi.json
acli jira workitem create --from-json /tmp/wi.json      # --from-json takes a FILE PATH, not stdin ('-' fails)
```
Supports `#`/`##`/`###`, ordered/bullet/task lists, `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`, `[text](url)`, `` ``` `` code blocks, `>` blockquotes, `---` rules. Nested lists flatten to top-level — use H3 sub-headings + flat bullets for scannable grouping instead. See [scripts/md2adf.py](scripts/md2adf.py).

To read back, [scripts/adf2md.py](scripts/adf2md.py) is the inverse — pipe `view --json` through it for a readable work-item card at ~80% fewer tokens than raw JSON:
```bash
acli jira workitem view KEY --json | python3 scripts/adf2md.py
```

Working GOOD/BAD inputs → [examples/](examples/).

## Output & scripting cheatsheet

| Need | Flag |
|---|---|
| Machine-parseable | `--json` |
| Spreadsheet export | `--csv` (search) |
| Open in browser | `-w/--web` |
| Count only | `--count` (search) |
| All results | `--paginate` (search) |
| Scaffold input file | `--generate-json` (create/edit/link/bulk/project/blog) |
| Skip confirm prompt | `-y/--yes` (mutating bulk ops) |
| Continue past failures | `--ignore-errors` (read the summary after!) |
| Read body/desc from file | `--from-file` / `--body-file` / `--description-file` |
| Markdown → ADF for `--from-json` | `python3 scripts/md2adf.py desc.md` |
| Read a work item cheaply (ADF → md) | `acli ... view KEY --json \| python3 scripts/adf2md.py` (~80% fewer tokens) |
| Create from Markdown in one step | `bash scripts/acli-new.sh desc.md -s "..." -p TP -t Bug` |
| Append to a description (no loss) | `bash scripts/acli-edit.sh KEY notes.md` |
| Remove a description section | `bash scripts/acli-edit.sh KEY --remove-section "HEADING"` |
| Replace a section in place | `bash scripts/acli-edit.sh KEY --replace-section "HEADING" new.md` |

ADF = Atlassian Document Format (Jira rich text); storage format = Confluence XHTML. Full rules + GOOD/BAD inputs: see **Description & body formats** above and [examples/](examples/).
