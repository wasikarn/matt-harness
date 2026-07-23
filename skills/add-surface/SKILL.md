---
name: add-surface
description: Build or remove a plugin surface (agent, skill, command, hook, output-style, theme). Use when creating one in an auto-discovered directory. Don't use for editing content.
---

**Auto-discovered directories:** `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`.

1. Create the file(s) following the pattern of an existing component in the same directory.
2. For hooks: register in `hooks/hooks.json` and add tests for any gate.
3. **Bump both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (the `version` field). Same-version edits to a cached plugin are silent no-ops.
4. Run validation (`claude plugin validate --strict`).
5. Commit and push.
6. `claude plugin update kbg@kobig` → restart Claude Code.

When `skills/inventory/` is present, regenerate the capability map with:
`bash skills/inventory/scripts/inventory-boundary.sh --repo-only > BOUNDARY.md`
(STDOUT-only — `>` redirect mandatory. Run `bash skills/inventory/scripts/inventory.sh` first for the unified cross-layer listing; see `skills/inventory/reference.md` for witness + boundary details.)

## Completion criterion

The new surface loads: `claude plugin validate --strict` passes, both manifests carry the same
bumped version, and the component appears in the live `/skills`/`/agents`/`/commands` listing after
`claude plugin update kbg@kobig` + restart. For a removal, confirm `harness-audit`'s fleet count
dropped by one and no dangling `kbg:`-reference to it remains.

## Failure modes

- **Same-version edit.** A cached plugin no-ops on an unchanged version — step 3's bump is not
  optional, and skipping it means the edit silently never takes effect.
- **Skipped `BOUNDARY.md` regen.** Leaves the capability map stale the next time `inventory` reads
  it as ground truth.
- **Editing content, not adding a surface.** This skill creates or removes a directory-level
  component. Changing an existing component's content is a direct edit, not this skill's job.
