---
name: inventory
description: List the Claude artifacts loadable here — skills, agents, commands, hooks. Use when asked "what skills do I have", "list my agents", "what's available here", or "what can this repo do". Merges ~/.claude/ (global) with <git-root>/.claude/ (project-local), marking user-authored vs plugin items; zero config. Do NOT use for installing new skills (use find-skills) or auditing skill quality (use code-review or a custom audit pass — inventory only lists, doesn't judge).
---

# Inventory

Single command, zero config. Shows what's actually loadable from where you are right now — both the project-local layer (if the repo has a `.claude/`) and the global layer (`~/.claude/`, which includes plugin-installed skills and your symlinked custom ones).

## Quick start

```bash
bash ~/.claude/skills/inventory/scripts/inventory.sh
```

That's it. No env var, no path argument, no setup. From inside a git repo you get two sections (Project-local + Global). From outside one, you get Global only.

For a specific dir (e.g. inspecting dotfiles source where the originals live):

```bash
bash ~/.claude/skills/inventory/scripts/inventory.sh /path/to/some/claude
```

## Output

```
# Inventory
_Legend: → symlinked (user-authored)  ◇ in-place (plugin / project-local)_

## Project-local — `<repo>/.claude`
_~/projects/example/.claude_

### Agents (3)
  ◇ codebase-explorer        ...
  ◇ test-strategist          ...

## Global — `~/.claude` (what Claude Code loads)
_~/.claude_

### Skills (23)
  → assert-presence          Sign a tamper-evident assertion...
  → decommission             Sign a tamper-evident witness...
  → inventory                Dynamic listing of Claude artifacts...
  ◇ caveman                  Ultra-compressed communication mode...
  ◇ gateguard                Fact-forcing gate...
  ...
```

### Markers

| Symbol | Meaning |
|---|---|
| `→` | symlinked — user-authored, sourced from somewhere else (typically dotfiles) |
| `◇` | in-place — plugin-installed, project-local, or otherwise not a symlink |

### Sources, in order

1. **Project-local**: `<git-root>/.claude/{skills,agents,commands,hooks}` if the repo has one (walks up from cwd to find `.git`).
2. **Global**: `~/.claude/{skills,agents,commands,hooks}` — what Claude Code actually surfaces in the skill list (plugin-installed + your symlinks).

Empty subdirs are skipped silently. No artifacts → no section.

Reference: [description extraction, boundary map, witness details](reference.md)

## When this skill pays back

- New project — see what global skills + this project's local skills are available
- Onboarding (including future-you 6 months later)
- Pre-audit pass — surface forgotten skills before deciding what's missing
- Verify that custom skills authored in dotfiles actually showed up in `~/.claude/` (look for `→` markers)
- Post-audit — confirm agent tool-grant fixes landed everywhere (use boundary map)
- Drift detection — committed `BOUNDARY.md` snapshot catches silent fleet changes
