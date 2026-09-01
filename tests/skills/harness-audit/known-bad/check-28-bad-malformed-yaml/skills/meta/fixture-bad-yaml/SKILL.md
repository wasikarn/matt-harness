---
name: fixture-bad-yaml
description: "Fixture for check 28 — deliberately malformed YAML frontmatter."
tools: [Bash, Read
---

# fixture-bad-yaml

Self-test fixture for check 28 — the `tools:` flow-sequence above has no
closing `]`, which is a YAML scanner error. Claude Code would silently drop
this skill from the runtime registry, so check 28 must CRIT on a genuinely
bucketed (2-level) `skills/<bucket>/<name>/SKILL.md` path.
