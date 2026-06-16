---
name: harness-nav
description: "L3 escape hatch for kbg-harness capability discovery. Use when no known skill, command, or agent clearly covers your task — teaches grep recipes to mine BOUNDARY.md, skills/, agents/, commands/ for the right capability. Returns the nearest match or confirms none exists. Don't use for: tasks where the right skill is already known (use it directly), or operational health queries (use kbg:harness-health). Reach for it only when the skill-nudge hook didn't surface the match."
---

# Harness Navigation — L3 Escape Hatch

kbg-harness context loads in three tiers:

| Tier | What's in it | When it loads |
|------|--------------|---------------|
| **L1** | METHODOLOGY / RTK / ACLI / DBGATE + CLAUDE.md + MEMORY.md | Every session, always resident |
| **L2** | Individual SKILL.md files | On demand — one invocation or skill-nudge keyword match |
| **L3** | BOUNDARY.md + raw source (skills/, agents/, commands/, hooks/) | Explicit read; reach here only when L2 has no coverage |

The model should prefer L2 (low cost, one discovery step) over L3 (multiple reads). Use this skill when the L2 path (skill-nudge, direct invoke) failed to surface the right capability and you need to mine L3 directly.

---

## Mining recipe — capability discovery

Run from the **repo root** (the session CWD).

### 1. Quick keyword search across skill descriptions

```bash
# Find skills covering a domain keyword
grep -r "^description:" skills/*/SKILL.md | grep -i "<keyword>"

# Examples
grep -r "^description:" skills/*/SKILL.md | grep -i "acceptance"
grep -r "^description:" skills/*/SKILL.md | grep -i "security"
grep -r "^description:" skills/*/SKILL.md | grep -i "review"
```

### 2. List all available commands (workflow pipeline commands)

```bash
ls commands/*.md | sed 's|commands/||;s|\.md||'

# Read a specific command's description
head -6 commands/<name>.md
```

### 3. Search BOUNDARY.md capability index

```bash
# BOUNDARY.md is the canonical inventory — grep it for any surface area
grep -A3 "<keyword>" BOUNDARY.md | head -30

# List all skills in the inventory
grep "^### " BOUNDARY.md | grep -i skill
```

### 4. Find agents by domain

```bash
# Agent descriptions live in the frontmatter
grep -l "description:.*<keyword>" agents/*.md 2>/dev/null

# Read a specific agent's spec
head -8 agents/<name>.md
```

### 5. Check if a named skill or agent exists

```bash
ls skills/<name>/SKILL.md 2>/dev/null && echo "skill exists" || echo "not found"
ls agents/<name>.md 2>/dev/null && echo "agent exists" || echo "not found"
```

---

## Decision tree

```
Need a capability?
  └─ Check L2 first (zero grep cost):
       └─ skill-nudge fired? → invoke that skill
       └─ known skill name? → invoke it directly (e.g. kbg:review-pr)
       └─ harness-health shows a relevant sensor? → check the sensor's skill
  └─ L2 miss → mine L3 (this skill):
       └─ keyword grep on skill descriptions → find nearest match
       └─ BOUNDARY.md grep → broader cross-surface search
       └─ Still nothing? → do it inline (no skill needed), or note the gap
```

If L3 confirms no coverage, do the task inline. Don't invent a new skill invocation for a missing skill — that's a fabrication. Either solve it inline or surface the gap to the user.

---

## Common capability map

| Task type | L2 to reach first |
|-----------|------------------|
| Code review before PR | `kbg:review-pr` |
| Security audit of high-stakes diff | `kbg:security-auditor` |
| Lock acceptance criteria | `kbg:accept-task` |
| Ship a change (classify → implement → review → merge) | `kbg:ship-change` |
| Full 9-step loop from scratch | `/ship-task` |
| Address PR review feedback | `/address-review` |
| Multi-agent team orchestration | `/team-plan` + `/team-build` |
| Harness self-audit (schema / manifest) | `bash skills/harness-audit/scripts/audit.sh .` |
| Governance journal / sensor staleness | `kbg:harness-health` |
| Research external library or approach | `kbg:research-brief` |
| Clarify scope before coding | `kbg:clarify-first` |

---

## Input Contract

- **Trigger phrases:** "which skill handles", "what skill covers", "is there a skill for", "find the right skill for", "no skill covers my need"
- **Required context:** task description
- **Optional context:** already-tried skill names (to avoid re-suggesting them)

## Output Format

Returns one of:
- The nearest L2 skill/command name + one-line "why it matches"
- A list of candidates if multiple qualify (with distinguishing criteria)
- "No coverage" — with suggested inline approach

## Failure Modes

- **False L2 hit:** a matching description keyword but wrong skill → read the full SKILL.md before invoking
- **L3 read cost:** reading many SKILL.md files is expensive; stop after finding a match, don't read all of them
- **No match found:** confirm with a second grep (synonyms, broader term) before declaring no coverage
