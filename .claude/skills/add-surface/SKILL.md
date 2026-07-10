---
name: add-surface
description: Add or remove a plugin surface (agent, skill, command, hook, output-style, theme) in kbg-harness. Use when creating a new file in one of those auto-discovered directories.
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
