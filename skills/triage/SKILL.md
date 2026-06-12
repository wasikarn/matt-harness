---
name: triage
description: "Single-issue triage: classify a bug, feature request, or task by severity, scope, and owner. Use when the user dumps a single issue and you need to decide whether to route it to /feature-dev, /fix-bug, /deep-dive, or kbg:orchestrate. Don't use for: prioritizing a batch (use kbg:orchestrate), or building a feature (use /feature-dev)."
---

# Triage

Classify one incoming item by asking 3 questions:
1. **Severity:** P0 (production down), P1 (blocked), P2 (annoyance), P3 (nice-to-have)
2. **Scope:** Single file, component, cross-component, or architecture
3. **Owner:** Which agent in the fleet owns this concern? (See BOUNDARY.md file ownership table)

Then route:
- P0 bug → `/fix-bug` + spawn `incident-commander` if production
- P1 bug / feature → `/feature-dev` or `kbg:orchestrate` if batch
- Research / unknown → `/deep-dive`
- Architecture question → `kbg:probe`

Done-when: a one-line classification + recommended next command.

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
