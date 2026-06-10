# Inventory Reference

## Description extraction

| Type | Source |
|---|---|
| Skills | YAML frontmatter `description:` in `SKILL.md` |
| Commands / Agents | YAML frontmatter `description:` in the `.md` file |
| Hooks | First `# ` comment line, skipping shebang and `Author/Copyright/License/SPDX` lines |

Items without a description show `(no description)` — flag for the user to add one.

## Boundary map — canonical capability reference

Add the `--boundary` view when you need a routing + security reference, not just a listing:

```bash
bash ~/.claude/skills/inventory/scripts/inventory-boundary.sh
```

This produces a markdown table with:

| Section | Columns |
|---|---|
| **Agents** | name, domain summary, `tools:` grant, mutates (yes/no) |
| **Skills** | name, description, dispatched agent (if any), invoke mode (auto/manual) |
| **Hooks** | name, purpose summary |

Use this to verify `orchestrate` routing table accuracy, detect tool-grant drift, or onboard a new agent to the fleet.

## Witness — drift detection

Generate a committed snapshot of the boundary map so CI or pre-commit hooks can detect unauthorized fleet changes:

```bash
bash ~/.claude/skills/inventory/scripts/inventory-witness.sh
# commits claude/BOUNDARY.md (customise path with $1)
```

Verify later:

```bash
bash ~/.claude/skills/inventory/scripts/inventory-witness.sh /tmp/BOUNDARY_NEW.md
diff claude/BOUNDARY.md /tmp/BOUNDARY_NEW.md
```

Run this after any agent/skill/hook addition, removal, or tool-grant change.
