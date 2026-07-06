---
name: context-budget
description: Scan context-window consumption across agents/skills/MCP/rules; flag bloat + top savings. Use when context feels full or costs climb. Don't use for one-off response trimming.
metadata:
  origin: ECC
---

# Context Budget

Analyze token overhead across every loaded component and surface the highest-ROI
reductions before adding more components or when session quality degrades.

## When to use

- Session output quality is degrading (symptom of context pressure)
- You've recently added many skills, agents, or MCP servers
- Planning to add more components and need to know if there's room
- Periodic hygiene check after a major adoption batch

## Token estimation rules

- Prose files: `word count × 1.3`
- Code-heavy files: `char count / 4`
- MCP tool schema: `~500 tokens per tool`
- Agent `description` frontmatter: always loaded, even if agent is never invoked

## Phase 1 — Inventory

Scan each component category and estimate tokens:

```bash
# Agents — flag files >200 lines or description >30 words
wc -l agents/*.md | sort -rn | head -20

# Skills — flag files >400 lines
find skills -name SKILL.md | xargs wc -l | sort -rn | head -20

# MCP servers — count tools (biggest lever: ~500 tokens/tool)
# Check ~/.claude.json mcpServers section

# CLAUDE.md chain — flag combined total >300 lines
wc -l ~/.claude/CLAUDE.md CLAUDE.md .claude/CLAUDE.md 2>/dev/null
```

## Phase 2 — Classify each component

| Bucket | Criteria | Action |
|--------|----------|--------|
| Always needed | Backs an active command, referenced in CLAUDE.md, matches project type | Keep |
| Sometimes needed | Domain-specific, not in CLAUDE.md | Consider on-demand only |
| Rarely needed | No command reference, overlaps another component, no project match | Remove or lazy-load |

## Phase 3 — Detect high-impact issues

Ranked by token savings:

1. **MCP over-subscription** — each tool costs ~500 tokens; a 30-tool server costs more than all skills combined. CLI-wrapping servers (`gh`, `git`, `npm`) are prime removal candidates.
2. **Bloated agent descriptions** — `description` frontmatter loads into every Task tool invocation. Cap at 25 words.
3. **Heavy agents** — files >200 lines inflate Task context on every spawn.
4. **Redundant components** — skill that duplicates agent logic, rule that duplicates CLAUDE.md.
5. **CLAUDE.md bloat** — verbose explanations and outdated sections that should be rules files.

## Phase 4 — Report

```
Context Budget Report
═══════════════════════════════════════

Total estimated overhead: ~XX,XXX tokens
Context window: 200K (Sonnet)
Effective available: ~XXX,XXX tokens (XX%)

Component Breakdown:
  Agents          N files    ~X,XXX tokens
  Skills          N files    ~X,XXX tokens
  MCP tools       N tools    ~XX,XXX tokens   ← usually the dominant line
  CLAUDE.md       N lines    ~X,XXX tokens

Findings (ranked by savings):
  1. [action] → saves ~X,XXX tokens
  2. [action] → saves ~X,XXX tokens

Potential savings: ~XX,XXX tokens (XX% of current overhead)
```

## kbg baseline

Owner global `skillOverrides.maxSkills = 0.08` → ~2.25× headroom vs default.
For the live surface count, run the inventory (`bash skills/inventory/scripts/inventory.sh`) rather than trusting a hardcoded snapshot — the count drifts.
MCP is the dominant variable — check active server count with `/doctor`.

## Guardrail

Do not remove a component based on token savings alone. Verify it has no active
command reference and no CLAUDE.md dependency before marking it removable.

1. verify each savings claim against the live context — confirm the component is actually loaded before counting it.
   If a claim drifts from measured usage or you remove a component still referenced, the audit fails — never cut based on token savings alone.
