# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Validation (run before committing)

```bash
claude plugin validate --strict
```

Plugin manifest is the primary validation gate. `scripts/run-gauntlet.sh` runs plugin-validate + full shell-lint + JSON lint + harness-audit in parallel. Critical-hooks behavioral suite and eval gate are pending rebuild.

## Adding or removing a surface

**Auto-discovered directories:** `agents/`, `skills/`, `commands/`, `hooks/`, `output-styles/`, `themes/`.

1. Create the file(s) following the pattern of an existing component in the same directory.
2. For hooks: register in `hooks/hooks.json` and add tests for any gate.
3. **Bump both** `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (the `version` field). Same-version edits to a cached plugin are silent no-ops.
4. Run validation.
5. Commit and push.
6. `claude plugin update kbg@kobig` → restart Claude Code.

When `skills/inventory/` is present, regenerate the capability map with:
`bash skills/inventory/scripts/inventory-boundary.sh --repo-only > BOUNDARY.md`
(STDOUT-only — `>` redirect mandatory. Run `bash skills/inventory/scripts/inventory.sh` first for the unified cross-layer listing; see `skills/inventory/reference.md` for witness + boundary details.)

## Git hooks

Hooks live in `git-hooks/` (not `.git/hooks/`). Wire once per clone:

```bash
git config core.hooksPath git-hooks
```

pre-commit: fast gate — syntax/lint (`bash -n` + shellcheck), JSON validation, CRITICAL harness-audit (graceful-skip if absent).
pre-push: full gauntlet (all validation layers in parallel).

## Composer-not-creator doctrine

Before writing a new skill, command, or agent from scratch, check the upstream ECC repo at `/Users/kobig/Codes/Personals/ECC` (HEAD `2bc924fa`). Cherry-pick and adapt from there. Create kbg-native surfaces only when no upstream fit exists.

## Architecture

The plugin ships as `kbg@kobig` from the `wasikarn/kbg-harness` GitHub repo. Claude Code loads all surfaces from `~/.claude/plugins/cache/kobig/kbg/<version>/` at startup. Nothing is symlinked.

**Doctrine injection:** `hooks/session/doctrine-bootstrap.sh` fires on SessionStart and injects `docs/METHODOLOGY.md` (decision-sizing triad + reasoning scaffold) into session context via `$CLAUDE_PLUGIN_ROOT` (the plugin install dir; the older `$CLAUDE_PLUGIN_DIR` name is not a real CC variable and expands empty).

**Operating model:** deny the irrecoverable set computationally (gates in `hooks/gates/`), advise on the rest (sensors in `hooks/advisory/`). Advisory sensors never emit `permissionDecision`. The L2–L5 autonomy ladder is retired.

When hooks are wired: gates/ (deny), advisory/ (journal), session/ (inject), post-tool/ (audit), lifecycle/ (enforce), maintenance/ (upkeep). Governance events append to `~/.claude/governance-events.jsonl`.

## Skill authoring doctrine (matt-pocock)

When creating or editing a skill under `skills/`, apply matt-pocock's `writing-great-skills` doctrine (canonical: `skills/writing-great-skills/SKILL.md`):

1. **Leading word** — frontmatter `description:` opens with a coined term that recruits a pretrained prior (e.g. *grill*, *seam*, *premature completion*, *vertical slice*). One trigger per branch — no synonym rewrites of the same condition.
2. **Description length** — ≤25 words (cap above). Trim, do not remove triggers.
3. **Completion criterion** — every procedure step ends with a verifiable checkable signal. Resists premature completion.
4. **No-op test** — each sentence changes behaviour vs default; delete sentences that don't.
5. **Two cuts** — split-by-invocation or split-by-sequence only when the cut earns it. Default to criterion-sharpening over structural split (kbg is MAXIMAL-BOUNDED — see memory `surface-consolidation-2026-06-18`).
6. **Failure-mode guard** — name the failure mode the skill prevents inline at the drift step, not only in a header.

The `docs/skill-template/SKILL.md` template carries this checklist as a `## Design checks` section. New skills that don't carry it are audit-flagged by `skills/harness-audit` on next pass.

## Branching model

Single branch: `develop` only. No feature branches. Commit and push direct.

## Non-obvious gotchas

- **Hardcoded home paths blocked:** `.sh`/`.py` files must use `$HOME` or `~`, never `/Users/<name>`. The pre-commit gate will reject the commit.
- **`defaultEnabled: false`:** plugin ships disabled. After install, add `"kbg@kobig": true` to Claude Code `settings.json`, then restart.
- **Output styles:** `output-styles/senior-eng.md` is the default live-response register; `output-styles/staff-eng.md` is opt-in for cross-boundary decisions.
- **Working frames:** `contexts/` holds `dev.md`, `review.md`, `research.md` — loaded by `/frame` to set session posture.
- **`grep` is aliased** to `rtk grep` in this environment. Use `/usr/bin/grep` or `awk` for count/stat operations.
- **Cache-invalidation:** same-version edits are no-ops. Always bump both manifests before `claude plugin update`.
- **`BOUNDARY.md` regen:** the script writes to STDOUT, not the file. The `> BOUNDARY.md` redirect is required every time.
- **Never `rm -rf`:** use `trash` for deletions.
- **Never `--no-verify`** on commits or pushes.
- **Stage by name:** never `git add -A` or `git add .`.
- **Skill descriptions load on every Task spawn** (~words×1.3 tokens). Keep descriptions ≤25 words.
- **Thinking models:** invoke `kbg:thinking` before complex/ambiguous reasoning — it's a compact index of 39 on-demand mental models. The full model files live in `docs/reference/thinking-skills/skills/` (never move to `skills/` — would break fleet count).
