---
name: inventory
description: "Catalogue loadable skills/agents/commands/hooks + the escape hatch. Use when stuck on routing. Thai: 'หา skill ไหนเหมาะ'. Don't use for single-layer lists or governance health."
---

# Inventory

Single command, zero config. Shows what's actually loadable from where you are right now — both the project-local layer (if the repo has a `.claude/`) and the global layer (`~/.claude/`, which includes plugin-delivered and legacy symlinked skills).

## Quick start

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/inventory.sh"
```

That's it. No env var, no path argument, no setup. From inside a git repo you get two sections (Project-local + Global). From outside one, you get Global only.

### Boundary map (committed snapshot)

For the canonical repo-local artifact map — agents, skills, hooks, with plugin-delivered / project-local markers and the witness trail — regenerate `BOUNDARY.md` from the script's STDOUT:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/inventory-boundary.sh" --repo-only > BOUNDARY.md
```

The boundary script's output is **STDOUT-only** — the `> BOUNDARY.md` redirect is mandatory; without it the dump goes to your terminal and `BOUNDARY.md` is never written. Witness/drift detection lives in `scripts/inventory-witness.sh` — see `reference.md` for both.

For a specific dir (e.g. inspecting dotfiles source where the originals live):

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/inventory.sh" /path/to/some/claude
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

## Discovery escape hatch (stuck-on-routing)

When no known skill, command, or agent clearly covers a task, this listing is the place to start: run the inventory, then grep the rendered output (or `BOUNDARY.md`) for keywords from the task to find the nearest match — or confirm none exists.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/inventory.sh" | /usr/bin/grep -i '<keyword>'
```

Each row carries its description, so a keyword scan surfaces the right capability without opening every SKILL.md. If nothing matches, the gap is real — fall back to native tooling rather than inventing a surface.

## When this skill pays back

- New project — see what global skills + this project's local skills are available
- Onboarding (including future-you 6 months later)
- Pre-audit pass — surface forgotten skills before deciding what's missing
- Verify that custom skills authored in dotfiles actually showed up in `~/.claude/` (look for `→` markers)
- Post-audit — confirm agent tool-grant fixes landed everywhere (use boundary map)
- Drift detection — committed `BOUNDARY.md` snapshot catches silent fleet changes

1. confirm the cross-layer list matches what Claude Code actually surfaces — verify a few entries load via /skills or /agents.
   If the list drifts from the live fleet (a surface added/removed since last regen), avoid routing from stale data — never present a capability that isn't loadable.
