---
name: context-budget
description: Scan context-window consumption across agents/skills/MCP/rules; flag bloat + top savings. Use when context feels full or costs climb. Don't use for one-off response trimming.
bucket: meta
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
- MCP tool schema: deferred by default (tool search is on unless disabled) — only tool
  names + server instructions (~100-150 tokens/tool) load at session start; full schemas
  load on demand when Claude actually searches for and uses a tool. Cost no longer scales
  linearly with connected-tool count under this default. Confirmed live against
  `code.claude.com/docs/en/mcp` ("Scale with MCP tool search"), 2026-07-31 —
  `docs/research/official-docs-audit-2026-07-31.md`.
- Agent `description` frontmatter: always loaded, even if agent is never invoked

## Phase 1 — Inventory

Scan each component category and estimate tokens:

```bash
# Agents — flag files >200 lines or description >30 words
wc -l agents/*.md | sort -rn | head -20

# Skills — flag files >400 lines
find skills -name SKILL.md | xargs wc -l | sort -rn | head -20

# MCP servers — count tools. With tool search on (the default), only names +
# server instructions load upfront; full schemas defer until actually used —
# a large server no longer costs proportionally at session start.
# Check ~/.claude.json mcpServers section

# CLAUDE.md chain — flag combined total >300 lines
wc -l ~/.claude/CLAUDE.md CLAUDE.md .claude/CLAUDE.md 2>/dev/null

# @path imports (memory.md: resolve anywhere in a file, up to 4 hops, and
# load in full at launch — they don't reduce context, only organize it).
# The fixed 3-path wc -l above can't see this: any @file pulled in by one of
# those files adds real tokens this scan will silently miss. Grep for the
# cascade before trusting the fixed-path total:
grep -rhoE '@[^[:space:]`]+' ~/.claude/CLAUDE.md CLAUDE.md .claude/CLAUDE.md 2>/dev/null

# Memory index — the ONE piece of native auto-memory overhead this repo can
# actually measure. MEMORY.md loads whole into every session (no scoped/
# on-demand loading exists — see docs/research/agent-memory-engineering-2026-08-07.md
# Part 4, Tier C: that's a Claude Code platform decision, not something a
# hook can filter). No prior instrument reported this at all before
# 2026-08-07 — flag over its own documented ~17KB soft target (200L/25,600B
# hard cap enforced separately by memory-lint).
MEMDIR="$HOME/.claude/projects/$(pwd -P | sed 's|/|-|g')/memory"
[ -f "$MEMDIR/MEMORY.md" ] && wc -lc "$MEMDIR/MEMORY.md"
```

## Phase 2 — Classify each component

| Bucket | Criteria | Action |
|--------|----------|--------|
| Always needed | Backs an active command, referenced in CLAUDE.md, matches project type | Keep |
| Sometimes needed | Domain-specific, not in CLAUDE.md | Consider on-demand only |
| Rarely needed | No command reference, overlaps another component, no project match | Remove or lazy-load |

## Phase 3 — Detect high-impact issues

Ranked by token savings:

1. **MCP over-subscription** — with tool search off (or on an older CLI version), each tool costs a full schema upfront and a 30-tool server can cost more than all skills combined; with tool search on (current default), only names load upfront and this matters far less. Check whether tool search is active before treating server count as the dominant lever. CLI-wrapping servers (`gh`, `git`, `npm`) are still removal candidates on cleanliness grounds even when the token cost is low.
2. **Bloated agent descriptions** — `description` frontmatter loads into every Task tool invocation. Cap at 25 words.
3. **Heavy agents** — files >200 lines inflate Task context on every spawn.
4. **Redundant components** — skill that duplicates agent logic, rule that duplicates CLAUDE.md.
5. **CLAUDE.md bloat** — verbose explanations and outdated sections that should be rules files.

## Phase 4 — Report

```
Context Budget Report
═══════════════════════════════════════

Total estimated overhead: ~XX,XXX tokens
Context window: 1M (Sonnet 5 default) — confirm the actual model/window in use;
  older models, a gateway without 1M support, or CLAUDE_CODE_DISABLE_1M_CONTEXT
  (Claude Code 2.1.223, holds every 1M-native model to 200K when set) all fall
  back to 200K
Effective available: ~XXX,XXX tokens (XX%)

Component Breakdown:
  Agents          N files    ~X,XXX tokens
  Skills          N files    ~X,XXX tokens
  MCP tools       N tools    ~XX,XXX tokens   ← usually the dominant line
  CLAUDE.md       N lines    ~X,XXX tokens
  Memory index    N bytes    ~X,XXX tokens (est.)  — MEMORY.md, loaded whole every session; N% of its 25,600B hard cap

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

## Completion criterion

Verify each savings claim against the live context — confirm the component is actually loaded before counting it. If a claim drifts from measured usage or you remove a component still referenced, the audit fails — never cut based on token savings alone.
