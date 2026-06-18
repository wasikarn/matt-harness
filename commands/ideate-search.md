---
name: ideate-search
description: "Search past kbg:ideate runs. Type `/ideate-search <query>` to find problems and outputs from previous ideate sessions using the local qmd collection (e.g., `/ideate-search caching`)."
disable-model-invocation: true
disable-model-invocation-reason: "This is a user-only slash command. The model should never invoke it unprompted; the user explicitly asks for a memory search. The command is a read-only reporter against local state, so it is safe for the model to run when the user types it."
---

# The ideate-search command

User-facing search across past `kbg:ideate` runs.

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
2. Run:
   ```bash
   python3 "${KBG_PLUGIN_ROOT}/scripts/ideate-memory.py" search "<query>"
   ```
   The path resolves from `${KBG_PLUGIN_ROOT}`.
3. Return the output to the user verbatim.

## What this command does NOT do

- Does **not** run a new ideate session.
- Does **not** modify code, the repo, or external systems.
- Does **not** silently re-rank or reinterpret qmd results.
