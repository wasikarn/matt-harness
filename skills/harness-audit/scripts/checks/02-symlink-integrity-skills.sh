#!/usr/bin/env bash
# 2. Symlink integrity — skills
for d in "$CLAUDE_DIR/skills"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  # Skip self during bootstrap; skip _-prefixed scaffolds (not deployed skills —
  # install.sh applies the same `_*` rule so the two never disagree). Skip
  # *-workspace dirs too — skill-creator eval workspaces, gitignored under
  # .gitignore's own "Session / skill workspaces" section, never deployed.
  [ "$name" = "harness-audit" ] && continue
  case "$name" in _*|*-workspace) continue ;; esac
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

