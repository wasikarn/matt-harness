---
name: research-brief
description: "Research brief with search-first + diagnose preloaded. Use when user says 'research this', 'deep dive on X', 'how does Y work in this codebase', 'compare Z approaches', or any open-ended exploration spanning files, docs, and external sources. Don't use for: implementation work (use /feature-dev or /backend-dev), bug fixes (use /fix-bug), or security audits (use /security-auditor)."
context: fork
agent: researcher
---

Research the topic provided by the user. Produce an actionable brief with cited sources (file:line, URL, commit sha).
