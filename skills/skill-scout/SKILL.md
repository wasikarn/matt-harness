---
name: skill-scout
description: Search existing local, marketplace, GitHub, and web skill sources before creating a new skill.
---

# Skill Scout

Search exhaustively before building. Use when the user wants to create, build, fork, or find a skill.

## Steps

**Step 1 — Local search**

```bash
find ~/.claude/skills -name "SKILL.md" 2>/dev/null | head -50
find ~/.claude/plugins -name "SKILL.md" 2>/dev/null | head -50
find ~/.claude/plugins/marketplaces -name "SKILL.md" 2>/dev/null | head -50
```

Read matching SKILL.md files and extract name + description from frontmatter.

**Step 2 — Marketplace search**

Check installed plugin directories for matching skills. Look for the ECC plugin cache at `~/.claude/plugins/cache/`.

**Step 3 — GitHub search**

```bash
gh search repos "claude skill [topic]" --limit 10
gh search code "SKILL.md [topic]" --limit 10
```

**Step 4 — Web search**

Search for "claude code skill [topic] site:github.com" and related queries.

**Step 5 — Rank results**

Priority order:
1. Exact name match (local or marketplace)
2. Description keyword match (local or marketplace)
3. Maintained GitHub repo with recent activity
4. Web-only sources

Cap at 10 results total. Prefer local/marketplace over remote.

**Step 6 — Present findings**

Output a table:

| Source | Name | Description | Location |
|--------|------|-------------|----------|
| local | … | … | path |

If nothing found: recommend creating a kbg-native skill following the pattern in `skills/` and the composer-not-creator doctrine (cherry-pick from ECC first).
