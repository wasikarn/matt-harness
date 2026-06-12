---
name: research-brief
description: "Research brief with search-first + diagnose preloaded. Use when user says 'research this', 'deep dive on X', 'how does Y work in this codebase', 'compare Z approaches', or any open-ended exploration spanning files, docs, and external sources. Don't use for: implementation work (use /feature-dev or kbg:backend-dev), bug fixes (use /fix-bug), or security audits (use kbg:security-auditor)."
context: fork
agent: researcher
---

Research the topic provided by the user. Produce an actionable brief with cited sources (file:line, URL, commit sha).

## Input Contract

- **Trigger phrases:** See `description` in SKILL.md frontmatter.
- **Required context:** The skill expects the user to provide the task scope, target files, or relevant domain context.
- **Optional context:** Prior session summaries, acceptance contracts, or memory pointers may improve output quality.

## Output Format

- **Primary artifact:** Varies by skill — typically a plan, script invocation, structured report, or file modification.
- **Structured sections:** When applicable, output uses markdown sections, tables, or code blocks for clarity.
- **Reference style:** Links to related memories use `[[name]]` wikilink syntax.

## Failure Modes

- **No-op:** Skill exits without action if preconditions are not met (e.g., missing context, already satisfied criteria).
- **Partial output:** If the task scope exceeds what the skill can safely automate, it returns a plan and defers execution to a scoped sub-agent.
- **Human gate:** Any destructive or irreversible action requires explicit user confirmation before proceeding.
