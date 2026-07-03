---
name: ideate-search
description: "Search past /ideate runs via the local qmd collection. Say 'ideate search/ค้นหาไอเดีย/หาไอเดีย'. Don't use for a new session (/ideate) or code/web research (/deep-dive)."
disable-model-invocation: true
disable-model-invocation-reason: This is a user-only slash command. The model should never invoke it unprompted; the user explicitly asks for a memory search. The command is a read-only reporter against local state, so it is safe for the model to run when the user types it.
---

# The ideate-search command

User-facing search across past `/ideate` runs.

When the user types `/ideate-search` followed by a query, run the deterministic
search helper and return the ranked results exactly as-is.

## Usage

```
/ideate-search caching
/ideate-search หาไอเดียที่เคยคิดเรื่อง caching
/ideate-search microservice logging latency
```

## Behaviour

1. Extract the query text from the command invocation (everything after `/ideate-search`).
2. Search the `ideate-memory` qmd collection via the qmd MCP tool: run both a
   lexical (`type:'lex'`) and a semantic (`type:'vec'`) sub-query for the
   extracted text, `intent` set to "Find a past /ideate run matching this
   query", and `minScore: 0.5` to drop weak hits.
3. Return the ranked results to the user verbatim.

## What this command does NOT do

- Does **not** run a new ideate session.
- Does **not** modify code, the repo, or external systems.
- Does **not** silently re-rank or reinterpret qmd results.
