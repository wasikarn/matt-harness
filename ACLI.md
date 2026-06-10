# ACLI - Atlassian Skill Gate

**Rule:** Before ANY Atlassian operation (Jira / Confluence) — search, view, create, edit, transition, comment, link, set parent — load the `/acli` skill first.

**Why:** the skill carries auth-gate, JQL-preview safety, ADF↔markdown scripts (`md2adf.py` / `adf2md.py`), and bulk-mutation guardrails. Going straight to MCP or raw commands skips them.

**How:** acli CLI is the default path. Fall back to `mcp__*atlassian*__*` tools only for fields acli can't set — e.g. `parent` needs `editJiraIssue` because `acli edit --from-json` has no parent field. Descriptions/comments are ADF: author in markdown → `md2adf.py`; read back with `adf2md.py`.
