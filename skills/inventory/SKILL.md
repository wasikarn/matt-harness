---
name: inventory
description: "inventory"
---

# Inventory

Single command, zero config. Shows what's actually loadable from where you are right now — both the project-local layer (if the repo has a `.claude/`) and the global layer (`~/.claude/`, which includes plugin-delivered and legacy symlinked skills).

## Quick start

```bash
bash skills/inventory/scripts/inventory.sh
```

That's it. No env var, no path argument, no setup. From inside a git repo you get two sections (Project-local + Global). From outside one, you get Global only.

For a specific dir (e.g. inspecting dotfiles source where the originals live):

```bash
bash skills/inventory/scripts/inventory.sh /path/to/some/claude
```

## Output

```
# Inventory
_Legend: ◇ plugin-delivered / project-local_

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
| `◇` | plugin-delivered or project-local |

### Sources, in order

1. **Project-local**: `<git-root>/.claude/{skills,agents,commands,hooks}` if the repo has one (walks up from cwd to find `.git`).
2. **Global**: `~/.claude/{skills,agents,commands,hooks}` — what Claude Code surfaces (plugin-delivered + legacy symlinks).

Empty subdirs are skipped silently. No artifacts → no section.

Reference: `reference.md` (description extraction, boundary map, witness details)

## When this skill pays back

- New project — see what global skills + this project's local skills are available
- Onboarding (including future-you 6 months later)
- Pre-audit pass — surface forgotten skills before deciding what's missing
- Verify that custom skills authored in dotfiles actually showed up in `~/.claude/` (look for `→` markers)
- Post-audit — confirm agent tool-grant fixes landed everywhere (use boundary map)
- Drift detection — committed `BOUNDARY.md` snapshot catches silent fleet changes
