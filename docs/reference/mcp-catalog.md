# MCP-Server Catalog (reference, not installable config)

A **curated, described** catalog of MCP servers used in this environment. This
is a reference doc — kbg **does not bundle MCP/LSP config** (deliberate non-goal;
per-machine config lives in `~/.claude.json` top-level `mcpServers` and
`~/.claude/settings*.json`, see memory `mcp-config-location`). The catalog closes
the discoverability gap without touching the non-goal: you can see what's vetted
and what each does, without kbg shipping installable config.

## Servers in this environment

| Server | Capability | Config note |
|---|---|---|
| `code-review-graph` | Persistent incremental structural knowledge graph (Tree-sitter); caller/callee/impact-radius context for code review — prefer over Grep/Glob for structural Qs when the graph is built (check `list_repos_tool` first) | run via local server |
| `mongodb` | MongoDB cluster CRUD/aggregate/index/explain/export + Atlas-local deployments | run via launcher `~/.claude/mongodb-mcp-launch.sh` (sources nvm + mongodb.env, `exec mongodb-mcp-server`); see memory `mongodb-mcp-green-via-launcher`. **Never echo the connection string.** |
| `plugin:atlassian:atlassian` | Jira + Confluence + Compass; JQL/CQL search, issue create/edit/link, page create/update, worklog, transitions | Atlassian MCP contract doctrine in `ACLI.md` |
| `plugin:context7:context7` | Current library/framework/SDK/CLI docs — prefer over web search for library docs (training data lags releases) | resolves library-id then queries docs |
| `plugin:qmd:qmd` | Local search over markdown collections (BM25 lex / vec / hyde); scope with `collection`; `status` for collection list | per-collection doc stores |
| `plugin:figma:figma` | Design↔code bridge: read designs from Figma, generate Figma from code, Code Connect mapping, FigJam/diagrams | use Figma skills before `use_figma` |
| `plugin:playwright:playwright` | Browser automation: navigate/click/fill/snapshot/screenshot/evaluate/network — for web UI verification | — |

## Official LSP plugin stubs (different surface)

`pyright-lsp`, `typescript-lsp`, `lua-lsp` (@ `claude-plugins-official`) are editor-side
LSP connectors — they have **no plugin surface** (agents/skills/commands/hooks) for
kbg's audit to verify, so `auth-health-check.py` flags them "degraded / unverified
stub." This is a false-positive (they work via the editor LSP connector, not the
plugin cache), not a real break and not caused by any kbg release.