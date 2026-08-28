#!/usr/bin/env bash
# 2. Symlink integrity — skills
#
# CI-safety (reproduced 2026-08-28 by an adversarial plan review: 0 CRIT
# locally vs 76 CRIT under an isolated $HOME simulating a fresh GitHub
# runner). This loop's per-component F1 CRIT depends on either a local
# ~/.claude symlink farm (dev-mode install) or the plugin cache
# ($PLUGIN_ACTIVE, set earlier in audit.sh) — a clean checkout with neither
# has genuinely no way to prove loadability, which is a different fact than
# "every skill is missing." Distinguish by whether $HOME/.claude/skills
# exists AT ALL: if it does, this machine is using symlink-mode and a
# missing individual symlink is still a real, per-component gap (unchanged
# behavior below). If it does not, AND $PLUGIN_ACTIVE=0, neither delivery
# mechanism is configured here at all — downgrade to one aggregated WARN
# instead of one CRIT per skill, and skip the loop.
if [ "${PLUGIN_ACTIVE:-0}" -eq 0 ] && [ ! -d "$HOME/.claude/skills" ]; then
  warn "no plugin cache and no ~/.claude/skills symlink farm present — skill loadability unverified in this environment (expected on a clean CI checkout; not a per-skill finding)"
else
for d in "$CLAUDE_DIR/skills"/*/ "$CLAUDE_DIR/skills"/*/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  # Skip self during bootstrap; skip _-prefixed scaffolds (not deployed skills —
  # install.sh applies the same `_*` rule so the two never disagree). Skip
  # *-workspace dirs too — skill-creator eval workspaces, gitignored under
  # .gitignore's own "Session / skill workspaces" section, never deployed.
  [ "$name" = "harness-audit" ] && continue
  case "$name" in _*|*-workspace) continue ;; esac
  # A directory under skills/ with no SKILL.md at all was never a real,
  # invocable skill in the first place -- e.g. skills/inventory/ holds only
  # a scripts/ subdir (inventory-witness.sh, sync-fleet-counts.sh), always
  # invoked by direct path, never via Skill(). Flagging it "not loadable" is
  # a false positive: there is nothing here Claude Code could load as a
  # skill. Found 2026-08-25 while this exact CRIT blocked an unrelated
  # commit (T12 #91) -- pre-existing, confirmed present on the base tree
  # before that ticket's own changes.
  [ -f "$d/SKILL.md" ] || continue
  # Skip upstream-tracked skills (Matt Pocock + gstack + ECC + etc.) — locked
  # in ~/.agents/.skill-lock.json. Editing them drifts the content hash and
  # corrupts the install. They are intentionally NOT symlinked to dotfiles.
  # SSOT: ~/.agents/.skill-lock.json, record in memory `project_skill_lock_ssot`.
  for locked in "${LOCKED_SKILLS[@]:-}"; do
    [ "$name" = "$locked" ] && continue 2
  done
  if [ ! -L "$HOME/.claude/skills/$name" ] && ! is_plugin_delivered skills "$name"; then
    crit "skill '$name' not loadable by Claude Code (not in plugin cache and not symlinked)"
  fi
done
fi

