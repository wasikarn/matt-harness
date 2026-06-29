---
name: documentation-lookup
description: "Host-model skill for current library/framework docs via Context7 MCP: resolve-library-id → query-docs → answer. Use when you need authoritative docs for a library/SDK/API right now and training data may be stale. Don't use for non-library questions (general programming, design, project-specific code) — for those, use the framework-specific skill."
metadata:
  origin: ECC
---

# Documentation Lookup (Context7)

Use the Context7 MCP (tools `resolve-library-id` and `query-docs`) for live docs instead of training data.

## Selection Criteria

When choosing from resolve-library-id results, prioritize by:

- **Benchmark score**: Higher scores indicate better documentation quality (100 is highest).
- **Source reputation**: Prefer High or Medium reputation when available.
- **Version match**: If the user specified a version (e.g. "React 19", "Next.js 15"), prefer version-specific library IDs (format `/org/project/v1.2.0`).

## Rate Limit

Do not call query-docs or resolve-library-id more than 3 times per question. If unclear after 3 calls, state the uncertainty and use the best information available.

## Secret Redaction

Redact API keys, passwords, tokens, and other secrets from any query sent to Context7 before calling resolve-library-id or query-docs.

## Rate Budget

Cap at 3 calls per question. Past 3: state uncertainty; do not loop.
