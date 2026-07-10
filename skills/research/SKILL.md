---
name: research
description: "Background-agent research: primary sources → one cited Markdown file. Use when the user wants a topic researched or reading legwork delegated. Don't use for single-file lookups or security audits (kbg:security-auditor)."
metadata.origin: matt-pocock
---

Spin up a **background agent** to do the research, so you keep working while it reads.

Its job:

1. Investigate the question against **primary sources** — official docs, source code, specs, first-party APIs — not a secondary write-up of them. Follow every claim back to the source that owns it. Local-repo and indexed-doc primary sources count too: search the `plugin:qmd:qmd` collections and query `plugin:context7:context7` for library/framework docs before reaching for open web search.
2. Write the findings to a single Markdown file, citing each claim's source (file:line, doc URL, or commit sha).
3. Save it where the repo already keeps such notes; match the existing convention, and if there is none, put it somewhere sensible (e.g. `.scratch/research/<topic>.md`) and say where.

## Suggested next step

- Findings feed a decision → `kbg:grilling` (or `kbg:grilling --with-docs` if a codebase-backed spec is next).
- Findings are the whole ask → done; hand the file back.
