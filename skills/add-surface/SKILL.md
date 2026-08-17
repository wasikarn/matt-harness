---
name: add-surface
description: Build or remove a plugin surface (agent, skill, command, hook, output-style, theme). Use when creating one in an auto-discovered directory. Don't use for editing content.
---

**Auto-discovered directories:** `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`.

1. Create the file(s) following the pattern of an existing component in the same directory.
2. For hooks: register in `hooks/hooks.json` and add tests for any gate. Removing a hook:
   deregister it, delete its test section, then grep the ENTIRE test file (not just the section
   you just deleted) for every shared helper function's name and remove any with zero remaining
   callers — a helper defined outside the deleted section can still have lost its only caller.
3. **Bump both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (the `version` field). Same-version edits to a cached plugin are silent no-ops.
4. Run `bash skills/inventory/scripts/sync-fleet-counts.sh` to patch the "N skills · M agents · P
   commands" triple into the anchors it auto-fixes (`plugin.json`, `marketplace.json`,
   `README.md`). For a new **agent** specifically, the script does NOT reach two prose-only spots
   — hand-edit both: `skills/orchestrate/reference.md`'s named routing table (an agent missing
   there loads fine but `orchestrate` can't route to it) and its "N-agent survivor set" count
   phrase, plus the count mention in `docs/agent-voice-extension.md`.
5. Run validation (`claude plugin validate . --strict`), then `bash
   skills/harness-audit/scripts/audit.sh` and fix any WARN it raises — checks 12 and 48 exist
   specifically to catch anything step 4 missed.
6. `claude plugin update kbg@kobig`. Do this **before** committing, not after — the pre-commit
   hook re-runs harness-audit, and its F1 check only sees the latest *cached* plugin version. A
   brand-new file isn't there until this command copies the working tree into a fresh cache dir,
   so committing first blocks on a CRIT F1 ("not loadable").
7. Commit and push.
8. Restart Claude Code to pick up the change in the current session.

When `skills/inventory/` is present, regenerate the capability map with:
`bash skills/inventory/scripts/inventory-boundary.sh --repo-only > BOUNDARY.md`
(STDOUT-only — `>` redirect mandatory. Run `bash skills/inventory/scripts/inventory.sh` first for the unified cross-layer listing; see `skills/inventory/reference.md` for witness + boundary details.)

## Completion criterion

The new surface loads: `claude plugin validate . --strict` passes, both manifests carry the same
bumped version, and the component appears in the live `/skills`/`/agents`/`/commands` listing after
`claude plugin update kbg@kobig` + restart. For an addition, `harness-audit` also reports no new
WARN — for a new agent, that means it appears in `orchestrate/reference.md`'s routing table AND
count phrase, `docs/agent-voice-extension.md`'s count phrase is current, and the fleet-count triple
in `plugin.json`/`marketplace.json`/`README.md` matches the new total. For a removal, confirm
`harness-audit`'s fleet count dropped by one, no dangling `kbg:`-reference to it remains, and a
fresh grep of the test file confirms every remaining shared helper still has at least one caller.

## Failure modes

- **Same-version edit.** A cached plugin no-ops on an unchanged version — step 3's bump is not
  optional, and skipping it means the edit silently never takes effect.
- **Committing before `claude plugin update`.** Confirmed live 2026-08-17 (`/bug-sweep` add):
  the pre-commit hook's harness-audit pass sees only the latest *cached* version, so a new file
  reads as CRIT F1 ("not loadable") until step 6 runs first.
- **Skipped `BOUNDARY.md` regen.** Leaves the capability map stale the next time `inventory` reads
  it as ground truth.
- **Skipped fleet-count/routing-table sync.** A new agent that never gets added to
  `orchestrate/reference.md`'s routing table loads fine but is invisible to `orchestrate`'s
  dispatch logic. `sync-fleet-counts.sh` only auto-fixes `plugin.json`/`marketplace.json`/
  `README.md` — the routing table itself and the two agent-count prose mentions
  (`orchestrate/reference.md`, `docs/agent-voice-extension.md`) need a hand edit, and a script
  run alone leaves them stale. `harness-audit` checks 12 and 48 catch both — run it, don't skip
  straight to commit.
- **Editing content, not adding a surface.** This skill creates or removes a directory-level
  component. Changing an existing component's content is a direct edit, not this skill's job.
- **Orphaned test helper after a hook removal.** A helper can lose its only caller even when it's
  defined outside the section you deleted — checking just the deleted section misses this. Grep
  the whole test file for each shared helper's name after removal, and don't trust a "no dead code
  left" claim (yours or a prior run's) without re-running that grep yourself.
