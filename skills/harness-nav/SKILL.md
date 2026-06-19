---
name: harness-nav
description: "L3 escape hatch for kbg-harness capability discovery. Use when no known skill, command, or agent clearly covers your task — teaches grep recipes to mine BOUNDARY.md, skills/, agents/, commands/ for the right capability. Returns the nearest match or confirms none exists. Also fires on Thai discovery queries like 'หา skill', 'navigate', 'skill ไหนเหมาะ', 'มีอะไรช่วยได้'. Don't use for: tasks where the right skill is already known (use it directly), or operational health queries (use kbg:harness-health). Reach for it only when the skill-nudge hook didn't surface the match."
---

# Harness Navigation — L3 Escape Hatch

kbg-harness context loads in three tiers — **L1** always-resident doctrine (METHODOLOGY/RTK/ACLI/DBGATE + CLAUDE.md + MEMORY.md), **L2** on-demand SKILL.md / command / agent specs, **L3** BOUNDARY.md + raw source (skills/, agents/, commands/, hooks/). Full table: `CLAUDE.md § Context hierarchy`.

The model should prefer L2 (low cost, one discovery step) over L3 (multiple reads). Use this skill when the L2 path (skill-nudge, direct invoke) failed to surface the right capability and you need to mine L3 directly.

---

## Mining recipe — capability discovery

Run from **any project CWD**; all source paths resolve from `${KBG_PLUGIN_ROOT}`.

### 1. Smart miner (preferred)

`nav.py` searches skills, commands, agents, and hooks by description/frontmatter, ranks matches, and prints a markdown table. Use this as the first L3 probe.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/nav.py" "<keyword-or-phrase>"

# Examples
python3 "${CLAUDE_SKILL_DIR}/scripts/nav.py" "acceptance"
python3 "${CLAUDE_SKILL_DIR}/scripts/nav.py" "security audit"
python3 "${CLAUDE_SKILL_DIR}/scripts/nav.py" "team orchestration"
```

### 2. List all available commands (workflow pipeline commands)

```bash
ls "${KBG_PLUGIN_ROOT}"/commands/*.md | sed 's|.*/||;s|\.md||'

# Read a specific command's description
head -6 "${KBG_PLUGIN_ROOT}/commands/<name>.md"
```

### 3. Search BOUNDARY.md capability index

```bash
# BOUNDARY.md is the canonical inventory — grep it for any surface area
grep -A3 "<keyword>" "${KBG_PLUGIN_ROOT}/BOUNDARY.md" | head -30

# List all skills in the inventory
grep "^### " "${KBG_PLUGIN_ROOT}/BOUNDARY.md" | grep -i skill
```

### 4. Find agents by domain

```bash
# Agent descriptions live in the frontmatter
grep -l "description:.*<keyword>" "${KBG_PLUGIN_ROOT}"/agents/*.md 2>/dev/null

# Read a specific agent's spec
head -8 "${KBG_PLUGIN_ROOT}/agents/<name>.md"
```

### 5. Check if a named skill or agent exists

```bash
ls "${KBG_PLUGIN_ROOT}/skills/<name>/SKILL.md" 2>/dev/null && echo "skill exists" || echo "not found"
ls "${KBG_PLUGIN_ROOT}/agents/<name>.md" 2>/dev/null && echo "agent exists" || echo "not found"
```

### 6. Mine the vendored reasoning-models reference library

The plugin ships 39 mental-model write-ups under `docs/reference/thinking-skills/` as a read-only reference library. These are **not** invokable skills — they are scaffolds the existing kbg surfaces already apply. Use these recipes to look up a named model or search by keyword.

> **Read-tool warning:** do not paste a `${KBG_PLUGIN_ROOT}` path into the `Read` tool. The variable expands only in shell context; `Read` will silently fail. Use `Bash` with the recipes below.

You can also surface these reference pages through the smart miner (§1):

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/nav.py" "mental models"
python3 "${CLAUDE_SKILL_DIR}/scripts/nav.py" "reasoning models"
```

```bash
# Guard: the variable is only available after a successful SessionStart hook
: "${KBG_PLUGIN_ROOT:?KBG_PLUGIN_ROOT is not set — run 'claude plugin update kbg@kobig' and restart Claude Code}"

# Read the kbg application catalog (which surface applies which model)
cat "${KBG_PLUGIN_ROOT}/docs/reference/reasoning-models.md"

# List all 39 vendored mental models (directory names start with `thinking-`)
find "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills" -maxdepth 2 -name SKILL.md \
  | sed 's|.*/skills/||; s|/SKILL.md||' | sort

# Read a specific model. Use the exact `Upstream dir` value from the table in
# reasoning-models.md (it always starts with `thinking-`). Do not strip the prefix.
cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/<thinking-dir>/SKILL.md"
# Example — read the systems-thinking vendored file (upstream dir is `thinking-systems`):
cat "${KBG_PLUGIN_ROOT}/docs/reference/thinking-skills/skills/thinking-systems/SKILL.md"

# Search vendored model bodies for a keyword
grep -Ril "<keyword>" "${KBG_PLUGIN_ROOT}"/docs/reference/thinking-skills/skills/*/SKILL.md
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
       └─ run `nav.py "<phrase>"` for ranked cross-surface matches
       └─ keyword grep on skill descriptions → secondary confirmation
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
| Harness self-audit (schema / manifest) | `bash "${CLAUDE_SKILL_DIR}/scripts/audit.sh"` |
| Governance journal / sensor staleness | `kbg:harness-health` |
| Research external library or approach | `kbg:research-brief` |
| Clarify scope before coding | `kbg:clarify-first` |
| Quick reference / what can kbg do | `/kbg-help` |

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
