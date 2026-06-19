---
name: research-brief
description: "Research brief with search-first + diagnose preloaded (the auto-routed flow; /deep-dive is the user-typed entry to the same thing). Use when the user says 'research this', 'how does Y work in this codebase', 'compare Z approaches', or any open-ended exploration spanning files, docs, and external sources. Also fires on Thai research requests like 'research', 'สำรวจ', 'หาข้อมูล', 'compare วิธี'. Don't use for: implementation work (use /feature-dev or kbg:backend-dev), bug fixes (use /fix-bug), or security audits (use kbg:security-auditor)."
---

Research the topic provided by the user. Produce an actionable brief with cited sources (file:line, URL, commit sha).
